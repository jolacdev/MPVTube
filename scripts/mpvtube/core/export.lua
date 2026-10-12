-- Copy supported tracks losslessly with one asynchronous FFmpeg process at a time.
local model=require('core.model')
local M={}
local formats={subrip={'srt','srt'},ass={'ass','ass'},ssa={'ssa','ass'},webvtt={'vtt','webvtt'},
    hdmv_pgs_subtitle={'sup','sup'},aac={'m4a','ipod'},opus={'opus','opus'},vorbis={'ogg','ogg'},
    mp3={'mp3','mp3'},flac={'flac','flac'},alac={'m4a','ipod'},ac3={'ac3','ac3'},eac3={'eac3','eac3'},dts={'dts','dts'}}
local function local_file(path)
    return type(path)=='string' and path~='' and not path:match('^%a[%w+.-]*://')
end

-- Stable native stream indices and sanitized metadata determine output names, never a shell.
function M.plan(state,kind,all)
    local jobs,skipped={},0
    if not local_file(state.path) then return jobs,'Exports require a local media file' end
    local stem=state.path:gsub('([^/\\]+)%.[^./\\]+$','%1')
    for _,track in ipairs(model.tracks(state.tracks,kind)) do
        local selected=tostring(track.id)==tostring(state[kind=='sub' and 'sid' or 'aid'])
        if all and not track.external or not all and selected then
            local format=formats[track.codec]
            if not format and (track.codec or ''):match('^pcm_') then format={'wav','wav'} end
            local source=track.external and track['external-filename'] or state.path
            local index=track['ff-index']
            if track.external and not index then index=0 end
            if format and local_file(source) and type(index)=='number' and index>=0 and index==math.floor(index) then
                local language=(track.lang or 'und'):gsub('[^%w_-]','_'):sub(1,24)
                jobs[#jobs+1]={source=source,index=index,format=format[2],
                    path=stem..'.'..kind..'-'..tostring(track.id)..'.'..language..'.'..format[1]}
            else skipped=skipped+1 end
        end
    end
    return jobs,#jobs==0 and 'No supported tracks to export' or nil,skipped
end

function M.new(state,options,view)
    local mp=require('mp')
    local utils=require('mp.utils')
    local worker,queue,generation
    generation=0
    local function status(text)
        state.export_status=text
        view.request_render()
    end
    -- Probe once, independently of hover previews; missing executables never block the UI.
    worker=mp.command_native_async({name='subprocess',args={options.ffmpeg_path,'-version'},
        playback_only=false,capture_stdout=true,capture_stderr=true,capture_size=65536},function(ok,result)
        worker=nil
        state.export_ready=ok and result and result.status==0
        options.ffmpeg_available=not not state.export_ready
        view.request_render()
    end)
    local function cancel()
        generation=generation+1
        if worker then mp.abort_async_command(worker);worker=nil end
        queue=nil
    end
    local function start(kind,all)
        if queue then view.feedback('Export already running','info');return end
        if not state.export_ready then return end
        local jobs,error,skipped=M.plan(state,kind,all)
        if error then view.feedback(error,'info');return end
        -- Refuse collisions before starting. FFmpeg's -n also protects a concurrent creator.
        for _,job in ipairs(jobs) do
            if utils.file_info(job.path) then status('File exists: '..job.path);view.feedback('Export file already exists','info');return end
        end
        queue=jobs
        local token,completed,total=generation,0,#jobs
        local function next_job()
            local job=table.remove(queue,1)
            if not job then
                queue=nil
                status('Exported '..completed..' track(s)'..(skipped>0 and '; skipped '..skipped..' unsupported' or ''))
                view.feedback(state.export_status,'info');return
            end
            status('Exporting '..(completed+1)..' / '..total)
            worker=mp.command_native_async({name='subprocess',playback_only=false,capture_stderr=true,capture_size=65536,
                args={options.ffmpeg_path,'-nostdin','-hide_banner','-loglevel','error','-n','-i',job.source,
                    '-map','0:'..job.index,'-map_metadata','-1','-map_chapters','-1','-c','copy','-f',job.format,job.path}},function(ok,result)
                if token~=generation then return end
                worker=nil
                if not ok or not result or result.status~=0 then
                    -- Keep the error visible; never remove a path that might belong to another writer.
                    queue=nil;status('Export failed; see MPV log')
                    mp.msg.error('Track export: '..tostring(result and (result.stderr or result.error_string) or "Cannot start FFmpeg"))
                    view.feedback(state.export_status,'info');return
                end
                completed=completed+1;next_job()
            end)
        end
        next_job()
    end
    return {start=start,shutdown=cancel}
end
return M
