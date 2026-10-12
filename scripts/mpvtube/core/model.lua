-- Pure formatting and timeline helpers shared by the UI and regression tests.
local M = {}
-- Speed input, menu drawing and native writes share one range and step size.
M.speed_controls={min=0.25,max=2,step=0.05,presets={1,1.25,1.5,2}}

function M.clamp(value, lo, hi)
    return math.max(lo, math.min(hi, value))
end

function M.time(seconds)
    if not seconds or seconds ~= seconds or seconds == math.huge then return "--:--" end
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds / 60) % 60
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, seconds % 60) end
    return string.format("%d:%02d", minutes, seconds % 60)
end

-- Prevent file/track metadata from becoming ASS tags or forced line breaks.
function M.escape(text)
    return tostring(text or ""):gsub("\\", "\\\239\187\191")
        :gsub("{", "\\{"):gsub("}", "\\}"):gsub("[\r\n]", " ")
end

-- Approximate glyph widths for clipping; preserve complete UTF-8 characters.
local function advance(char, size)
    if #char >= 3 then return size end
    if char:match("[ ilI.,:!|'`]") then return size*0.28 end
    if char:match("[MW@]") then return size*0.85 end
    return size*0.56
end

function M.text_width(text, size)
    local used=0
    for char in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do used=used+advance(char,size) end
    return used
end

-- Avoid splitting a UTF-8 character; reserve ellipsis space only when needed.
function M.fit(text, width, size)
    text = tostring(text or "")
    if M.text_width(text,size) <= width then return text end
    local chars, used = {}, 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local step=advance(char,size)
        if used+step > math.max(0,width-size) then return table.concat(chars).."…" end
        chars[#chars+1],used=char,used+step
    end
    return text
end

-- Preserve text and UTF-8 exactly; prose prefers spaces, while long tokens can still wrap.
function M.wrap(text,width,size,word_wrap)
    local lines,line,used={},"",0
    for char in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local step=advance(char,size)
        if used+step>width and line~="" then
            local prefix,carry
            if word_wrap then prefix,carry=line:match("^(.*%s)(%S*)$") end
            if prefix and M.text_width(carry,size)+step<=width then
                lines[#lines+1]=prefix;line,used=carry,M.text_width(carry,size)
            else lines[#lines+1]=line;line,used="",0 end
        end
        line,used=line..char,used+step
    end
    if line~="" then lines[#lines+1]=line end
    return lines
end

-- Favor human-readable metadata, falling back to the stable MPV track ID.
function M.track_name(track)
    if not track then return "Off" end
    local title = track.title or track.lang or ("Track " .. tostring(track.id))
    if track.title and track.lang then title = title .. " · " .. track.lang end
    if track.external then title = title .. " (external)" end
    return title
end

function M.tracks(list, kind)
    local result = {}
    for _, track in ipairs(list or {}) do
        if track.type == kind then result[#result + 1] = track end
    end
    return result
end

-- Resolve native IDs without assuming consecutive numbers or a particular track order.
function M.track(list, kind, id)
    for _, track in ipairs(list or {}) do
        if track.type == kind and tostring(track.id) == tostring(id) then return track end
    end
end

-- Normalize malformed chapter metadata and include an untitled leading segment.
function M.chapters(list, duration)
    local result = {}
    if not duration or duration <= 0 then return result end
    for _, chapter in ipairs(list or {}) do
        local time = tonumber(chapter.time)
        if time and time >= 0 and time < duration then
            result[#result + 1] = {time = time, title = chapter.title or "Chapter " .. (#result + 1)}
        end
    end
    table.sort(result, function(a, b) return a.time < b.time end)
    for i = #result, 2, -1 do
        if result[i].time == result[i - 1].time then table.remove(result, i) end
    end
    if #result > 0 and result[1].time > 0 then
        table.insert(result, 1, {time = 0, title = "Introduction"})
    end
    return result
end

function M.chapter_at(chapters, time)
    for i = #chapters, 1, -1 do
        if time >= chapters[i].time then return chapters[i], i end
    end
end

-- A DVR/live stream with no duration can still expose a finite seekable window.
function M.seek_window(state)
    if state.seekable == false then return nil end
    if state.duration and state.duration > 0 then return 0, state.duration end
    local ranges = (state.cache or {})["seekable-ranges"] or {}
    local lo, hi
    for _, range in ipairs(ranges) do
        if range.start and range["end"] and range["end"] > range.start then
            lo = math.min(lo or range.start, range.start)
            hi = math.max(hi or range["end"], range["end"])
        end
    end
    return lo, hi
end

function M.contains(rect, x, y)
    return rect and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

-- A burst of seeks accumulates in one direction; reversal or an expired label starts again.
function M.seek_feedback(previous, amount, now, lifetime)
    local side = amount < 0 and "left" or "right"
    local total = math.abs(amount)
    if previous and previous.kind == "seek" and previous.side == side and now-previous.start < (lifetime or 0.75) then
        total = total+previous.amount
    end
    return {kind="seek",side=side,amount=total,start=now,opacity=1}
end

return M
