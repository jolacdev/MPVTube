-- Translate UI actions into native MPV commands and restore temporary player settings.
local mp = require("mp")
local model = require("core.model")
local speed_controls=model.speed_controls
local menu = require("ui.menu")
local M = {}

-- Wall-clock sleep timers pause playback and cancel cleanly.
function M.new_sleep_timer(state,view)
    local timer
    local function cancel()
        if timer then timer:kill(); timer=nil end
        state.sleep_minutes=nil
    end
    local function set(minutes)
        cancel()
        if minutes > 0 then
            state.sleep_minutes=minutes
            timer=mp.add_timeout(minutes*60,function()
                cancel()
                mp.set_property_bool("pause",true)
                view.feedback("Sleep timer finished","pause")
                view.show()
            end)
        end
        view.show()
    end
    return {set=set,shutdown=cancel}
end

-- State is observed playback data; options are validated settings; view provides visibility/feedback callbacks.
function M.new(state, options, view, preview)
    local show, feedback = view.show, view.feedback
    local saved_window, saved_keep_open
    local subtitle_position = mp.get_property_number("sub-pos",100)
    local adjusted_subtitle_position
    local menu_keys_bound = false
    local action
    local captions = require("core.captions").new(state,view.request_render)
    local sleep = M.new_sleep_timer(state,view)

    -- Both the drag slider and its step buttons use the same range and rounding.
    local function speed(value)
        local rounded=math.floor(value/speed_controls.step+0.5)*speed_controls.step
        mp.set_property_number("speed",model.clamp(rounded,speed_controls.min,speed_controls.max))
        show()
    end

    -- File changes and menu dismissal both restore the user's keyboard bindings.
    local function update_menu_binding()
        if not state.menu and menu_keys_bound then
            for _, name in ipairs({"escape","up","down","select"}) do mp.remove_key_binding("menu-"..name) end
            menu_keys_bound=false
        end
    end

    -- Menu navigation owns keys only while open, then restores the user's bindings.
    local function close_menu()
        state.menu,state.menu_scroll,state.menu_focus=nil,0,nil
        update_menu_binding()
        show()
    end

    local function open_menu(page)
        if state.menu == page then close_menu(); return end
        state.menu,state.menu_scroll=page,0
        state.menu_focus=nil
        local panel=menu.geometry(state,options)
        if page == "chapters" then
            -- Keep the current chapter visible when a long list opens in a short window.
            for index,row in ipairs(panel.rows) do
                if row.selected then state.menu_scroll=math.max(0,index-panel.visible); break end
            end
        end
        if not menu_keys_bound then
            local function move(direction)
                if state.menu == "speed" then speed(state.speed-direction*speed_controls.step); return end
                local current=menu.geometry(state,options)
                local index=state.menu_focus or current.offset+(direction > 0 and 0 or current.visible+1)
                repeat index=index+direction until index < 1 or index > #current.rows or current.rows[index].action
                if index < 1 or index > #current.rows then return end
                state.menu_focus=index
                state.menu_scroll=model.clamp(state.menu_scroll,index-current.visible,index-1)
                show()
            end
            mp.add_forced_key_binding("ESC","menu-escape",close_menu)
            mp.add_forced_key_binding("UP","menu-up",function() move(-1) end,{repeatable=true})
            mp.add_forced_key_binding("DOWN","menu-down",function() move(1) end,{repeatable=true})
            mp.add_forced_key_binding("ENTER","menu-select",function()
                if state.menu == "speed" then close_menu(); return end
                local rows=menu.rows(state,state.menu)
                if state.menu_focus and rows[state.menu_focus] then action(rows[state.menu_focus].action) end
            end)
            menu_keys_bound=true
        end
        state.hover=nil
        preview:hide()
        show()
    end

    local function pause()
        mp.set_property_bool("pause",not state.pause)
        feedback("",state.pause and "play" or "pause")
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
        value=model.clamp(value,0,100)
        -- YouTube's arrow feedback uses a small/large wave for decrease/increase.
        local icon=value == 0 and "volume_off" or value < state.volume and "volume_down" or "volume_up"
        mp.set_property_number("volume",value)
        -- YouTube's arrows preserve mute; moving its slider unmutes the video.
        if value > 0 and state.mute and not show_feedback then mp.set_property_bool("mute",false) end
        if show_feedback then feedback(string.format("%d%%",math.floor(value+0.5)),icon) end
        show()
    end

    -- Enabling CC selects a real subtitle track if MPV currently has none selected.
    local function subtitles()
        if #model.tracks(state.tracks,"sub") == 0 then feedback("No subtitles","cc"); return end
        if state.sid == "no" or state.sid == false then
            mp.set_property_number("sid",model.tracks(state.tracks,"sub")[1].id)
            mp.set_property_bool("sub-visibility",true)
        else mp.set_property_bool("sub-visibility",not state.sub_visibility) end
        show()
    end

    local function restore_window()
        if not saved_window then return end
        -- Restore the exact options and client window size changed by either mode.
        for _, name in ipairs({"ontop","border","autofit","autofit-larger","autofit-smaller","geometry"}) do
            if saved_window[name] ~= nil then mp.set_property_native(name,saved_window[name]) end
        end
        if saved_window.size then mp.set_property_native("current-window-scale",saved_window.size) end
        saved_window=nil
        state.pip,state.theater=false,false
    end

    -- Both window modes share one snapshot, so switching modes never loses the original.
    local function window_mode(mode)
        if not mp.get_property_bool("vo-configured",false) then return end
        local was_active=state[mode]
        restore_window()
        if was_active then show(); return end
        saved_window={size=mp.get_property_native("current-window-scale")}
        for _, name in ipairs({"ontop","border","autofit","autofit-larger","autofit-smaller","geometry"}) do
            saved_window[name]=mp.get_property_native(name)
        end
        mp.set_property_bool("fullscreen",false)
        mp.set_property_bool("border",mode ~= "pip")
        mp.set_property_bool("ontop",mode == "pip")
        local width=mode == "pip" and options.pip_width or options.theater_width
        mp.set_property("autofit",tostring(width).."x"..tostring(math.floor(width*9/16)))
        mp.set_property("geometry",mode == "pip" and "-24-24" or "50%:50%")
        -- window-scale applies immediately after startup, unlike autofit on some VOs.
        local video=state.video or {}
        if video.w and video.w > 0 then mp.set_property_number("window-scale",width/video.w) end
        state[mode]=true
        feedback(mode == "pip" and "Mini player" or "Theater mode",mode == "pip" and "pip" or "theater")
        show()
    end

    -- Layout/menu descriptors carry commands, keeping drawing independent of MPV writes.
    action=function(descriptor)
        if not descriptor then return end
        if descriptor.page then open_menu(descriptor.page)
        elseif descriptor.speed then speed(descriptor.speed)
        elseif descriptor.speed_step then speed(state.speed+descriptor.speed_step)
        elseif descriptor.caption then
            captions.apply(descriptor.caption,descriptor.value)
            -- Keep the choice page open for quick comparisons, as YouTube does.
            show()
        elseif descriptor.sleep then
            sleep.set(descriptor.sleep)
            state.menu,state.menu_scroll="settings",0
            state.menu_focus=nil
        elseif descriptor.property then
            local ok,error=mp.set_property_native(descriptor.property,descriptor.value)
            if not ok then mp.msg.warn(tostring(error)); feedback("Unavailable","info") end
            if descriptor.property == "sid" and descriptor.value ~= "no" then mp.set_property_bool("sub-visibility",true) end
            if state.menu and state.menu ~= "settings" then
                if state.menu == "playlist" then close_menu() else state.menu,state.menu_scroll,state.menu_focus="settings",0,nil end
            end
            show()
        elseif descriptor.kind == "pause" then pause()
        elseif descriptor.kind == "time" then state.time_remaining=not state.time_remaining; show()
        elseif descriptor.kind == "mute" then
            mp.set_property_bool("mute",not state.mute)
            if descriptor.show_feedback then
                feedback(state.mute and string.format("%d%%",math.floor(state.volume+0.5)) or "0%",state.mute and "volume_up" or "volume_off")
            end
            show()
        elseif descriptor.kind == "fullscreen" then
            restore_window()
            -- Native macOS fullscreen callbacks can lag behind the last window transition.
            mp.set_property_bool("fullscreen",not mp.get_property_bool("fullscreen",state.fullscreen))
            show()
        elseif descriptor.kind == "next" then mp.commandv("playlist-next","weak"); show()
        elseif descriptor.kind == "previous" then mp.commandv("playlist-prev","weak"); show()
        elseif descriptor.kind == "subtitles" then subtitles()
        elseif descriptor.kind == "expand" then state.controls_expanded=not state.controls_expanded; show()
        elseif descriptor.kind == "seek" and descriptor.value then
            seek(descriptor.value,true)
            mp.set_property_bool("pause",false)
            show()
        elseif descriptor.kind == "pip" and options.pip then window_mode("pip")
        elseif descriptor.kind == "theater" and options.theater then window_mode("theater")
        elseif descriptor.kind == "autoplay" then
            -- keep-open=always pauses at every file end; remember the previous policy.
            if state.keep_open ~= "always" then
                saved_keep_open=state.keep_open
                mp.set_property("keep-open","always")
            else mp.set_property("keep-open",saved_keep_open or "no"); saved_keep_open=nil end
            show()
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
        if fullscreen and (state.pip or state.theater) then restore_window() end
    end)

    local function shutdown()
        sleep.shutdown()
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
        update_subtitles=update_subtitles, update_menu_binding=update_menu_binding, shutdown=shutdown}
end

return M
