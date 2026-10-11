-- Build menu rows from real player state, then draw the visible rows supplied by ui.view.
local model = require("core.model")
local speed_controls=model.speed_controls
local captions = require("core.captions")
local spacing=require("ui.draw").metrics
local timing=require("ui.motion").duration

local M = {}

-- The presets mirror YouTube; timer ownership stays in the player controller.
local function sleep_rows(state)
    local rows={{label="Off",value="",selected=not state.sleep_minutes,action={sleep=0}}}
    for _, minutes in ipairs({10,15,20,30,45,60}) do
        rows[#rows+1]={label=minutes.." minutes",value="",selected=state.sleep_minutes==minutes,action={sleep=minutes}}
    end
    return rows
end


local function track_label(state, kind, id)
    if kind == "sub" and not state.sub_visibility then return "Off" end
    local track=model.track(state.tracks,kind,id)
    return track and model.track_name(track) or kind == "sub" and "Off" or "None"
end

-- Menus are rebuilt from observed properties, including changes made by other scripts.
function M.rows(state, page)
    if captions.titles[page] then return captions.rows(state,page) end
    if page == "sleep" then return sleep_rows(state) end
    local rows = {}
    local function row(label, value, icon, action, selected, toggle)
        rows[#rows + 1] = {label=label, value=value, icon=icon, action=action,
            selected=selected, toggle=toggle}
    end
    if page == "settings" then
        row("Playback speed", state.speed == 1 and "Normal" or tostring(state.speed) .. "×", "speed", {page="speed"})
        row("Audio track", track_label(state, "audio", state.aid), "audio", {page="audio"})
        row("Subtitles/CC", track_label(state, "sub", state.sid), "cc", {page="sub"})
        if #model.tracks(state.tracks, "video") > 1 then
            row("Video track", track_label(state, "video", state.vid), "quality", {page="video"})
        end
        row("Loop video", "", "loop", {property="loop-file", value=state.loop_file == "no" and "inf" or "no"}, state.loop_file ~= "no", true)
        if #state.playlist > 1 then
            row("Autoplay", "", "play", {kind="autoplay"}, state.keep_open ~= "always", true)
            row("Playlist", tostring(state.playlist_pos+1).." / "..#state.playlist, "playlist", {page="playlist"})
        end
        row("Sleep timer", state.sleep_minutes and state.sleep_minutes.." minutes" or "Off", "sleep", {page="sleep"})
        row("Video information", "", "info", {page="info"})
    elseif page == "speed" then
        -- Three reusable rows keep the custom control scrollable in a short player.
        for _,kind in ipairs({"speed-value","speed-slider","speed-presets"}) do
            rows[#rows+1]={label="",value="",kind=kind}
        end
    elseif page == "audio" or page == "sub" or page == "video" then
        -- Track IDs come from MPV, so external tracks and nonconsecutive IDs work too.
        local property = ({audio="aid", sub="sid", video="vid"})[page]
        local subtitles_off = not state.sub_visibility or state.sid == "no" or state.sid == false
        if page == "sub" then row("Off", "", nil, {property="sub-visibility", value=false}, subtitles_off) end
        for _, track in ipairs(model.tracks(state.tracks, page)) do
            row(model.track_name(track), "", nil, {property=property, value=track.id},
                tostring(state[property]) == tostring(track.id) and (page ~= "sub" or not subtitles_off))
        end
        if #rows == 0 then row("No " .. page .. " tracks", "", nil) end
    elseif page == "chapters" then
        local _, current = model.chapter_at(state.chapters, state.time)
        for i, chapter in ipairs(state.chapters) do
            row(chapter.title, model.time(chapter.time), nil, {kind="seek", value=chapter.time}, i == current)
        end
    elseif page == "playlist" then
        for i, item in ipairs(state.playlist) do
            local title = item.title or (item.filename or "Untitled"):gsub(".*[/\\]", "")
            row(title, "", nil, {property="playlist-pos", value=i-1}, state.playlist_pos == i-1)
        end
    elseif page == "info" then
        local video = state.video or {}
        row("Resolution", video.w and string.format("%d × %d", video.w, video.h) or "Audio only")
        row("Video codec", state.video_codec or "—")
        row("Frame rate", state.fps and string.format("%.2f fps", state.fps) or "—")
        row("Audio codec", state.audio_codec or "—")
        row("Duration", state.duration and model.time(state.duration) or "Live / unknown")
    end
    return rows
end

M.titles = {settings="Settings", speed="Playback speed", audio="Audio track",
    sub="Subtitles/CC", video="Video track", chapters="Chapters", playlist="Playlist", sleep="Sleep timer", info="Video information"}
for page,title in pairs(captions.titles) do M.titles[page]=title end
function M.parent(page) return captions.titles[page] and captions.parent(page) or "settings" end

-- Panels share the player's 12 px inset; simple choices need less width than settings.
function M.geometry(state, options)
    local rows = M.rows(state,state.menu)
    local header = state.menu == "settings" and 0 or math.min(spacing.menu_header,state.h-126)
    local capacity = math.max(1,math.floor((state.h-100-header-2*spacing.menu_padding)/spacing.menu_row))
    local visible = math.min(#rows,capacity)
    local width = state.menu == "settings" and options.menu_width or state.menu == "speed" and 320 or 240
    width = math.max(width,model.text_width(M.titles[state.menu],14)+(state.menu == "sub" and 132 or 76))
    for _, row in ipairs(rows) do
        width = math.max(width,model.text_width(row.label,14)+model.text_width(row.value,14)
            +(row.icon and 96 or row.value ~= "" and 76 or 72)+(row.toggle and 48 or 0))
    end
    width = math.min(width,options.menu_width,state.w-2*spacing.inset)
    local height = header+visible*spacing.menu_row+2*spacing.menu_padding
    return {x=state.w-width-spacing.inset,y=state.h-spacing.menu_bottom-height,w=width,h=height,rows=rows,row_h=spacing.menu_row,
        header=header,padding=spacing.menu_padding,offset=model.clamp(state.menu_scroll or 0,0,math.max(0,#rows-visible)),
        visible=visible,page=state.menu}
end

-- Rendering consumes layout's clipped rows; passive information rows have no action.
local function render_panel(canvas,state,controls,options,background)
    local menu = controls.menu
    if not menu then return end
    if background then canvas:rect(menu.x,menu.y,menu.w,menu.h,"000000",options.menu_opacity,12) end
    if menu.header > 0 then
        for _,hit in ipairs(controls.hits) do
            if hit.id == "back" then hit.hover_inset=0; canvas:hover(hit)
            elseif hit.id == "caption-options" then hit.hover_inset,hit.hover_radius=0,4; canvas:hover(hit) end
        end
        canvas:icon("back",menu.x+24,menu.y+28,32)
        canvas:label("header",menu.x+48,menu.y+28,M.titles[menu.page])
        if menu.page == "sub" then
            canvas:label("header_action",menu.x+menu.w-18,menu.y+28,"Options","ffffff",6)
        end
        canvas:rect(menu.x,menu.y+56,menu.w,1,"ffffff",0.16)
    end
    for _, hit in ipairs(controls.hits) do
        local row = hit.row
        if row then
            local cy = hit.y+hit.h/2
            if row.kind == "speed-value" then
                canvas:label("speed",menu.x+menu.w/2,cy,string.format("%.2fx",state.speed),"ffffff",5)
            elseif row.kind == "speed-slider" then
                local slider=controls.speed
                local fraction=model.clamp((state.speed-speed_controls.min)/(speed_controls.max-speed_controls.min),0,1)
                canvas:circle(menu.x+32,cy,16,"ffffff",0.1)
                canvas:circle(menu.x+menu.w-32,cy,16,"ffffff",0.1)
                canvas:hover(controls.speed_down)
                canvas:hover(controls.speed_up)
                canvas:label("step",menu.x+32,cy,"-","ffffff",5)
                canvas:label("step",menu.x+menu.w-32,cy,"+","ffffff",5)
                canvas:rect(slider.x,cy-2,slider.w,4,"ffffff",0.3,2)
                canvas:rect(slider.x,cy-2,slider.w*fraction,4,"ffffff",1,2)
                canvas:circle(slider.x+slider.w*fraction,cy,6,"ffffff")
            elseif row.kind == "speed-presets" then
                for _,preset in ipairs(controls.speed_buttons) do
                    local selected=math.abs(state.speed-preset.value)<0.001
                    canvas:rect(preset.x,preset.y,preset.w,preset.h,"ffffff",selected and 0.9 or 0.1,16)
                    canvas:hover(preset,not selected and state.hover == preset.id)
                    canvas:label("preset",preset.x+preset.w/2,preset.y+16,preset.value==1 and "1.0" or tostring(preset.value),selected and "000000" or "ffffff",5)
                    if preset.value==1 then canvas:label("hint",preset.x+preset.w/2,preset.y+40,"Normal","ffffff",5) end
                end
            else
                canvas:hover(hit)
                if row.icon then canvas:icon(row.icon,menu.x+28,cy,24)
                elseif row.selected then canvas:icon("check",menu.x+26,cy,20) end
                -- Reserve columns for icons/checkmarks; plain rows share one text inset.
                local label_x = menu.x+(row.icon and 64 or row.selected ~= nil and 43 or 16)
                local value_w = row.value ~= "" and math.min(menu.w*0.47,model.text_width(row.value,14)+4) or 0
                local label_w = menu.x+menu.w-32-label_x-value_w-(row.toggle and 48 or 0)
                if row.value ~= "" then label_w=label_w-16 end
                canvas:label("body",label_x,cy,model.fit(row.label,label_w,14))
                if row.value ~= "" then
                    canvas:label("body",menu.x+menu.w-32,cy,model.fit(row.value,value_w,14),"dddddd",6)
                end
                if row.toggle then
                    canvas:toggle(menu.page..":"..row.label,menu.x+menu.w-36,cy,row.selected)
                elseif row.action and row.action.page then canvas:icon("menu_arrow",menu.x+menu.w-16,cy,18,"ffffff",0.7) end
            end
        end
    end
    -- The scroll thumb reflects row count rather than a fixed pixel travel distance.
    if #menu.rows > menu.visible then
        local track_h = menu.h-menu.header-10
        local thumb_h = math.max(20,track_h*menu.visible/#menu.rows)
        local ty = menu.y+menu.header+track_h*menu.offset/#menu.rows
        canvas:rect(menu.x+menu.w-6,ty,3,thumb_h,"ffffff",0.45,1.5)
    end
end

-- Fade opening/closing; page navigation shares a clipped, anchored resize/slide.
function M.render(canvas,state,controls,options)
    local motion=canvas.motion
    if not motion then render_panel(canvas,state,controls,options,true); return end
    local previous=motion.menu_controls
    local page=controls.menu and controls.menu.page
    if page ~= motion.menu_page then
        if page and previous and motion.menu_page then
            motion.old_menu,motion.menu_from=previous,motion.menu_frame or previous.menu
            motion.menu_direction=M.parent(motion.menu_page) == page and -1 or 1
            motion.menu_serial=(motion.menu_serial or 0)+1
            motion.menu_started=motion.now
        else motion.old_menu=nil end
        motion.menu_page=page
    end
    local opacity=canvas:animate("menu-opacity",page and 1 or 0,"menu",page and "enter" or "leave",0)
    controls.menu_transition,state.menu_transition=nil,nil
    if opacity <= 0 and not page then motion.menu_controls=nil; return end
    local content=page and controls or previous
    if not content then return end
    local panel=content.menu
    local progress=motion.old_menu and canvas:animate("menu-page:"..motion.menu_serial,1,"panel","standard",0) or 1
    if progress < 1 then
        local from=motion.menu_from
        panel={w=from.w+(panel.w-from.w)*progress,h=from.h+(panel.h-from.h)*progress}
        panel.x,panel.y=state.w-spacing.inset-panel.w,state.h-spacing.menu_bottom-panel.h
        panel.deadline=motion.menu_started+timing.panel
        controls.menu_transition,state.menu_transition=panel,panel
    else motion.old_menu=nil end
    motion.menu_frame=panel
    local layer=canvas:layer(opacity,panel)
    layer:rect(panel.x,panel.y,panel.w,panel.h,"000000",options.menu_opacity,12)
    local function paint(source,dx,old)
        local child=layer:layer(1,panel,panel.x-source.menu.x+dx,panel.y-source.menu.y)
        if old then child.motion,child.state=nil,{} end
        render_panel(child,state,source,options,false)
        canvas.events[#canvas.events+1]=child:finish()
    end
    canvas.events[#canvas.events+1]=layer:finish()
    -- Both pages travel the same distance so unequal widths cannot overlap at their seam.
    local travel=motion.old_menu and (motion.menu_direction == 1 and motion.old_menu.menu.w or content.menu.w) or 0
    if motion.old_menu then paint(motion.old_menu,-motion.menu_direction*progress*travel,true) end
    paint(content,motion.old_menu and motion.menu_direction*(1-progress)*travel or 0)
    if page then motion.menu_controls=controls end
end

return M
