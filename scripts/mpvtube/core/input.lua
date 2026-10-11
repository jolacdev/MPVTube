-- Mouse gestures and keyboard bindings use the same geometry as the rendered controls.
local mp = require("mp")
local model = require("core.model")
local speed_controls=model.speed_controls
local ui = require("ui.view")
local spacing=require("ui.draw").metrics
local M = {}

function M.new(state, options, view, player, preview)
    local show, feedback = view.show, view.feedback
    local request_render, schedule_hide = view.request_render, view.schedule_hide
    local update_dimensions = view.update_dimensions
    local action, pause, seek = player.action, player.pause, player.seek
    local volume, relative_seek = player.volume, player.relative_seek
    local subtitles, close_menu = player.subtitles, player.close_menu
    local click_timer
    local function current_hit()
        return view.layout and ui.hit(view.layout,state.mx,state.my,mp.get_time()) or nil
    end
    local function outside_menu(hit)
        return state.menu and not (hit and (hit.id == "menu" or hit.group == state.menu))
    end
    local tooltip_timer = mp.add_timeout(options.tooltip_delay,request_render,true)

    -- Holding the video accelerates playing media; release never turns it into a tap.
    local video_pressed, saved_speed, hold_consumed
    local hold_timer = mp.add_timeout(0.35,function()
        if video_pressed and not state.pause and not state.idle and not state.menu then
            saved_speed=mp.get_property_number("speed",1)
            mp.set_property_number("speed",2)
            state.speed_hold=true
            hold_consumed=true
            request_render()
        end
    end,true)
    local function stop_hold()
        local held=hold_consumed
        video_pressed=false
        hold_timer:kill()
        -- Preserve any later speed change made by another script or user binding.
        if saved_speed and mp.get_property_number("speed") == 2 then mp.set_property_number("speed",saved_speed) end
        saved_speed,state.speed_hold=nil,nil
        request_render()
        return held
    end

    -- Throttle decoding during seek drags, then commit the exact position on release.
    local last_seek = 0
    local function drag_update(final)
        if not view.layout then return end
        if state.drag == "seek" then
            local lo,hi=view.layout.seek_lo,view.layout.seek_hi
            if not lo or not hi then return end
            local timeline=view.layout.timeline
            state.drag_time=lo+model.clamp((state.mx-timeline.x)/timeline.w,0,1)*(hi-lo)
            local now=mp.get_time()
            if final or now-last_seek >= 0.08 then
                seek(state.drag_time,final)
                last_seek=now
            end
        elseif state.drag == "volume" and view.layout.volume.w > 0 then
            volume((state.mx-view.layout.volume.x)/view.layout.volume.w*100)
        elseif state.drag == "speed" and view.layout.speed then
            local slider=view.layout.speed
            local fraction=model.clamp((state.mx-slider.x)/slider.w,0,1)
            player.speed(speed_controls.min+fraction*(speed_controls.max-speed_controls.min))
        end
        request_render()
    end

    -- A changed hit starts the tooltip delay; ordinary pointer motion does not restart it.
    local function update_hover()
        -- Reserve UI gestures from native window dragging; held sliders capture the full window.
        local top=state.idle and state.h or state.h-spacing.safe_height
        if state.drag or state.menu then top=0 end
        mp.set_mouse_area(0,top*state.scale,state.w*state.scale,state.h*state.scale,"mpvtube-controls")
        local hit=state.mouse_inside and current_hit() or nil
        local id=hit and hit.id
        if id ~= state.hover then
            state.hover,state.hover_start=id,mp.get_time()
            tooltip_timer:kill()
            if hit and hit.tip then tooltip_timer.timeout=options.tooltip_delay; tooltip_timer:resume() end
            request_render()
        end
    end

    local function mouse_move()
        local x,y=mp.get_mouse_pos()
        local mx,my=x/state.scale,y/state.scale
        -- Rendering also samples the pointer; a held slider must still receive every move.
        if not state.drag and state.mouse_inside and mx == state.mx and my == state.my then return end
        state.mouse_inside=true
        state.mx,state.my=mx,my
        if state.menu_focus then state.menu_focus=nil; request_render() end
        update_hover()
        if state.drag then drag_update(false) end
        show()
    end

    -- Activate buttons only when press and release match; sliders own the full gesture.
    local pressed_hit
    local function mouse_button(event)
        if state.idle then return end
        -- A resize/fullscreen event can arrive just before the next rendered frame.
        -- Recompute hit areas here so clicks always use the current window geometry.
        update_dimensions()
        view.layout=ui.layout(state,options)
        state.mouse_inside=true
        if event.canceled then
            state.pressed=nil
            stop_hold()
            hold_consumed=false
            if state.drag then drag_update(true) end
            state.drag,state.drag_time,pressed_hit=nil,nil,nil
            schedule_hide(); request_render(); return
        end
        if event.event == "down" or event.event == "press" then
            update_hover()
            pressed_hit=current_hit()
            local menu_open=state.menu
            -- Outside clicks dismiss first; bottom controls still own their actions.
            if outside_menu(pressed_hit) then
                close_menu()
                if pressed_hit and pressed_hit.id == "settings" then pressed_hit=nil end
            end
            if state.opacity < 0.1 and not state.menu then
                pressed_hit=model.contains(view.layout.safe_area,state.mx,state.my) and view.layout.safe_area or nil
            end
            state.pressed=pressed_hit and pressed_hit.id
            stop_hold()
            hold_consumed=false
            if not pressed_hit and not menu_open and options.video_click then video_pressed=true; hold_timer:resume() end
            if pressed_hit and pressed_hit.id == "timeline" then state.drag="seek"
            elseif pressed_hit and pressed_hit.id == "volume" then state.drag="volume" end
            if pressed_hit and pressed_hit.id == "speed-slider" then state.drag="speed" end
            if state.drag then update_hover(); drag_update(false) end
            show()
        end
        if event.event == "up" or event.event == "press" then
            local video_tap=video_pressed
            local held=stop_hold()
            hold_consumed=false
            if state.drag then
                drag_update(true)
                state.drag,state.drag_time=nil,nil
            else
                local hit=current_hit()
                if held then show()
                elseif pressed_hit and hit and pressed_hit.id == hit.id then action(hit.action)
                elseif state.menu then close_menu()
                elseif video_tap and not pressed_hit and not hit and options.video_click then
                    -- Wait for a possible double-click before changing pause state.
                    if click_timer then click_timer:kill() end
                    click_timer=mp.add_timeout(mp.get_property_number("input-doubleclick-time",300)/1000,pause)
                end
            end
            pressed_hit=nil
            state.pressed=nil
            schedule_hide(); request_render()
        end
    end

    local function double_click()
        stop_hold()
        hold_consumed=false
        if click_timer then click_timer:kill() end
        pressed_hit=nil
        state.pressed=nil
        update_dimensions()
        view.layout=ui.layout(state,options)
        local hit=current_hit()
        if not hit then action({kind="fullscreen"}) end
    end

    -- Right clicks dismiss outside menus; UI capture prevents MPV's native pause binding.
    local function right_click()
        if state.idle then return end
        update_dimensions()
        view.layout=ui.layout(state,options)
        if outside_menu(current_hit()) then close_menu() end
        show()
    end

    -- Menus consume wheel scrolling inside their bounds; elsewhere it adjusts volume.
    local function wheel(direction)
        if state.menu and view.layout and model.contains(view.layout.menu,state.mx,state.my) then
            state.menu_focus=nil
            state.menu_scroll=model.clamp((state.menu_scroll or 0)-direction,0,math.max(0,#view.layout.menu.rows-view.layout.menu.visible))
            request_render()
        else volume(state.volume+direction*5) end
    end

    -- Capture the bottom strip, or the whole window while a menu owns outside clicks.
    mp.set_key_bindings({{"MBTN_RIGHT",right_click}},"mpvtube-controls","force")
    mp.enable_key_bindings("mpvtube-controls","allow-hide-cursor")
    -- Mouse capture supports dragging while retaining MPV's cursor/window-drag behavior elsewhere.
    mp.set_key_bindings({{"mouse_move",mouse_move},{"mouse_leave",function()
        stop_hold()
        state.pressed,pressed_hit=nil,nil
        state.mouse_inside,state.hover=false,nil
        if state.drag then drag_update(true) end
        state.drag,state.drag_time=nil,nil
        preview:hide(); schedule_hide(); request_render()
    end}},"mpvtube-motion","force")
    mp.enable_key_bindings("mpvtube-motion","allow-vo-dragging+allow-hide-cursor")
    mp.add_forced_key_binding("MBTN_LEFT","mouse-button",mouse_button,{complex=true})
    mp.add_forced_key_binding("MBTN_LEFT_DBL","double-click",double_click)
    mp.add_key_binding("WHEEL_UP","wheel-up",function() wheel(1) end)
    mp.add_key_binding("WHEEL_DOWN","wheel-down",function() wheel(-1) end)

    -- Normal keyboard bindings allow input.conf overrides; toggles never repeat on hold.
    if options.keyboard then
        local function change_speed(amount)
            local value=model.clamp(state.speed+amount,speed_controls.min,speed_controls.max)
            mp.set_property_number("speed",value)
            feedback(string.format("%.2g×",value),"speed")
            show()
        end
        local keys = {
            {"SPACE","play-pause",pause},{"k","play-pause-k",pause},
            {"j","rewind",function() relative_seek(-10) end},{"l","forward",function() relative_seek(10) end},
            {"LEFT","seek-left",function() relative_seek(-5) end},{"RIGHT","seek-right",function() relative_seek(5) end},
            {"UP","volume-up",function() volume(state.volume+5,true) end},{"DOWN","volume-down",function() volume(state.volume-5,true) end},
            {"m","mute",function() action({kind="mute",show_feedback=true}) end},{"f","fullscreen",function() action({kind="fullscreen"}) end},
            {"c","subtitles",subtitles},{"t","theater",function() action({kind="theater"}) end},
            {"i","mini-player",function() action({kind="pip"}) end},
            {"Shift+N","next",function() action({kind="next"}) end},{"Shift+P","previous",function() action({kind="previous"}) end},
            {".","frame-next",function() mp.commandv("frame-step"); show() end},
            {",","frame-previous",function() mp.commandv("frame-back-step"); show() end},
            {">","speed-up",function() change_speed(0.25) end},
            {"<","speed-down",function() change_speed(-0.25) end},
        }
        local repeatable={j=true,l=true,LEFT=true,RIGHT=true,UP=true,DOWN=true,["."]=true,[","]=true,[">"]=true,["<"]=true}
        for _, key in ipairs(keys) do mp.add_key_binding(key[1],key[2],key[3],{repeatable=repeatable[key[1]] or false}) end
        for digit=0,9 do
            local percent=digit/10
            mp.add_key_binding(tostring(digit),"seek-"..digit,function()
                local lo,hi=model.seek_window(state)
                if lo and hi then seek(lo+(hi-lo)*percent,true); show() end
            end)
        end
    end
    -- Escape is forced only while a menu is open; otherwise retain MPV's native action.
    mp.add_key_binding(nil,"close-menu",close_menu)

    -- A file change cancels the whole gesture, including a tap waiting for a double-click.
    local function reset_interaction()
        stop_hold()
        hold_consumed=false
        pressed_hit,state.pressed,state.drag,state.drag_time=nil,nil,nil,nil
        tooltip_timer:kill()
        if click_timer then click_timer:kill() end
    end
    mp.register_event("end-file",reset_interaction)
    mp.register_event("file-loaded",reset_interaction)
    mp.observe_property("pause","bool",function(_,paused) if paused then stop_hold() end end)
    mp.observe_property("speed","number",function(_,speed)
        if state.speed_hold and speed ~= 2 then stop_hold() end
    end)
    return {update_hover=update_hover, shutdown=reset_interaction}
end

return M
