#!/usr/bin/env python3
"""Exercise the skin in real MPV over JSON IPC. Requires mpv, ffmpeg, and a desktop.

Run: python3 tests/integration.py
Artifacts and an MPV log go to tests/output; no user configuration is changed.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/output"
OUT.mkdir(parents=True, exist_ok=True)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--generate-fixtures",action="store_true",help="create the video, MP3 and WAV fixtures without launching MPV")
parser.add_argument("--animations",choices=("yes","no"),default="yes",help="test the animation setting, default: yes")
args=parser.parse_args()
for executable in (("ffmpeg",) if args.generate_fixtures else ("mpv", "ffmpeg")):
    if not shutil.which(executable):
        raise SystemExit(f"Install {executable} and put it on PATH first.")
if os.name == "nt" and not args.generate_fixtures:
    raise SystemExit("This IPC harness uses Unix sockets; use regression.lua and the README checklist on Windows.")
input_isolation=["--input-vo-keyboard=no","--input-terminal=no","--input-cursor=no"]
if not args.generate_fixtures:
    available=subprocess.check_output(["mpv","--list-options"],text=True)
    focus=next((line for line in available.splitlines() if line.lstrip().startswith("--focus-on ")),None)
    input_isolation.append("--focus-on=never" if focus else "--focus-on-open=no")

metadata = OUT / "chapters.ffmeta"
metadata.write_text(";FFMETADATA1\ntitle=MPVTube · Chapters and Tracks\n" + "".join(
    f"[CHAPTER]\nTIMEBASE=1/1000\nSTART={start}\nEND={end}\ntitle={title}\n"
    for start, end, title in [(0, 8000, "Introduction"),
        (8000, 16000, "Writing Your First Ansible Playbook (Step by Step)"),
        (16000, 24000, "Review & Next Steps")]), encoding="utf-8")
captions = OUT / "captions.srt"
captions.write_text("1\n00:00:00,000 --> 00:00:24,000\nMPVTube: subtitles and track selection work.\n", encoding="utf-8")
sample = OUT / "fixture.mkv"
subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
    "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=12",
    "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
    "-f", "lavfi", "-i", "sine=frequency=660:sample_rate=48000",
    "-i", str(captions), "-i", str(metadata), "-t", "24", "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:s",
    "-map_metadata", "4", "-map_chapters", "4", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "30",
    "-c:a", "aac", "-c:s", "srt", "-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=spa",
    "-metadata:s:s:0", "language=eng", str(sample)], check=True)

# Distinct pictures expose previews that accidentally keep decoding the first video track.
multi_video=OUT / "multi-video.mkv"
subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(sample),
    "-f","lavfi","-i","color=c=blue:s=1280x720:r=12","-t","24",
    "-map","0:v:0","-map","0:a:0","-map","1:v:0","-c","copy",
    "-c:v:1","libx264","-preset","ultrafast",str(multi_video)],check=True)

# Use the same tone in compressed and lossless files, with no video or subtitle track.
audio_samples=[]
for extension,codec in (("mp3","libmp3lame"),("wav","pcm_s16le")):
    audio=OUT / f"audio.{extension}"
    subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(sample),
        "-map","0:a:0","-map_metadata","-1","-map_chapters","-1","-c:a",codec,
        "-metadata","title=MPVTube audio fixture",str(audio)],check=True)
    audio_samples.append(audio)
# Authored ASS fonts, colors and positions must survive startup and export, but strip on request.
authored_subtitles=OUT / "styled.ass"
subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(captions),
    "-c:s","ass",str(authored_subtitles)],check=True)
authored=authored_subtitles.read_text()
authored=authored.replace("Style: Default,Arial,16,", "Style: Default,Courier New,36,")
authored=authored.replace("MPVTube: subtitles and track selection work.",
    r"{\pos(192,50)\c&H00FF00&\i1}Styled ASS captions")
authored_subtitles.write_text(authored)

# Whole-second frames permit exact 3/10/60/300 second seek checks without a large long-video fixture.
seek_sample=OUT / "seek-tiers.mkv"
subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-f","lavfi",
    "-i","color=c=0x26323f:s=640x360:r=1","-t","800","-c:v","libx264",
    "-preset","ultrafast","-crf","40",str(seek_sample)],check=True)
if args.generate_fixtures:
    print("Generated:",sample,multi_video,seek_sample,authored_subtitles,*audio_samples,sep="\n")
    raise SystemExit(0)


from player import Player


def preview_uploads(logfile):
    return logfile.read_text(errors="replace").count("Run command: overlay-add")


def wait_preview(logfile, previous, timeout=1):
    deadline=time.monotonic()+timeout
    while time.monotonic() < deadline:
        if preview_uploads(logfile) > previous:
            return
        time.sleep(.01)
    raise AssertionError("Preview did not render after moving over the timeline")


with tempfile.TemporaryDirectory(prefix="mpvtube-ipc-") as temp:
    # Read the setting from a real isolated .conf, also reused by later player launches.
    configuration=Path(temp)/"config"
    (configuration/"script-opts").mkdir(parents=True)
    preferences=configuration/"script-opts/mpvtube.conf"
    preferences.write_text(f"animations={args.animations}\n")
    ui_preferences=Path(temp)/"mpvtube-preferences.json"
    ipc = Path(temp) / "player.sock"
    logfile = OUT / "integration.log"
    # Record checkmarks from actual drawing calls, without adding diagnostics to the skin.
    script=Path(temp) / "mpvtube"
    script.mkdir()
    (script / "main.lua").write_text('''local source=%s
package.path=source.."/?.lua;"..package.path
local mp=require("mp")
local drawing=require("ui.draw")
local new_canvas=drawing.new
local record_checks=false
mp.observe_property("user-data/mpvtube-test-record-checks","bool",function(_,value) record_checks=value end)
drawing.new=function(...)
    local canvas=new_canvas(...)
    local icon,layer,finish=canvas.icon,canvas.layer,canvas.finish
    canvas.test_checks={}
    function canvas:icon(name,x,y,...)
        if name=="check" then self.test_checks[#self.test_checks+1]={x=x+(self.dx or 0),y=y+(self.dy or 0)} end
        return icon(self,name,x,y,...)
    end
    function canvas:layer(...)
        local child=layer(self,...)
        child.test_checks=self.test_checks
        return child
    end
    function canvas:finish()
        if record_checks and not self.clip then mp.set_property_native("user-data/mpvtube-test-checks",self.test_checks) end
        return finish(self)
    end
    return canvas
end
-- Snapshot state only on request, keeping preview timing free of per-frame IPC writes.
local ui=require("ui.view")
local layout=ui.layout
local last_state,last_options
local render_count=0
local render=ui.render
ui.render=function(...) render_count=render_count+1;return render(...) end
ui.layout=function(state,options)
    last_state,last_options=state,options
    return layout(state,options)
end
mp.register_script_message("test-state",function(token)
    if not last_state then return end
    local current=layout(last_state,last_options)
    mp.set_property_native("user-data/mpvtube-test-state",{token=token,focus=last_state.focus or false,
        menu=last_state.menu or false,hover=last_state.hover or false,drag=last_state.drag or false,opacity=last_state.opacity,hits=current.hits,panel=current.menu,rows=current.menu and current.menu.rows or {},
        key_capture=last_state.key_capture or false,key_candidate=last_state.key_candidate or false,keymap_message=last_state.keymap_message or "",
        keymap_tone=last_state.keymap_tone or "",feedback=last_state.feedback or false,
        export_ready=last_state.export_ready or false,export_status=last_state.export_status or "",
        animations=last_options.animations,volume_expand=last_state.volume_expand,render_count=render_count,
        hide_timeout=last_options.hide_timeout})
end)
dofile(source.."/main.lua")
''' % json.dumps(str(ROOT / "scripts/mpvtube")))
    with (OUT / "console.log").open("w") as console:
        process = subprocess.Popen(["mpv", f"--config-dir={configuration}","--load-scripts=no", *input_isolation, f"--script={script}",f"--osd-fonts-dir={ROOT / 'fonts'}",
            "--force-window=yes", "--idle=yes", "--geometry=1920x1200", "--pause", "--ao=null", "--keep-open=yes",
            f"--input-ipc-server={ipc}", f"--log-file={logfile}", f"--script-opts=mpvtube-keymap_path={temp}/keys.json,mpvtube-preferences_path={ui_preferences}", str(sample)], stdout=console, stderr=console)
        player = None
        try:
            deadline = time.monotonic()+15
            while not ipc.exists() and time.monotonic() < deadline:
                assert process.poll() is None, "MPV failed to start; inspect console.log"
                time.sleep(.05)
            player = Player(ipc)
            player.wait("vo-configured", True, 12)
            player.settle()
            player.wait("osc",False)
            assert len(player.get("chapter-list")) == 3
            player.command("script-message-to", "mpvtube", "show")
            player.screenshot(OUT / "controls.png")
            w, h, scale = player.dimensions()
            snapshot=player.snapshot()
            assert snapshot["animations"]==(args.animations=="yes"),"animation setting did not load from .conf"
            assert snapshot["hide_timeout"]==.7,"default auto-hide is not 0.7 seconds"
            for enabled in (args.animations!="yes",args.animations=="yes"):
                player.menu("settings",100,row="Animations",header=False)
                player.wait_state("animations",enabled,.2)
                assert json.loads(ui_preferences.read_text())["animations"]==enabled,"UI preference was not saved"
                row=next(row for row in player.snapshot()["rows"] if row["label"]=="Animations")
                assert row.get("selected",False)==enabled,"animation toggle did not reflect its accepted value"
                player.screenshot(OUT/f"animations-{'on' if enabled else 'off'}.png")
                player.close_menu()
            saved_preferences=ui_preferences.read_text()
            ui_preferences.write_text(saved_preferences+"\n")
            player.menu("settings",100,row="Animations",header=False)
            assert player.snapshot()["animations"]==(args.animations=="yes"),"rejected preference save changed the toggle"
            assert ui_preferences.read_text()==saved_preferences+"\n","UI overwrote externally edited preferences"
            ui_preferences.write_text(saved_preferences)
            player.close_menu()
            if args.animations=="no":
                # Revealing and clicking a hidden bar in one event must not swallow the action.
                player.mouse(w/2,h/2)
                player.command("script-message-to","mpvtube","hide")
                player.wait_state("opacity",0,.15)
                player.command("mouse",round(32*scale),round((h-27)*scale),0,"single")
                player.wait("pause",False,.15)
                player.command("set_property","pause",True)
                player.wait("pause",True)
                # First-frame geometry and static feedback must not wait for a tween or keep ticking.
                player.mouse(83,h-27)
                player.wait_state("volume_expand",1,.15)
                player.command("keypress","UP")
                time.sleep(.06)
                snapshot=player.snapshot()
                assert snapshot["feedback"]["opacity"]==1 and snapshot["feedback"]["scale"]==1.33
                count=snapshot["render_count"]
                time.sleep(.15)
                assert player.snapshot()["render_count"]<=count+1,"static feedback kept redrawing"
                player.screenshot(OUT/"instant-feedback.png")
                # A real video tap acts before MPV's 300 ms double-click window expires.
                player.mouse(w/2,h/2)
                player.command("mouse",round(w/2*scale),round(h/2*scale),0,"single")
                player.wait("pause",False,.15)
                started=time.monotonic()
                player.wait_state("opacity",0,1.05)
                hide_latency=time.monotonic()-started
                assert hide_latency<1,"controls did not hide promptly"
                player.command("set_property","pause",True)
                player.wait("pause",True)
                player.mouse(32,h-27)
                player.wait_state("opacity",1,.15)
                print(f"Instant UI: auto-hide observed within {hide_latency*1000:.0f} ms",flush=True)
                player.command("set_property","volume",100)
                player.command("seek",0,"absolute+exact")
                player.position(0,.1)
            player.mouse(w/2,h/2)
            cursor_policy=player.get("cursor-autohide")
            cursor_fs_only=player.get("cursor-autohide-fs-only")
            drag_policy={name:player.get(name) for name in ("window-dragging","input-builtin-dragging")}
            player.mouse(32,h-27)
            player.wait("cursor-autohide",cursor_policy)
            player.wait("cursor-autohide-fs-only",cursor_fs_only)
            player.screenshot(OUT / "native-cursor.png")
            player.mouse(w/2,h/2)
            player.wait("cursor-autohide",cursor_policy)
            player.wait("cursor-autohide-fs-only",cursor_fs_only)

            # Time real bitmap uploads, including an uncached first hover and a cached revisit.
            uploads=preview_uploads(logfile)
            start=time.monotonic()
            player.command("mouse",round(w*.48*scale),round((h-59)*scale))
            wait_preview(logfile,uploads)
            cold_preview=time.monotonic()-start
            assert cold_preview < .5, f"Cold preview took {cold_preview:.3f}s"
            assert player.get("time-pos") < .1, "hovering must not seek playback"
            player.mouse(w/2,h/2)
            uploads=preview_uploads(logfile)
            start=time.monotonic()
            player.command("mouse",round(w*.48*scale),round((h-59)*scale))
            wait_preview(logfile,uploads)
            warm_preview=time.monotonic()-start
            assert warm_preview < .15, f"Cached preview took {warm_preview:.3f}s"
            player.mouse(w/2,h/2)
            player.command("script-message-to","mpvtube","hide")
            time.sleep(.2)
            uploads=preview_uploads(logfile)
            start=time.monotonic()
            player.command("mouse",round(w*.48*scale),round((h-59)*scale))
            wait_preview(logfile,uploads)
            hidden_preview=time.monotonic()-start
            assert hidden_preview < .15, f"Cached preview waited for the control fade: {hidden_preview:.3f}s"
            (OUT / "preview-timing.json").write_text(json.dumps({
                "cold_ms":round(cold_preview*1000),"cached_ms":round(warm_preview*1000),
                "hidden_cached_ms":round(hidden_preview*1000)},indent=2)+"\n")

            # Review intermediate native frames; deterministic Lua checks verify their keyframes.
            player.command("set_property","volume",50)
            player.mouse(83,h-27)
            time.sleep(.3)
            player.frames(OUT / "motion-volume-up",lambda:player.command("keypress","UP"),(.04,.14,.3,.85,.97,1.15))
            player.wait("volume",55)
            player.frames(OUT / "motion-volume-down",lambda:player.command("keypress","DOWN"),(.06,.18,.3))
            player.wait("volume",50)
            player.command("set_property","volume",100)
            player.frames(OUT / "motion-menu-open",lambda:player.command("script-message-to","mpvtube","menu","settings"),(.04,.15))
            player.frames(OUT / "motion-menu-page",lambda:player.command("script-message-to","mpvtube","menu","speed"),(.06,.15,.3))
            player.frames(OUT / "motion-menu-close",lambda:player.command("keypress","BS"),(.04,.15))
            player.wait("pause",True)

            player.mouse(32, h-27, True)
            player.wait("pause", False)
            player.mouse(32, h-27, True)
            player.wait("pause", True)
            player.screenshot(OUT / "feedback.png")
            # The timeline's generous hit area must not steal the top edge of a button.
            player.mouse(32,h-46,True)
            player.wait("pause",False)
            player.mouse(32,h-46,True)
            player.wait("pause",True)

            # Gaps, outer margins and the space below buttons never act as video clicks.
            for paused in (True,False):
                player.command("seek",1,"absolute+exact")
                player.command("set_property","pause",paused)
                for x,y in ((6,h-27),(w-6,h-60),(w/2,h-4),(56,h-27)):
                    for button in (0,2):
                        player.mouse(x,y,True,button=button)
                        time.sleep(.35)
                        player.wait("pause",paused)
                player.mouse(w/2,h-4)
                player.command("mouse",round(w/2*scale),round((h-4)*scale),0,"double")
                player.wait("fullscreen",False)
                player.command("mouse",round(w/2*scale),round((h-4)*scale),2,"double")
                player.wait("pause",paused)
                player.wait("fullscreen",False)
                player.command("keydown","MBTN_LEFT")
                time.sleep(.45)
                player.wait("speed",1)
                player.command("keyup","MBTN_LEFT")
                time.sleep(.35)
                player.wait("pause",paused)
            player.command("set_property","pause",True)
            player.command("seek",0,"absolute+exact")

            # One outside click closes settings/submenus, including passive safe-area space.
            for page,count in (("settings",7),("speed",3)):
                for x,y in ((6,h-27),(w-6,h-60),(w/2,h-4),(56,h-27),(6,h/2),(32,h-27)):
                    for button in (0,2):
                        # Left clicks on Play retain their action, so test it with right click only.
                        if x==32 and button==0: continue
                        player.menu(page,count,header=page!="settings")
                        assert player.menu_is_open(),"menu did not open"
                        player.mouse(x,y,True,button=button)
                        assert not player.menu_is_open(),f"{page} needed another outside click at {(x,y)}, button {button}"
                        time.sleep(.35)
                        player.wait("pause",True)
                        player.wait("speed",1)
            x,y=player.menu("speed",3)
            player.mouse(x+100,y+90,True,button=2)
            assert player.menu_is_open(),"right click inside a menu dismissed it"
            player.wait("speed",1)
            player.command("keypress","BS")
            player.mouse(w/2,h/2)  # Let menu dismissal restore the mouse capture area.
            player.mouse(w/2,h/2,True,button=2)
            player.wait("pause",True)  # Unassigned native input has no fallback.
            player.mouse(w/2,h/2,True,button=2)
            player.wait("pause",True)
            player.mouse(32,h-27,True,button=2)
            player.wait("pause",True)
            player.menu("settings",7,header=False)
            player.screenshot(OUT / "menu-before-outside-click.png")
            player.mouse(w/2,h-4,True)
            player.screenshot(OUT / "menu-after-outside-click.png")
            # The gear closes submenus without reopening Settings; other buttons still act.
            player.menu("speed",3)
            player.control("settings")
            assert not player.menu_is_open(),"gear reopened settings instead of dismissing the submenu"
            player.menu("settings",7,header=False)
            player.mouse(32,h-27,True)
            assert not player.menu_is_open(),"play button left settings open"
            player.wait("pause",False)
            player.mouse(32,h-27,True)
            player.wait("pause",True)
            player.command("seek",0,"absolute+exact")

            # Time clicks toggle the label without changing position or pause state.
            player.mouse(w/2,h/2)
            time.sleep(.2)
            player.mouse(150,h-27)
            player.screenshot(OUT / "time-elapsed.png")
            player.mouse(150,h-27,True)
            player.screenshot(OUT / "time-remaining.png")
            player.position(0)
            player.wait("pause",True)
            player.mouse(150,h-27,True)

            # Mouse hit testing and real track/speed changes through the menu.
            player.control("settings")
            player.screenshot(OUT / "settings.png")
            player.command("keypress", "BS")
            player.speed(1.5)
            player.wait("speed", 1.5)
            player.command("keypress", "BS")
            player.menu("audio", 2, row=2)
            player.wait("aid", 2)
            player.command("keypress", "BS")
            player.command("set_property","sid",1)
            player.menu("sub", 3, row=1)
            player.wait("sid", 1)
            player.wait("sub-visibility", False)
            player.command("keypress", "BS")
            player.command("keypress", "c")
            player.wait("sid", 1)
            player.wait("sub-visibility", True)
            for control,page in (("cc","sub"),("audio","audio")):
                player.control(control)
                player.wait_state("menu",page)
                player.control(control)
                player.wait_state("menu",False)
                player.wait("pause",True)
                player.wait("sub-visibility",True)
            player.control("cc")
            player.wait_state("menu","sub")
            player.control("caption-options")
            player.wait_state("menu","captions")
            player.control("cc")
            player.wait_state("menu",False)
            player.control("cc")
            player.wait_state("menu","sub")
            player.control("audio")
            player.wait_state("menu",False)
            player.control("audio")
            player.wait_state("menu","audio")
            player.control("audio")
            player.wait_state("menu",False)
            for page in ("settings","speed","caption-font","shortcuts"):
                for control in ("cc","audio","settings"):
                    player.menu(page,100,header=page!="settings")
                    player.control(control)
                    player.wait_state("menu",False)
                    player.wait("pause",True)
                    player.wait("sub-visibility",True)
            player.control("cc")
            player.wait_state("menu","sub")
            player.wait("sub-visibility",True)
            player.control("row-1")
            player.wait("sub-visibility",False)
            assert player.snapshot()["feedback"]["text"]=="Subtitles off"
            player.screenshot(OUT / "cc-off.png")
            player.close_menu()
            player.control("cc")
            player.wait_state("menu","sub")
            player.control("row-2")
            player.wait("sub-visibility",True)
            assert player.snapshot()["feedback"]["text"].startswith("Subtitles: ")
            player.screenshot(OUT / "cc-on.png")
            player.close_menu()
            assert player.get("sub-pos") < 100, "subtitles must clear the controls"

            # Appearance writes reach MPV's subtitle renderer and Reset restores its settings.
            player.command("set_property","user-data/mpvtube-test-record-checks",True)
            style_names=("sub-font","sub-font-size","sub-color","sub-back-color",
                "sub-border-style","sub-border-size","sub-shadow-offset","sub-border-color","sub-ass-override")
            original_style={name:player.get(name) for name in style_names}
            assert player.get("sub-border-style") == "outline-and-shadow", "default captions have no box"
            sub_x,sub_y=player.menu("sub",3)
            player.mouse(w-40,sub_y+24,True)
            player.screenshot(OUT / "caption-options.png")
            player.command("keypress","BS")
            player.menu("caption-background-opacity",5,row=4)
            player.wait("sub-border-style","background-box")
            player.wait("sub-back-color","#BF000000")
            player.selected_row(5,4)
            player.command("keypress","BS")
            player.menu("caption-color",8,row=2)
            player.wait("sub-color","#FFFFFF00")
            player.selected_row(8,2)
            player.command("keypress","BS")
            player.menu("caption-opacity",5,row=3)
            player.wait("sub-color","#80FFFF00")
            player.selected_row(5,3)
            player.command("keypress","BS")
            player.menu("caption-size",22,row=10)
            player.near("sub-font-size",original_style["sub-font-size"]*1.05)
            player.selected_row(22,10)
            player.command("keypress","BS")
            player.menu("caption-edge",3,row=1)
            player.wait("sub-border-size",0)
            player.selected_row(3,1)
            player.screenshot(OUT / "caption-edge-none.png")
            player.command("keypress","DOWN")
            player.command("keypress","DOWN")
            player.command("keypress","ENTER")
            player.wait("sub-shadow-offset",2)
            player.selected_row(3,2)
            player.screenshot(OUT / "caption-edge-shadow.png")
            player.command("set_property","sub-border-size",1.65)
            player.selected_row(3,3)  # Native commands also move the visible checkmark.
            player.screenshot(OUT / "caption-edge-outline.png")
            player.command("keypress","BS")
            for row,font in ((2,"serif"),(3,"monospace"),(4,"cursive"),(1,"sans-serif")):
                player.menu("caption-font",5,row=row)
                player.wait("sub-font",font)
                player.selected_row(5,row)
                if row==3: player.screenshot(OUT / "caption-font-selected.png")
                player.command("keypress","BS")
            player.menu("caption-background",8,row=2)
            player.selected_row(8,2)
            player.command("keypress","BS")
            player.screenshot(OUT / "custom-captions.png")
            player.menu("captions",8,row=8)
            for name,value in original_style.items(): player.wait(name,value)
            player.screenshot(OUT / "caption-reset.png")
            player.command("keypress","BS")
            player.command("set_property","user-data/mpvtube-test-record-checks",False)

            # sub-add exercises the same track-list updates used by an SRT drop in MPV.
            external=OUT / "external.es.srt"
            external.write_text("1\n00:00:00,000 --> 00:00:24,000\nSubtítulos externos: Español.\n",encoding="utf-8")
            player.command("sub-add",str(external),"select")
            player.wait("sid",2)
            assert len([t for t in player.get("track-list") if t["type"]=="sub"]) == 2
            player.wait("sub-text","Subtítulos externos: Español.")
            player.command("keypress","v")
            player.wait("sid",1)
            player.command("keypress","Alt+v")
            player.wait("sid",2)
            player.menu("sub",4)
            player.screenshot(OUT / "external-subtitles.png")
            player.command("keypress","BS")
            player.menu("caption-background-opacity",5,row=5)
            player.wait("sub-back-color","#FF000000")
            player.command("keypress","BS")
            player.screenshot(OUT / "external-custom-captions.png")
            player.menu("captions",8,row=8)
            player.command("keypress","BS")
            player.command("sub-remove",2)
            player.command("set_property","sid",1)
            player.wait("sub-visibility",True)

            # New controls use real MPV tracks/properties, and clearing focus releases keys immediately.
            player.close_menu()
            player.command("keypress","TAB")
            player.wait_state("focus","play")
            player.command("keypress","SPACE")
            player.wait("pause",False)
            player.command("keypress","SPACE")
            player.wait("pause",True)
            player.screenshot(OUT / "keyboard-focus.png")
            focused_time=player.get("time-pos")
            player.command("keypress","Ctrl+RIGHT")
            player.wait_state("focus","mute")
            player.position(focused_time)
            player.command("keypress","HOME")
            player.wait("volume",0)
            player.command("keypress","END")
            player.wait("volume",200)
            player.command("keypress","BS")
            player.command("seek",0,"absolute+exact")
            player.command("keypress","RIGHT")
            player.position(10)
            player.command("keypress","TAB")
            player.wait_state("focus","play")
            player.mouse(w/2,h/2,True)
            player.wait_state("focus",False)
            time.sleep(.35)
            player.command("set_property","pause",True)
            player.command("seek",0,"absolute+exact")
            player.command("keypress","TAB")
            player.wait_state("focus","play")
            player.command("script-message-to","mpvtube","hide")
            player.wait_state("focus",False)
            player.command("script-message-to","mpvtube","show")
            for _ in range(24):
                player.command("keypress","TAB")
                if player.snapshot()["focus"]=="settings": break
            else: raise AssertionError("Tab cannot reach settings")
            player.command("keypress","ENTER")
            player.wait_state("menu","settings")
            player.command("keypress","ENTER")
            player.wait_state("menu","speed")
            player.command("keypress","ESC")
            player.wait_state("menu","settings")
            player.close_menu()
            player.menu("controls",18)
            actions={row["label"]:row.get("action") for row in player.snapshot()["rows"]}
            assert all(actions.get(name) for name in ("Mini player","Time remaining","Previous frame","Next frame"))
            player.command("keypress","HOME")
            player.wait_state("focus","row-2")
            player.command("keypress","END")
            player.wait_state("focus",f"row-{len(player.snapshot()['rows'])}")
            player.screenshot(OUT / "more-controls.png")
            player.close_menu()
            player.command("set_property","volume",195)
            player.command("keypress","UP")
            player.wait("volume",200)
            player.command("keypress","UP")
            player.wait("volume",200)
            player.command("set_property","volume-max",150)
            player.command("set_property","volume",150)
            player.command("keypress","UP")
            player.wait("volume",150)
            player.command("set_property","volume-max",200)
            player.command("set_property","volume",100)
            player.command("keypress","b")
            player.wait("aid",1)
            player.command("keypress","B")
            player.wait("aid",2)
            player.command("keypress","c")
            player.wait("sub-visibility",False)
            player.command("keypress","v")
            player.wait("sub-visibility",True)
            player.command("keypress","g")
            player.near("sub-delay",-.05,.001)
            player.command("keypress","h")
            player.near("sub-delay",0,.001)
            player.command("keypress","j")
            player.near("audio-delay",-.05,.001)
            player.command("keypress","k")
            player.near("audio-delay",0,.001)
            player.command("keypress","h")
            player.command("keypress","Ctrl+Shift+k")
            player.near("sub-delay",0,.001)
            player.screenshot(OUT / "synchronization-feedback.png")
            player.command("sub-add",str(authored_subtitles),"select")
            player.wait("sub-text","Styled ASS captions")
            authored_id=player.get("sid")
            player.screenshot(OUT / "authored-subtitles.png")
            player.command("keypress","u")
            player.wait("sub-ass-override","strip")
            player.wait("sub-font","Roboto")
            player.screenshot(OUT / "clean-subtitles.png")
            player.command("keypress","u")
            for name,value in original_style.items(): player.wait(name,value)
            for path in OUT.glob(f"fixture.sub-{authored_id}.*.ass"): path.unlink()
            player.menu("exports",6,row=3)
            deadline=time.monotonic()+5
            while "Exported" not in player.snapshot()["export_status"] and time.monotonic()<deadline: time.sleep(.02)
            ass_exports=list(OUT.glob(f"fixture.sub-{authored_id}.*.ass"))
            assert len(ass_exports)==1 and "Courier New" in ass_exports[0].read_text(),"ASS export lost its native authored style"
            player.close_menu()
            player.command("sub-remove",authored_id)
            player.command("set_property","sid",1)
            player.command("keypress","F1")
            guide=player.wait_state("menu","shortcuts")
            assert any(row["value"]=="j" and "audio sync" in row["label"].lower() for row in guide["rows"])
            player.screenshot(OUT / "shortcut-guide.png")
            # Exclusive ownership rejects duplicates but allows suspended native assignments.
            pause_row=next(i+1 for i,row in enumerate(guide["rows"]) if row["label"]=="Play / pause")
            player.control(f"row-{pause_row}")
            player.wait_state("menu","binding")
            player.wait_state("focus","row-3")
            player.screenshot(OUT / "shortcut-editor.png")
            player.command("keypress","ENTER")
            player.wait_state("key_capture",True)
            for key in ("f",):
                player.command("keypress",key)
                status=player.wait_state("keymap_tone","error")
                assert status["key_capture"] and "Already used" in status["keymap_message"]
                assert status["key_candidate"] is False and not (Path(temp)/"keys.json").exists()
            player.screenshot(OUT / "shortcut-conflict.png")
            player.command("keypress","d")
            player.wait_state("key_candidate","d")
            player.wait_state("key_capture",False)
            player.control("row-3")
            player.command("keypress","ESC")
            player.wait_state("key_capture",False)
            player.control("row-3")
            player.command("keypress","F12")
            player.wait_state("key_candidate","F12")
            player.wait_state("focus","row-6")
            player.screenshot(OUT / "shortcut-ready.png")
            player.command("keypress","ENTER")
            player.wait_state("keymap_message","Saved")
            player.wait_state("focus","row-3")
            player.screenshot(OUT / "shortcut-saved.png")
            assert json.loads((Path(temp)/"keys.json").read_text())["keys"]["pause-SPACE"]=="F12"
            player.close_menu()
            player.command("keypress","SPACE")
            time.sleep(.1)
            player.wait("pause",True)
            player.command("keypress","F12")
            player.wait("pause",False)
            player.command("keypress","F12")
            player.wait("pause",True)
            player.control("play",False)
            assert "F12" in next(hit["tip"] for hit in player.snapshot()["hits"] if hit["id"]=="play")
            # Reset all restores both a remapped key and an unassigned key, after confirmation.
            player.command("keypress","F1")
            guide=player.wait_state("menu","shortcuts")
            player.menu_row("Mute")
            player.wait_state("menu","binding")
            player.control("row-5")
            player.wait_state("key_candidate","none")
            player.control("row-6")
            player.wait_state("keymap_message","Saved")
            player.close_menu()
            muted=player.get("mute")
            player.command("keypress","m")
            player.wait("mute",muted)
            player.command("keypress","F1")
            guide=player.wait_state("menu","shortcuts")
            player.menu_row("Input diagnostics")
            diagnostics=player.wait_state("menu","bindings")
            assert diagnostics["rows"][-1]["pinned"] and "Read-only" in diagnostics["rows"][-1]["label"]
            player.screenshot(OUT / "input-diagnostics.png")
            player.control("row-1")
            details=player.wait_state("menu","binding")
            assert all(not row.get("action") for row in details["rows"]),"diagnostics must not offer editing commands"
            assert any(row["label"]=="Owner" for row in details["rows"])
            player.screenshot(OUT / "input-details.png")
            player.command("keypress","ESC")
            guide=player.wait_state("menu","shortcuts")
            before_reset=(Path(temp)/"keys.json").read_text()
            player.menu_row("Reset all shortcuts")
            player.wait_state("menu","shortcut-reset")
            player.screenshot(OUT / "shortcut-reset.png")
            player.control("row-2")
            player.wait_state("menu","shortcuts")
            assert (Path(temp)/"keys.json").read_text()==before_reset,"cancelled reset changed saved keys"
            player.menu_row("Reset all shortcuts")
            player.wait_state("menu","shortcut-reset")
            player.control("row-1")
            guide=player.wait_state("menu","shortcuts")
            player.wait_state("keymap_message","All shortcuts reset")
            assert json.loads((Path(temp)/"keys.json").read_text())["keys"]=={},"reset must clear overrides while retaining a JSON key dictionary"
            assert next(row["value"] for row in guide["rows"] if row["label"]=="Play / pause")=="Space"
            player.screenshot(OUT / "shortcuts-reset-complete.png")
            player.close_menu()
            player.command("keypress","F12")
            player.wait("pause",True)
            for key,property,value in (("SPACE","pause",False),("SPACE","pause",True),("m","mute",not muted),("m","mute",muted)):
                player.command("keypress",key)
                player.wait(property,value)
            player.menu("settings",100,header=False)
            assert next(row["shortcut"] for row in player.snapshot()["rows"] if row["label"]=="Shortcut guide")=="F1"
            player.close_menu()
            player.control("native-menu")
            time.sleep(.2)
            player.screenshot(OUT / "native-menu.png")
            player.close_native()
            player.command("keypress","Ctrl+Shift+p")
            time.sleep(.2)
            player.screenshot(OUT / "native-properties.png")
            player.close_native()

            # The owned screenshot action writes to ignored output and announces success.
            for path in OUT.glob("mpvtube-action-*"): path.unlink()
            player.command("set_property","screenshot-directory",str(OUT))
            player.command("set_property","screenshot-template","mpvtube-action-%n")
            player.command("keypress","s")
            deadline=time.monotonic()+3
            while not list(OUT.glob("mpvtube-action-*")) and time.monotonic()<deadline: time.sleep(.02)
            assert list(OUT.glob("mpvtube-action-*")),"owned screenshot action produced no file"
            assert player.snapshot()["feedback"]["text"]=="Screenshot saved"

            # Export selected/all embedded streams without transcoding or overwriting existing files.
            exports=[OUT / "fixture.sub-1.eng.srt",OUT / "fixture.audio-1.eng.m4a",OUT / "fixture.audio-2.spa.m4a"]
            for path in exports: path.unlink(missing_ok=True)
            deadline=time.monotonic()+3
            while not player.snapshot()["export_ready"] and time.monotonic()<deadline: time.sleep(.02)
            assert player.snapshot()["export_ready"],"FFmpeg export backend did not become ready"
            player.menu("exports",6,row=3)
            deadline=time.monotonic()+5
            while "Exported" not in player.snapshot()["export_status"] and time.monotonic()<deadline: time.sleep(.02)
            assert "MPVTube: subtitles" in exports[0].read_text()
            player.menu("exports",6)  # close
            player.menu("exports",6,row=6)
            deadline=time.monotonic()+5
            while player.snapshot()["export_status"]!="Exported 2 track(s)" and time.monotonic()<deadline: time.sleep(.02)
            assert player.snapshot()["export_status"]=="Exported 2 track(s)"
            for path in exports[1:]:
                probe=json.loads(subprocess.check_output(["ffprobe","-v","error","-show_streams","-of","json",str(path)]))
                assert len(probe["streams"])==1 and probe["streams"][0]["codec_name"]=="aac"
            saved=exports[0].read_bytes()
            player.menu("exports",6)
            player.menu("exports",6,row=3)
            assert player.snapshot()["export_status"].startswith("File exists:")
            assert exports[0].read_bytes()==saved,"existing export was modified"
            player.screenshot(OUT / "export-tracks.png")
            player.close_menu()

            # Timeline click, drag with exact release, chapter menu, and keyboard seeks.
            w, h, scale = player.dimensions()
            player.mouse(w*.5, h-59, True)
            assert abs(player.get("time-pos")-12) < .25, "click-to-seek"
            player.mouse(w*.25, h-59)
            player.command("keydown", "MBTN_LEFT")
            player.mouse(w*.75, h-59)
            player.command("keyup", "MBTN_LEFT")
            time.sleep(.2)
            assert abs(player.get("time-pos")-18) < .5, "drag seek"
            player.menu("chapters", 3, row=2)
            player.wait("pause",False)
            player.command("set_property","pause",True)
            assert abs(player.get("time-pos")-8) < .4, "chapter selection"
            player.screenshot(OUT / "chapter-selection.png")
            player.command("keypress","BS")
            player.command("keypress", "RIGHT")
            player.position(18)
            player.command("keypress", "0")
            player.position(0)

            # Arrow presses render signed chevrons; opposite directions start a new label.
            player.command("keypress","RIGHT")
            player.position(10)
            player.screenshot(OUT / "seek-right.png")
            player.command("keypress","RIGHT")
            player.position(20)
            player.screenshot(OUT / "seek-right-repeat.png")
            player.command("keypress","LEFT")
            player.position(10)
            player.screenshot(OUT / "seek-left.png")
            player.command("keypress","0")
            player.position(0)

            # A video hold restores the exact prior rate without turning release into a tap.
            player.command("set_property","speed",1.5)
            player.command("set_property","pause",False)
            player.mouse(w/2,h/2)
            player.command("keydown","MBTN_LEFT")
            player.wait("speed",2)
            player.screenshot(OUT / "hold-speed.png")
            player.command("keyup","MBTN_LEFT")
            player.wait("speed",1.5)
            time.sleep(.4)
            player.wait("pause",False)
            # Native pointer events during a capture can move the IPC pointer; reset each gesture.
            player.mouse(w/2,h/2)
            player.command("keydown","MBTN_LEFT")
            player.wait("speed",2)
            player.command("set_property","pause",True)
            player.wait("speed",1.5)
            player.command("keyup","MBTN_LEFT")
            time.sleep(.4)
            player.wait("pause",True)
            player.command("set_property","speed",1)
            player.command("keypress","0")
            player.position(0)

            # Keyboard menu navigation consumes arrows only while the menu is open.
            before_navigation_volume=player.get("volume")
            player.menu("speed",3)
            player.command("keypress","DOWN")
            player.command("keypress","DOWN")
            player.command("keypress","ENTER")
            player.near("speed",.9)
            player.wait("volume",before_navigation_volume)
            player.command("keypress","BS")
            player.command("set_property","speed",1)

            # Check intermediate rates before release, including reversals and dragging outside the track.
            player.speed_drag((1,1.5,.5,1.75,.75,2.2,.1,1.15))
            player.screenshot(OUT / "speed-drag.png")
            for name,value in drag_policy.items(): player.wait(name,value)
            player.command("keypress","BS")
            player.command("set_property","speed",1)

            # Continuous movement across samples must show new images without a settling delay.
            for fraction in (.12,.28,.48,.68,.88):
                uploads=preview_uploads(logfile)
                player.command("mouse",round(w*fraction*scale),round((h-59)*scale))
                wait_preview(logfile,uploads)
            player.position(0)
            player.mouse(w*.48, h-59)
            player.screenshot(OUT / "thumbnail.png")
            assert "overlay-add" in logfile.read_text(errors="replace"), "thumbnail did not render"

            player.mouse(83, h-27)
            time.sleep(.3)
            player.screenshot(OUT / "volume.png")
            player.mouse(130, h-27, True)
            assert 90 <= player.get("volume") <= 110, "volume slider"
            player.mouse(130, h-27)
            player.command("keydown", "MBTN_LEFT")
            player.mouse(155, h-27)
            player.command("keyup", "MBTN_LEFT")
            time.sleep(.15)
            assert player.get("volume") > 170, "volume drag"
            player.screenshot(OUT / "volume-slider-no-feedback.png")
            player.mouse(83, h-27, True)
            player.wait("mute", True)
            player.command("keypress", "UP")
            player.wait("mute", True)
            player.command("keypress", "DOWN")
            player.wait("mute", True)
            player.mouse(130,h-27,True)
            player.wait("mute", False)

            # Mini player must restore size, border, and pinning.
            player.mouse(w/2, h/2)
            size = player.get("current-window-scale")
            border, ontop = player.get("border"), player.get("ontop")
            player.command("keypress", "i")
            player.wait("ontop", True)
            player.wait("border", False)
            player.command("keypress", "i")
            player.wait("ontop", ontop)
            player.wait("border", border)
            player.near("current-window-scale",size)
            player.settle()
            # Fullscreen button and double-click must both toggle the actual window.
            w,h,_=player.dimensions()
            player.mouse(w-40,h-27,True)
            player.wait("fullscreen",True)
            player.settle()
            w,h,scale=player.dimensions()
            player.mouse(w-40,h-27,True)
            player.wait("fullscreen",False)
            player.settle()
            w,h,scale=player.dimensions()
            double_click_pause=player.get("pause")
            player.command("mouse",round(w/2*scale),round(h/2*scale),0,"single")
            player.wait("pause",not double_click_pause,.15)
            player.command("mouse",round(w/2*scale),round(h/2*scale),0,"double")
            player.wait("fullscreen",True)
            player.settle()
            assert player.get("pause")==double_click_pause,"double-click must not toggle pause"
            w,h,scale=player.dimensions()
            player.command("mouse",round(w/2*scale),round(h/2*scale),0,"double")
            player.wait("fullscreen",False)
            player.settle()
            assert player.get("pause")==double_click_pause,"double-click exit must not toggle pause"

            player.command("loadfile", str(sample), "append")
            w,h,_=player.dimensions()
            player.mouse(82,h-27,True)
            player.wait("playlist-pos", 1)
            player.mouse(82,h-27,True)
            player.wait("playlist-pos", 0)
            player.wait("pause", True)
            player.menu("playlist", 2, row=2)
            player.wait("playlist-pos", 1)
            player.wait("pause", True)
            player.command("script-message-to", "mpvtube", "show")
            time.sleep(.2)
            player.menu("settings",9,row="Autoplay",header=False)
            player.wait("keep-open","always")
            player.menu("settings",9,header=False)  # close the currently open settings
            player.menu("settings",9,row="Autoplay",header=False)
            player.wait("keep-open",True)
            player.command("keypress","BS")

            # Real VO resizing, hover transitions, tooltips, and scrollable menus.
            for width,height in [(1280,800),(800,500),(600,360),(1920,1200)]:
                player.command("set_property","geometry",f"{width}x{height}")
                # A stable old size can precede macOS applying the requested resize.
                player.near("osd-width",width,.5)
                player.near("osd-height",height,.5)
                w,h,_=player.settle()
                player.mouse(32,h-27)
                time.sleep(.5)
                player.screenshot(OUT / f"responsive-{width}.png")
                player.mouse(32,h-27,True)
                player.wait("pause",False)
                player.mouse(32,h-27,True)
                player.wait("pause",True)
                if w<540:
                    player.command("keypress","Ctrl+Shift+k")
                    player.screenshot(OUT / f"compact-feedback-{width}.png")
                    player.mouse(w-70,h-28,True)
                    player.screenshot(OUT / f"compact-expanded-{width}.png")
                    slots=5
                    cc_slot=3
                    cc_x=w-12-(slots*36+8)+4+(cc_slot-.5)*36
                    player.mouse(cc_x,h-28,True)
                    player.wait_state("menu","sub")
                    player.wait("sub-visibility",True)
                    player.control("row-1")
                    player.wait("sub-visibility",False)
                    player.close_menu()
                    player.command("keypress","c")
                    player.wait("sub-visibility",True)
                    player.mouse(w-slots*36+2,h-28,True)
                    player.screenshot(OUT / f"compact-collapsed-{width}.png")
                player.speed_drag((1,1.5,.5,2.2,.1,1.25))
                player.command("keypress","BS")
                player.command("set_property","speed",1)
                player.wait("speed",1)
                x,y=player.menu("speed",3)
                before_scroll_volume=player.get("volume")
                for _ in range(8):
                    player.command("keypress","WHEEL_DOWN")
                time.sleep(.15)
                player.control("speed-2")
                player.wait("speed",2)
                assert player.get("volume")==before_scroll_volume,"wheel over menu must scroll, not change volume"
                player.close_menu()

            # Let playback auto-hide, then stop: no stale preview, menu, or Lua errors.
            player.mouse(w/2, h/2)
            player.command("keypress", "SPACE")
            player.wait("pause", False)
            player.wait("sub-pos",100,6)
            player.screenshot(OUT / "hidden.png")
            assert player.snapshot()["opacity"]<.1,"controls did not auto-hide"

            # A file with no embedded captions must gain CC as soon as an external SRT arrives.
            plain=OUT / "without-subtitles.mkv"
            subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(sample),
                "-map","0:v:0","-map","0:a:0","-c","copy",str(plain)],check=True)
            player.command("loadfile",str(plain),"replace")
            player.command("set_property","pause",True)
            player.wait("vo-configured",True)
            player.wait("path",str(plain))
            player.wait("sid",False)
            assert not any(t["type"]=="sub" for t in player.get("track-list"))
            player.command("sub-add",str(external),"select")
            player.wait("sid",1)
            player.wait("sub-text","Subtítulos externos: Español.")
            player.menu("sub",3)
            player.screenshot(OUT / "external-only-subtitles.png")
            player.command("keypress","BS")
            player.menu("caption-color",8,row=3)
            player.wait("sub-color","#FF00FF00")
            player.command("keypress","BS")
            player.screenshot(OUT / "external-only-custom.png")
            player.menu("captions",8,row=8)
            player.command("keypress","BS")

            # Long chapter lists open around the current chapter, then scroll to later entries.
            long_metadata=OUT / "long-chapters.ffmeta"
            long_metadata.write_text(";FFMETADATA1\n"+"".join(
                f"[CHAPTER]\nTIMEBASE=1/1000\nSTART={index*500}\nEND={(index+1)*500}\ntitle=Chapter {index+1}\n"
                for index in range(48)),encoding="utf-8")
            long_sample=OUT / "long-chapters.mkv"
            subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(sample),
                "-i",str(long_metadata),"-map","0","-map_metadata","1","-map_chapters","1",
                "-c","copy",str(long_sample)],check=True)
            player.command("loadfile",str(long_sample),"replace")
            player.wait("path",str(long_sample))
            player.command("set_property","pause",True)
            player.command("set_property","geometry","1280x800")
            w,h,_=player.settle()
            player.command("seek",20,"absolute+exact")
            player.position(20)
            player.wait("chapter",40)
            chapter_x,chapter_y=player.menu("chapters",48)
            visible=player.snapshot()["panel"]["visible"]
            player.screenshot(OUT / "long-chapters.png")
            player.mouse(chapter_x+100,chapter_y+57+8+24,True)
            player.wait("pause",False)
            player.command("set_property","pause",True)
            player.position((41-visible)*.5)
            for _ in range(48): player.command("keypress","WHEEL_DOWN")
            player.mouse(chapter_x+100,chapter_y+57+8+(visible-.5)*48,True)
            player.wait("pause",False)
            player.command("set_property","pause",True)
            player.position(23.5)
            player.command("keypress","BS")

            # Changing files during a held gesture restores the prior rate and consumes release.
            player.command("seek",0,"absolute+exact")
            player.command("set_property","speed",1.25)
            player.command("set_property","pause",False)
            player.mouse(w/2,h/2)
            player.command("keydown","MBTN_LEFT")
            player.wait("speed",2)
            player.command("loadfile",str(sample),"replace")
            player.wait("path",str(sample))
            player.wait("speed",1.25)
            player.command("set_property","pause",True)
            player.command("keyup","MBTN_LEFT")
            time.sleep(.4)
            player.wait("pause",True)
            # A tap awaiting double-click detection must never pause/unpause the next file.
            player.mouse(w/2,h/2,True)
            player.command("loadfile",str(sample),"replace")
            player.command("set_property","pause",True)
            time.sleep(.4)
            player.wait("pause",True)

            # Track changes clear old cache entries and decode the selected blue stream.
            player.command("loadfile",str(multi_video),"replace")
            player.wait("path",str(multi_video))
            player.wait("vo-configured",True)
            player.settle()
            player.menu("video",2,row=2)
            player.wait("vid",2)
            video=next(track for track in player.get("track-list") if track["type"]=="video" and track["id"]==2)
            assert video["ff-index"]==2
            player.command("keypress","BS")
            time.sleep(.3)
            uploads=preview_uploads(logfile)
            log_offset=len(logfile.read_text(errors="replace"))
            player.mouse(w*.48,h-59)
            wait_preview(logfile,uploads)
            player.screenshot(OUT / "selected-video-preview.png")
            assert ",0:2," in logfile.read_text(errors="replace")[log_offset:],"preview decoded the wrong video stream"
            # A sparse generated video exercises hour fields without downloading long media.
            long_duration=OUT / "ten-hours.mkv"
            subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-f","lavfi",
                "-i","color=c=0x26323f:s=1280x720:r=1/600","-frames:v","61","-c:v","libx264",
                "-preset","ultrafast","-crf","40",str(long_duration)],check=True)
            player.command("loadfile",str(long_duration),"replace")
            player.wait("path",str(long_duration))
            player.wait("vo-configured",True)
            player.command("set_property","pause",True)
            w,h,scale=player.settle()
            for position in (0,600,3600,36000):
                player.command("seek",position,"absolute+exact")
                player.position(position)
                player.mouse(w/2,h/2)
                time.sleep(.2)
                player.control("time",False)
                player.screenshot(OUT / f"time-{position}.png")
                player.control("time")
                player.screenshot(OUT / f"remaining-{position}.png")
                player.position(position)
                player.wait("pause",True)
                player.control("time")

            player.command("loadfile",str(seek_sample),"replace")
            player.wait("path",str(seek_sample))
            player.command("set_property","pause",True)
            player.command("seek",20,"absolute+exact")
            player.position(20)
            player.command("keypress","Shift+RIGHT")
            player.position(23)
            player.command("keypress","Ctrl+RIGHT")
            player.position(83)
            player.command("keypress","Shift+LEFT")
            player.position(80)
            player.command("keypress","Ctrl+LEFT")
            player.position(20)

            # Audio-only media keeps playback controls usable without invented video/CC/previews.
            for audio in audio_samples:
                player.command("loadfile",str(audio),"replace")
                player.wait("path",str(audio))
                player.wait("vid",False)
                player.wait("aid",1)
                player.command("set_property","pause",True)
                tracks=player.get("track-list")
                assert all(track["type"]=="audio" for track in tracks),"audio fixture gained a video/subtitle track"
                player.command("keypress",".")
                deadline=time.monotonic()+2
                while (player.snapshot()["feedback"] or {}).get("text")!="No video frames" and time.monotonic()<deadline: time.sleep(.01)
                assert player.snapshot()["feedback"]["text"]=="No video frames"
                assert player.get("chapter-list")==[],"audio fixture retained video chapters"
                player.near("duration",24,.1)
                # Paused audio position follows decoded packet/buffer boundaries, rather than video frames.
                player.command("seek",10,"absolute+exact")
                player.position(10,.5)
                player.command("keypress","RIGHT")
                player.position(20,.5)
                player.speed(1.5)
                player.wait("speed",1.5)
                player.command("keypress","BS")
                player.command("keypress","DOWN")
                player.command("keypress","m")
                player.wait("mute",True)
                player.command("keypress","m")
                player.wait("mute",False)
                player.command("keypress","SPACE")
                player.wait("pause",False)
                before=player.get("time-pos")
                time.sleep(.3)
                assert player.get("time-pos")>before,"audio playback clock did not advance"
                player.command("keypress","SPACE")
                player.wait("pause",True)
                player.command("set_property","speed",1)
                time.sleep(1)
                uploads=preview_uploads(logfile)
                player.mouse(w*.5,h-59)
                player.screenshot(OUT / f"audio-{audio.suffix[1:]}.png")
                assert preview_uploads(logfile)==uploads,"audio-only hover uploaded a video thumbnail"
                player.menu("info",5)
                player.screenshot(OUT / f"audio-{audio.suffix[1:]}-info.png")
                player.command("keypress","BS")
            player.command("stop")
            player.wait("idle-active", True)
            player.wait("cursor-autohide",cursor_policy)
            text = logfile.read_text(errors="replace")
            assert not any(marker in text for marker in ("Lua error", "stack traceback", "[e][mpvtube]")), "Lua runtime error"
            font_selections="\n".join(line for line in text.splitlines() if "fontselect:" in line)
            for face in ("Roboto-Regular","Roboto-Medium","Roboto-Bold","Roboto-Black"):
                assert face in font_selections,f"UI font did not resolve to {face}"
            print(f"Preview latency: cold {cold_preview*1000:.0f}ms, cached {warm_preview*1000:.0f}ms")
            print("Passed native MPV integration: Roboto font weights, bottom safe area, time toggle, ten-hour timestamps, MP3/WAV audio-only playback, native cursor, caption styles, external SRT, clean subtitle override, exports, keyboard focus, feedback, menus, tracks, seeks, continuous previews, shortcuts, window modes, playlist, auto-hide, idle.")
        finally:
            if player:
                try:
                    player.command("quit")
                except (OSError, RuntimeError):
                    pass
                player.sock.close()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)

    # Small isolated launches verify ownership, persisted keys and absent optional helpers.
    # Saved UI choices take precedence even if the configuration default changes.
    preferences.write_text(f"animations={'no' if args.animations=='yes' else 'yes'}\n")
    native_input=Path(temp)/"input.conf"
    native_input.write_text("SPACE set volume 77\nc set volume 43\nd set volume 37\nMBTN_LEFT cycle pause\n")
    empty_keys={row["action"]["id"]:"none" for row in guide["rows"] if row.get("action",{}).get("shortcut")=="select"}
    for policy in ("mpvtube","compatible","exclusive","empty"):
        profile_ipc=Path(temp)/f"{policy}.sock"
        keymap=Path(temp)/f"{policy}.json"
        keys=empty_keys if policy=="empty" else {"pause-SPACE":"F12","mute-m":"none"}
        keymap.write_text(json.dumps({"version":1,"keys":keys}))
        profile_log=OUT/f"policy-{policy}.log"
        with profile_log.open("w") as console:
            process=subprocess.Popen(["mpv",f"--config-dir={configuration}","--load-scripts=no",*input_isolation[:3],"--force-window=yes",f"--script={script}",f"--osd-fonts-dir={ROOT/'fonts'}",
                f"--input-conf={native_input}",f"--input-ipc-server={profile_ipc}","--pause","--ao=null","--geometry=960x600",
                f"--script-opts=mpvtube-keymap_path={keymap},mpvtube-preferences_path={ui_preferences},mpvtube-shortcut_policy={'mpvtube' if policy=='empty' else policy},mpvtube-volume_step=2,mpvtube-sync_step=0.025,mpvtube-ffmpeg_path=/mpvtube-missing-ffmpeg",str(sample)],
                stdout=console,stderr=console)
            player=None
            try:
                deadline=time.monotonic()+15
                while not profile_ipc.exists() and time.monotonic()<deadline:
                    assert process.poll() is None,"Ownership profile failed to start"
                    time.sleep(.05)
                player=Player(profile_ipc)
                player.wait("vo-configured",True,12)
                w,h,_=player.settle()
                assert player.snapshot()["animations"]==(args.animations=="yes"),"animation setting did not survive restarting MPV"
                player.mouse(6,h-4,True)
                player.wait("pause",True)
                if policy=="empty":
                    initial={name:player.get(name) for name in ("time-pos","volume","mute","sub-visibility","pause")}
                    for key in ("SPACE","c","d","m","RIGHT","F12","0"):
                        player.command("keypress",key)
                    time.sleep(.2)
                    for name,value in initial.items(): player.wait(name,value)
                    player.control("play")
                    player.wait("pause",False)
                    player.control("play")
                    player.wait("pause",True)
                    print("Passed entirely unassigned keyboard with working pointer controls")
                    continue
                player.command("keypress","F12")
                player.wait("pause",False)
                player.command("keypress","F12")
                player.wait("pause",True)
                player.command("keypress","SPACE")
                time.sleep(.1)
                player.wait("pause",True)
                player.wait("volume",77 if policy=="compatible" else 100)
                player.command("keypress","m")
                time.sleep(.1)
                player.wait("mute",policy=="compatible")
                player.command("set_property","sid",1)
                player.wait("sid",1)
                player.command("keypress","c")
                if policy=="compatible": player.wait("volume",43)
                else: player.wait("sub-visibility",False)
                player.command("set_property","volume",100)
                player.command("keypress","d")
                player.wait("volume",37 if policy=="compatible" else 100)
                if policy=="mpvtube":
                    player.command("keypress","UP")
                    player.wait("volume",102)
                    player.command("keypress","WHEEL_UP")
                    player.wait("volume",104)
                    player.command("keypress","g")
                    player.near("sub-delay",-.025,.001)
                    player.menu("sync",7,row="Subtitle earlier")
                    player.near("sub-delay",-.05,.001)
                    player.close_menu()
                player.mouse(w*.5,h-59)
                assert not player.snapshot()["export_ready"]
                player.menu("settings",8,header=False)
                rows=player.snapshot()["rows"]
                export_row=next((i+1,row) for i,row in enumerate(rows) if row["label"]=="Export tracks")
                assert export_row[1]["disabled"] and not export_row[1].get("action")
                player.close_menu()
                player.menu("settings",8,row=export_row[0],header=False)
                player.screenshot(OUT/f"missing-ffmpeg-{policy}.png")
                player.close_menu()
                player.command("keypress","Ctrl+p")
                time.sleep(.1)
                player.close_native()
                player.command("keypress","F1")
                guide=player.wait_state("menu","shortcuts")
                if policy in ("mpvtube","compatible"):
                    saved_keymap=keymap.read_text()
                    if policy=="mpvtube": keymap.write_text(saved_keymap+"\n")
                    player.menu_row("Reset all shortcuts")
                    player.wait_state("menu","shortcut-reset")
                    player.control("row-1")
                    error=player.wait_state("keymap_tone","error")
                    assert ("changed or unreadable" if policy=="mpvtube" else "Already used") in error["keymap_message"]
                    assert keymap.read_text()==saved_keymap+("\n" if policy=="mpvtube" else ""),"failed reset overwrote saved keys"
                    player.close_menu()
                    player.command("keypress","F12")
                    player.wait("pause",False)
                    player.command("keypress","F12")
                    player.wait("pause",True)
                print(f"Passed {policy} ownership, persisted keys and disabled FFmpeg actions")
            finally:
                if player:
                    try:player.command("quit")
                    except (OSError,RuntimeError):pass
                    player.sock.close()
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.terminate();process.wait(timeout=5)
