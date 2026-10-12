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

local o={title=true,pip=true,menu_width=380,menu_opacity=.6,
    accent="ff0033",font="Arial",tooltip_delay=.45,ffmpeg_path="ffmpeg",volume_max=200}
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
local hover_widths={play=32,previous=32,next=32,mute=103,autoplay=48,cc=48,settings=48,pip=48,fullscreen=48}
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
    "caption-background-opacity","caption-edge","controls","sync","exports","shortcuts","binding","mappings"}) do
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
                if hit.id~="timeline" then check(hit.action~=nil or hit.enabled==false,"available control must have an action: "..hit.id) end
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

-- Every central label gets its own background, with bounded text and space above the circle.
for _,size in ipairs({{300,180},{425,240},{960,600},{1440,900}}) do
    s.w,s.h,s.opacity=size[1],size[2],0
    for _,text in ipairs({"Synchronization reset","Export file already exists",string.rep("Long chapter / track name ",12)}) do
        s.feedback={icon="info",text=text,opacity=1,scale=1.33}
        local shapes,labels={},{}
        drawing.new=function(...)
            local canvas=original_canvas(...)
            local rect,label=canvas.rect,canvas.label
            function canvas:rect(x,y,w,h,...)
                shapes[#shapes+1]={x=x,y=y,w=w,h=h};return rect(self,x,y,w,h,...)
            end
            function canvas:label(role,x,y,text,...)
                labels[#labels+1]={role=role,x=x,y=y,text=text};return label(self,role,x,y,text,...)
            end
            return canvas
        end
        ui.render(s,o)
        local circle,card=shapes[1],shapes[2]
        check(#shapes==2 and #labels==1,"central feedback has one circle, one card and one label")
        check(card.x>=12 and card.x+card.w<=s.w-12 and card.y>=0,"feedback card fits narrow and wide players")
        check(card.y+card.h<circle.y,"feedback text background never overlaps the icon circle")
        local font_size=drawing.text_styles[labels[1].role][1]
        check(model.text_width(labels[1].text,font_size)<=card.w-40,"feedback label retains equal inner padding")
    end
end
drawing.new=original_canvas
s.w,s.h,s.feedback,s.opacity=1440,900,nil,1

s.menu,s.feedback="shortcuts",{icon="info",text="Transient notification",opacity=1,scale=1}
check(not ui.render(s,o):find("Transient notification",1,true),"central feedback never covers the shortcut workspace")
s.menu,s.feedback=nil,nil

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
local immediate,opened_speed=frame(1.4)
check(not immediate:find("Audio track",1,true),"page changes discard the previous menu immediately")
check(ui.hit(opened_speed,opened_speed.speed.x+10,opened_speed.speed.y+12).id=="speed-slider","new sliders accept clicks on the opening frame")
check(not animator.tracks["menu-opacity"],"menus have no opacity animation or input guard")
animated_state.menu=nil
local closed=frame(1.5)
check(not closed:find("Playback speed",1,true),"closing removes menu content immediately")
animated_state.hover,animated_state.hover_age="play",1
frame(2.1);frame(2.4)
check(animator.tooltip~=nil,"stable hover retains the visible tooltip")
animated_state.hover=nil
frame(2.5)
check(animator.tooltip~=nil,"departing tooltip remains during its fade")
frame(2.8)
check(animator.tooltip==nil and not animator.active,"tooltip fade clears cached content and stops animating")
animated_state.menu="settings"
local direct,settings_layout=frame(3)
check(direct:find("Audio track",1,true),"return navigation paints its destination immediately")
check(settings_layout.menu.y+settings_layout.menu.h==animated_state.h-62,"immediate panels retain their bottom margin")
animated_state.menu=nil

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
opts.ffmpeg_available=false
check(p:provider()==nil and p:request(10)==nil and #jobs==0,"missing FFmpeg disables previews without starting a failed worker")
opts.ffmpeg_available=true
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

function fake_mp.set_property_bool(name,value) caption_properties[name]=value end
local player_module=require("core.player")
-- Exercise the actual action dispatcher, with native writes replaced by recorded values.
function fake_mp.get_property_number(name,fallback) return caption_properties[name] or fallback end
function fake_mp.set_property_number(name,value) caption_properties[name]=value end
function fake_mp.get_property_bool(name,fallback)
    local value=caption_properties[name]
    if value==nil then return fallback end
    return value
end
local playback={volume=75,mute=false,time_remaining=false}
local feedback_icon,feedback_text
local controller=player_module.new(playback,o,{show=function() end,request_render=function() end,
    feedback=function(text,icon) feedback_text,feedback_icon=text,icon end},{hide=function() end})
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
feedback_icon=nil
controller.volume(70)
check(feedback_icon==nil and caption_properties.volume==70,"mouse volume updates sound without central feedback")
controller.speed(1.05)
check(feedback_text=="1.05×","speed feedback preserves fine slider increments")
controller.speed(1.25)
check(feedback_text=="1.25×","speed feedback preserves preset precision")
controller.action({kind="frame",value=1})
check(feedback_text=="No video frames","frame actions explain unavailable audio-only frames")
caption_properties["load-console"]=false
controller.action({command="script-binding console/enable"})
check(feedback_text=="MPV console is disabled","disabled native tools report their dependency instead of executing a fake action")
caption_properties["load-console"]=nil
feedback_icon=nil
controller.action({kind="mute"})
check(feedback_icon==nil and caption_properties.mute,"mouse mute has no central feedback")
controller.action({kind="mute",show_feedback=true})
check(feedback_icon=="volume_up","keyboard mute reads native state before restoring the speaker")
caption_properties.volume=75
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
function fake_mp.get_script_name() return "mpvtube" end
function fake_mp.get_mouse_pos() return pointer_x,pointer_y end
function fake_mp.set_mouse_area() end
function fake_mp.enable_key_bindings() end
function fake_mp.set_key_bindings(keys)
    for _,key in ipairs(keys) do bindings[key[1]]=key[2] end
end
function fake_mp.remove_key_binding(name) bindings[name]=nil end
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
local input_options={tooltip_delay=.45,video_click=true,keyboard=false,menu_width=380,keymap_path=os.tmpname(),shortcut_policy="mpvtube"}
os.remove(input_options.keymap_path)
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
for _,page in ipairs({"settings","audio","sub","captions","caption-font","speed","shortcuts"}) do
    for _,id in ipairs({"settings","cc","audio"}) do
        input_state.menu=page
        local layout=ui.layout(input_state,input_options)
        for _,hit in ipairs(layout.hits) do
            if hit.id==id then
                local before=#actions
                mouse("press",hit.x+hit.w/2,hit.y+hit.h/2)
                check(not input_state.menu and #actions==before,"any settings view closes when clicking "..id..": "..page)
            end
        end
    end
end
mouse("press");input.shutdown();fire_pending()
check(pauses==1,"shutdown cancels pending input callbacks")
-- Short control labels must fit alongside their shortcut column, using the painted insets.
s.w,s.h,s.menu,s.menu_scroll=960,600,"controls",99
local full_labels={}
local label_canvas=drawing.new(1,"Roboto")
function label_canvas:label(role,_,_,text) if role=="body" then full_labels[text]=true end end
require("ui.menu").render(label_canvas,s,ui.layout(s,o),o)
check(full_labels["MPV properties"],"native properties label fits beside its shortcut without unnecessary truncation")

-- Configurable seek tiers and live bindings use one registry without overlapping assignments.
local shortcuts=require("core.shortcuts")
local assigned={}
for _,binding in ipairs(shortcuts.defaults({seek_precise=1,seek_short=2,seek_medium=20,seek_long=120})) do
    check(not assigned[binding.key],"shortcut has one assignment: "..binding.key)
    assigned[binding.key]=binding.action
end
local custom_steps={}
for _,binding in ipairs(shortcuts.defaults({volume_step=2,sync_step=.025})) do custom_steps[binding.key]=binding end
check(custom_steps.UP.action.value==2 and custom_steps.DOWN.action.value==-2,"volume keys share the configured percentage step")
check(custom_steps.g.action.value==-.025 and custom_steps.k.action.value==.025,"sync keys share the configured seconds step")
check(shortcuts.category(custom_steps["Alt+c"].action)=="Subtitles" and custom_steps["Alt+c"].action.page=="sub","subtitle selector has its own categorized shortcut")
check(assigned.RIGHT.value==2 and assigned["Shift+RIGHT"].value==1 and assigned["Ctrl+LEFT"].value==-20 and assigned["Ctrl+Alt+LEFT"].value==-120,"all seek tiers respect configured seconds")
check(assigned.j.kind=="delay" and assigned.k.kind=="delay" and assigned.g.track=="sub","VLC synchronization keys replace conflicting playback keys")
local live=shortcuts.active({{key="a",cmd="weak",priority=10,is_weak=true},{key="a",cmd="user",priority=1,is_weak=false},
    {key="a",cmd="focused",priority=2,is_weak=false},{key="b",cmd="disabled",priority=-1},{key="c",cmd="ignore",priority=1}})
check(#live==1 and live[1].cmd=="focused","guide reports the effective strong binding, excluding disabled/ignored keys")
local blocked={{section="default",key="d",cmd="native",priority=0,is_weak=true},
    {section="default",key="x",cmd="user",priority=0,is_weak=false},
    {section="mpvtube-shortcuts",key="x",cmd="skin",priority=4,is_weak=false},
    {section="mpvtube-shortcuts",key="UNMAPPED",cmd="ignore",priority=4,is_weak=false},
    {section="console",key="ESC",cmd="close",priority=5,is_weak=false}}
local owned={shortcut_exclusive=true,shortcuts={}}
local effective=shortcuts.effective(owned,blocked)
check(#effective==2 and effective[1].key=="ESC" and effective[2].cmd=="skin","exclusive guide hides shadowed native/user bindings but retains later native panels")
check(not shortcuts.conflict(owned,"new","d",blocked),"suspended native bindings cannot cause false shortcut conflicts")
check(shortcuts.conflict(owned,"new","x",blocked),"effective owned assignments still block conflicts")
-- Canonical conflicts and tooltip labels share the same registry, without accepting duplicates.
check(shortcuts.normalize("Shift+c")==shortcuts.normalize("C"),"Shift+letter aliases normalize to the same key")
check(shortcuts.normalize("Alt+Ctrl+RIGHT")=="Ctrl+Alt+RIGHT","modifier order is canonical")
local key_state={shortcuts={{id="one",key="x",label="One",action={kind="pause"},command="own/one"},
    {id="two",key="C",label="Two",action={kind="subtitles"},command="own/two"}}}
check(shortcuts.conflict(key_state,"one","Shift+c",{}):find("Two",1,true),"duplicate detection catches equivalent Shift notation")
check(shortcuts.conflict(key_state,"one","d",{{key="d",cmd="cycle deinterlace",priority=0,is_weak=true}}):find("deinterlace",1,true),"active native assignments block edits")
check(not shortcuts.conflict(key_state,"one","d",{{key="d",cmd="cycle deinterlace",priority=-1,is_weak=true}}),"exclusive-mode suspended assignments do not occupy keys")
check(shortcuts.conflict(key_state,"one","ENTER",{}),"activation key is reserved")
check(not shortcuts.conflict(key_state,"one","none",{}),"owned assignments can be disabled")
shortcuts.refresh(key_state,{{key="x",cmd="own/one",priority=0,is_weak=false}})
check(shortcuts.tip(key_state,{kind="pause"},"Play")=="Play (x)","tooltips show actual active keys")
check(shortcuts.tip(key_state,{kind="subtitles"},"CC")=="CC","overridden keys are not advertised as available")
check(shortcuts.hint(key_state,{kind="pause"})=="x","menu hints reuse live tooltip assignments")
local reset_state={shortcut_exclusive=true,shortcuts={
    {id="one",key="b",default="a",label="One"},{id="two",key="a",default="b",label="Two"}}}
local reset_routes={{section="mpvtube-shortcuts",key="UNMAPPED",cmd="ignore",priority=4,is_weak=false},
    {section="mpvtube-shortcuts",key="a",cmd="old-two",priority=4,is_weak=false},
    {section="default",key="a",cmd="native",priority=0,is_weak=false}}
check(not shortcuts.conflict(reset_state,"one","a",reset_routes,true),"reset validates defaults together and ignores old swapped keys and shadowed native routes")
reset_routes[#reset_routes+1]={section="another-script",key="a",cmd="external",priority=5,is_weak=false}
check(shortcuts.conflict(reset_state,"one","a",reset_routes,true):find("external",1,true),"reset still detects an effective external conflict before changing any assignment")
local hints_state=setmetatable({shortcut_hints={["audio::"]="F12",["sub::"]="Alt+c",["shortcuts::"]="F1"}},{__index=s})
for _,row in ipairs(ui.menu_rows(hints_state,"settings",o)) do
    if row.label=="Audio track" then check(row.shortcut=="F12","settings show remapped selector keys") end
    if row.label=="Subtitles/CC" then check(row.shortcut=="Alt+c","settings distinguish opening captions from toggling them") end
end
for _,width in ipairs({300,600,1440}) do
    local top_state=setmetatable({w=width,h=900,menu=false},{__index=s})
    local layout=ui.layout(top_state,o)
    for _,button in ipairs(layout.buttons) do
        if button.id=="native-menu" then
            check(button.top and button.y==10 and button.y+button.h<layout.safe_area.y,"MPV menu stays in the top tools across window sizes")
            if layout.info then check(button.x+button.w<layout.info_area.x,"native menu and information hit areas do not overlap") end
        end
    end
end
local diagnostic_rows=ui.menu_rows({active_bindings={{key="a",cmd="external",owner="other-script",priority=5}}},"bindings",o)
check(diagnostic_rows[1].action.binding.owner=="other-script" and diagnostic_rows[#diagnostic_rows].kind=="notice" and diagnostic_rows[#diagnostic_rows].label:find("Read-only",1,true),"input diagnostics expose the actual owner and explain their troubleshooting purpose")
local reset_rows=ui.menu_rows(s,"shortcut-reset",o)
check(reset_rows[1].action.shortcut=="reset-all" and reset_rows[2].action.page=="shortcuts" and reset_rows[2].shortcut=="Esc" and reset_rows[#reset_rows].pinned,"reset confirmation shares ordinary actions, navigation hints and a passive explanation")
local old_tracks,old_menu,old_size=s.tracks,s.menu,{s.w,s.h}
s.w,s.h,s.menu=960,600,"sub"
s.tracks={}
for id=1,30 do s.tracks[#s.tracks+1]={type="sub",id=id,lang="en"} end
local footer_y
for _,offset in ipairs({0,15,99}) do
    s.menu_scroll=offset
    local panel=ui.layout(s,o)
    local footer=panel.hits[#panel.hits]
    check(footer.pinned and footer.row.label=="Clean subtitle style","clean styling remains outside the scrolling track list")
    check(not footer_y or footer_y==footer.y,"pinned subtitle footer does not move while scrolling")
    footer_y=footer.y
end
s.tracks,s.menu,s.w,s.h,s.menu_scroll=old_tracks,old_menu,old_size[1],old_size[2],0
local controls_rows=ui.menu_rows(s,"controls",o)
local categories={}
for _,row in ipairs(controls_rows) do
    if row.kind=="section" then categories[row.label]=true end
    if row.label=="Export tracks" then check(not row.action and row.disabled,"missing FFmpeg disables the export entry") end
end
check(categories.Subtitles and categories.Audio and categories.Playback and categories.Synchronization,"more controls separates related actions by category")
local chapter_time=s.time
for _,time in ipairs({0,s.duration}) do
    s.time=time
    for _,row in ipairs(ui.menu_rows(s,"controls",o)) do
        if row.label==(time==0 and "Previous chapter" or "Next chapter") then
            check(row.disabled and not row.action,"chapter menu boundaries match the bar's disabled buttons")
        end
        if row.label=="Previous subtitle track" or row.label=="Next audio track" then
            check(row.disabled and not row.action,"single-track navigation is unavailable in both menu and bar")
        end
    end
end
s.time=chapter_time
local settings_rows=ui.menu_rows(s,"settings",o)
check(settings_rows[4].label=="Export tracks" and settings_rows[4].disabled,"export has a prominent disabled entry in Settings without FFmpeg")
for _,button in ipairs(ui.layout(s,o).buttons) do
    if button.id=="cc" then check(button.action.page=="sub","CC opens the subtitle selector like the audio button") end
end
-- Shortcut information stays passive; actions reuse ordinary menu rows and notices stay fixed.
local editor={w=1440,h=900,menu="binding",menu_scroll=0,key_edit="one",
    shortcuts={{id="one",key="SPACE",default="SPACE",label="Play / pause"}}}
for _,size in ipairs({{1440,900},{600,360},{300,180}}) do
    editor.w,editor.h=size[1],size[2]
    local before
    for _,tone in ipairs({"info","error","success"}) do
        editor.keymap_tone=tone
        editor.keymap_message=tone=="error" and "Already used: Fullscreen" or tone=="success" and "Saved" or "Ready to save"
        local panel=require("ui.menu").geometry(editor,o)
        local notice=panel.rows[#panel.rows]
        check(notice.kind=="notice" and notice.pinned and not notice.action,"shortcut status is separate from selectable options")
        check(panel.y>=0 and panel.y+panel.h<=editor.h,"shortcut editor stays within small and large windows")
        check(not before or before==panel.y,"changing status does not move the shortcut controls")
        before=panel.y
        check(panel.rows[2].kind=="summary" and panel.rows[2].current=="Space" and panel.rows[3].divider and panel.rows[3].action.shortcut=="capture","current/proposed keys share one information block, separated from commands")
    end
end
editor.w,editor.h,editor.key_candidate,editor.keymap_tone=1440,900,"F12","error"
local editor_canvas=drawing.new(1,"Roboto")
local insets,status_color,editor_shapes={},nil,{}
local editor_rect=editor_canvas.rect
function editor_canvas:rect(x,y,w,h,...)
    editor_shapes[#editor_shapes+1]={x=x,y=y,w=w,h=h}
    return editor_rect(self,x,y,w,h,...)
end
function editor_canvas:label(role,x,_,text,color)
    if role=="field_label" or role=="body" then insets[text]=x end
    if role=="tooltip" and text:find("Error: ",1,true) then status_color=color end
end
local editor_layout=ui.layout(setmetatable(editor,{__index=s}),o)
editor.hover,editor_canvas.state="row-2",editor
require("ui.menu").render(editor_canvas,editor,editor_layout,o)
check(insets["Current key"]==editor_layout.menu.x+32,"shortcut information keeps its paired inset")
check(insets["Record new shortcut"]==editor_layout.menu.x+16 and insets["Save changes"]==insets["Record new shortcut"],"editor actions reuse the ordinary menu text inset")
check(insets["New key"]==editor_layout.menu.x+32+(editor_layout.menu.w-64)/2,"wide editors group current/new information in two columns")
for _,hit in ipairs(editor_layout.hits) do
    if hit.row and hit.row.kind=="summary" then
        check(not hit.action,"shortcut information cannot be clicked or focused")
        for _,shape in ipairs(editor_shapes) do
            check(not (shape.y>=hit.y and shape.y+shape.h<=hit.y+hit.h),"shortcut information has no button-like box or hover fill")
        end
    elseif hit.row and hit.row.action and hit.row.action.shortcut then
        check(hit.x==editor_layout.menu.x+editor_layout.menu.padding and hit.w==editor_layout.menu.w-2*editor_layout.menu.padding and hit.h==editor_layout.menu.row_h and hit.hover_radius==0,"shortcut actions reuse full-width menu hit and hover geometry")
    end
end
check(status_color=="ff8a80","error guidance has a distinct semantic color")
local long_command=string.rep("字幕 example ",20)
check(table.concat(model.wrap(long_command,100,14))==long_command,"command inspection wraps without losing UTF-8 or spaces")
local prose="Restore default keys. Replace saved edits."
local prose_lines=model.wrap(prose,228,13,true)
check(table.concat(prose_lines)==prose and #prose_lines==2 and prose_lines[1]:match("%s$"),"compact notices wrap at spaces without splitting words or changing text")
for _,line in ipairs(model.wrap(long_command,100,14,true)) do check(model.text_width(line,14)<=100,"word wrapping still bounds long UTF-8 tokens") end

-- Native track IDs, delays, amplification and clean subtitle overrides share action dispatch.
playback.tracks={{type="sub",id=3},{type="sub",id=12,external=true},{type="audio",id=4},{type="audio",id=20}}
caption_properties.sid,caption_properties.aid=3,4
controller.action({kind="track-step",track="sub",value=1})
check(caption_properties.sid==12 and caption_properties["sub-visibility"],"subtitle next includes a dynamically added track")
controller.action({kind="track-step",track="sub",value=1})
check(caption_properties.sid==3,"subtitle cycling wraps nonconsecutive IDs")
controller.action({kind="track-step",track="audio",value=-1})
check(caption_properties.aid==20,"audio previous wraps IDs")
controller.action({kind="subtitles"})
check(caption_properties["sub-visibility"]==false and caption_properties.sid==3,"CC Off retains the subtitle ID")
check(feedback_icon=="cc" and feedback_text=="Subtitles off","subtitle toggle provides shared on-screen feedback")
controller.action({kind="subtitles"})
check(caption_properties.sid==3 and caption_properties["sub-visibility"] and feedback_text:find("Subtitles: ",1,true)==1,"subtitle toggle restores the retained track and announces it")
controller.action({property="sub-visibility",value=false})
check(feedback_text=="Subtitles off" and caption_properties.sid==3,"selector Off shares toggle semantics and feedback")
caption_properties["sub-delay"],caption_properties["audio-delay"]=0,0
controller.action({kind="delay",track="sub",value=-.05})
controller.action({kind="delay",track="audio",value=.05})
check(caption_properties["sub-delay"]==-.05 and caption_properties["audio-delay"]==.05,"sync controls independently advance/delay by 50 ms")
controller.action({kind="sync-reset"})
check(caption_properties["sub-delay"]==0 and caption_properties["audio-delay"]==0,"sync reset clears both native delays")
caption_properties["volume-max"]=200
controller.volume(180);check(caption_properties.volume==180,"volume supports amplification above 100%")
controller.volume(300);check(caption_properties.volume==200,"volume clamps at the configured native ceiling")
caption_properties["volume-max"]=150
controller.volume(180);check(caption_properties.volume==150,"external native ceiling changes take effect immediately")
caption_service.apply("reset")
local authored={}
for _,field in ipairs({"sub-font","sub-ass-override","sub-font-size","sub-color"}) do authored[field]=caption_properties[field] end
caption_service.override()
check(caption_properties["sub-ass-override"]=="strip" and caption_properties["sub-font"]=="Roboto","clean subtitles strip authored styles and use Roboto")
caption_service.apply("font","serif")
check(caption_properties["sub-ass-override"]=="strip","appearance changes retain a universal override")
caption_service.override()
for field,value in pairs(authored) do check(caption_properties[field]==value,"override Off restores the pre-toggle setting: "..field) end

-- A preconfigured strip policy can be disabled, while Reset still honors startup settings.
caption_properties["sub-ass-override"]="strip"
local startup_strip=captions.new({},function() end)
startup_strip.override()
check(caption_properties["sub-ass-override"]=="scale","Off allows authored styles even when MPV started in strip mode")
startup_strip.apply("reset")
check(caption_properties["sub-ass-override"]=="strip","Reset preserves a startup strip preference")
caption_properties["sub-ass-override"]="scale"

-- Export planning refuses remote paths/unsupported codecs and uses native stream indices.
local exporter=require("core.export")
local export_state={path="/tmp/a video.mkv",sid=7,aid=8,tracks={
    {type="sub",id=7,codec="ass",["ff-index"]=4,lang="../../en"},
    {type="sub",id=9,codec="dvd_subtitle",["ff-index"]=5},
    {type="sub",id=10,codec="webvtt",external=true,["external-filename"]="https://example.com/a.vtt"},
    {type="audio",id=8,codec="opus",["ff-index"]=2},{type="audio",id=20,codec="aac",["ff-index"]=3}}}
local planned,error,skipped=exporter.plan(export_state,"sub",true)
check(#planned==1 and planned[1].index==4 and planned[1].format=="ass" and skipped==1,"all embedded exports skip unsupported tracks, preserving stream indices")
check(planned[1].path=="/tmp/a video.sub-7.______en.ass","export names sanitize metadata without changing the source path")
export_state.sid=10
check(#exporter.plan(export_state,"sub",false)==0,"remote external subtitles cannot be exported through the local worker")
export_state.path="https://example.com/video.mkv"
check(#exporter.plan(export_state,"audio",true)==0,"remote media never starts local extraction")
export_state.path="/tmp/a video.mkv"
local base_job=#jobs
local export_service=exporter.new(export_state,o,{request_render=noop,feedback=noop})
jobs[base_job+1].callback(true,{status=0})
export_service.start("audio",true)
check(#jobs==base_job+2,"batch export starts only one worker")
local first_export=jobs[base_job+2].command.args
check(table.concat(first_export," "):find("-map 0:2",1,true) and table.concat(first_export," "):find("-c copy",1,true),"exports copy the selected source stream losslessly")
export_service.start("audio",false)
check(#jobs==base_job+2,"another export cannot start while a batch runs")
jobs[base_job+2].callback(true,{status=0})
check(#jobs==base_job+3,"the next track waits for the first worker")
jobs[base_job+3].callback(true,{status=0})
check(export_state.export_status=="Exported 2 track(s)","export batch reports completion")
local target=exporter.plan(export_state,"audio",false)[1].path
files[target]={size=10}
export_service.start("audio",false)
check(#jobs==base_job+3 and export_state.export_status:find("File exists:",1,true),"existing output files are never overwritten")
files[target]=nil
export_service.start("audio",false)
local aborted=#jobs
export_service.shutdown()
check(jobs[aborted].aborted,"shutdown cancels active export")
local last_status=export_state.export_status
jobs[aborted].callback(true,{status=0})
check(export_state.export_status==last_status,"late export completion cannot revive a cancelled worker")

-- Missing or failed extraction cannot advertise readiness or falsely complete a batch.
local unavailable={path=export_state.path,tracks=export_state.tracks,aid=8}
local probe_index=#jobs+1
local unavailable_service=exporter.new(unavailable,o,{request_render=noop,feedback=noop})
jobs[probe_index].callback(false,nil)
check(not unavailable.export_ready,"missing FFmpeg disables extraction")
unavailable_service.start("audio",false)
check(#jobs==probe_index,"an unavailable backend never starts an export worker")
local backend_errors=0
fake_mp.msg.error=function() backend_errors=backend_errors+1 end
local failed_service=exporter.new(unavailable,o,{request_render=noop,feedback=noop})
jobs[#jobs].callback(true,{status=0})
failed_service.start("audio",true)
local failed_index=#jobs
jobs[failed_index].callback(true,{status=1,stderr="test container rejection"})
check(backend_errors==1 and unavailable.export_status=="Export failed; see MPV log","container rejection reports failure instead of completion")
check(#jobs==failed_index,"failed batch does not silently continue")
failed_service.shutdown()

-- Focus capture must release synchronously, before the next keyboard event or rendered frame.
function fake_mp.remove_key_binding(name) bindings[name]=nil end
local focus_active=false
function fake_mp.commandv(command,section)
    if section=="mpvtube-focus" then
        if command=="enable-section" then focus_active=true elseif command=="disable-section" then focus_active=false end
    end
end
input_options.keyboard=true
input_player.speed=noop
input_player.open_menu=function(page) input_state.menu=page end
input_state.menu,input_state.focus,input_state.menu_focus=nil,nil,nil
input_view.layout=ui.layout(input_state,input_options)
local keyboard_input=require("core.input").new(input_state,input_options,input_view,input_player,{hide=noop})
bindings["focus-next"]()
check(input_state.focus and focus_active,"Tab immediately captures UI navigation")
local before_modifier_actions=#actions
bindings["focus-Ctrl+RIGHT"]()
check(input_state.focus=="mute" and #actions==before_modifier_actions,"modifier arrows navigate the focused UI without seeking")
local queued_right=bindings["focus-RIGHT"]
bindings["focus-reset"]()
check(not input_state.focus and not focus_active,"Backspace immediately restores playback navigation and resets Tab")
caption_properties["input-bindings"]={{key="RIGHT",cmd="script-binding mpvtube/focus-RIGHT",priority=20,is_weak=false},
    {key="RIGHT",cmd="seek 7",priority=0,is_weak=true}}
local forwarded
function fake_mp.command(command) forwarded=command end
queued_right()
check(forwarded=="seek 7","a queued UI event forwards to the underlying native/user binding after clearing")
bindings["focus-next"]()
local first_focus=input_state.focus
bindings["focus-next"]()
check(input_state.focus~=first_focus,"Tab advances to another available control")
bindings["focus-reset"]();bindings["focus-next"]()
check(input_state.focus==first_focus,"clear-to-player resets the Tab starting point")
local title_option=input_options.title
input_options.title=true
local top_order={}
for _=1,#ui.layout(input_state,input_options).hits do
    bindings["focus-next"]()
    if input_state.focus=="native-menu" or input_state.focus=="info" then top_order[#top_order+1]=input_state.focus end
    if #top_order==2 then break end
end
check(top_order[1]=="native-menu" and top_order[2]=="info","Tab visits the top tools after the playback bar, from left to right")
input_options.title=title_option
input_state.menu="caption-font";keyboard_input.update_focus()
bindings["menu-escape"]()
check(input_state.menu=="captions","Escape steps back rather than clearing all menus")
bindings["focus-reset"]()
check(not input_state.menu and not focus_active,"clear shortcut closes the menu and releases Escape synchronously")
input_state.menu=nil
input_state.focus,input_state.focus_group="cc",nil
input_view.layout=ui.layout(input_state,input_options)
keyboard_input.update_focus()
check(not input_state.focus,"unavailable controls cannot retain keyboard capture")
bindings["focus-reset"]()
bindings["focus-next"]();bindings["focus-next"]();bindings["focus-next"]()
check(input_state.focus=="time","Tab follows the bar's visual order, including controls created later")
bindings["focus-reset"]()
input_state.menu="sub"
bindings["focus-next"]()
check(input_state.focus=="back","menu Tab starts at the leftmost header control")
bindings["focus-next"]()
check(input_state.focus=="caption-options","header controls with unequal heights share visual focus order")
keyboard_input.shutdown()

os.remove=original_remove
print(string.format("Passed %d regression checks",count))
