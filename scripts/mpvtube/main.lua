-- MPVTube entry point: wire modules, observe player state, and schedule rendering.
local mp = require("mp")
local utils = require("mp.utils")
local model = require("core.model")
local ui = require("ui.view")
local thumbnails = require("core.thumbnails")
local motion = require("ui.motion")
local draw = require("ui.draw")

local mp_options = require("mp.options")

-- Validate skin options once; drawing and input share these values.
local function load_options()
    local options = {
        scale=1, font="Roboto", accent="ff0033", hide_timeout=3, fade_duration=0.25,
        show_on_pause=true, title=true, tooltip_delay=0.45, menu_width=380, menu_opacity=0.6,
        keyboard=true, video_click=true, theater=true, pip=true, raise_subtitles=true, thumbnails="auto",
        ffmpeg_path="ffmpeg", thumbnail_width=200, thumbnail_interval=2, thumbnail_delay=0,
        thumbnail_cache=64, pip_width=480, theater_width=1280,
    }

    -- Bound dimensions/timings to keep malformed settings usable and the cache finite.
    local function validate_options()
        local function number(name, lo, hi)
            options[name]=model.clamp(tonumber(options[name]) or lo,lo,hi)
        end
        number("scale",0.5,3); number("hide_timeout",0.1,30); number("fade_duration",0,1)
        number("tooltip_delay",0,5); number("menu_width",240,600); number("menu_opacity",0.2,1)
        number("thumbnail_width",120,320); number("thumbnail_interval",1,60)
        number("thumbnail_delay",0,2); number("thumbnail_cache",1,256)
        number("pip_width",240,960); number("theater_width",640,3840)
        options.thumbnail_cache=math.floor(options.thumbnail_cache)
        options.accent=options.accent:gsub("^#","")
        if not options.accent:match("^%x%x%x%x%x%x$") then options.accent="ff0033" end
        if not ({auto=true,no=true,ffmpeg=true,thumbfast=true})[options.thumbnails] then options.thumbnails="auto" end
        -- Font names are placed inside an ASS tag, so strip tag delimiters.
        options.font=options.font:gsub("[{}\\\r\n]","")
    end
    mp_options.read_options(options,"mpvtube",validate_options)
    validate_options()

    return options
end

local options = load_options()

-- Observers fill playback fields; input and animation fields live in the same state table.
local state = {w=1280,h=720,scale=1,time=0,pause=false,mute=false,volume=100,speed=1,
    tracks={},chapters={},raw_chapters={},playlist={},playlist_pos=0,aid="no",sid="no",vid="no",
    sub_visibility=true,loop_file="no",keep_open="no",cache={},title="",idle=true,
    fullscreen=false,opacity=0,volume_expand=0,timeline_expand=0,mx=-1,my=-1,mouse_inside=false}
local overlay = mp.create_osd_overlay("ass-events")
overlay.z=1000
local text_overlay=mp.create_osd_overlay("ass-events")
text_overlay.hidden,text_overlay.compute_bounds=true,true
local text_cache,text_count,text_geometry,text_warmup={},0,nil,false

-- Measure visible glyphs with the same renderer/font as the controls. Cache to avoid work per frame.
state.measure_text=function(text,size,weight)
    local geometry=table.concat({options.font,state.w,state.h,state.scale},":")
    if geometry ~= text_geometry then text_cache,text_count,text_geometry,text_warmup={},0,geometry,true
    elseif text_count >= 32 then text_cache,text_count={},0 end
    local key=size..":"..(weight or 400)..":"..text
    if not text_cache[key] then
        local canvas=draw.new(1,options.font)
        canvas:text(state.w/2,state.h/2,text,size,nil,5,1,weight)
        text_overlay.res_x,text_overlay.res_y=state.w,state.h
        text_overlay.data=canvas:finish()
        local bounds=text_overlay:update()
        local width=bounds and bounds.x1 and bounds.x1-bounds.x0
        text_cache[key]=width or model.text_width(text,size)
        text_count=text_count+1
    end
    return text_cache[key]
end
local render_timer, hide_timer
local view = {}
local visibility_target=0
local animation=motion.new()
local stopped = false

-- Coalesce changes into one frame. Hidden playback never starts a continuous render loop.
local function request_render()
    if render_timer and not render_timer:is_enabled() and not stopped then render_timer:resume() end
end

local function fade(target)
    if target == visibility_target then return end
    visibility_target=target
    request_render()
end

-- Interaction and paused playback prevent the inactivity timer from hiding controls.
local function held_open()
    return state.menu or state.drag or state.hover or (state.pause and options.show_on_pause)
end

local function schedule_hide()
    hide_timer:kill()
    hide_timer.timeout=options.hide_timeout
    hide_timer:resume()
end

local function show()
    if state.idle then return end
    fade(1)
    schedule_hide()
    request_render()
end

local function feedback(text, icon, side, amount)
    local now=mp.get_time()
    state.feedback=amount and model.seek_feedback(state.feedback,amount,now,motion.duration.seek)
        or {text=text,icon=icon,side=side,start=now,opacity=1}
    request_render()
end

-- Convert both the window and pointer to logical pixels, including display DPI.
local function update_dimensions()
    local w,h=mp.get_osd_size()
    if not w or not h or w <= 0 or h <= 0 then return false end
    local dpi=mp.get_property_number("display-hidpi-scale",1)
    -- Keep controls usable in small windows without changing normal-size proportions.
    local scale=options.scale*math.max(1,dpi)
    scale=math.min(scale,w/300,h/180)
    state.scale=math.max(0.25,scale)
    state.w,state.h=math.floor(w/state.scale+0.5),math.floor(h/state.scale+0.5)
    local x,y=mp.get_mouse_pos()
    state.mx,state.my=x/state.scale,y/state.scale
    return true
end

-- Share state and the current layout so rendering and input agree after each resize.
view.show, view.feedback, view.request_render = show, feedback, request_render
view.schedule_hide, view.update_dimensions = schedule_hide, update_dimensions
local preview = thumbnails.new(options,request_render)
local player = require("core.player").new(state,options,view,preview)
local input = require("core.input").new(state,options,view,player,preview)

-- Frames run only for active transitions or feedback.
local function render()
    if stopped or not update_dimensions() then return end
    local now=mp.get_time()
    animation:begin(now)
    state.opacity=animation:value("controls",visibility_target,options.fade_duration*(visibility_target == 1 and 1 or 0.4),
        visibility_target == 1 and "enter" or "leave",0)
    local volume_hover=ui.volume_hover(state,view.layout)
    state.volume_expand=animation:value("volume-expand",volume_hover and 1 or 0,"volume",volume_hover and "enter" or "leave",0)
    state.timeline_expand=animation:value("timeline-expand",(state.hover == "timeline" or state.drag == "seek") and 1 or 0,"timeline",nil,0)
    if state.feedback then
        if not motion.feedback(state.feedback,now) then state.feedback=nil end
    end
    state.hover_age=state.hover_start and now-state.hover_start or 0
    player.update_subtitles()
    -- Bitmap previews have a separate overlay; convert thumbfast's physical size once.
    state.preview=nil
    if state.opacity > 0 and not state.menu and state.mouse_inside and (state.hover == "timeline" or state.drag == "seek") then
        local lo,hi=model.seek_window(state)
        if lo and hi then
            local timeline=view.layout.timeline
            state.preview=preview:request(lo+model.clamp((state.mx-timeline.x)/timeline.w,0,1)*(hi-lo))
            if state.preview and state.preview.physical then
                state.preview.w,state.preview.h=state.preview.w/state.scale,state.preview.h/state.scale
            end
        else preview:hide() end
    else preview:hide() end
    -- Submit ASS only when it changes; cached bitmaps appear during the control fade too.
    if state.idle then
        overlay:remove()
        preview:hide()
    else
        local ass_events
        ass_events,view.layout=ui.render(state,options,animation)
        overlay.res_x,overlay.res_y=state.w,state.h
        if overlay.data ~= ass_events then overlay.data=ass_events; overlay:update() end
        -- Bounds use the VO's last rendered size; repeat once after its first frame/resize.
        if text_warmup then text_cache,text_count,text_warmup={},0,false; request_render() end
        preview:display(view.layout.preview,state.scale)
    end
    input.update_hover()
    player.update_menu_binding()
    if animation:finish() or state.feedback then request_render() end
end

render_timer=mp.add_timeout(1/60,render,true)
hide_timer=mp.add_timeout(options.hide_timeout,function()
    if not held_open() then fade(0) end
end,true)

-- Each entry maps an MPV property to its type, state field and missing-value fallback.
local properties = {
    {"time-pos","number","time",0},{"duration","number","duration"},
    {"pause","bool","pause",false},{"mute","bool","mute",false},
    {"volume","number","volume",100},{"speed","number","speed",1},
    {"fullscreen","bool","fullscreen",false},{"idle-active","bool","idle",true},
    {"seekable","bool","seekable",false},{"track-list","native","tracks",{}},
    {"chapter-list","native","raw_chapters",{}},{"playlist","native","playlist",{}},
    {"playlist-pos","number","playlist_pos",0},{"aid","native","aid","no"},
    {"sid","native","sid","no"},{"vid","native","vid","no"},
    {"sub-visibility","bool","sub_visibility",true},{"loop-file","string","loop_file","no"},
    {"keep-open","string","keep_open","no"},{"demuxer-cache-state","native","cache",{}},
    {"demuxer-cache-duration","number","cache_time",0},{"media-title","string","title",""},
    {"video-params","native","video",{}},{"video-codec","string","video_codec"},
    {"audio-codec-name","string","audio_codec"},{"container-fps","number","fps"},
}
for _, property in ipairs(properties) do
    mp.observe_property(property[1],property[2],function(_,value)
        if value == nil then value=property[4] end
        state[property[3]]=value
        if property[3] == "raw_chapters" or property[3] == "duration" then state.chapters=model.chapters(state.raw_chapters,state.duration) end
        if property[3] == "duration" then preview.duration=state.duration end
        if property[3] == "vid" or property[3] == "tracks" then preview:set_video(model.track(state.tracks,"video",state.vid)) end
        if property[3] == "pause" then show() end
        if property[3] == "idle" and state.idle then
            state.menu,state.drag,state.drag_time=nil,nil,nil
            fade(0); preview:hide()
        end
        local timeline_property=property[3] == "time" or property[3] == "cache" or property[3] == "cache_time"
        -- Frequent playback/cache observations need a frame only while controls are visible.
        if not timeline_property or state.opacity > 0 or visibility_target > 0 then request_render() end
    end)
end
for _, property in ipairs({"osd-dimensions","display-hidpi-scale"}) do mp.observe_property(property,"native",request_render) end

-- Public script messages let input.conf and other scripts control visibility and menus.
mp.register_script_message("menu",function(page)
    page=page or "settings"
    if require("ui.menu").titles[page] then player.open_menu(page) end
end)
mp.register_script_message("show",show)
mp.register_script_message("hide",function() state.menu=nil; fade(0) end)
mp.register_script_message("toggle",function() if visibility_target > 0 then state.menu=nil; fade(0) else show() end end)

-- File changes cancel old previews; shutdown also restores temporary player settings.
local function reset_interactions()
    state.menu,state.drag,state.drag_time=nil,nil,nil
    state.feedback,state.pressed,state.menu_transition=nil,nil,nil
    -- Keep the current control fade; replacing the clock would briefly block playlist buttons.
    animation.menu_page,animation.menu_controls,animation.old_menu,animation.tooltip=nil,nil,nil,nil
end
mp.register_event("file-loaded",function()
    reset_interactions()
    local path=mp.get_property("path")
    if path and not path:match("^%a[%w+.-]*://") and not path:match("^[/\\]") and not path:match("^%a:") then
        path=utils.join_path(mp.get_property("working-directory",""),path)
    end
    local video=model.track(mp.get_property_native("track-list",{}),"video",mp.get_property_native("vid"))
    preview:reset(path,mp.get_property_number("duration"),video ~= nil,video and video["ff-index"])
    show()
end)
mp.register_event("end-file",function()
    reset_interactions()
    preview:reset(nil,nil)
end)
mp.register_event("shutdown",function()
    stopped=true
    render_timer:kill(); hide_timer:kill()
    input.shutdown(); preview:shutdown(); overlay:remove(); text_overlay:remove(); player.shutdown()
end)

-- Disable the stock controller automatically as well as documenting osc=no.
mp.set_property_bool("osc",false)
mp.msg.info("MPVTube loaded. Move the mouse to show the controls.")
request_render()
