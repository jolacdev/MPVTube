#!/usr/bin/env python3
"""Optional real-video check. Requires yt-dlp, MPV, network access and a desktop."""
import json
from pathlib import Path
import subprocess
import tempfile
import time
from player import Player

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT / "tests/output"
OUT.mkdir(parents=True,exist_ok=True)
RESULTS=OUT / "online-results.json"
RESULTS.unlink(missing_ok=True)  # A failed run must not leave an earlier success report.
URL="https://www.youtube.com/watch?v=CMB5GCexb84"

# Keep streamed media separate from the generated fixture. MPV fetches chapters and captions.
with tempfile.TemporaryDirectory(prefix="mpvtube-online-") as temp:
    ipc=Path(temp) / "player.sock"
    logfile=OUT / "online.log"
    with (OUT / "online-console.log").open("w") as console:
        process=subprocess.Popen(["mpv","--no-config",f"--script={ROOT / 'scripts/mpvtube'}",f"--osd-fonts-dir={ROOT / 'fonts'}",
            "--pause","--ao=null","--force-window=yes","--geometry=1280x800",
            "--ytdl-format=bestvideo[height<=720]+bestaudio/best[height<=720]",
            "--ytdl-raw-options=write-auto-subs=,sub-langs=%10%en-orig,es",
            f"--input-ipc-server={ipc}",f"--log-file={logfile}",URL],stdout=console,stderr=console)
        player=None
        try:
            deadline=time.monotonic()+15
            while not ipc.exists() and time.monotonic()<deadline:
                assert process.poll() is None,"MPV could not start"
                time.sleep(.05)
            player=Player(ipc)
            player.wait("vo-configured",True,90)
            player.settle()
            chapters=player.get("chapter-list")
            tracks=[track for track in player.get("track-list") if track["type"]=="sub"]
            assert len(chapters)==10,chapters
            assert any(track.get("lang","").startswith("en") for track in tracks),tracks
            assert any(track.get("lang","").startswith("es") for track in tracks),tracks
            original_background=player.get("sub-back-color")
            original_style=player.get("sub-border-style")
            rendered,unavailable=[],[]

            # Select the long chapter title through the actual skin, then compare both languages.
            player.menu("chapters",len(chapters),row=4)
            player.command("set_property","pause",True)
            player.command("keypress","ESC")
            player.position(chapters[3]["time"],1,20)
            for language in ("en","es"):
                track=next(track for track in tracks if track.get("lang","").startswith(language))
                player.command("set_property","sid",track["id"])
                player.command("seek",290,"absolute+exact")
                player.position(290,1,20)
                deadline=time.monotonic()+15
                while not player.optional("sub-text") and time.monotonic()<deadline: time.sleep(.1)
                if not player.optional("sub-text"):
                    unavailable.append(language)
                    continue
                rendered.append(language)
                player.command("script-message-to","mpvtube","show")
                player.screenshot(OUT / f"online-{language}.png")

            assert rendered,"Remote captions returned no text; inspect online-console.log for network/rate-limit errors"
            if unavailable:
                track=next(track for track in tracks if track.get("lang","").startswith(rendered[0]))
                player.command("set_property","sid",track["id"])
                player.command("seek",290,"absolute+exact")

            player.menu("caption-background-opacity",5,row=4)
            player.wait("sub-back-color","#BF000000")
            player.wait("sub-border-style","background-box")
            player.command("keypress","ESC")
            player.screenshot(OUT / "online-caption-background.png")
            player.menu("captions",8,row=8)
            player.wait("sub-back-color",original_background)
            player.wait("sub-border-style",original_style)
            player.screenshot(OUT / "online-caption-options.png")
            player.command("keypress","ESC")
            player.command("keypress","c");player.wait("sub-visibility",False)
            player.screenshot(OUT / "online-cc-off.png")
            player.command("keypress","c");player.wait("sub-visibility",True)
            player.screenshot(OUT / "online-cc-on.png")

            # Exercise the same controls on streamed media, rather than only the synthetic fixture.
            player.command("set_property","pause",True)
            player.command("seek",290,"absolute+exact");player.position(290,1,20)
            player.command("keypress","RIGHT");player.position(295,1,20)
            player.command("keypress","LEFT");player.position(290,1,20)
            player.speed_drag([1,1.5,.75,2,1])
            player.command("keypress","ESC")
            player.command("set_property","volume",50)
            player.command("keypress","UP");player.wait("volume",55)
            player.command("keypress","DOWN");player.wait("volume",50)
            w,h,_=player.dimensions()
            player.mouse(w/2,h-4,True)
            player.wait("pause",True)
            player.position(290,1)
            RESULTS.write_text(json.dumps({"url":URL,
                "chapters":len(chapters),"subtitle_languages":[track.get("lang") for track in tracks],
                "rendered_languages":rendered,"unavailable_languages":unavailable,
                "checked":["chapter selection","caption box","Reset","CC on/off",
                    "arrow keys","held speed slider","keyboard volume","bottom safe area"]},indent=2)+"\n")
            assert "Lua error" not in logfile.read_text(errors="replace")
            if unavailable: raise SystemExit("Real-video checks completed except remote captions: "+", ".join(unavailable)+". Inspect online-console.log for network/rate-limit errors.")
            print("Passed real Learn Linux TV playback: chapters, English/Spanish captions, styling, Reset, CC states, keys, held speed slider and safe area.")
        except (OSError,RuntimeError) as error:
            raise SystemExit(f"Online playback unavailable: {error}. Inspect tests/output/online-console.log and online.log.") from error
        finally:
            if player:
                try: player.command("quit")
                except (OSError,RuntimeError): pass
                player.sock.close()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate();process.wait(timeout=5)
