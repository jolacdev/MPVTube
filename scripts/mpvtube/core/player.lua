-- Translate UI actions into native MPV commands and restore temporary player settings.
local mp = require("mp")
local model = require("core.model")
local speed_controls=model.speed_controls
local menu = require("ui.menu")
local caption_options=require("core.captions")
local M = {}

-- State is observed playback data; options are validated settings; view provides visibility/feedback callbacks.
function M.new(state, options, view, preview)
    local show, feedback = view.show, view.feedback
    local saved_window, saved_keep_open
    local subtitle_position = mp.get_property_number("sub-pos",100)
    local adjusted_subtitle_position
    local action
    local captions = caption_options.new(state,view.request_render)
    local exports = require("core.export").new(state,options,view)
    local original_volume_max=mp.get_property_number("volume-max",130)
    local owned_volume_max=options.volume_max or 200
    mp.set_property_number("volume-max",owned_volume_max)
    state.volume_max=mp.get_property_number("volume-max",owned_volume_max)

    -- Reuse one feedback card for accepted changes, regardless of their UI or key entry point.
    local function notify(text,icon) feedback(text,icon or "info");show() end
    local function track_name(kind,id)
        local track=model.track(state.tracks,kind,id)
        return track and model.track_name(track) or "None"
    end
    local function subtitle_feedback()
        local visible=mp.get_property_bool("sub-visibility",state.sub_visibility)
        local id=mp.get_property_native("sid",state.sid)
        notify(visible and id~="no" and id~=false and "Subtitles: "..track_name("sub",id) or "Subtitles off","cc")
    end

    -- Both the drag slider and its step buttons use the same range and rounding.
    local function speed(value)
        local rounded=math.floor(value/speed_controls.step+0.5)*speed_controls.step
        mp.set_property_number("speed",model.clamp(rounded,speed_controls.min,speed_controls.max))
        notify(string.format("%g×",mp.get_property_number("speed",state.speed)),"speed")
    end

    -- Closing menus releases their navigation bindings, retaining MPVTube's keyboard ownership.
    local function close_menu()
        if view.cancel_key_capture then view.cancel_key_capture() end
        state.menu,state.menu_scroll,state.menu_focus=nil,0,nil
        state.focus,state.focus_group=nil,nil
        if view.update_focus then view.update_focus() end
        show()
    end

    local function open_menu(page)
        if view.cancel_key_capture then view.cancel_key_capture() end
        if state.menu == page then close_menu(); return end
        state.menu,state.menu_scroll=page,0
        state.menu_focus,state.focus,state.focus_group=nil,nil,nil
        if view.update_focus then view.update_focus() end
        local panel=menu.geometry(state,options)
        if page == "chapters" then
            -- Keep the current chapter visible when a long list opens in a short window.
            for index,row in ipairs(panel.rows) do
                if row.selected then state.menu_scroll=math.max(0,index-panel.visible); break end
            end
        end
        state.hover=nil
        preview:hide()
        show()
    end

    local function pause()
        local paused=mp.get_property_bool("pause",state.pause)
        mp.set_property_bool("pause",not paused)
        feedback("",paused and "play" or "pause")
        show()
    end

    -- Clamp all seeks to the file or DVR window; dragging uses cheap keyframe seeks.
    local function seek(time, exact, preserve_feedback)
        local lo,hi=model.seek_window(state)
        if not lo or not hi then return end
        if not preserve_feedback then state.feedback=nil end
        mp.commandv("seek",model.clamp(time,lo,hi),exact and "absolute+exact" or "absolute+keyframes")
    end

    local function relative_seek(amount)
        local lo,hi=model.seek_window(state)
        if not lo or not hi then feedback("LIVE","info"); return end
        seek(mp.get_property_number("time-pos",state.time)+amount,true,true)
        feedback(nil,nil,nil,amount)
        show()
    end

    -- Pointer controls show their own value; only keyboard shortcuts request central feedback.
    local function volume(value, show_feedback)
        value=model.clamp(value,0,mp.get_property_number("volume-max",state.volume_max or options.volume_max or 200))
        -- Keyboard feedback uses a small/large wave for decrease/increase.
        local icon=value == 0 and "volume_off" or value < mp.get_property_number("volume",state.volume) and "volume_down" or "volume_up"
        mp.set_property_number("volume",value)
        -- Keyboard changes preserve mute; moving the slider unmutes the video.
        if value > 0 and state.mute and not show_feedback then mp.set_property_bool("mute",false) end
        if show_feedback then feedback(string.format("%d%%",math.floor(value+0.5)),icon) end
        show()
    end

    -- Enabling CC selects a real subtitle track if MPV currently has none selected.
    local function subtitles()
        if #model.tracks(state.tracks,"sub") == 0 then feedback("No subtitles","cc"); return end
        local selected=mp.get_property_native("sid",state.sid)
        if selected == "no" or selected == false then
            mp.set_property_number("sid",model.tracks(state.tracks,"sub")[1].id)
            mp.set_property_bool("sub-visibility",true)
        else mp.set_property_bool("sub-visibility",not mp.get_property_bool("sub-visibility",state.sub_visibility)) end
        subtitle_feedback()
    end

    local function restore_window()
        if not saved_window then return end
        -- Restore the exact options and client window size changed by mini player.
        for _, name in ipairs({"ontop","border","autofit","autofit-larger","autofit-smaller","geometry"}) do
            if saved_window[name] ~= nil then mp.set_property_native(name,saved_window[name]) end
        end
        if saved_window.size then mp.set_property_native("current-window-scale",saved_window.size) end
        saved_window=nil
        state.pip=false
    end

    -- Mini player owns one snapshot until restored or native fullscreen is entered.
    local function window_mode()
        if not mp.get_property_bool("vo-configured",false) then return end
        local was_active=state.pip
        restore_window()
        if was_active then notify("Mini player off","pip"); return end
        saved_window={size=mp.get_property_native("current-window-scale")}
        for _, name in ipairs({"ontop","border","autofit","autofit-larger","autofit-smaller","geometry"}) do
            saved_window[name]=mp.get_property_native(name)
        end
        mp.set_property_bool("fullscreen",false)
        mp.set_property_bool("border",false)
        mp.set_property_bool("ontop",true)
        local width=options.pip_width
        mp.set_property("autofit",tostring(width).."x"..tostring(math.floor(width*9/16)))
        mp.set_property("geometry","-24-24")
        -- window-scale applies immediately after startup, unlike autofit on some VOs.
        local video=state.video or {}
        if video.w and video.w > 0 then mp.set_property_number("window-scale",width/video.w) end
        state.pip=true
        feedback("Mini player","pip")
        show()
    end

    -- Track cycling uses native IDs, includes external tracks and never depends on list order.
    local function track_step(kind,direction)
        local tracks=model.tracks(state.tracks,kind)
        if #tracks==0 then feedback("No "..kind.." tracks","info");return end
        local property=kind=="sub" and "sid" or "aid"
        local current=mp.get_property_native(property)
        local index=direction>0 and 0 or 1
        for i,track in ipairs(tracks) do if tostring(track.id)==tostring(current) then index=i;break end end
        local track=tracks[(index-1+direction)%#tracks+1]
        mp.set_property_native(property,track.id)
        if kind=="sub" then mp.set_property_bool("sub-visibility",true) end
        feedback(model.track_name(track),kind=="sub" and "cc" or "audio");show()
    end

    local function delay(kind,amount)
        local property=kind.."-delay"
        local value=mp.get_property_number(property,0)+amount
        mp.set_property_number(property,value)
        feedback(string.format("%s sync: %+.0f ms",kind=="sub" and "Subtitle" or "Audio",value*1000),"info");show()
    end

    -- Layout/menu descriptors carry commands, keeping drawing independent of MPV writes.
    action=function(descriptor)
        if not descriptor then return end
        if descriptor.page then open_menu(descriptor.page)
        elseif descriptor.kind=="animations" then
            local ok,error=view.set_animations(not options.animations)
            notify(ok and (options.animations and "Animations on" or "Animations off") or error,"animations")
        elseif descriptor.speed then speed(descriptor.speed)
        elseif descriptor.speed_step then speed(mp.get_property_number("speed",state.speed)+descriptor.speed_step)
        elseif descriptor.caption then
            local accepted=captions.apply(descriptor.caption,descriptor.value)
            local text=descriptor.caption=="reset" and "Subtitle appearance reset" or "Subtitle appearance updated"
            for _,row in ipairs(caption_options.rows(state,"captions")) do
                if row.action.page=="caption-"..descriptor.caption then text=row.label..": "..row.value;break end
            end
            notify(accepted and text or "Subtitle option unavailable","cc")
            -- Keep choice pages open for quick comparisons.
            show()
        elseif descriptor.property then
            local ok,error=mp.set_property_native(descriptor.property,descriptor.value)
            if not ok then mp.msg.warn(tostring(error)); feedback("Unavailable","info");return end
            if descriptor.property == "sid" and descriptor.value ~= "no" then mp.set_property_bool("sub-visibility",true) end
            local field=({aid="aid",sid="sid",vid="vid",["sub-visibility"]="sub_visibility",["playlist-pos"]="playlist_pos"})[descriptor.property]
            if field then state[field]=mp.get_property_native(descriptor.property) end
            local property=descriptor.property
            local value=mp.get_property_native(property)
            if property=="sid" or property=="sub-visibility" then subtitle_feedback()
            elseif property=="aid" or property=="vid" then
                local kind=property=="aid" and "audio" or "video"
                notify((property=="aid" and "Audio: " or "Video: ")..track_name(kind,value),property=="aid" and "audio" or "quality")
            elseif property=="loop-file" then notify(value~="no" and "Loop on" or "Loop off","loop")
            elseif property=="playlist-pos" then
                local item=state.playlist[(tonumber(value) or 0)+1] or {}
                notify(item.title or (item.filename or "Video selected"):gsub(".*[/\\]",""),"playlist")
            end
            if state.menu and state.menu ~= "settings" and not descriptor.keep_menu then
                if state.menu == "playlist" then close_menu() else open_menu("settings") end
            end
            show()
        elseif descriptor.shortcut then view.edit_shortcut(descriptor.shortcut,descriptor.id)
        elseif descriptor.command then
            if descriptor.command=="script-binding console/enable" and not mp.get_property_bool("load-console",true) then
                notify("MPV console is disabled");return
            end
            local ok=mp.command(descriptor.command)
            if descriptor.command=="screenshot" then notify(ok and "Screenshot saved" or "Screenshot failed") end
        elseif descriptor.binding then state.key_edit=nil;state.binding_detail=descriptor.binding;open_menu("binding")
        elseif descriptor.export then exports.start(descriptor.export,descriptor.all)
        elseif descriptor.kind == "relative-seek" then relative_seek(descriptor.value)
        elseif descriptor.kind == "percent-seek" then
            local lo,hi=model.seek_window(state)
            if lo and hi then
                local time=lo+(hi-lo)*descriptor.value
                seek(time,true);notify(string.format("%.0f%%, %s",descriptor.value*100,model.time(time)))
            else notify("Cannot seek this media") end
        elseif descriptor.kind == "volume-step" then volume(mp.get_property_number("volume",state.volume)+descriptor.value,true)
        elseif descriptor.kind == "speed-step" then
            speed(mp.get_property_number("speed",state.speed)+descriptor.value)
        elseif descriptor.kind == "frame" then
            local video=model.track(state.tracks,"video",state.vid)
            if not video or video.image then notify("No video frames");return end
            mp.commandv(descriptor.value>0 and "frame-step" or "frame-back-step")
            notify(descriptor.value>0 and "Next frame" or "Previous frame",descriptor.value>0 and "seek_right" or "seek_left")
        elseif descriptor.kind == "track-step" then track_step(descriptor.track,descriptor.value)
        elseif descriptor.kind == "chapter-step" then
            local chapters=state.chapters
            local _,index=model.chapter_at(chapters,mp.get_property_number("time-pos",state.time))
            index=(index or 1)+descriptor.value
            if chapters[index] then seek(chapters[index].time,true);notify(chapters[index].title,"playlist")
            else notify(descriptor.value>0 and "No next chapter" or "No previous chapter","playlist") end
        elseif descriptor.kind == "delay" then delay(descriptor.track,descriptor.value)
        elseif descriptor.kind == "sync-reset" then
            mp.set_property_number("sub-delay",0);mp.set_property_number("audio-delay",0);feedback("Synchronization reset","info");show()
        elseif descriptor.kind == "subtitle-override" then
            captions.override()
            feedback(state.caption_style["sub-ass-override"]=="strip" and "Clean subtitle style" or "Original subtitle style","cc")
            show()
        elseif descriptor.kind == "native-menu" or descriptor.kind == "properties" then
            close_menu()
            if not mp.get_property_bool("load-select",true) or not mp.get_property_bool("load-console",true) then
                notify("MPV select/console is disabled");return
            end
            mp.commandv("script-binding",descriptor.kind=="native-menu" and "select/menu" or "select/show-properties")
        elseif descriptor.kind == "pause" then pause()
        elseif descriptor.kind == "time" then
            state.time_remaining=not state.time_remaining
            notify(state.time_remaining and "Remaining time" or "Elapsed time")
        elseif descriptor.kind == "mute" then
            local muted=mp.get_property_bool("mute",state.mute)
            mp.set_property_bool("mute",not muted)
            if descriptor.show_feedback then
                feedback(muted and string.format("%d%%",math.floor(state.volume+0.5)) or "0%",muted and "volume_up" or "volume_off")
            end
            show()
        elseif descriptor.kind == "fullscreen" then
            restore_window()
            -- Native macOS fullscreen callbacks can lag behind the last window transition.
            mp.set_property_bool("fullscreen",not mp.get_property_bool("fullscreen",state.fullscreen))
            notify(mp.get_property_bool("fullscreen") and "Fullscreen" or "Windowed","fullscreen")
        elseif descriptor.kind == "next" or descriptor.kind == "previous" then
            local direction=descriptor.kind=="next" and 1 or -1
            local position=mp.get_property_number("playlist-pos",state.playlist_pos)
            if state.playlist[position+direction+1] then
                mp.commandv(direction>0 and "playlist-next" or "playlist-prev","weak")
                notify(direction>0 and "Next video" or "Previous video",descriptor.kind)
            else notify(direction>0 and "No next video" or "No previous video","playlist") end
        elseif descriptor.kind == "subtitles" then subtitles()
        elseif descriptor.kind == "expand" then state.controls_expanded=not state.controls_expanded; show()
        elseif descriptor.kind == "seek" and descriptor.value then
            seek(descriptor.value,true)
            mp.set_property_bool("pause",false)
            local chapter=model.chapter_at(state.chapters,descriptor.value)
            notify(chapter and chapter.title or model.time(descriptor.value),"playlist")
        elseif descriptor.kind == "pip" and options.pip then window_mode()
        elseif descriptor.kind == "autoplay" then
            -- keep-open=always pauses at every file end; remember the previous policy.
            if state.keep_open ~= "always" then
                saved_keep_open=state.keep_open
                mp.set_property("keep-open","always")
            else mp.set_property("keep-open",saved_keep_open or "no"); saved_keep_open=nil end
            notify(mp.get_property_native("keep-open")=="always" and "Autoplay off" or "Autoplay on","play")
        end
    end

    local function update_subtitles()
        -- Lift ordinary bottom subtitles above the controls, then restore the user's position.
        local subtitle_target=subtitle_position
        if options.raise_subtitles and state.opacity > 0.2 and not state.idle and state.sid ~= "no" and state.sid ~= false then
            subtitle_target=math.min(subtitle_position,math.floor(100-82/state.h*100))
        end
        if adjusted_subtitle_position ~= subtitle_target then
            adjusted_subtitle_position=subtitle_target
            mp.set_property_number("sub-pos",subtitle_target)
        end
    end

    -- Remember external subtitle moves without mistaking our own adjustment for user input.
    mp.observe_property("sub-pos","number",function(_,value)
        if value and value ~= adjusted_subtitle_position then subtitle_position=value; view.request_render() end
    end)

    -- Native fullscreen changes can also arrive through input.conf or another script.
    mp.observe_property("fullscreen","bool",function(_,fullscreen)
        if fullscreen and state.pip then restore_window() end
    end)

    local function shutdown()
        exports.shutdown()
        if mp.get_property_number("volume-max") == owned_volume_max then mp.set_property_number("volume-max",original_volume_max) end
        restore_window()
        -- Leave later user changes alone; restore only the position set by this skin.
        if adjusted_subtitle_position and mp.get_property_number("sub-pos") == adjusted_subtitle_position then
            mp.set_property_number("sub-pos",subtitle_position)
        end
        if saved_keep_open and mp.get_property_native("keep-open") == "always" then
            mp.set_property("keep-open",saved_keep_open)
        end
    end

    return {action=action, pause=pause, seek=seek, relative_seek=relative_seek,
        volume=volume, speed=speed, subtitles=subtitles, close_menu=close_menu, open_menu=open_menu,
        update_subtitles=update_subtitles, shutdown=shutdown}
end

return M
