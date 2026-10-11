-- Run from the project root: luajit tests/regression.lua (or lua).
package.path="scripts/mpvtube/?.lua;"..package.path
local model=require("core.model")
local ui=require("ui.view")
local icons=require("ui.icons")
local motion=require("ui.motion")
local drawing=require("ui.draw")
local count=0
local function check(condition,message)
    assert(condition,message)
    count=count+1
end

-- CSS sizes and actual font weights must survive conversion to ASS.
local text_canvas=drawing.new(1,"Roboto")
text_canvas:label("timer",100,20,"1:24 / 23:40")
text_canvas:label("speed",100,40,"1.00x")
text_canvas:label("body",100,60,"Playback speed")
text_canvas:label("title",100,80,"Video title")
text_canvas:label("seek",100,100,"+ 5")
local typography=text_canvas:finish()
check(typography:find("\\fnRoboto\\fs18.46\\b500",1,true),"timer uses Roboto Medium at CSS 14 px")
check(typography:find("\\fnRoboto\\fs23.74\\b900",1,true),"speed value uses the real Black weight")
check(typography:find("\\b400",1,true) and typography:find("\\b700",1,true),"regular rows and bold titles keep distinct weights")
check(typography:find("\\i0\\fsp0",1,true),"UI text does not inherit italic or extra tracking from native OSD settings")
check(typography:find("\\fs31.65\\b700",1,true),"arrow seek labels use the reference bold weight")

-- Deterministic clocks verify easing, interrupted gestures and timer termination.
for _,curve in ipairs({"modern","enter","leave","standard","linear"}) do
    local previous=0
    for step=0,20 do
        local value=motion.ease(step/20,curve)
        check(value>=previous and value<=1,"easing is bounded and monotonic: "..curve)
        previous=value
    end
    check(motion.ease(0,curve)==0 and motion.ease(1,curve)==1,"easing preserves endpoints")
end
local tween=motion.new()
tween:begin(0);check(tween:value("test",1,"hover",nil,0)==0,"transition starts at its initial value")
check(tween:finish(),"changing transition requests another frame")
tween:begin(.08);local halfway=tween:value("test",1,"hover")
check(halfway>0 and halfway<1,"transition has intermediate frames")
check(tween:value("test",0,"hover")==halfway,"reversal starts from the displayed value")
tween:finish();tween:begin(.5)
check(tween:value("test",0,"hover")==0,"elapsed clock settles after a long frame gap")
check(not tween:finish(),"settled animation stops requesting frames")
tween:begin(.6);tween:finish()
check(next(tween.tracks)==nil,"removed controls release their transition tracks")
for _,age in ipairs({0,.125,.25,.5,.75,.875,1}) do
    local item={start=0,icon="volume_up"}
    local running=motion.feedback(item,age)
    check(running==(age<1),"modern feedback lasts one second")
    if age==0 or age==1 then check(item.opacity==0 and item.scale==1,"feedback pulse has invisible endpoints")
    elseif age>=.25 and age<=.75 then check(item.opacity==1 and item.scale==1.33,"feedback pulse holds its expanded plateau")
    else check(item.opacity>0 and item.opacity<1 and item.scale>1 and item.scale<1.33,"feedback fades and scales between keyframes") end
end
local seek_pulse={kind="seek",start=0}
motion.feedback(seek_pulse,0)
check(seek_pulse.opacity==0 and seek_pulse.offset==16,"seek starts with a faded, inset chevron")
motion.feedback(seek_pulse,.05)
check(seek_pulse.opacity>0 and seek_pulse.opacity<1 and seek_pulse.offset>0 and seek_pulse.offset<16,"seek fades in while its chevron moves")
motion.feedback(seek_pulse,.5)
check(seek_pulse.opacity==1 and seek_pulse.offset==0,"seek holds its signed label and settled chevron")
motion.feedback(seek_pulse,1.15)
check(seek_pulse.opacity>0 and seek_pulse.opacity<1,"seek fades out after its hold")
check(not motion.feedback(seek_pulse,1.2) and seek_pulse.opacity==0,"seek animation ends and releases its timer")
check(model.time(0)=="0:00","zero time")
check(model.time(3661)=="1:01:01","hour time")
check(model.time(-5)=="0:00","negative time")
check(model.time(nil)=="--:--","missing time")
check(model.time(0/0)=="--:--","NaN time")
check(model.fit("Normal",50,14)=="Normal","short menu values must not truncate")
check(model.fit("章节标题章节标题",42,14)=="章节…","UTF-8 truncation")
check(not model.escape("x\\N{\\an1}"):find("\\N",1,true),"metadata must not inject ASS tags")
local chapters=model.chapters({{time=8,title="Middle"},{time=8},{time=-2},{time=20}},16)
check(#chapters==2 and chapters[1].time==0 and chapters[2].time==8,"normalize chapter boundaries")
check(model.chapter_at(chapters,9).title=="Middle","chapter lookup")
local lo,hi=model.seek_window({seekable=true,cache={["seekable-ranges"]={{start=120,["end"]=240}}}})
check(lo==120 and hi==240,"DVR seek window")
check(model.seek_window({seekable=false,duration=100})==nil,"non-seekable stream")

-- Known cache ranges take priority over the approximate read-ahead duration.
local cache_rectangles={}
local canvas={rect=function(_,x,y,w,h,color,opacity)
    if opacity==.40 and w>0 then cache_rectangles[#cache_rectangles+1]={x=x,w=w} end
end,circle=function() end}
local cache_state={w=960,h=720,time=5,chapters={},cache_time=5,
    cache={["seekable-ranges"]={{start=0,["end"]=10}}}}
ui.render_timeline(canvas,cache_state,{seek_lo=0,seek_hi=20},{accent="ff0033"})
check(#cache_rectangles==1,"buffered data is painted once rather than doubling its opacity")
cache_state.cache={};cache_rectangles={}
ui.render_timeline(canvas,cache_state,{seek_lo=0,seek_hi=20},{accent="ff0033"})
check(#cache_rectangles==1,"read-ahead duration remains a fallback when ranges are unavailable")

local o={title=true,theater=true,pip=true,menu_width=380,menu_opacity=.6,
    accent="ff0033",font="Arial",tooltip_delay=.45}
local s={w=1440,h=900,opacity=1,time=405,duration=1581,seekable=true,pause=true,
    mute=false,volume=75,speed=1,volume_expand=0,timeline_expand=0,fullscreen=true,
    title="Ansible for Complete Beginners: Your First Playbook",sub_visibility=true,sid=3,aid=2,vid=1,
    loop_file="no",keep_open="no",cache={["seekable-ranges"]={{start=0,["end"]=440}}},
    tracks={{type="video",id=1},{type="audio",id=2,lang="eng"},{type="sub",id=3,lang="eng"}},
    chapters={{time=0,title="Introduction"},{time=80,title="Installation"},{time=187,title="Writing Your First Ansible Playbook (Step by Step)"},{time=900,title="Summary"}},
    playlist={{filename="one.mkv"}},playlist_pos=0,mx=400,my=841,mouse_inside=true}
local ass,layout=ui.render(s,o)
check(layout.cy==872 and layout.timeline.x==12,"reference spacing")
check(ass:find("&H3300ff&",1,true),"reference red in ASS BGR format")
check(layout.chapter~=nil,"chapter capsule")
s.volume_expand=1
local volume_layout=ui.layout(s,o)
local speaker
for _,button in ipairs(volume_layout.buttons) do if button.id=="mute" then speaker=button end end
check(volume_layout.volume.x==speaker.x+speaker.w,"volume panel directly follows its speaker button")
check(volume_layout.volume_pill.x+volume_layout.volume_pill.w-volume_layout.volume.x-volume_layout.volume.w==19,
    "volume panel leaves the reference's 3 px gap and 16 px trailing padding")
check(ui.hit(volume_layout,volume_layout.volume.x+26,volume_layout.volume.y+2).id=="volume",
    "the full volume panel height remains clickable")
for _,button in ipairs(volume_layout.buttons) do
    if button.action then
        check(ui.hit(volume_layout,button.x+button.w/2,button.y+2).id==button.id,
            "top of button has priority over the timeline: "..button.id)
    end
end
s.volume_expand=0
-- Timestamp width follows both fields; toggling remaining time never clips the sign.
for _,duration in ipairs({599,600,36000,360000,36000000}) do
    local previous_width=0
    for _,time in ipairs({0,59,599,3600,36000}) do
        if time <= duration then
            s.time,s.duration=time,duration
            for _,remaining in ipairs({false,true}) do
                s.time_remaining=remaining
                local clock=ui.layout(s,o).time
                local current=remaining and "-"..model.time(duration-time) or model.time(time)
                check(clock.text==current.." / "..model.time(duration),"full elapsed/remaining timestamp")
                check(clock.w>=model.text_width(clock.text,14)+32,"time preserves 16 px text padding")
                check(ui.hit(ui.layout(s,o),clock.x+clock.w/2,clock.y+20).action.kind=="time","whole timestamp capsule is clickable")
                if not remaining then
                    check(clock.w>=previous_width,"elapsed capsule grows at minute/hour boundaries")
                    previous_width=clock.w
                end
            end
        end
    end
end
s.time,s.duration,s.time_remaining=405,1581,false
-- Native font widths take priority over the rough estimate used for menu clipping.
s.measure_text=function() return 52 end
local measured_ass,measured_layout=ui.render(s,o)
check(measured_layout.time.w==84,"timestamp uses measured glyph width plus equal padding")
local text_x=measured_layout.time.x+measured_layout.time.w/2
check(measured_ass:find(string.format("\\an5\\pos(%.2f,%.2f)",text_x,measured_layout.cy),1,true),"timestamp uses native centered alignment instead of a fixed left anchor")
s.measure_text=nil
for _,point in ipairs({{2,s.h-2},{s.w/2,s.h-4},{s.w-2,s.h-60}}) do
    local background=ui.hit(ui.layout(s,o),point[1],point[2])
    check(background.id=="controls-background" and background.action~=nil,"empty bottom strip consumes clicks")
end

-- Check painted hover dimensions against the browser measurements for every bottom button.
local original_canvas=drawing.new
local highlights={}
drawing.new=function(...)
    local canvas=original_canvas(...)
    local rect=canvas.rect
    function canvas:rect(x,y,w,h,color,opacity,radius)
        if color=="ffffff" and opacity==0.1 then highlights[#highlights+1]={w=w,h=h} end
        return rect(self,x,y,w,h,color,opacity,radius)
    end
    return canvas
end
s.fullscreen,s.volume_expand=false,1
s.playlist,s.playlist_pos={{filename="one"},{filename="two"},{filename="three"}},1
local hover_widths={play=32,previous=32,next=32,mute=103,autoplay=48,cc=48,settings=48,pip=48,theater=48,fullscreen=48}
for _,button in ipairs(ui.layout(s,o).buttons) do
    if hover_widths[button.id] then
        s.hover,s.mx,s.my=button.id,button.x+button.w/2,button.y+20
        highlights={}
        ui.render(s,o)
        check(#highlights==1 and highlights[1].w==hover_widths[button.id] and highlights[1].h==32,"reference hover size: "..button.id)
    end
end
s.hover,s.mouse_inside,s.menu=nil,false,"settings"
highlights={}
local active_settings=ui.render(s,o)
check(#highlights==0,"open settings does not retain a hover background")
check(active_settings:find("\\frz-30.00",1,true)~=nil,"open settings rotates the gear clockwise by 30 degrees")
drawing.new=original_canvas
s.fullscreen,s.volume_expand,s.menu=true,0,nil
s.playlist,s.playlist_pos={{filename="one.mkv"}},0
s.mx,s.my,s.mouse_inside=400,841,true
for _,page in ipairs({"settings","speed","audio","sub","chapters","playlist","info","captions",
    "caption-font","caption-size","caption-color","caption-opacity","caption-background",
    "caption-background-opacity","caption-edge","sleep"}) do
    s.menu=page
    local data,l=ui.render(s,o)
    check(#data>0 and l.menu and #l.menu.rows>0,"render menu: "..page)
    for _,row in ipairs(l.menu.rows) do
        if row.action and row.action.property=="sid" then
            check(row.selected==(row.action.value==s.sid and s.sub_visibility),"subtitle menu reflects selection")
        end
    end
end
s.menu="sub"
local sub_layout=ui.layout(s,o)
local options_hit=ui.hit(sub_layout,sub_layout.menu.x+sub_layout.menu.w-30,sub_layout.menu.y+24)
check(options_hit.action.page=="captions","Options takes priority over the subtitle back button")
check(require("ui.menu").parent("captions")=="sub","Options returns to subtitle tracks")
check(require("ui.menu").parent("caption-size")=="captions","appearance choices return to Options")
for _,enabled in ipairs({false,true}) do
    s.sub_visibility=enabled
    local cc
    for _,button in ipairs(ui.layout(s,o).buttons) do if button.id=="cc" then cc=button end end
    check(cc.icon==(enabled and "cc_active" or "cc"),"CC icon reflects visibility")
end
s.sub_visibility=true
s.menu=nil
s.hover="timeline"
s.preview={w=200,h=112}
local _,l=ui.render(s,o)
check(l.preview and l.preview.x>=12,"thumbnail positioning")
s.menu="captions"
local _,caption_hover=ui.render(s,o)
check(not caption_hover.preview,"open menus suppress timeline hover previews")
s.menu=nil
s.preview=nil
s.hover=nil
-- Loading, ready and missing previews keep the same timestamp and chapter anchor.
do
    local timestamp
    local hover_canvas={rect=function() end,circle=function() end,
        label=function(_,role,x,y) if role=="tooltip" then timestamp={x=x,y=y} end end}
    for _,width in ipairs({300,960}) do
        for _,chapters in ipairs({{},{{time=0,title="Chapter"}}}) do
            for _,pointer in ipairs({12,width/2,width-12}) do
                local state={w=width,h=720,time=0,chapters=chapters,hover="timeline",mouse_inside=true,mx=pointer}
                local anchor
                for _,image in ipairs({false,{w=200,h=112},{w=200,h=200},false}) do
                    state.preview=image or nil
                    local controls={seek_lo=0,seek_hi=100}
                    ui.render_timeline(hover_canvas,state,controls,o)
                    anchor=anchor or timestamp
                    check(timestamp.x==anchor.x and timestamp.y==anchor.y,"preview availability preserves the hover label position")
                    if image then
                        check(controls.preview.y+controls.preview.h < timestamp.y-15.5,"preview stays above its timestamp capsule")
                    end
                end
            end
        end
    end
end
-- All interactive controls must fit, stay distinct, and have an implementation.
for _,width in ipairs({300,360,400,460,600,640,740,1000,1440,1920}) do
    for _,full in ipairs({false,true}) do
        for _,expanded in ipairs({0,1}) do
            s.w,s.h,s.fullscreen,s.volume_expand=width,math.max(240,width*9/16),full,expanded
            local data,l=ui.render(s,o)
            check(#data>0,"responsive ASS output")
            for _,button in ipairs(l.buttons) do
                check(icons[button.icon]~=nil,"valid icon: "..tostring(button.icon))
                check(button.x>=0 and button.x+button.w<=width,"button within viewport: "..button.id)
            end
            for i,a in ipairs(l.pills) do
                for j=i+1,#l.pills do
                    local b=l.pills[j]
                    check(a.x+a.w<=b.x+.1 or b.x+b.w<=a.x+.1,"capsules must not overlap at "..width)
                end
            end
        end
    end
end
-- Expanding the compact strip must hide time without overlapping the left controls.
for _,width in ipairs({300,360,400,425,460,539}) do
    for _,full in ipairs({false,true}) do
        s.w,s.h,s.fullscreen,s.controls_expanded=width,math.max(180,width*9/16),full,true
        local _,compact=ui.render(s,o)
        check(not compact.time and not compact.chapter,"expanded compact controls release middle space")
        for i,left in ipairs(compact.pills) do
            for j=i+1,#compact.pills do
                local right=compact.pills[j]
                check(left.x+left.w<=right.x+.1 or right.x+right.w<=left.x+.1,"expanded compact capsules stay distinct")
            end
        end
        for _,button in ipairs(compact.buttons) do
            check(button.x>=12 and button.x+button.w<=width-12,"expanded compact control fits: "..button.id)
        end
    end
end
s.controls_expanded=false
-- Long-running media and multi-item playlists stress the left/right space budget.
s.time,s.duration=36661,72000
s.playlist={{filename="one.mkv"},{filename="two.mkv"},{filename="three.mkv"}}
for _,position in ipairs({0,1,2}) do
    s.playlist_pos=position
    for _,width in ipairs({300,360,400,460,600,640,740,760,1000,1440}) do
        for _,expanded in ipairs({0,1}) do
            s.w,s.h,s.fullscreen,s.volume_expand=width,math.max(240,width*9/16),false,expanded
            local _,l=ui.render(s,o)
            for i,a in ipairs(l.pills) do
                for j=i+1,#l.pills do
                    local b=l.pills[j]
                    check(a.x+a.w<=b.x+.1 or b.x+b.w<=a.x+.1,"long-media capsules overlap at "..width)
                end
            end
            for _,hit in ipairs(l.hits) do
                if hit.id~="timeline" then check(hit.action~=nil,"control must have an action: "..hit.id) end
            end
        end
    end
end
-- A long playlist/track list must scroll inside a short window.
s.w,s.h,s.menu,s.menu_scroll=640,360,"playlist",99
s.playlist={}
for i=1,50 do s.playlist[i]={filename="File "..i..".mkv"} end
local _,scroll=ui.render(s,o)
check(scroll.menu.offset==#s.playlist-scroll.menu.visible,"clamp menu scroll")
check(scroll.menu.y>=0,"menu stays in the window")

-- Icon-only feedback must be vertically centered, including when the OSC itself is hidden.
s.menu,s.opacity=nil,0
s.w,s.h=1440,900
for _,icon in ipairs({"play","pause"}) do
    s.feedback={icon=icon,text="",opacity=1}
    local data=ui.render(s,o)
    check(data:find("\\pos(693.00,423.00)",1,true)~=nil,"54 px feedback canvas centered: "..icon)
    check(not data:find("\\fn",1,true),"icon-only feedback has no empty label")
end
s.feedback=nil
s.opacity=1

-- Volume arrows retain their legacy reference shapes and put the percentage above the video.
s.opacity=0
for _,icon in ipairs({"volume_down","volume_up","volume_off"}) do
    s.feedback={icon=icon,text="50%",opacity=1}
    local data=ui.render(s,o)
    check(data:find("\\pos(693.00,423.00)",1,true)~=nil,"volume icon centered: "..icon)
    check(data:find("\\pos(720.00,112.50)",1,true)~=nil,"volume percentage at the top")
end
s.feedback,s.opacity=nil,1

-- Seek bursts must match YouTube's signed amount and have no circular background.
local burst=model.seek_feedback(nil,5,1)
burst=model.seek_feedback(burst,5,1.2)
check(burst.amount==10 and burst.side=="right","repeated arrows accumulate their amount")
burst=model.seek_feedback(burst,-5,1.3)
check(burst.amount==5 and burst.side=="left","reversing arrows starts a new signed amount")
burst=model.seek_feedback(burst,-10,2.2)
check(burst.amount==10,"expired arrow feedback starts a new burst")
check(model.seek_feedback(burst,-5,3.2,motion.duration.seek).amount==15,"runtime bursts share the animation lifetime")
s.feedback,s.opacity=burst,0
local seek_ass=ui.render(s,o)
check(seek_ass:find("− 10",1,true)~=nil,"backwards feedback uses the signed number")
check(select(2,seek_ass:gsub("\n",""))==1,"seek feedback contains just a chevron and a label")
check(seek_ass:find("\\pos(90.00,450.00)",1,true)~=nil,"seek number aligns 90 pixels from the left edge")
s.feedback,s.opacity=nil,1

-- Panel widths and padding depend on their contents, while the right edge stays fixed.
s.menu,s.menu_scroll="settings",0
local settings_geometry=ui.layout(s,o).menu
s.menu="caption-size"
local choice_geometry=ui.layout(s,o).menu
check(choice_geometry.w<settings_geometry.w,"simple choices use a narrower panel")
check(choice_geometry.x+choice_geometry.w==s.w-12,"submenus retain the 12 pixel right margin")
check(choice_geometry.y+choice_geometry.h==s.h-62,"menus clear the progress bar")
check(choice_geometry.row_h==48 and choice_geometry.padding==8,"menu row spacing follows the real player")
-- Custom speed controls remain reachable when a short window scrolls the panel.
for _,size in ipairs({{300,180},{425,240},{960,600}}) do
    for _,offset in ipairs({0,99}) do
        s.w,s.h,s.menu,s.menu_scroll=size[1],size[2],"speed",offset
        local _,speed_layout=ui.render(s,o)
        for _,hit in ipairs(speed_layout.hits) do
            if hit.id:find("speed-",1,true) == 1 then
                check(hit.x>=speed_layout.menu.x and hit.x+hit.w<=speed_layout.menu.x+speed_layout.menu.w,"speed control fits the panel")
                check(hit.y>=speed_layout.menu.y and hit.y+hit.h<=speed_layout.menu.y+speed_layout.menu.h,"speed control fits the visible panel")
                check(hit.action~=nil,"speed control has an action")
            end
        end
    end
end
s.w,s.h,s.menu_scroll=1440,900,0
-- Chapter timestamps must not pull the title into the selected checkmark's column.
s.menu="chapters"
local chapter_layout=ui.layout(s,o)
local chapter_labels={}
local menu_canvas=drawing.new(1,"Arial",nil,s)
function menu_canvas:text(x,y,text) chapter_labels[#chapter_labels+1]={x=x,text=text} end
require("ui.menu").render(menu_canvas,s,chapter_layout,o)
for _,label in ipairs(chapter_labels) do
    if label.text=="Introduction" or label.text=="Installation" or label.text=="Summary" then
        check(label.x==chapter_layout.menu.x+43,"chapter title clears the checkmark column")
    end
end
s.menu="captions"
-- Reset and ordinary option labels stay aligned, including when scrolling a short menu.
for _,size in ipairs({{300,180},{425,240},{960,600}}) do
    s.w,s.h=size[1],size[2]
    local labels={}
    for _,offset in ipairs({0,99}) do
        s.menu_scroll=offset
        local layout=ui.layout(s,o)
        local canvas=drawing.new(1,"Arial",nil,s)
        function canvas:label(role,x,_,text)
            if role=="body" then labels[text]=x-layout.menu.x end
        end
        require("ui.menu").render(canvas,s,layout,o)
    end
    check(labels.Reset and labels.Reset==labels["Font family"],"Reset aligns with caption options in narrow and wide menus")
end
s.w,s.h,s.menu_scroll=1440,900,0
s.menu="sub";s.sub_visibility=false
local subtitle_rows=ui.menu_rows(s,"sub")
check(subtitle_rows[1].selected and not subtitle_rows[2].selected,"hidden captions select Off rather than a language")
check(ui.menu_rows(s,"settings")[3].value=="Off","settings reports hidden captions as Off")
for _,row in ipairs(ui.menu_rows(s,"settings")) do
    check(row.label~="Show subtitles","subtitle visibility has no duplicate settings row")
end
s.menu,s.sub_visibility=nil,true

-- The CC control remains visibly disabled when a file has no subtitles.
local previous_tracks=s.tracks
s.tracks={{type="video",id=1},{type="audio",id=2}}
for _,button in ipairs(ui.layout(s,o).buttons) do
    if button.id=="cc" then check(button.enabled==false and not button.action,"unavailable CC is a passive control") end
end
s.tracks=previous_tracks

-- Render real transition frames, including shared hover geometry and menu click capture.
local animated_state={}
for key,value in pairs(s) do animated_state[key]=value end
animated_state.menu,animated_state.hover,animated_state.mouse_inside=nil,nil,false
animated_state.volume,animated_state.mute=50,false
local animator=motion.new()
local function frame(now)
    animator:begin(now)
    local data,layout=ui.render(animated_state,o,animator)
    return data,layout,animator:finish()
end
frame(0)
animated_state.volume=55
local starting_wave=frame(.1)
local moving_wave=frame(.225)
local ending_wave=frame(.4)
check(starting_wave~=moving_wave and moving_wave~=ending_wave,"volume boundary paints intermediate wave sizes")
animated_state.hover="play"
local hover_start=frame(.5)
local hover_middle=frame(.6)
local hover_end=frame(.75)
check(hover_start~=hover_middle and hover_middle~=hover_end,"button hover paints progressive alpha")
animated_state.hover=nil
local hover_exit=frame(.76)
check(hover_exit==hover_end,"hover exit retains its first displayed frame")
frame(1)
local bar_hover=animator.tracks["hover:bar:play"]
animated_state.menu="settings"
frame(1.1)
check(animator.tracks["hover:bar:play"]==bar_hover,"menu navigation preserves bottom-button hover tracks")
local opening_gear=frame(1.15)
local open_gear,opened=frame(1.3)
check(opening_gear~=open_gear and open_gear:find("\\frz-30.00",1,true),"gear rotates through intermediate frames")
animated_state.menu="speed"
frame(1.4)
local moving_panel,transition=frame(1.5)
local function text_x(data,label)
    for line in data:gmatch("[^\n]+") do
        if line:sub(-#label)==label then return tonumber(line:match("\\pos%(([%d.%-]+),")) end
    end
end
local old_right=text_x(moving_panel,"Audio track")-64+animator.old_menu.menu.w
local new_left=text_x(moving_panel,string.format("%.2fx",animated_state.speed))-transition.menu.w/2
check(math.abs(old_right-new_left)<.05,"different-width menu pages meet without overlapping their contents")
check(transition.menu_transition~=nil,"page slide temporarily captures menu clicks")
local panel=transition.menu_transition
check(math.abs(panel.x+panel.w-animated_state.w+12)<.001 and math.abs(panel.y+panel.h-animated_state.h+62)<.001,"animated menus retain their right/bottom margins")
check(ui.hit(transition,panel.x+panel.w/2,panel.y+panel.h/2).id=="menu","sliding rows cannot trigger an unintended action")
check(ui.hit(transition,transition.speed.x+10,transition.speed.y+12,panel.deadline).id=="speed-slider","expired page guard restores input even before a delayed render")
check(moving_panel:find("\\clip(",1,true),"menu slide clips both pages to its animated bounds")
local _,settled=frame(1.7)
check(not settled.menu_transition and ui.hit(settled,settled.speed.x+10,settled.speed.y+12).id=="speed-slider","settled page restores normal slider hits")
animated_state.menu=nil
frame(1.8)
check(animator.menu_controls~=nil,"closing menu is retained during its fade")
frame(2)
check(animator.menu_controls==nil,"closed menu releases cached content")
animated_state.hover,animated_state.hover_age="play",1
frame(2.1);frame(2.4)
check(animator.tooltip~=nil,"stable hover retains the visible tooltip")
animated_state.hover=nil
frame(2.5)
check(animator.tooltip~=nil,"departing tooltip remains during its fade")
frame(2.8)
check(animator.tooltip==nil and not animator.active,"tooltip fade clears cached content and stops animating")
animated_state.menu="speed"
frame(3);frame(3.2)
animated_state.menu="settings"
local _,growing=frame(3.3)
local pending_y=growing.menu.y+1
check(pending_y<growing.menu_transition.y,"growing panel has rows outside its first visible frame")
check(ui.hit(growing,growing.menu.x+20,pending_y,3.3).id=="menu","hidden destination rows stay passive during a page slide")
check(ui.active_transition(growing,3.6)==nil,"native capture stops using a stale panel after its deadline")
local returning=frame(3.4)
local old_left=text_x(returning,string.format("%.2fx",animated_state.speed))-animator.old_menu.menu.w/2
local new_right=text_x(returning,"Audio track")-64+growing.menu.w
check(math.abs(old_left-new_right)<.05,"back navigation also keeps unequal-width page contents separated")

-- Thumbnail lifecycle: one worker, cache reuse/eviction, stale-job cleanup and fallback.
local jobs, files, removed, messages = {}, {}, {}, {}
local original_remove=os.remove
os.remove=function(path) removed[path]=true; return original_remove(path) end
local fake_mp={msg={verbose=function() end}}
function fake_mp.add_timeout(_,fn)
    return {fn=fn,enabled=false,resumes=0,kill=function(t) t.enabled=false end,
        is_enabled=function(t) return t.enabled end,
        resume=function(t) t.enabled=true; t.resumes=t.resumes+1 end}
end
function fake_mp.register_script_message(name,fn) messages[name]=fn end
function fake_mp.commandv(...) end
function fake_mp.abort_async_command(id) jobs[id].aborted=true end
function fake_mp.command_native_async(command,callback)
    jobs[#jobs+1]={command=command,callback=callback}
    return #jobs
end
package.preload["mp"]=function() return fake_mp end
package.preload["mp.utils"]=function()
    return {file_info=function(path) return files[path] end,parse_json=function(value) return value end,
        join_path=function(a,b) return a.."/"..b end}
end
local opts={thumbnails="auto",thumbnail_delay=.18,thumbnail_interval=5,thumbnail_width=200,
    thumbnail_cache=2,ffmpeg_path="ffmpeg"}
local p=require("core.thumbnails").new(opts,function() end)
files["/video.mkv"]={is_file=true}
p:reset("/video.mkv",100)
check(p:provider()=="ffmpeg","local previews without thumbfast")
p:request(10); p.timer.fn()
p:request(30); p.timer.fn()
check(#jobs==1,"only one background worker")
local function finish(index)
    local job=jobs[index]
    local path=job.command.args[#job.command.args]
    files[path]={size=320*180*4}
    job.callback(true,{status=0})
    return path
end
finish(1); p.timer.fn(); finish(2)
check(p:request(31)~=nil,"cached bucket preview")
check(#jobs==2,"cache hit does not spawn a worker")
local first_path=p.entries[2].path
p:request(60); p.timer.fn(); finish(3)
check(p.entries[2]==nil and removed[first_path],"bounded cache evicts its oldest frame")
p:request(85); p.timer.fn()
local stale_path=jobs[4].command.args[#jobs[4].command.args]
p:reset("/video.mkv",100)
check(jobs[4].aborted,"file change aborts pending decode")
finish(4)
check(removed[stale_path] and next(p.entries)==nil,"stale callbacks cannot restore an old preview")
p:request(0); p.timer.fn(); jobs[5].callback(false,{status=-1})
check(p.full_decode and p.timer:is_enabled() and p:provider()=="ffmpeg","fast decode failure retries the normal path immediately")
p.timer.fn();jobs[6].callback(false,{status=-1})
check(p:provider()==nil,"missing FFmpeg falls back to timestamps")
p:reset("https://example.test/live",nil)
check(p:provider()==nil,"FFmpeg never opens network streams")
messages["thumbfast-info"]({width=320,height=180,available=true,disabled=false})
check(p:provider()=="thumbfast","external provider takes precedence when ready")
check(p:request(25).physical==true,"thumbfast coordinates use physical pixels")
p:reset("/audio.mp3",24,false)
check(p:provider()==nil and p:request(10)==nil,"audio-only files skip both thumbnail providers")
opts.thumbnails="no"
check(p:provider()==nil,"preview disable option")

-- A moving pointer must not postpone generation. The latest requested frame precedes prefetch.
opts.thumbnails,opts.thumbnail_cache,opts.thumbnail_delay="ffmpeg",3,.03
p:reset("/video.mkv",1000)
local base=#jobs
local resumes=p.timer.resumes
p:request(10); p:request(20); p:request(30)
check(p.timer.resumes==resumes+1,"continuous motion does not restart the initial timer")
p.timer.fn()
local function seek_argument(index)
    local args=jobs[index].command.args
    for i,arg in ipairs(args) do if arg=="-ss" then return tonumber(args[i+1]) end end
end
check(seek_argument(base+1)==30,"first decode uses the latest pointer position")
p:request(90); p:request(100)
finish(base+1)
check(p.timer.timeout==0,"queued positions do not wait for another debounce delay")
p.timer.fn()
check(seek_argument(base+2)==100,"requested position takes priority over neighboring frames")
finish(base+2); p.timer.fn(); finish(base+3); p.timer.fn(); finish(base+4)
check(p.entries[20] and p.entries[19] and p.entries[21],"both neighboring frames are prepared")
check(#p.order==3,"prefetch stays inside the cache limit and retains the hovered frame")
local warmed=#jobs
check(p:request(105)~=nil and #jobs==warmed,"scanning into a warmed neighbor is immediate")
local nearby=p:request(110)
check(nearby and nearby.entry==p.entries[21],"adjacent cached frame remains visible during a new decode")
p:hide()
check(not p.timer:is_enabled(),"leaving the timeline cancels queued prefetch")

-- A new uncached hover interrupts prefetch, without letting its late callback clear the new job.
p:reset("/video.mkv",1000,true,2)
base=#jobs
p:request(10);p.timer.fn();finish(base+1);p.timer.fn()
check(p.prefetching,"a cached hover schedules a neighboring frame")
p:request(300)
check(jobs[base+2].aborted,"unrelated prefetch is aborted for a new foreground position")
p.timer.fn()
check(seek_argument(base+3)==300,"new hover starts immediately after prefetch cancellation")
finish(base+2)
check(p.job==base+3 and not p.entries[3],"late aborted prefetch cannot affect the active worker/cache")
local map
for i,arg in ipairs(jobs[base+3].command.args) do if arg=="-map" then map=jobs[base+3].command.args[i+1] end end
check(map=="0:2","FFmpeg previews the selected native stream index")
local decoder_args=jobs[base+3].command.args
local decoder_flags={}
for i,arg in ipairs(decoder_args) do if arg:sub(1,1)=="-" then decoder_flags[arg]=decoder_args[i+1] end end
check(decoder_flags["-filter_threads"]=="1" and decoder_flags["-probesize"]=="32768" and decoder_flags["-skip_frame"]=="noref",
    "fast previews bound scaling/probing and skip frames unused by the decoder")
finish(base+3)
p:display({x=12,y=12,w=200,h=112,entry=p.entries[60]},1)
check(p.shown~=nil,"FFmpeg frame has its own overlay")
opts.thumbnails="auto"
p:request(300)
check(p.shown==nil and p.wanted.provider=="thumbfast","provider handoff clears the previous bitmap")
p:display({x=12,y=12,w=320,h=180},1)
opts.thumbnails="ffmpeg"
p:request(300)
check(not p.thumbfast_shown,"returning to FFmpeg clears the external provider")
p.timer.fn()
p:set_video({["ff-index"]=3})
check(next(p.entries)==nil and p.stream_index==3 and not p.job,"video track changes invalidate cached/pending frames")
p:set_video(nil)
check(p:provider()==nil,"disabling video stops thumbnail decoding")
messages["thumbfast-info"]({width=0,height=180,available=true})
check(p.thumbfast.width==320,"malformed provider dimensions cannot replace a usable announcement")
p:set_video({["ff-index"]=2})
p:request(0);p.timer.fn()
local hidden_job=p.job
p:hide();opts.thumbnails="auto";p:request(0)
check(jobs[hidden_job].aborted and not p.job,"external provider cancels a worker left by a previous hidden hover")
-- A valid file can need full probing/decoding; the retry must restore usable previews.
opts.thumbnails="ffmpeg"
p:reset("/video.mkv",1000)
base=#jobs
p:request(10);p.timer.fn();jobs[base+1].callback(true,{status=0})
p.timer.fn()
local retry_flags={}
for i,arg in ipairs(jobs[base+2].command.args) do if arg:sub(1,1)=="-" then retry_flags[arg]=jobs[base+2].command.args[i+1] end end
check(retry_flags["-probesize"]=="5000000" and retry_flags["-skip_frame"]=="default","empty fast output retries normal probing and all frames")
finish(base+2)
check(p:request(10)~=nil,"the full decode retry restores a cached preview")
p:shutdown()

-- Caption actions preserve channel alpha/hue and restore the startup configuration exactly.
local caption_properties={["sub-font"]="Arial",["sub-font-size"]=42,["sub-color"]="#FFFFFFFF",
    ["sub-back-color"]="#AF000000",["sub-border-style"]="outline-and-shadow",
    ["sub-outline-size"]=1.65,["sub-shadow-offset"]=0,["sub-outline-color"]="#FF000000",
    ["sub-ass-override"]="scale"}
local original,observers,writes={},{},0
local notify_captions=true
for key,value in pairs(caption_properties) do original[key]=value end
function fake_mp.get_property_native(name,fallback) return caption_properties[name] or fallback end
function fake_mp.observe_property(name,_,callback) observers[name]=callback end
function fake_mp.set_property_native(name,value)
    name=({["sub-border-size"]="sub-outline-size",["sub-border-color"]="sub-outline-color"})[name] or name
    writes=writes+1; caption_properties[name]=value
    if notify_captions and observers[name] then observers[name](name,value) end
    return true
end
fake_mp.msg.warn=function(message) error(message) end
local captions=require("core.captions")
local cs={}
local caption_service=captions.new(cs,function() end)
check(writes==0,"loading the skin leaves native caption styling alone")
check(captions.rows(cs,"captions")[5].value=="0%","no box is displayed as zero background opacity")
caption_service.apply("background-opacity",75)
check(caption_properties["sub-border-style"]=="background-box","opacity enables a real subtitle box")
check(caption_properties["sub-back-color"]=="#BF000000","75% background opacity uses alpha first")
caption_service.apply("background","0000ff")
check(caption_properties["sub-back-color"]=="#BF0000FF","background color preserves opacity")
caption_service.apply("opacity",50); caption_service.apply("color","ffff00")
check(caption_properties["sub-color"]=="#80FFFF00","font hue preserves 50% opacity")
caption_service.apply("size",150)
check(caption_properties["sub-font-size"]==63,"size percentages use the startup font size")
caption_service.apply("edge","None")
check(caption_properties["sub-outline-size"]==0 and caption_properties["sub-shadow-offset"]==4,"None removes the outline while retaining box padding")
caption_service.apply("edge","Drop shadow")
check(caption_properties["sub-border-style"]=="outline-and-shadow" and caption_properties["sub-shadow-offset"]==2,"shadow selects MPV's shadow renderer")
caption_service.apply("reset")
for key,value in pairs(original) do check(caption_properties[key]==value,"Reset restores "..key) end
fake_mp.set_property_native("sub-color","#FF00FF00")
check(captions.rows(cs,"captions")[2].value=="Green","external styling updates the menu")
-- Real MPV defers observers. Every choice must still move its checkmark immediately.
notify_captions=false
for _,page in ipairs({"caption-font","caption-color","caption-size","caption-background",
    "caption-background-opacity","caption-edge","caption-opacity"}) do
    for index,row in ipairs(captions.rows(cs,page)) do
        caption_service.apply(row.action.caption,row.action.value)
        local selected=0
        for _,updated in ipairs(captions.rows(cs,page)) do if updated.selected then selected=selected+1 end end
        check(selected==1 and captions.rows(cs,page)[index].selected,"accepted choice updates its only checkmark: "..page.." "..row.label)
    end
end
caption_service.apply("opacity",25);caption_service.apply("color","00ff00")
check(caption_properties["sub-color"]=="#4000FF00","rapid choices preserve the latest opacity before observers run")
caption_service.apply("reset")
check(cs.caption_style["sub-font"]=="Arial" and cs.caption_style["sub-outline-size"]==1.65,"Reset refreshes menu state before observers run")

-- Border aliases do not emit the canonical option's change notifications on tested MPV.
check(observers["sub-outline-size"] and observers["sub-outline-color"] and not observers["sub-border-size"],"caption menus observe canonical outline options")
notify_captions=true
fake_mp.set_property_native("sub-border-size",2)
check(captions.rows(cs,"caption-edge")[3].selected,"external alias writes refresh the native edge checkmark")
local accepted_setter=fake_mp.set_property_native
fake_mp.set_property_native=function() return false,"test rejection" end
local warnings=0
fake_mp.msg.warn=function() warnings=warnings+1 end
caption_service.apply("font","serif")
check(warnings>0 and cs.caption_style["sub-font"]=="Arial","rejected choices do not claim a successful selection")
fake_mp.set_property_native=accepted_setter
fake_mp.msg.warn=function(message) error(message) end
for _,page in ipairs({"captions","caption-color","caption-background-opacity","caption-size"}) do
    s.w,s.h,s.menu,s.menu_scroll=300,180,page,99
    local _,small=ui.render(s,o)
    check(small.menu.y>=0 and small.menu.x>=0,"caption menu fits a small window: "..page)
end

-- Sleep timers cancel old deadlines and pause at expiry without closing the player.
local sleep=require("core.player")
local timers={}
function fake_mp.add_timeout(duration,callback)
    local timer={duration=duration,callback=callback,killed=false}
    function timer:kill() self.killed=true end
    timers[#timers+1]=timer
    return timer
end
function fake_mp.set_property_bool(name,value) caption_properties[name]=value end
local ss={}
local sleep_service=sleep.new_sleep_timer(ss,{show=function() end,feedback=function() end})
sleep_service.set(10)
check(timers[1].duration==600 and ss.sleep_minutes==10,"ten minute timer uses wall-clock seconds")
sleep_service.set(15)
check(timers[1].killed and timers[2].duration==900,"changing the timer cancels the old deadline")
timers[2].callback()
check(caption_properties.pause==true and not ss.sleep_minutes,"timer expiry pauses and clears the selection")
sleep_service.set(20); sleep_service.set(0)
check(timers[3].killed and not ss.sleep_minutes,"Off cancels a running timer")
sleep_service.set(30); sleep_service.shutdown()
check(timers[4].killed,"shutdown cancels the sleep timer")

-- Exercise the actual action dispatcher, with native writes replaced by recorded values.
function fake_mp.get_property_number(name,fallback) return caption_properties[name] or fallback end
function fake_mp.set_property_number(name,value) caption_properties[name]=value end
function fake_mp.get_property_bool(name,fallback)
    local value=caption_properties[name]
    if value==nil then return fallback end
    return value
end
local playback={volume=75,mute=false,time_remaining=false}
local feedback_icon
local controller=sleep.new(playback,o,{show=function() end,request_render=function() end,
    feedback=function(_,icon) feedback_icon=icon end},{hide=function() end})
controller.action({kind="time"})
check(playback.time_remaining,"time action selects remaining mode")
controller.action({kind="time"})
check(not playback.time_remaining,"second time action restores elapsed mode")
playback.fullscreen,caption_properties.fullscreen=true,false
controller.action({kind="fullscreen"})
check(caption_properties.fullscreen==true,"fullscreen entry reads native state when an observer lags")
playback.fullscreen=false
controller.action({kind="fullscreen"})
check(caption_properties.fullscreen==false,"fullscreen exit reads native state when an observer lags")
controller.volume(70)
check(feedback_icon==nil and caption_properties.volume==70,"mouse volume updates sound without central feedback")
controller.action({kind="mute"})
check(feedback_icon==nil and caption_properties.mute,"mouse mute has no central feedback")
controller.action({kind="mute",show_feedback=true})
check(feedback_icon=="volume_off","keyboard mute shows the crossed speaker")
controller.volume(70,true)
check(feedback_icon=="volume_down","decreasing volume uses the reference decrease icon")
controller.volume(80,true)
check(feedback_icon=="volume_up","increasing volume uses the reference increase icon")
controller.volume(0,true)
check(feedback_icon=="volume_off","zero volume uses the reference muted icon")
playback.mute,caption_properties.mute=true,true
controller.volume(80,true)
check(caption_properties.mute,"keyboard volume preserves mute, matching YouTube")
controller.volume(80)
check(not caption_properties.mute,"mouse volume unmutes a positive level")
fake_mp.set_property=fake_mp.set_property_native
playback.keep_open="no"
controller.action({kind="autoplay"})
check(caption_properties["keep-open"]=="always","Autoplay Off owns a temporary end-of-file override")
caption_properties["keep-open"]="yes"
controller.shutdown()
check(caption_properties["keep-open"]=="yes","shutdown preserves a later native end-of-file policy change")
controller.action({kind="autoplay"});controller.shutdown()
check(caption_properties["keep-open"]=="no","shutdown restores an override still owned by the skin")

-- Input lifecycle runs real handlers with a deterministic pointer and cancellable clock.
local input_timers,bindings,events={}, {}, {}
local pointer_x,pointer_y,pauses=480,250,0
function fake_mp.add_timeout(duration,callback,disabled)
    local timer={timeout=duration,callback=callback,enabled=not disabled}
    function timer:kill() self.enabled=false end
    function timer:resume() self.enabled=true end
    function timer:is_enabled() return self.enabled end
    input_timers[#input_timers+1]=timer
    return timer
end
function fake_mp.get_time() return 1 end
function fake_mp.get_mouse_pos() return pointer_x,pointer_y end
function fake_mp.set_mouse_area() end
function fake_mp.enable_key_bindings() end
function fake_mp.set_key_bindings(keys)
    for _,key in ipairs(keys) do bindings[key[1]]=key[2] end
end
function fake_mp.add_forced_key_binding(_,name,callback) bindings[name]=callback end
function fake_mp.add_key_binding(_,name,callback) bindings[name]=callback end
function fake_mp.register_event(name,callback) events[name]=callback end
local input_state={w=960,h=600,scale=1,opacity=1,time=0,duration=24,speed=1,pause=false,
    volume=100,tracks={},chapters={},playlist={},mx=480,my=250,mouse_inside=true}
local noop=function() end
local input_view={show=noop,feedback=noop,request_render=noop,schedule_hide=noop,update_dimensions=noop}
local actions,menus_closed={},0
local input_player={action=function(descriptor) if descriptor and next(descriptor) then actions[#actions+1]=descriptor end end,
    pause=function() pauses=pauses+1 end,seek=noop,volume=noop,relative_seek=noop,subtitles=noop,
    close_menu=function() input_state.menu=nil;menus_closed=menus_closed+1 end}
local input_options={tooltip_delay=.45,video_click=true,keyboard=false,menu_width=380}
local input=require("core.input").new(input_state,input_options,input_view,input_player,{hide=noop})
local function mouse(event,x,y)
    pointer_x,pointer_y=x or 480,y or 250
    bindings.mouse_move()
    bindings["mouse-button"]({event=event})
end
local function fire_pending()
    for _,timer in ipairs(input_timers) do
        if timer.enabled then timer:kill();timer.callback() end
    end
end
mouse("up");fire_pending()
check(pauses==0,"an unmatched mouse release cannot toggle playback")
for _,event in ipairs({"file-loaded","end-file"}) do
    mouse("press");events[event]();fire_pending()
    check(pauses==0,"file lifecycle cancels pending video taps: "..event)
    mouse("down");events[event]();mouse("up");fire_pending()
    check(pauses==0 and not input_state.pressed,"old held releases do not act on the next file: "..event)
end
mouse("press");fire_pending()
check(pauses==1,"a normal video tap still pauses after the double-click deadline")
mouse("down",480,596);fire_pending();mouse("up",480,596);fire_pending()
check(pauses==1 and not input_state.speed_hold,"bottom safe area consumes taps and holds")
-- Menu dismissal uses the same hits as controls, including passive bar margins.
for _,page in ipairs({"settings","speed"}) do
    for _,point in ipairs({{6,573},{954,540},{480,596},{56,573},{480,50},{6,250}}) do
        input_state.menu=page
        local before=menus_closed
        mouse("down",point[1],point[2]);fire_pending();mouse("up",point[1],point[2]);fire_pending()
        check(not input_state.menu and menus_closed==before+1,"one outside click dismisses "..page)
        check(pauses==1 and not input_state.speed_hold,"dismissing a menu does not become a video tap or hold")
    end
end
input_state.menu="settings"
local panel=ui.layout(input_state,input_options).menu
mouse("press",panel.x+2,panel.y+2)
check(input_state.menu=="settings","inside panel padding keeps settings open")
mouse("press",panel.x+panel.w/2,panel.y+panel.padding+panel.row_h/2)
check(input_state.menu=="settings" and actions[#actions].page=="speed","inside rows retain their menu action")
input_state.menu_transition={x=panel.x-100,y=panel.y,w=panel.w+100,h=panel.h,deadline=2}
mouse("press",panel.x-50,panel.y+20)
check(input_state.menu=="settings","a sliding panel's captured area does not count as an outside click")
input_state.menu_transition=nil
-- Scoped right clicks dismiss without activating buttons or invoking native pause.
for _,page in ipairs({"settings","speed"}) do
    for _,point in ipairs({{6,573},{954,540},{480,596},{32,573},{480,50},{6,250}}) do
        input_state.menu=page
        local before,previous_actions=menus_closed,#actions
        pointer_x,pointer_y=point[1],point[2]
        bindings.mouse_move();bindings.MBTN_RIGHT();fire_pending()
        check(not input_state.menu and menus_closed==before+1,"one outside right click dismisses "..page)
        check(#actions==previous_actions and pauses==1,"right dismissal never activates a button or pauses")
    end
end
input_state.menu="settings"
pointer_x,pointer_y=panel.x+50,panel.y+30
bindings.mouse_move();bindings.MBTN_RIGHT()
check(input_state.menu=="settings","right clicks inside the panel leave its options unchanged")
input_state.menu=nil
pointer_x,pointer_y=32,573
bindings.mouse_move();bindings.MBTN_RIGHT()
check(pauses==1,"right clicks on the bottom play control cannot pause")
for _,id in ipairs({"settings","play","time","mute"}) do
    input_state.menu="speed"
    local layout=ui.layout(input_state,input_options)
    for _,hit in ipairs(layout.hits) do
        if hit.id==id then
            local before=#actions
            mouse("press",hit.x+hit.w/2,hit.y+hit.h/2)
            check(not input_state.menu,"bottom control dismisses the open submenu: "..id)
            check(#actions==before+(id=="settings" and 0 or 1),"settings closes without reopening; other controls retain their action: "..id)
        end
    end
end
mouse("press");input.shutdown();fire_pending()
check(pauses==1,"shutdown cancels pending input callbacks")
os.remove=original_remove
print(string.format("Passed %d regression checks",count))
