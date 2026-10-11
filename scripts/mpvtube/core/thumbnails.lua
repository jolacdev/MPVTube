-- Responsive single-worker previews with neighboring-frame prefetch and thumbfast support.
local mp = require("mp")
local utils = require("mp.utils")
local M = {}
local Preview = {}
Preview.__index = Preview

function M.new(options, request_render)
    local self = setmetatable({options=options, request_render=request_render, entries={}, order={},
        generation=0, serial=0, overlay_id=42, thumbfast=nil}, Preview)
    self.prefix = os.tmpname()
    os.remove(self.prefix)
    -- Windows' tmpname may be rooted outside TEMP; move just its basename into TEMP.
    if package.config:sub(1,1) == "\\" then
        local temp=os.getenv("TEMP") or os.getenv("TMP")
        if temp then self.prefix=utils.join_path(temp,self.prefix:gsub(".*[/\\]","")) end
    end
    self.timer = mp.add_timeout(options.thumbnail_delay, function() self:generate() end, true)
    -- thumbfast announces its availability and physical bitmap dimensions by message.
    mp.register_script_message("thumbfast-info", function(json)
        local data = utils.parse_json(json)
        if type(data) == "table" and type(data.width) == "number" and type(data.height) == "number"
            and data.width > 0 and data.width < math.huge and data.height > 0 and data.height < math.huge then
            self.thumbfast = data
            request_render()
        elseif type(data) == "table" and (not data.available or data.disabled) then
            self.thumbfast=nil
            request_render()
        end
    end)
    return self
end

function Preview:clear_overlay()
    if self.shown then mp.commandv("overlay-remove",self.overlay_id); self.shown=nil end
    if self.thumbfast_shown then
        mp.commandv("script-message-to","thumbfast","clear")
        self.thumbfast_shown=nil
    end
end

function Preview:hide()
    self.wanted=nil
    self.timer:kill()
    self:clear_overlay()
end

-- Invalidate callbacks before aborting; a late completion must not overwrite the next worker.
function Preview:cancel_job()
    self.generation=self.generation+1
    if self.job then mp.abort_async_command(self.job); self.job=nil end
    if self.job_path then os.remove(self.job_path); self.job_path=nil end
    self.prefetching=nil
end

-- A file or video-track change discards frames from the previous source.
function Preview:reset(path, duration, has_video, stream_index)
    self:hide()
    self:cancel_job()
    for _, entry in pairs(self.entries) do os.remove(entry.path) end
    self.entries, self.order, self.failed, self.direction, self.full_decode = {}, {}, false, 1, false
    self.path, self.duration = path, duration
    self.has_video=has_video ~= false
    self.stream_index=stream_index
    if path and not path:match("^%a[%w+.-]*://") then
        local info = utils.file_info(path)
        self.local_file = info and info.is_file
    else self.local_file=false end
end

-- Track-list observations also include captions; reset only when the selected video changes.
function Preview:set_video(track)
    local has_video=track ~= nil
    local stream_index=track and track["ff-index"]
    if self.path and (has_video ~= self.has_video or stream_index ~= self.stream_index) then
        self:reset(self.path,self.duration,has_video,stream_index)
    end
end

-- auto prefers thumbfast; FFmpeg is a local-file fallback and failures keep timestamps usable.
function Preview:provider()
    if self.options.thumbnails == "no" or not self.has_video then return nil end
    if self.options.thumbnails ~= "ffmpeg" and self.thumbfast
        and self.thumbfast.available and not self.thumbfast.disabled then return "thumbfast" end
    if self.options.thumbnails ~= "thumbfast" and self.local_file and self.duration and self.duration > 0 and not self.failed then return "ffmpeg" end
end

-- The requested bucket always wins. Warm at most two neighbors while the pointer is nearby.
function Preview:next_bucket()
    local wanted=self.wanted
    if not wanted or wanted.provider ~= "ffmpeg" or self.failed then return nil end
    if not self.entries[wanted.bucket] then return wanted.bucket end
    local limit=math.floor(math.max(0,self.duration-0.1)/self.options.thumbnail_interval)
    local offsets={self.direction or 1,-(self.direction or 1)}
    for i=1,math.min(2,self.options.thumbnail_cache-1) do
        local bucket=wanted.bucket+offsets[i]
        if bucket >= 0 and bucket <= limit and not self.entries[bucket] then return bucket end
    end
end

-- Coalesce the first request without restarting on movement; follow-up work has no delay.
function Preview:queue(delay)
    if not self.job and self:next_bucket() and not self.timer:is_enabled() then
        self.timer.timeout=delay or self.options.thumbnail_delay
        self.timer:resume()
    end
end

-- Return a neighboring cached frame while decoding, avoiding a blank flash between samples.
function Preview:request(time)
    local provider = self:provider()
    if not provider then self:hide(); return nil end
    if self.wanted and self.wanted.provider ~= provider then
        self:clear_overlay()
        self.timer:kill()
        self:cancel_job()
    end
    if provider == "thumbfast" then
        self.timer:kill()
        if self.job then self:cancel_job() end
        self.wanted = {time=time, provider=provider}
        return {w=self.thumbfast.width, h=self.thumbfast.height, physical=true}
    end
    local interval = self.options.thumbnail_interval
    local bucket = math.floor(math.max(0,math.min(time,self.duration-0.1))/interval)
    local previous = self.wanted
    if previous and previous.bucket and previous.bucket ~= bucket then self.direction=bucket > previous.bucket and 1 or -1 end
    self.wanted={bucket=bucket, time=math.min(bucket*interval,math.max(0,self.duration-0.1)), provider=provider}
    -- Foreground decoding may finish during motion; unrelated prefetch never delays a new hover.
    if self.prefetching and not self.entries[bucket] and self.job_bucket ~= bucket then self:cancel_job() end
    self:queue()
    local entry=self.entries[bucket] or self.entries[bucket-1] or self.entries[bucket+1]
    if entry then return {w=self.options.thumbnail_width,h=math.floor(self.options.thumbnail_width*9/16),entry=entry} end
    self:clear_overlay()
    return nil
end

function Preview:generate()
    self.timer:kill()
    local bucket=self:next_bucket()
    if self.job or not bucket then return end
    self.serial=self.serial+1
    local generation = self.generation
    local path = self.prefix .. "-" .. self.serial .. ".bgra"
    self.job_path=path
    self.job_bucket,self.prefetching=bucket,bucket ~= self.wanted.bucket
    local width = math.floor(self.options.thumbnail_width*1.6/2)*2
    local height = math.floor(width*9/16/2)*2
    -- Reference frames and a small probe reduce preview work; playback is unaffected.
    -- One filter thread avoids creating a CPU-wide pool just to scale one tiny image.
    local args = {self.options.ffmpeg_path,"-hide_banner","-loglevel","error","-nostdin","-y",
        "-filter_threads","1","-probesize",self.full_decode and "5000000" or "32768",
        "-skip_frame",self.full_decode and "default" or "noref",
        "-threads","4","-ss",string.format("%.3f",bucket*self.options.thumbnail_interval),"-i",self.path,
        "-map",self.stream_index and "0:"..self.stream_index or "0:v:0","-an","-sn","-dn","-frames:v","1","-vf",
        string.format("scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2",width,height,width,height),
        "-threads","1","-pix_fmt","bgra","-f","rawvideo",path}
    self.job = mp.command_native_async({name="subprocess",args=args,playback_only=false,
        capture_stdout=true,capture_stderr=true}, function(success,result)
        -- A finished worker may belong to a file already closed; discard its frame safely.
        if generation ~= self.generation then os.remove(path); return end
        self.job,self.job_path,self.prefetching=nil,nil,nil
        local info=utils.file_info(path)
        if success and result and result.status == 0 and info and info.size == width*height*4 then
            self.entries[bucket]={path=path,w=width,h=height}
            self.order[#self.order+1]=bucket
            -- Evict oldest frames to bound both memory metadata and temporary disk usage.
            while #self.order > self.options.thumbnail_cache do
                -- Keep the hovered sample even when it was cached before its neighbors.
                local index=self.wanted and self.order[1] == self.wanted.bucket and 2 or 1
                local old=table.remove(self.order,index)
                os.remove(self.entries[old].path)
                self.entries[old]=nil
            end
            self.request_render()
            self:queue(0)
        else
            os.remove(path)
            if not self.full_decode then
                -- Unusual headers or a final non-reference frame need the normal decoder path.
                self.full_decode=true
                self:queue(0)
            else
                self.failed=true
                mp.msg.verbose("Thumbnail generation unavailable; using timestamps. " .. tostring(result and result.error_string or ""))
            end
            self.request_render()
        end
    end)
end

-- Bitmap overlays use physical pixels; suppress duplicate upload/message calls per position.
function Preview:display(rect, scale)
    if not rect or not self.wanted then self:clear_overlay(); return end
    local x, y = math.floor(rect.x*scale), math.floor(rect.y*scale)
    if self.wanted.provider == "thumbfast" then
        local key=string.format("%.2f:%d:%d",self.wanted.time,x,y)
        if key ~= self.thumbfast_shown then
            mp.commandv("script-message-to","thumbfast","thumb",self.wanted.time,x,y)
            self.thumbfast_shown=key
        end
    else
        local entry=rect.entry or self.entries[self.wanted.bucket]
        if not entry then self:clear_overlay(); return end
        local width, height=math.floor(rect.w*scale),math.floor(rect.h*scale)
        local key=entry.path..":"..x..":"..y..":"..width..":"..height
        if key ~= self.shown then
            mp.commandv("overlay-add",self.overlay_id,x,y,entry.path,0,"bgra",entry.w,entry.h,entry.w*4,width,height)
            self.shown=key
        end
    end
end

function Preview:shutdown()
    self:reset(nil,nil)
    os.remove(self.prefix)
end

return M
