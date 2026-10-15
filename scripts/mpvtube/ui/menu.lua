-- Build menu rows from real player state, then draw the visible rows supplied by ui.view.
local model = require("core.model")
local speed_controls=model.speed_controls
local captions = require("core.captions")
local spacing=require("ui.draw").metrics
local shortcuts=require("core.shortcuts")

local M = {}

local function track_label(state, kind, id)
    if kind == "sub" and not state.sub_visibility then return "Off" end
    local track=model.track(state.tracks,kind,id)
    return track and model.track_name(track) or kind == "sub" and "Off" or "None"
end

-- Menus are rebuilt from observed properties, including changes made by other scripts.
function M.rows(state, page, options)
    if captions.titles[page] then return captions.rows(state,page) end
    local rows = {}
    local function row(label, value, icon, action, selected, toggle)
        rows[#rows + 1] = {label=label, value=value, icon=icon, action=action,
            selected=selected, toggle=toggle, shortcut=shortcuts.hint(state,action),disabled=page=="controls" and not action}
    end
    local function section(label) rows[#rows+1]={label=label,value="",kind="section"} end
    local function notice(text,tone)
        row(text,"")
        rows[#rows].kind,rows[#rows].pinned,rows[#rows].tone="notice",true,tone or "info"
    end
    local function status(default)
        local tone=state.keymap_tone or "info"
        notice((tone=="error" and "Error: " or tone=="success" and "Success: " or "")..(state.keymap_message or default),tone)
    end
    if page == "settings" then
        row("Playback speed", state.speed == 1 and "Normal" or tostring(state.speed) .. "×", "speed", {page="speed"})
        row("Audio track", track_label(state, "audio", state.aid), "audio", {page="audio"})
        row("Subtitles/CC", track_label(state, "sub", state.sid), "cc", {page="sub"})
        if #model.tracks(state.tracks, "video") > 1 then
            row("Video track", track_label(state, "video", state.vid), "quality", {page="video"})
        end
        row("Export tracks",state.export_ready and "" or "FFmpeg required","export",state.export_ready and {page="exports"} or nil)
        rows[#rows].disabled=not state.export_ready
        row("Loop video", "", "loop", {property="loop-file", value=state.loop_file == "no" and "inf" or "no"}, state.loop_file ~= "no", true)
        row("Animations", "", "animations", {kind="animations"}, not options or options.animations~=false, true)
        if #state.playlist > 1 then
            row("Autoplay", "", "play", {kind="autoplay"}, state.keep_open ~= "always", true)
            row("Playlist", tostring(state.playlist_pos+1).." / "..#state.playlist, "playlist", {page="playlist"})
        end
        row("More controls", "", "controls", {page="controls"})
        row("Shortcut guide", "", "keyboard", {page="shortcuts"})
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
        if page == "sub" then
            row("Clean subtitle style", "", "cc", {kind="subtitle-override"},(state.caption_style or {})["sub-ass-override"]=="strip",true)
            rows[#rows].pinned=true
        end
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
    elseif page == "controls" then
        local _,chapter_index=model.chapter_at(state.chapters,state.time)
        section("Chapters and playlist")
        row("Playlist", "", "playlist", #state.playlist>0 and {page="playlist"} or nil)
        row("Chapters", "", "chapter_next", #state.chapters>0 and {page="chapters"} or nil)
        for _,item in ipairs({{"Previous video","previous",state.playlist_pos>0},
            {"Next video","next",state.playlist_pos<#state.playlist-1}}) do
            row(item[1],"",item[2],item[3] and {kind=item[2]} or nil)
        end
        for _,direction in ipairs({{-1,"Previous"},{1,"Next"}}) do
            local available=chapter_index and state.chapters[chapter_index+direction[1]]
            row(direction[2].." chapter","",direction[1]<0 and "chapter_previous" or "chapter_next",available and {kind="chapter-step",value=direction[1]} or nil)
        end
        for _,kind in ipairs({"sub","audio"}) do
            section(kind=="sub" and "Subtitles" or "Audio")
            row(kind=="sub" and "Subtitles/CC" or "Audio track","",kind=="sub" and "cc" or "audio",{page=kind})
            if kind=="sub" then row("Toggle subtitles","","cc",#model.tracks(state.tracks,kind)>0 and {kind="subtitles"} or nil) end
            for _,direction in ipairs({{-1,"Previous"},{1,"Next"}}) do
                row(direction[2]..(kind=="sub" and " subtitle track" or " audio track"),"",kind=="sub" and "cc" or "audio",
                    #model.tracks(state.tracks,kind)>1 and {kind="track-step",track=kind,value=direction[1]} or nil)
            end
        end
        section("Playback")
        row("Time remaining","","info",state.duration and {kind="time"} or nil,state.time_remaining or false,true)
        local video=model.track(state.tracks,"video",state.vid)
        row("Previous frame","","seek_left",video and not video.image and {kind="frame",value=-1} or nil)
        row("Next frame","","seek_right",video and not video.image and {kind="frame",value=1} or nil)
        section("Synchronization")
        row("Adjust delays","","sync",{page="sync"})
        row("Reset synchronization","","sync",{kind="sync-reset"})
        section("Window and tools")
        if not options or options.pip then row("Mini player","","pip",{kind="pip"},state.pip or false,true) end
        row("MPV menu","","native_menu",state.native_tools~=false and {kind="native-menu"} or nil)
        row("MPV properties","","info",state.native_tools~=false and {kind="properties"} or nil)
        for _,item in ipairs({{"Take screenshot","info","screenshot"},{"MPV console","keyboard","script-binding console/enable"}}) do
            row(item[1],"",item[2],(item[3]=="screenshot" or state.native_console~=false) and {command=item[3]} or nil)
        end
    elseif page == "sync" then
        local step=options and options.sync_step or .05
        for _,kind in ipairs({"sub","audio"}) do
            local label=kind=="sub" and "Subtitle" or "Audio"
            row(label.." delay",string.format("%+.0f ms",(state[kind.."_delay"] or 0)*1000))
            for _,amount in ipairs({-step,step}) do
                row(label..(amount<0 and " earlier" or " later"),string.format("%.0f ms",step*1000),nil,{kind="delay",track=kind,value=amount})
            end
        end
        row("Reset synchronization","",nil,{kind="sync-reset"})
    elseif page == "exports" then
        local exporter=require("core.export")
        row("Destination","Beside local media")
        row("Status",state.export_status or (state.export_ready and "Ready" or "FFmpeg unavailable"))
        for _,kind in ipairs({"sub","audio"}) do
            for _,all in ipairs({false,true}) do
                local jobs,error=exporter.plan(state,kind,all)
                row((all and "All embedded " or "Selected ")..(kind=="sub" and "subtitles" or "audio"),
                    error and "Unavailable" or #jobs.." track(s)",nil,
                    state.export_ready and not error and {export=kind,all=all} or nil)
                rows[#rows].disabled=not rows[#rows].action
            end
        end
    elseif page == "shortcuts" then
        local priority=options and options.shortcut_policy or "mpvtube"
        row("Keyboard ownership",priority=="compatible" and "Your input config first" or "MPVTube only")
        rows[#rows].informational=true
        row("Track mappings","",nil,{page="mappings"})
        row("Input diagnostics","Read-only",nil,{page="bindings"})
        row("Reset all shortcuts","",nil,{shortcut="confirm-reset"})
        for _,category in ipairs(shortcuts.categories) do
            section(category)
            for _,binding in ipairs(state.shortcuts or {}) do
                if binding.category==category then
                    row(binding.label,shortcuts.display_key(binding.key)..(binding.active==false and binding.key~="none" and " (overridden)" or ""),nil,
                        {shortcut="select",id=binding.id})
                end
            end
        end
        status("Select an action to edit its key.")
    elseif page == "bindings" then
        for _,binding in ipairs(state.active_bindings or require("core.shortcuts").active(state.bindings)) do
            local name=(binding.cmd or ""):match("script%-binding mpvtube/([^ ]+)$")
            row(binding.key,binding.comment or (state.shortcut_labels or {})[name] or binding.cmd,nil,{binding=binding})
        end
        notice("Read-only. See who handles each input when a key acts unexpectedly.")
    elseif page == "shortcut-reset" then
        row("Reset all shortcuts","",nil,{shortcut="reset-all"})
        row("Cancel","",nil,{page="shortcuts"})
        rows[#rows].shortcut="Esc"
        status("Restore default keys. Replace saved edits.")
    elseif page == "binding" then
        local editable
        for _,binding in ipairs(state.shortcuts or {}) do if binding.id==state.key_edit then editable=binding;break end end
        if editable then
            row(editable.label,"")
            rows[#rows].kind="heading"
            row("",state.key_candidate and shortcuts.display_key(state.key_candidate) or (state.key_capture and "Listening..." or "No change"))
            rows[#rows].kind,rows[#rows].current="summary",shortcuts.display_key(editable.key)
            row(state.key_capture and "Cancel recording" or "Record new shortcut","",nil,{shortcut=state.key_capture and "cancel" or "capture"})
            rows[#rows].divider=true
            row("Use default ("..shortcuts.display_key(editable.default)..")","",nil,{shortcut="default"})
            row("Unassign shortcut","",nil,{shortcut="disable"})
            row("Save changes","",nil,state.key_candidate and {shortcut="save"} or nil)
            rows[#rows].disabled=not state.key_candidate
            status("Record a key, then save.")
            return rows
        end
        local binding=state.binding_detail or {}
        row("Key",binding.key or "")
        row("Command","")
        for _,line in ipairs(model.wrap(binding.cmd,math.min(state.w-72,(options and options.shortcut_width or 900)-48),14)) do row(line,"") end
        row("Owner",binding.owner or binding.section or "input.conf / MPV")
        row("Priority",tostring(binding.priority or ""))
        notice("Read-only input route. Change editable shortcuts in the guide.")
    elseif page == "mappings" then
        for _,kind in ipairs({"audio","sub","video"}) do
            local property=({audio="aid",sub="sid",video="vid"})[kind]
            for _,track in ipairs(model.tracks(state.tracks,kind)) do
                row(kind.." #"..track.id,model.track_name(track),nil,{property=property,value=track.id,keep_menu=true},
                    tostring(track.id)==tostring(state[property]) and (kind~="sub" or state.sub_visibility))
            end
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
    sub="Subtitles/CC", video="Video track", chapters="Chapters", playlist="Playlist", info="Video information",
    controls="More controls",sync="Synchronization",exports="Export tracks",shortcuts="Keyboard shortcuts",
    binding="Input details",bindings="Input diagnostics",["shortcut-reset"]="Reset shortcuts",mappings="Track mappings"}
for page,title in pairs(captions.titles) do M.titles[page]=title end
function M.parent(page)
    if page=="binding" or page=="bindings" or page=="shortcut-reset" or page=="mappings" then return "shortcuts" end
    if page=="sync" then return "controls" end
    return captions.titles[page] and captions.parent(page) or "settings"
end

-- Drawing and width estimates reserve exactly the same icon/checkmark/value columns.
local function label_inset(row)
    return (row.kind=="summary" or row.kind=="heading") and 32 or row.icon and 64 or row.selected~=nil and 43 or 16
end

-- An explicit gap prevents approximate name widths from crowding the smaller key hint.
local function shortcut_label(row)
    local text=row.shortcut and "("..row.shortcut..")" or ""
    return text,text~="" and model.text_width(text,12)+spacing.compact_gap or 0
end

-- Settings stay near their trigger; shortcut tools use a larger centered workspace.
function M.geometry(state, options)
    local rows=M.rows(state,state.menu,options)
    local title=state.menu=="binding" and state.key_edit and "Edit shortcut" or M.titles[state.menu]
    local wide=state.menu=="shortcuts" or state.menu=="binding" or state.menu=="bindings" or state.menu=="shortcut-reset" or state.menu=="mappings"
    local pinned=rows[#rows] and rows[#rows].pinned and 1 or 0
    local row_h=state.menu=="speed" and spacing.menu_row or state.h<300 and 30 or wide and 40 or spacing.menu_row
    local header=state.menu=="settings" and 0 or state.h<300 and 30 or spacing.menu_header
    -- Ordinary panels leave room above for the shared action-feedback card.
    local top=state.h>=300 and 64 or spacing.inset
    local limit=wide and state.h*(state.h<300 and .95 or .8) or state.h-spacing.menu_bottom-top
    local max_width=wide and (options.shortcut_width or 900) or options.menu_width
    if state.menu=="shortcut-reset" or state.menu=="binding" and state.key_edit then max_width=math.min(max_width,620) end
    local width=wide and max_width or state.menu=="settings" and max_width or state.menu=="speed" and 320 or 240
    width=math.max(width,model.text_width(title,14)+(state.menu=="sub" and 132 or 76))
    for _,row in ipairs(rows) do
        local value_width=row.value~="" and model.text_width(row.value,14)+20 or 0
        local _,shortcut_width=shortcut_label(row)
        width=math.max(width,model.text_width(row.label,14)+shortcut_width+label_inset(row)+32+value_width+(row.toggle and 48 or 0))
    end
    width=math.min(math.ceil(width),max_width,state.w-2*spacing.inset)
    local footer_h=pinned*row_h
    if pinned==1 and rows[#rows].kind=="notice" then
        local notice=rows[#rows]
        notice.lines=model.wrap(notice.label,width-48,13,true)
        -- A fixed notice height keeps controls still when status text changes or wraps.
        footer_h=state.h<300 and 48 or 60
    end
    local capacity=math.max(1,math.floor((limit-header-2*spacing.menu_padding-footer_h)/row_h))
    local visible=math.min(#rows-pinned,capacity)
    local height=header+visible*row_h+footer_h+2*spacing.menu_padding
    return {x=wide and (state.w-width)/2 or state.w-width-spacing.inset,
        y=wide and (state.h-height)/2 or state.h-spacing.menu_bottom-height,w=width,h=height,
        rows=rows,title=title,row_h=row_h,header=header,padding=spacing.menu_padding,pinned=pinned,footer_h=footer_h,wide=wide,
        offset=model.clamp(state.menu_scroll or 0,0,math.max(0,#rows-pinned-visible)),visible=visible,page=state.menu}
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
        canvas:icon("back",menu.x+24,menu.y+menu.header/2,32)
        canvas:label(menu.wide and "dialog_title" or "header",menu.x+48,menu.y+menu.header/2,menu.title)
        if menu.page == "sub" then
            canvas:label("header_action",menu.x+menu.w-18,menu.y+menu.header/2,"Options","ffffff",6)
        end
        canvas:rect(menu.x,menu.y+menu.header-1,menu.w,1,"ffffff",0.16)
    end
    for _, hit in ipairs(controls.hits) do
        local row = hit.row
        if row then
            local cy = hit.y+hit.h/2
            if hit.pinned then canvas:rect(hit.x,hit.y,hit.w,1,"ffffff",.16) end
            if row.divider then canvas:rect(menu.x+24,hit.y+1,menu.w-48,1,"ffffff",.16) end
            if row.kind=="notice" then
                local color=({error="ff8a80",success="8ee59c",info="b8c9e8"})[row.tone] or "b8c9e8"
                canvas:rect(hit.x+8,hit.y+6,hit.w-16,hit.h-12,color,.13,6)
                for index=1,math.min(2,#row.lines) do
                    local text=index==2 and table.concat(row.lines,"",2) or row.lines[index]
                    canvas:label("tooltip",hit.x+16,hit.y+(hit.h<60 and 16 or 21)+(index-1)*18,model.fit(text,hit.w-32,13),color)
                end
            elseif row.kind=="heading" then
                canvas:label("dialog_title",menu.x+32,cy,model.fit(row.label,menu.w-64,18))
            elseif row.kind=="summary" then
                -- Read-only data uses typography, not control backgrounds or hover states.
                local compact=menu.w<480
                for index,value in ipairs({row.current,row.value}) do
                    local x=menu.x+32+(compact and 0 or (index-1)*(menu.w-64)/2)
                    local label_y=compact and hit.y+hit.h*(index-.5)/2 or hit.y+9
                    local value_x=compact and x+64 or x
                    local width=compact and menu.w-128 or (menu.w-64)/2-16
                    canvas:label("field_label",x,label_y,index==1 and (compact and "Current" or "Current key") or (compact and "New" or "New key"),"bbbbbb")
                    canvas:label(compact and "field_value_compact" or "field_value",value_x,compact and label_y or hit.y+hit.h-11,
                        model.fit(value,width,compact and 14 or 16),value=="No change" and "aaaaaa" or "ffffff")
                end
            elseif row.kind=="section" then
                canvas:rect(hit.x,hit.y,hit.w,1,"ffffff",.16)
                canvas:text(hit.x+8,cy,row.label,14,"bbbbbb",4,1,500)
            elseif row.kind == "speed-value" then
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
                if row.icon then canvas:icon(row.icon,menu.x+28,cy,24,"ffffff",row.disabled and .5 or 1)
                elseif row.selected then canvas:icon("check",menu.x+26,cy,20) end
                -- Reserve columns for icons/checkmarks; plain rows share one text inset.
                local label_x = menu.x+label_inset(row)
                local value_w = row.value ~= "" and math.min(menu.w*0.47,model.text_width(row.value,14)+4) or 0
                local label_w = menu.x+menu.w-32-label_x-value_w-(row.toggle and 48 or 0)
                if row.value ~= "" then label_w=label_w-16 end
                local label=hit.pinned and menu.w<320 and "Clean style" or row.label
                local hint,hint_w=shortcut_label(row)
                label=model.fit(label,math.max(0,label_w-hint_w),14)
                canvas:label(row.informational and "field_label" or "body",label_x,cy,label,row.informational and "bbbbbb" or "ffffff",nil,row.disabled and .5 or 1)
                if hint~="" then
                    canvas:label("field_label",label_x+model.text_width(label,14)+spacing.compact_gap,cy,hint,"bbbbbb",nil,row.disabled and .5 or 1)
                end
                if row.value ~= "" then
                    canvas:label("body",menu.x+menu.w-32,cy,model.fit(row.value,value_w,14),"dddddd",6,row.disabled and .5 or 1)
                end
                if row.toggle then
                    canvas:toggle(menu.page..":"..row.label,menu.x+menu.w-36,cy,row.selected)
                elseif row.action and (row.action.page or row.action.shortcut=="select" or row.action.shortcut=="confirm-reset" or row.action.binding) then
                    canvas:icon("menu_arrow",menu.x+menu.w-16,cy,18,"ffffff",0.7)
                end
            end
        end
    end
    -- The scroll thumb reflects row count rather than a fixed pixel travel distance.
    if #menu.rows-menu.pinned > menu.visible then
        local count=#menu.rows-menu.pinned
        local track_h = menu.visible*menu.row_h
        local thumb_h = math.max(20,track_h*menu.visible/count)
        local ty = menu.y+menu.header+track_h*menu.offset/count
        canvas:rect(menu.x+menu.w-6,ty,3,thumb_h,"ffffff",0.45,1.5)
    end
end

-- Open, navigate and scroll immediately; only the shared hover/toggle feedback animates.
function M.render(canvas,state,controls,options)
    if not controls.menu then return end
    if not canvas.motion then render_panel(canvas,state,controls,options,true);return end
    local layer=canvas:layer(1,controls.menu)
    layer.opacity=1
    render_panel(layer,state,controls,options,true)
    canvas.events[#canvas.events+1]=layer:finish()
end

return M
