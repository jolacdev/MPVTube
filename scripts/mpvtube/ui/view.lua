-- Compose ASS drawing layers; this facade also exposes layout helpers for callers/tests.
local model = require("core.model")
local speed_controls=model.speed_controls
local draw = require("ui.draw")
local menu = require("ui.menu")
local M = {menu_rows=menu.rows}
local clamp, contains = model.clamp, model.contains
local spacing=draw.metrics

-- The capsule, its revealed slider and a captured drag share one hover decision.
function M.volume_hover(state,layout)
    return state.drag == "volume" or state.focus == "mute" or state.hover == "mute" or state.hover == "volume" or
        layout and state.mouse_inside and contains(layout.volume_pill,state.mx,state.my)
end

-- Hits and visible buttons share rectangles, including expanded sliders and menu rows.
function M.layout(state, options)
    local w, h = state.w, state.h
    local compact = w < 540
    local cy = h-spacing.control_bottom-spacing.control_height/2
    local layout = {hits={},buttons={},pills={},timeline={x=spacing.inset,y=h-68,
        w=math.max(1,w-2*spacing.inset),h=20},cy=cy}
    local function hit(id, x, y, width, height, tip, action)
        local area = {id=id, x=x, y=y, w=width, h=height, tip=require("core.shortcuts").tip(state,action,tip), action=action}
        layout.hits[#layout.hits+1] = area
        return area
    end
    local function button(id, icon, x, width, tip, action, active)
        local control = hit(id,x,cy-spacing.control_height/2,width,spacing.control_height,tip,action)
        control.icon, control.active = icon, active
        layout.buttons[#layout.buttons+1] = control
        return control
    end
    -- Empty strip space consumes clicks too, including when controls are fading in.
    layout.safe_area = hit("controls-background",0,h-spacing.safe_height,w,spacing.safe_height,nil,{})
    local lo,hi=model.seek_window(state)
    layout.seek_lo,layout.seek_hi=lo,hi
    -- Buttons win where their top edge touches the generous timeline hit area.
    if lo and hi then hit("timeline",spacing.inset,h-spacing.safe_height,w-2*spacing.inset,28,nil,{kind="seek"}) end
    local x = spacing.inset
    local function pill(width)
        layout.pills[#layout.pills+1] = {x=x,y=cy-spacing.control_height/2,w=width,h=spacing.control_height}
        local start = x
        x = x+width+(compact and spacing.compact_gap or spacing.gap)
        return start
    end
    -- Pack essential controls from the left; hide extras as the window narrows.
    button("play", state.pause and "play" or "pause", pill(40), 40, state.pause and "Play (Space)" or "Pause (Space)", {kind="pause"})
    if #state.playlist > 1 and w >= 640 then
        local previous = state.playlist_pos > 0
        local width = previous and 80 or 40
        local start = pill(width)
        if previous then button("previous", "previous", start, 40, "Previous (Shift+P)", {kind="previous"}) end
        if state.playlist_pos < #state.playlist-1 then
            button("next", "next", start+(previous and 40 or 0), 40, "Next (Shift+N)", {kind="next"})
        elseif previous then
            -- The last item has only a previous control, so shrink its capsule.
            layout.pills[#layout.pills].w = 40
            x = start+40+spacing.gap
        end
    end
    if w>=1360 then
        local start=pill(80)
        local _,chapter_index=model.chapter_at(state.chapters,state.time)
        for _,entry in ipairs({{"chapter-previous","chapter_previous",-1,chapter_index and chapter_index>1},
            {"chapter-next","chapter_next",1,chapter_index and chapter_index<#state.chapters}}) do
            local control=button(entry[1],entry[2],start+(entry[3]>0 and 40 or 0),40,entry[3]>0 and "Next chapter (])" or "Previous chapter ([)",
                entry[4] and {kind="chapter-step",value=entry[3]} or nil)
            control.enabled=not not entry[4]
        end
    end
    local expand = compact and 0 or (state.volume_expand or 0)
    local volume_x = pill(40+71*expand)
    button("mute", (state.mute or state.volume <= 0) and "muted" or state.volume <= 50 and "volume_low" or "volume", volume_x, 40, state.mute and "Unmute (m)" or "Mute (m)", {kind="mute"})
    layout.volume = {x=volume_x+40, y=cy-20, w=52*expand, h=40}
    layout.volume_pill = layout.pills[#layout.pills]
    layout.volume_pill.id,layout.volume_pill.action="mute",{kind="mute"}
    if expand > 0.8 then hit("volume", layout.volume.x, layout.volume.y, layout.volume.w, 40, string.format("Volume: %.0f%%",state.volume), {kind="volume"}) end

    local right={}
    local function control(item) right[#right+1]=item end
    if #state.playlist>1 and w>=1000 then
        control({id="autoplay",icon="play",tip="Autoplay",action={kind="autoplay"},toggle=state.keep_open~="always"})
    end
    -- Small arrows flank one recognizable track icon instead of repeating that icon three times.
    for _,kind in ipairs({"sub","audio"}) do
        local count=#model.tracks(state.tracks,kind)
        local function arrow(direction)
            control({id=kind..(direction<0 and "-previous" or "-next"),icon=direction<0 and "left" or "right",width=24,size=16,
                tip=(direction<0 and "Previous " or "Next ")..(kind=="sub" and "subtitle" or "audio").." track",enabled=count>1,
                action=count>1 and {kind="track-step",track=kind,value=direction} or nil})
        end
        if w>=900 then arrow(-1) end
        local enabled=count>0 and state.sub_visibility and state.sid~="no" and state.sid~=false
        control({id=kind=="sub" and "cc" or "audio",icon=kind=="sub" and (enabled and "cc_active" or "cc") or "audio",
            tip=kind=="sub" and "Subtitles/CC" or "Audio track",enabled=count>0,
            action=count>0 and {page=kind} or nil,active=kind=="sub" and enabled,dismiss_menu=true})
        if w>=900 then arrow(1) end
    end
    control({id="settings",icon="settings",tip="Settings",action={page="settings"},active=state.menu~=nil,dismiss_menu=true})
    if not state.fullscreen and w>=760 and options.pip then
        control({id="pip",icon="pip",tip="Mini player",action={kind="pip"},active=state.pip})
    end
    control({id="fullscreen",icon=state.fullscreen and "exit_fullscreen" or "fullscreen",
        tip=state.fullscreen and "Exit full screen" or "Full screen",action={kind="fullscreen"}})
    if compact then
        local by_id={}
        for _,item in ipairs(right) do by_id[item.id]=item end
        local expand={id="expand",icon=state.controls_expanded and "right" or "left",
            tip=state.controls_expanded and "Close" or "Expand",action={kind="expand"}}
        right=state.controls_expanded and {expand,by_id.audio,by_id.cc,by_id.settings,by_id.fullscreen} or {expand,by_id.settings}
    end
    local right_w=8
    for _,item in ipairs(right) do right_w=right_w+(compact and 36 or item.width or 48) end
    local right_x=w-spacing.inset-right_w
    layout.pills[#layout.pills+1]={x=right_x,y=cy-20,w=right_w,h=40}
    local control_x=right_x+4
    for _,item in ipairs(right) do
        local width=compact and 36 or item.width or 48
        local area=button(item.id,item.icon,control_x,width,item.tip,item.action,item.active)
        area.icon_size=item.size or 24
        if compact then area.y,area.h,area.icon_size=cy-16,32,20 end
        area.toggle,area.enabled=item.toggle,item.enabled
        area.dismiss_menu=item.dismiss_menu
        area.hover_width,area.hover_height=width,spacing.control_height-2*spacing.hover_inset
        control_x=control_x+width
    end
    -- Size time from its current label, then fall back to current-only text if space is tight.
    if w >= 370 and not (compact and state.controls_expanded) then
        local current = state.time_remaining and state.duration and "-"..model.time(state.duration-state.time) or model.time(state.time)
        local label = current..(state.duration and " / "..model.time(state.duration) or "  LIVE")
        local time_x = x-(compact and 0 or 4)
        local measure=state.measure_text or model.text_width
        local style=draw.text_styles.timer
        local text_width=measure(label,style[1],style[2])
        if w < 460 or time_x+text_width+40 > right_x then label=current; text_width=measure(label,style[1],style[2]) end
        local width = text_width+32
        if time_x+width+8 <= right_x then
            x=time_x
            local start=pill(width)
            layout.time=hit("time",start,cy-20,width,40,"Elapsed / remaining time",state.duration and {kind="time"} or nil)
            layout.time.text=label
            x=x-(compact and 0 or 4)
        end
    end
    local chapter = model.chapter_at(state.chapters, state.time)
    local available = right_x-x-spacing.gap
    if chapter and available >= 40 and not compact then
        local cw = math.min(342,model.text_width(chapter.title,13)+52,available)
        local start = pill(cw)
        layout.chapter = {x=start+16, width=math.max(0,cw-48), title=chapter.title,button_x=start,button_width=cw}
        layout.chapter.area=hit("chapter",start,cy-20,cw,40,"Chapters",{page="chapters"})
        layout.buttons[#layout.buttons+1] = {id="chapter-arrow", x=start+cw-32, y=cy-20, w=26, h=40, icon="right",icon_size=20}
    end
    if options.title and w > 360 then
        if state.fullscreen then layout.title = {x=24, y=34, width=w-144} end
        layout.info = true
        layout.info_area=hit("info",w-46,10,32,32,"Video information",{page="info"})
        layout.info_area.hover_inset,layout.info_area.top=0,true
    end
    -- Top tools reuse button drawing, hover and focus; they do not occupy the playback bar.
    local native=button("native-menu","native_menu",w-46-(layout.info and 44 or 0),32,"MPV menu (Ctrl+P)",state.native_tools~=false and {kind="native-menu"} or nil)
    native.y,native.h,native.icon_size,native.hover_inset,native.top=10,32,24,0,true
    native.enabled=state.native_tools~=false

    -- Fit and scroll rows within the window; append menu hits last so they take priority.
    if state.menu then
        local first_menu_hit=#layout.hits+1
        local panel = menu.geometry(state,options)
        layout.menu = panel
        hit("menu", panel.x, panel.y, panel.w, panel.h)
        if state.menu ~= "settings" then hit("back",panel.x+8,panel.y+(panel.header-30)/2,32,30,nil,{page=menu.parent(state.menu)}) end
        if state.menu == "sub" then hit("caption-options",panel.x+panel.w-76,panel.y,68,panel.header,nil,{page="captions"}) end
        for i = 1, panel.visible+panel.pinned do
            local pinned=i>panel.visible
            local index=pinned and #panel.rows or panel.offset+i
            local row = panel.rows[index]
            local area=hit("row-"..index,panel.x+panel.padding,panel.y+panel.header+panel.padding+(i-1)*panel.row_h,
                panel.w-2*panel.padding,pinned and panel.footer_h or panel.row_h,nil,row.action)
            area.row,area.index = row,index
            area.hover_inset,area.hover_radius=0,0
            area.pinned=pinned
            if row.kind == "speed-slider" then
                local center_y=area.y+24
                layout.speed={x=panel.x+64,y=center_y-12,w=panel.w-128,h=24}
                hit("speed-slider",layout.speed.x,layout.speed.y,layout.speed.w,24,nil,{kind="speed-slider"})
                layout.speed_down=hit("speed-down",panel.x+16,center_y-16,32,32,nil,{speed_step=-speed_controls.step})
                layout.speed_up=hit("speed-up",panel.x+panel.w-48,center_y-16,32,32,nil,{speed_step=speed_controls.step})
                layout.speed_down.hover_inset,layout.speed_up.hover_inset=0,0
            elseif row.kind == "speed-presets" then
                layout.speed_buttons={}
                local button_width=(panel.w-56)/4
                for preset_index,value in ipairs(speed_controls.presets) do
                    local preset=hit("speed-"..value,panel.x+16+(preset_index-1)*(button_width+8),area.y,button_width,32,nil,{speed=value})
                    preset.value=value
                    preset.hover_inset=0
                    layout.speed_buttons[#layout.speed_buttons+1]=preset
                end
            end
        end
        -- Page rows have separate animation keys; opening a menu does not restart bar hovers.
        for index=first_menu_hit,#layout.hits do layout.hits[index].group=state.menu end
    end
    return layout
end

-- Reverse paint order makes the topmost menu/control receive an overlapping click.
function M.hit(layout,x,y)
    for i = #layout.hits, 1, -1 do
        if contains(layout.hits[i], x, y) then return layout.hits[i] end
    end
end


-- Draw cache ranges, chapter gaps and hover labels from the same seek geometry.
function M.render_timeline(canvas, state, controls, options)
    local lo, hi = controls.seek_lo, controls.seek_hi
    local y = state.h-spacing.timeline_bottom
    if not lo or not hi or hi <= lo then
        canvas:rect(12,y-1.5,state.w-24,3,"ffffff",0.18,1.5)
        return
    end
    local x, width = spacing.inset,state.w-2*spacing.inset
    local function position(time) return x+clamp((time-lo)/(hi-lo),0,1)*width end
    local hovering = not state.menu and (state.hover == "timeline" or state.drag == "seek")
    local thickness = 3+3*(state.timeline_expand or 0)
    local chapters = (#state.chapters > 0 and lo == 0) and state.chapters or {{time=lo}}
    local progress = position(state.drag_time or state.time)
    local ranges=(state.cache or {})["seekable-ranges"] or {}
    -- Clip cache and elapsed layers to each chapter, preserving the gaps between them.
    for i, chapter in ipairs(chapters) do
        local start = position(chapter.time)
        local finish = position(chapters[i+1] and chapters[i+1].time or hi)
        local gap = i < #chapters and math.min(4,(finish-start)/4) or 0
        finish = finish-gap
        canvas:rect(start,y-thickness/2,finish-start,thickness,"ffffff",0.22,1)
        for _, range in ipairs(ranges) do
            if range.start and range["end"] then
                local a, b = math.max(start,position(range.start)), math.min(finish,position(range["end"]))
                canvas:rect(a,y-thickness/2,b-a,thickness,"ffffff",0.40,1)
            end
        end
        -- Duration is only a fallback; painting it over real ranges would brighten overlaps.
        if #ranges == 0 and state.cache_time and state.cache_time > 0 then
            local a, b = math.max(start,position(state.time)), math.min(finish,position(state.time+state.cache_time))
            canvas:rect(a,y-thickness/2,b-a,thickness,"ffffff",0.40,1)
        end
        canvas:rect(start,y-thickness/2,math.min(finish,progress)-start,thickness,options.accent,1,1)
    end
    -- The supplied screenshots keep the red handle visible even without hover.
    canvas:circle(progress,y,6+3*(state.timeline_expand or 0),options.accent)
    -- Keep hover labels and the separate bitmap preview inside the window edges.
    if hovering and state.mouse_inside then
        local hover_time = lo+clamp((state.mx-x)/width,0,1)*(hi-lo)
        local chapter = model.chapter_at(state.chapters,hover_time)
        local preview = state.preview
        local preview_width = preview and preview.w or math.min(options.thumbnail_width or 200,state.w-24)
        local center_x = clamp(state.mx,12+preview_width/2,state.w-12-preview_width/2)
        -- Anchor to the timeline so loading or missing images cannot move the timestamp.
        local label_y = y-48
        if preview then
            local preview_y = label_y-28-preview.h
            canvas:rect(center_x-preview_width/2-1,preview_y-1,preview_width+2,preview.h+2,"ffffff",0.95,8)
            controls.preview = {x=center_x-preview_width/2,y=preview_y,w=preview_width,h=preview.h,time=hover_time,entry=preview.entry}
        end
        -- Timestamp and current chapter share one capsule below the preview image.
        local timestamp = model.time(hover_time)
        local time_width = model.text_width(timestamp,13)
        local label_width = chapter and preview_width or time_width+32
        canvas:rect(center_x-label_width/2,label_y-15.5,label_width,31,"000000",0.6,16)
        if chapter then
            local text_x = center_x-label_width/2+16
            canvas:label("tooltip",text_x,label_y,timestamp)
            canvas:label("chapter",text_x+time_width+12,label_y,model.fit(chapter.title,label_width-time_width-44,13))
        else canvas:label("tooltip",center_x,label_y,timestamp,"ffffff",5) end
    end
end


-- Seeks use signed labels and rounded chevrons at the edges; other feedback stays centered.
local function feedback(canvas, state, options, controls)
    local feedback_item = state.feedback
    if not feedback_item or feedback_item.opacity <= 0 then return end
    local feedback_canvas = draw.new(feedback_item.opacity,options.font,nil,state)
    local y = state.h/2
    if feedback_item.kind == "seek" then
        local inset = math.min(48,state.w*0.06)
        local left = feedback_item.side == "left"
        local offset=feedback_item.offset or 0
        feedback_canvas:icon(left and "seek_left" or "seek_right",left and inset+11+offset or state.w-inset-11-offset,y,24)
        feedback_canvas:label("seek",left and inset+42 or state.w-inset-42,y,
            (left and "− " or "+ ")..tostring(feedback_item.amount),"ffffff",left and 4 or 6)
    else
        local has_text = feedback_item.text and feedback_item.text ~= ""
        -- Keep the icon centered; all feedback text uses the same separate top card as volume.
        local scale=(feedback_item.scale or 1)*math.min(1,state.h/300)
        -- Menus already identify the action; a text card avoids covering their choices.
        if not controls.menu then
            feedback_canvas:circle(state.w/2,y,39*scale,"000000",0.6)
            if feedback_item.icon then feedback_canvas:icon(feedback_item.icon,state.w/2,y,54*scale) end
        end
        if has_text then
            local height=state.h<300 and 31 or 45
            local cy=controls.menu and spacing.inset+height/2 or state.h*.1+height/2
            feedback_canvas:badge(state.h<300 and "body" or "percentage",state.w/2,cy,
                feedback_item.text,state.w-2*spacing.inset,height)
        end
    end
    canvas.events[#canvas.events+1] = feedback_canvas:finish()
end

-- Retain a departing tooltip only for its fade; all tooltip motion uses the shared engine.
local function render_tooltip(canvas,state,controls,options)
    local content
    local delay=options.animations==false and 0 or options.tooltip_delay
    if not state.menu and state.hover and (state.hover_age or 0) >= delay then
        for _,hit in ipairs(controls.hits) do
            if hit.id == state.hover and hit.tip then
                local width=model.text_width(hit.tip,13)+20
                content={w=width,x=clamp(hit.x+hit.w/2,width/2+spacing.inset,state.w-width/2-spacing.inset),
                    y=hit.y-37,text=hit.tip}
                break
            end
        end
    end
    local animation=canvas.motion
    local opacity=canvas:animate("tooltip",content and 1 or 0,"tooltip","modern",0)
    if animation then
        if content then animation.tooltip=content end
        content=content or animation.tooltip
        if opacity <= 0 then animation.tooltip=nil end
    end
    if not content or opacity <= 0 then return end
    local layer=canvas:layer(opacity)
    layer:badge("tooltip",content.x,content.y,content.text,state.w-2*spacing.inset,31,10,16)
    canvas.events[#canvas.events+1]=layer:finish()
end

function M.render(state, options, motion)
    local canvas = draw.new(state.opacity,options.font,motion,state)
    local controls = M.layout(state, options)
    if state.opacity > 0 then
        -- Draw shared control capsules without a bottom scrim.
        if controls.title then
            canvas:title_scrim(state.w)
            canvas:label("title",controls.title.x,controls.title.y,model.fit(state.title,controls.title.width,20),"ffffff",4)
        end
        if controls.info then
            canvas:hover(controls.info_area)
            canvas:icon("top_info",state.w-30,26,36)
        end
        for _, pill in ipairs(controls.pills) do canvas:rect(pill.x,pill.y,pill.w,pill.h,"000000",spacing.capsule_opacity,20) end
        canvas:hover(controls.volume_pill,M.volume_hover(state,controls))
        for _, button in ipairs(controls.buttons) do
            local cx, cy = button.x+button.w/2, button.y+button.h/2
            if button.id ~= "mute" then canvas:hover(button) end
            if button.toggle ~= nil then
                canvas:toggle(button.id,cx,cy,button.toggle,true)
            elseif button.id == "mute" then canvas:volume_icon(button.icon,cx,cy,button.icon_size or 24)
            else
                local rotation
                if button.id == "settings" then rotation=canvas:animate("gear",button.active and 30 or 0,"gear","leave")
                elseif button.id == "expand" then rotation=canvas:animate("expand",state.controls_expanded and 180 or 0,"expand") end
                canvas:icon(button.id == "expand" and "left" or button.icon,cx,cy,button.icon_size or 24,
                    "ffffff",button.enabled == false and 0.5 or 1,rotation)
            end
            -- The quality badge describes the loaded stream, not selectable online resolutions.
            if button.id == "settings" and state.video and state.video.h and state.video.h >= 720 then
                local badge=state.video.h >= 2160 and "4K" or "HD"
                canvas:rect(cx+7,cy-13,13,8,options.accent,1,1)
                canvas:label("badge",cx+13.5,cy-9,badge,"ffffff",5)
            end
        end
        if controls.time then
            canvas:hover(controls.time)
            canvas:label("timer",controls.time.x+controls.time.w/2,controls.cy,controls.time.text,nil,5)
        end
        if controls.chapter then
            canvas:hover(controls.chapter.area,state.hover == "chapter" or state.focus=="chapter" or state.menu == "chapters")
            if controls.chapter.width >= 18 then canvas:label("chapter",controls.chapter.x,controls.cy,model.fit(controls.chapter.title,controls.chapter.width,13)) end
        end
        if controls.volume.w > 1 then
            local maximum=state.volume_max or options.volume_max or 200
            local v = clamp(state.mute and 0 or state.volume,0,maximum)/maximum
            -- The 12 px knob travels inside the panel; clip it while that panel expands.
            local panel=canvas:layer(1,controls.volume)
            local knob=6+math.max(0,controls.volume.w-12)*v
            panel:rect(controls.volume.x,controls.cy-1,controls.volume.w,2,"ffffff",0.28,1)
            panel:rect(controls.volume.x,controls.cy-1,knob,2,"ffffff",1,1)
            panel:circle(controls.volume.x+knob,controls.cy,6,"ffffff")
            canvas.events[#canvas.events+1]=panel:finish()
        end
        M.render_timeline(canvas,state,controls,options)
        menu.render(canvas,state,controls,options)
        render_tooltip(canvas,state,controls,options)
    end
    -- Feedback has its own opacity so key presses remain visible when controls are hidden.
    -- A centered workspace owns this space; transient playback icons must not cover its rows.
    if not (controls.menu and controls.menu.wide) then feedback(canvas,state,options,controls) end
    -- Temporary speed sits above the video, independent of control visibility.
    if state.speed_hold then
        local badge=draw.new(1,options.font)
        badge:rect(state.w/2-36,16,72,31,"000000",0.6,16)
        badge:text(state.w/2-9,31.5,"2x",14,"ffffff",5,1,true)
        badge:icon("seek_right",state.w/2+13,31.5,15)
        badge:icon("seek_right",state.w/2+20,31.5,15)
        canvas.events[#canvas.events+1]=badge:finish()
    end
    return canvas:finish(), controls
end

return M
