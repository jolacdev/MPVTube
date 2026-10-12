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
    local close_menu = player.close_menu
    local click_timer
    local focus_keys_bound=false
    local update_focus
    local function current_hit()
        return view.layout and ui.hit(view.layout,state.mx,state.my,mp.get_time()) or nil
    end
    local function outside_menu(hit)
        return state.menu and not (hit and (hit.id == "menu" or hit.group == state.menu))
    end
    local tooltip_timer = mp.add_timeout(options.tooltip_delay,request_render,true)

    -- Focus is a stable hit ID plus menu page, never a stale rectangle after resize.
    local function clear_focus(close)
        state.focus,state.focus_group,state.menu_focus=nil,nil,nil
        if close and state.menu then close_menu() end
        if update_focus then update_focus() end
        request_render()
    end
    local function focus(area)
        state.focus,state.focus_group=area.id,area.group
        state.menu_focus=area.index
        state.hover=nil
        preview:hide();show()
        if update_focus then update_focus() end
    end
    local function focusable(layout)
        local result={}
        for _,area in ipairs(layout.hits) do
            if area.action and next(area.action) and area.enabled~=false and area.id~="volume" and area.id~="timeline"
                and (not state.menu or area.group==state.menu) then result[#result+1]=area end
        end
        table.sort(result,function(a,b)
            if not state.menu then
                if a.top~=b.top then return not a.top end
                return a.x<b.x
            end
            local ay,by=a.y+a.h/2,b.y+b.h/2
            if math.abs(ay-by)<1 then return a.x<b.x end
            return ay<by
        end)
        if layout.seek_lo and not state.menu then
            for _,area in ipairs(layout.hits) do if area.id=="timeline" then result[#result+1]=area;break end end
        end
        return result
    end
    local function cycle_focus(direction)
        if state.idle then return end
        update_dimensions()
        view.layout=ui.layout(state,options)
        local areas=focusable(view.layout)
        if #areas==0 then return end
        local index=direction>0 and 0 or 1
        for i,area in ipairs(areas) do if area.id==state.focus and area.group==state.focus_group then index=i;break end end
        focus(areas[(index-1+direction)%#areas+1])
    end
    local function focused_hit()
        for _,area in ipairs((view.layout or {}).hits or {}) do
            if area.id==state.focus and area.group==state.focus_group then return area end
        end
    end
    local function activate_focus()
        local area=focused_hit()
        if not area then return end
        local page=state.menu
        action(area.action)
        if state.menu and state.menu~=page and not state.focus then
            local layout=ui.layout(state,options)
            view.layout=layout
            for _,hit in ipairs(layout.hits) do if hit.group==state.menu and hit.action then focus(hit);break end end
        end
        show()
    end
    -- Reuse the same reveal/focus path for arrow navigation and shortcut-recording results.
    local function focus_menu_row(panel,index)
        if index<=#panel.rows-panel.pinned then
            state.menu_scroll=model.clamp(panel.offset,index-panel.visible,index-1)
        end
        view.layout=ui.layout(state,options)
        for _,area in ipairs(view.layout.hits) do if area.index==index then focus(area);break end end
    end
    view.focus_menu_action=function(operation)
        local panel=require("ui.menu").geometry(state,options)
        for index,row in ipairs(panel.rows) do
            if row.action and row.action.shortcut==operation then focus_menu_row(panel,index);return end
        end
    end
    -- Up/down traverses the whole menu, scrolling focused rows into view.
    local function menu_move(direction,edge)
        if state.menu=="speed" then
            player.speed(edge and (direction>0 and speed_controls.min or speed_controls.max) or mp.get_property_number("speed",state.speed)-direction*speed_controls.step)
            return
        end
        local panel=require("ui.menu").geometry(state,options)
        local index=edge and (direction>0 and 0 or #panel.rows+1) or state.menu_focus or panel.offset+(direction>0 and 0 or panel.visible+1)
        repeat index=index+direction until index<1 or index>#panel.rows or panel.rows[index].action
        if index<1 or index>#panel.rows then return end
        focus_menu_row(panel,index)
    end
    local function navigate(key)
        -- MPV may already have queued this handler before a preceding clear event ran.
        -- Forward stale events to the effective playback binding, respecting keyboard ownership.
        if not state.menu and not state.focus then
            local bindings={}
            for _,binding in ipairs(mp.get_property_native("input-bindings",{})) do
                if not binding.cmd:find(mp.get_script_name().."/focus-",1,true) and not binding.cmd:find(mp.get_script_name().."/menu-escape",1,true) then
                    bindings[#bindings+1]=binding
                end
            end
            for _,binding in ipairs(require("core.shortcuts").effective(state,bindings)) do
                if binding.key==key then mp.command(binding.cmd);break end
            end
            return
        end
        key=key:match("([^+]+)$")
        if key=="ESC" then
            if state.menu and state.menu~="settings" then player.open_menu(require("ui.menu").parent(state.menu));clear_focus(false)
            else clear_focus(true) end
        elseif key=="ENTER" or key=="SPACE" then
            if state.menu=="speed" and not state.focus then close_menu() else activate_focus() end
        elseif state.menu and (not state.focus or state.focus_group==state.menu) and (key=="UP" or key=="DOWN") then
            menu_move(key=="UP" and -1 or 1)
        else
            local hit=focused_hit()
            local direction=(key=="LEFT" or key=="DOWN") and -1 or 1
            local edge=key=="HOME" or key=="END"
            if hit and (hit.id=="mute" or hit.id=="volume") then
                volume(edge and (key=="HOME" and 0 or state.volume_max or 200) or mp.get_property_number("volume",state.volume)+direction*(options.volume_step or 5),true)
            elseif hit and hit.id=="speed-slider" then
                player.speed(edge and (key=="HOME" and speed_controls.min or speed_controls.max) or mp.get_property_number("speed",state.speed)+direction*speed_controls.step)
            elseif hit and hit.id=="timeline" then
                if edge then
                    local lo,hi=model.seek_window(state)
                    if lo and hi then seek(key=="HOME" and lo or hi,true) end
                else relative_seek(direction*(options.seek_short or 5)) end
            elseif edge and state.menu and (not hit or hit.group==state.menu) then menu_move(key=="HOME" and 1 or -1,true)
            elseif state.menu and key=="LEFT" then player.open_menu(require("ui.menu").parent(state.menu));clear_focus(false)
            elseif key=="HOME" or key=="END" then
                clear_focus(false);cycle_focus(key=="HOME" and 1 or -1)
            else cycle_focus(direction) end
        end
        show()
    end
    -- Keep callbacks registered so already queued key events survive section deactivation.
    local navigation_keys={"ESC","UP","DOWN","LEFT","RIGHT","ENTER","SPACE","HOME","END"}
    for _,modifier in ipairs({"Shift+","Ctrl+","Ctrl+Alt+"}) do
        for _,key in ipairs({"UP","DOWN","LEFT","RIGHT"}) do navigation_keys[#navigation_keys+1]=modifier..key end
    end
    local routes={}
    local script_name=mp.get_script_name()
    for _,key in ipairs(navigation_keys) do
        local name=key=="ESC" and "menu-escape" or "focus-"..key
        mp.add_key_binding(nil,name,function() navigate(key) end,
            {repeatable=key:match("UP$")~=nil or key:match("DOWN$")~=nil or key:match("LEFT$")~=nil or key:match("RIGHT$")~=nil})
        routes[#routes+1]=key.." nonscalable script-binding "..script_name.."/"..name
    end
    mp.commandv("define-section","mpvtube-focus",table.concat(routes,"\n"),"force")
    update_focus=function()
        if state.focus then
            local hit=focused_hit()
            if not hit or not hit.action or hit.enabled==false then clear_focus(false) end
        end
        local active=state.menu~=nil or state.focus~=nil
        if active==focus_keys_bound then return end
        focus_keys_bound=active
        if active then mp.commandv("enable-section","mpvtube-focus","allow-hide-cursor+allow-vo-dragging")
        else mp.commandv("disable-section","mpvtube-focus") end
    end

    view.update_focus=update_focus

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
            volume((state.mx-view.layout.volume.x)/view.layout.volume.w*(state.volume_max or 200))
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
        if state.focus or state.menu_focus then clear_focus(false) end
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
            clear_focus(false)
            update_hover()
            pressed_hit=current_hit()
            local menu_open=state.menu
            -- Settings, CC and Audio dismiss any open panel; other controls keep their actions.
            if outside_menu(pressed_hit) then
                local page=pressed_hit and pressed_hit.action and pressed_hit.action.page
                local trigger=pressed_hit and (pressed_hit.dismiss_menu or page==state.menu)
                close_menu()
                if trigger then pressed_hit=nil end
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
            clear_focus(false)
            state.menu_scroll=model.clamp((state.menu_scroll or 0)-direction,0,math.max(0,#view.layout.menu.rows-view.layout.menu.pinned-view.layout.menu.visible))
            request_render()
        else volume(mp.get_property_number("volume",state.volume)+direction*(options.volume_step or 5)) end
    end

    -- Capture the bottom strip, or the whole window while a menu owns outside clicks.
    mp.set_key_bindings({{"MBTN_RIGHT",right_click}},"mpvtube-controls","force")
    mp.enable_key_bindings("mpvtube-controls","allow-hide-cursor")
    local function mouse_leave()
        stop_hold()
        state.pressed,pressed_hit=nil,nil
        state.mouse_inside,state.hover=false,nil
        if state.drag then drag_update(true) end
        state.drag,state.drag_time=nil,nil
        preview:hide();schedule_hide();request_render()
    end
    local function execute(descriptor)
        if descriptor.kind=="focus" then cycle_focus(descriptor.value)
        elseif descriptor.kind=="clear-focus" then clear_focus(true)
        else action(descriptor) end
    end
    view.open_menu=player.open_menu
    local shortcuts=require("core.shortcuts").new(state,options,view,execute,{
        {key="MOUSE_MOVE",id="mouse_move",callback=mouse_move},
        {key="MOUSE_LEAVE",id="mouse-leave",callback=mouse_leave},
        {key="MBTN_LEFT",id="mouse-button",callback=mouse_button,complex=true},
        {key="MBTN_LEFT_DBL",id="double-click",callback=double_click},
        {key="WHEEL_UP",id="wheel-up",callback=function() wheel(1) end},
        {key="WHEEL_DOWN",id="wheel-down",callback=function() wheel(-1) end},
        {key="CLOSE_WIN",id="close-window",callback=function() mp.commandv("quit") end},
    })
    mp.add_key_binding(nil,"close-menu",close_menu)

    -- A file change cancels the whole gesture, including a tap waiting for a double-click.
    local function reset_interaction()
        if view.cancel_key_capture then view.cancel_key_capture() end
        stop_hold()
        hold_consumed=false
        pressed_hit,state.pressed,state.drag,state.drag_time=nil,nil,nil,nil
        state.menu=nil
        clear_focus(false)
        tooltip_timer:kill()
        if click_timer then click_timer:kill() end
    end
    mp.register_event("end-file",reset_interaction)
    mp.register_event("file-loaded",reset_interaction)
    mp.observe_property("pause","bool",function(_,paused) if paused then stop_hold() end end)
    mp.observe_property("speed","number",function(_,speed)
        if state.speed_hold and speed ~= 2 then stop_hold() end
    end)
    return {update_hover=update_hover,update_focus=update_focus,shutdown=function()
        reset_interaction();state.menu=nil;update_focus();shortcuts.shutdown()
    end}
end

return M
