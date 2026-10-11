# Development

Run commands from the repository root. Users need MPV; developers also need
Lua/LuaJIT, Python 3 and FFmpeg for the checks below. Follow [AGENTS.md](../AGENTS.md)
and keep [Features and controls](FEATURES.md) aligned with actual behavior.

## Structure and shared behavior

`scripts/mpvtube/` is one MPV script package. MPV loads `main.lua`; Lua's `require`
loads its `core/` and `ui/` modules. Install the whole folder, not individual
modules. This follows [MPV script packaging](https://mpv.io/manual/stable/#script-location).

| Module | Responsibility |
| --- | --- |
| `main.lua` | Options, observers, frame scheduling, visibility and lifecycle |
| `core/model.lua` | Pure formatting, metadata, track IDs, seek bounds and feedback bursts |
| `core/player.lua` | Native actions, menus, sleep timer and temporary window settings |
| `core/input.lua` | Mouse gestures, 2× holds, tooltips and shortcuts |
| `core/captions.lua` | Native subtitle choices, observations and Reset |
| `core/thumbnails.lua` | Providers, worker, cache and bitmap overlay |
| `ui/view.lua` | Shared draw/hit geometry; controls, timeline and feedback |
| `ui/menu.lua` | Rows from observed state, panel sizing and drawing |
| `ui/draw.lua` / `ui/icons.lua` | Reusable ASS shapes/text and normalized vector paths |
| `ui/motion.lua` | Pure easing, interruptible transitions and feedback keyframes |

`state` holds observed playback and interaction data; `options` holds validated
settings; `view` shares callbacks and the current layout. UI action descriptors
are executed by `core/player.lua`. Drawing modules issue no MPV commands, so they
can run without a player in regression tests. Brief comments explain ownership,
major sections and non-obvious decisions. Short names are limited to coordinates
and dimensions, such as `x`, `y`, `w`, `h`, `cx`, `cy`.

Key invariants:

- Geometry uses logical pixels after DPI scaling. Input rebuilds layout before
  clicks to handle resizes. Reverse hit order gives controls/menus priority over
  the bottom safe area and overlapping timeline edges. Outside left/right clicks dismiss menus
  without becoming video taps. Left clicks retain bottom-control actions; right clicks
  are captured only over UI or while menus are open. Held sliders capture the window; seek drags throttle
  keyframe seeks and commit exactly on release.
- File changes cancel pending taps, presses and 2× holds. Shutdown kills callbacks
  and restores temporary settings, preserving later subtitle-position/end-of-file
  changes. Menu key capture ends when its menu closes.
- Property changes coalesce into a frame. Hidden playback skips frequent time/
  cache redraws; settled animations stop scheduling frames.
- Caption choices read back successful writes and observe native outline options.
  Border aliases can miss change notifications. The native names are available
  throughout our supported MPV 0.40+ range.
- `ui.draw.metrics`, `Canvas:hover`, `Canvas:toggle` and `ui.view.volume_hover`
  share spacing, highlights and expanded-volume behavior. `ui.motion` owns timing;
  player actions do not create separate animation timers.
- Plain menu rows share a text inset, including Reset; only icons/checkmarks
  reserve an extra column.
- Menu pages slide/resize inside a shared clip, retaining right/bottom anchors.
  One travel distance separates unequal widths. Pointer capture covers both pages
  until a deadline, preventing invisible rows or delayed renders blocking input.

### Typography and assets

`ui.draw.text_styles` defines named CSS sizes/weights; `Canvas:label` uses them.
`Canvas:text` converts CSS em sizes to ASS ascent/descent sizes: Roboto uses
`(2146+555)/2048` from its OS/2/head tables. Arial has its own conversion; unknown
fonts use native ASS sizing. Explicit weight/italic/tracking avoids inherited OSD
styles. See [libass font metrics](https://github.com/libass/libass/blob/master/libass/ass_font.c).

Timers use a hidden [compute_bounds overlay](https://mpv.io/manual/stable/#command-interface)
to measure the same font/weight being drawn. Its small cache resets on font/window/
scale changes; a warm-up frame handles the VO's previous dimensions. Other clipped
labels use a cheaper width estimate.

Four unmodified [Google Roboto TTFs](https://github.com/googlefonts/roboto-2/tree/38062f4b4a0be4346d07a928408da21602545e9e/src/hinted)
provide Regular, Medium, Bold and Black. Keep these runtime assets in Git.
`LICENSE-Roboto.txt` stays outside `fonts/`, because MPV tries to load every file
there as a font. Fonts are loaded by MPV, not installed system-wide.

### Preview worker

The fallback passes an argument array to FFmpeg, never a shell command. It decodes
the selected video's native `ff-index`, not an assumed first stream. One worker
serves the latest hover, then warms at most two neighbors. Foreground work can
finish during pointer motion; unrelated prefetch is aborted for an uncached hover.
The default delay is zero; a configured delay coalesces initial requests without
restarting on motion. Cached/neighboring frames can show during the control fade.

Generation IDs invalidate cancelled/file/track callbacks before aborting workers.
The bounded cache retains the hovered bucket on eviction. Provider handoff clears
both kinds of overlay to prevent stacking. Normal cleanup removes temporary BGRA
frames; forced termination can leave them in the OS temporary directory.
FFmpeg uses four decoder threads, one filter/output thread, a 32 KiB probe and
reference frames to reduce startup/seek work. A failed or empty fast decode retries
once with normal probing/all frames, then falls back to timestamps. No extra
worker, persistent process or background scan is added.

## Script messages

Use `script-message-to mpvtube show`, `hide` or `toggle` for visibility.
`script-message-to mpvtube menu PAGE` toggles a page. Supported pages:
`settings`, `speed`, `audio`, `sub`, `video`, `chapters`, `playlist`, `sleep`,
`info`, `captions`; subtitle choice pages are `caption-font`, `caption-color`,
`caption-size`, `caption-opacity`, `caption-background`,
`caption-background-opacity`, `caption-edge`. Unknown pages are ignored.
Messages work with `keyboard=no`.

## Checks and what they prove

The skin runs in **Lua inside MPV**. Python only drives a real MPV process during
development; users do not need it. Tests are executable assertion scripts without
a framework. Failed assertions stop with a nonzero exit code.

| Check | Command | Purpose |
| --- | --- | --- |
| Syntax | `luac -p path/to/file.lua` | Parse Lua without executing it |
| Regression | `luajit tests/regression.lua` | Real Lua modules, deterministic layout/motion and mocked native services |
| Native | `python3 tests/integration.py` | Real Lua skin in isolated MPV, generated local media and screenshots |
| Online, optional | `python3 tests/online.py` | Real Learn Linux TV URL, chapters, English/Spanish captions and native controls |

Parse every runtime file with:

```sh
for file in $(rg --files scripts/mpvtube -g '*.lua'); do luac -p "$file"; done
```

Native checks need MPV, FFmpeg, Python 3 and a macOS/Linux desktop. `--no-config`
keeps them separate from user settings. `tests/player.py` is the shared JSON IPC
client, not another suite. Windows needs the Lua check and the
[manual checklist](../README.md#5-open-media-and-check-the-controls); this harness
uses Unix sockets. Online checks additionally require yt-dlp/network access;
missing streams or captions fail the run, rather than being counted as success.

### Understanding the Lua tests

```lua
package.path = "scripts/mpvtube/?.lua;" .. package.path
local model = require("core.model")
assert(model.time(3661) == "1:01:01", "format one hour, one minute, one second")
```

`package.path` locates modules; `require` loads one; `local` declares a variable;
`assert` raises an error if its condition is false. The suite's `check` wrapper
also counts successes. The total includes repeated checks across widths/states,
not that many independent scenarios.

Pure checks use sample state, generated ASS instructions and deterministic clocks.
They verify formatting, missing metadata, bounds, timers, styling, animations and
hit capture. A fake `mp` records native writes/workers and lets tests trigger
callbacks immediately or defer property notifications, including sleep expiry,
delayed clicks, aborted prefetch, provider handoff and stale file/track completions.
Installed code uses the real API.

### Understanding the Python tests

```text
Python -> JSON IPC commands -> MPV input -> real Lua skin -> native properties
Python <- matching JSON replies with the resulting MPV properties
```

For example, `player.command("keypress", "c")` sends a key press;
`player.wait("sub-visibility", True)` checks its result. Request IDs match replies
despite other events. Exact/numeric waits have deadlines because input/decoding is
asynchronous. IPC replies precede Lua callbacks; brief waits after mouse-down are
test synchronization, not an application slider delay.

An integration-only wrapper records the skin's drawn checkmarks, so subtitle
tests check visible selections as well as native properties. Production code has
no test hooks.

Native coverage includes buttons, keyboard/menu navigation, volume/mute feedback,
held sliders through reversals/overshoot/out-of-bounds movement, left/right safe-area
clicks/double-clicks, held video clicks, seeks, dynamic hour/remaining timers, window modes, playlists,
long chapters, audio-only MP3/WAV, external SRT, caption styles/Reset/CC, sleep,
auto-hide and lifecycle cleanup. Preview checks measure cold/cached/hidden-control
uploads and verify the selected video track. The log confirms all four Roboto faces.
Lua checks keep hover labels anchored across missing, loaded and tall previews,
with chapters and at both edges of narrow and wide players.

Screenshots, logs and timings go to ignored `tests/output/`. Transition captures
use JPEG and record requested times; deterministic Lua clocks verify keyframes.
Screenshots need visual review: geometry/property assertions do **not** prove
pixel identity. IPC does not reproduce physical mouse events or file-manager
drops; external captions use `sub-add`. Audio uses `ao=null`, so audible output
still needs a listening check. Linux/Windows window behavior remains unverified.

## Reproducible test media

Keep generation recipes in Git, not generated media. The moving colored video
is FFmpeg `testsrc2`, made by `integration.py`: 24 seconds, 1280 × 720, two tone
tracks labeled English/Spanish, an English SRT and three chapters. Motion makes
pause, frame stepping, seeks and preview differences visible; it is not a movie.

The generator also creates MP3/WAV without video/subtitles and a second-video
variant with a blue stream to expose wrong-track previews. The full run adds
external Spanish SRT, 48 short chapters and a sparse 10:10:00 video containing
61 frames, one per ten minutes, for hour-field tests without large media.

```sh
python3 tests/integration.py --generate-fixtures
mpv --no-config --osd-fonts-dir=./fonts --script=./scripts/mpvtube tests/output/fixture.mkv
mpv --no-config --osd-fonts-dir=./fonts --script=./scripts/mpvtube --force-window=yes tests/output/audio.mp3
```

The first command needs only Python/FFmpeg; the others open generated media with
the repository's skin. No user configuration is changed.

## YouTube comparison and motion reference

The 11 October 2026 embedded-browser audit used Learn Linux TV's
[Ansible tutorial](https://www.youtube.com/watch?v=CMB5GCexb84) in regular,
fullscreen and compact players. It covered icons, active/disabled states, captions,
chapter selection, speed, time, volume, key feedback and settings. A prior long-time
comparison used [this ten-hour rain video](https://www.youtube.com/watch?v=zSKfyjcR4x4).
YouTube experiments can change the reference. The current MPV online attempt was
blocked by HTTP 403; browser comparison and local integration still completed.

| Geometry / typography | Observed target |
| --- | --- |
| Capsules / hovers | 40 px high; 12 px side / 8 px bottom margin; black 30%; white hover 10%, 32 px high |
| Icons | Bottom SVG canvas 24 px, chapter chevron 20 px, information canvas 36 px |
| Volume | 52 px panel, 2 px rail, 12 px knob, then 3 px gap / 16 px padding; one/two waves at 50% |
| Time | Dynamic width; 16 px padding; 14 px Medium |
| Timeline | Center 59 px from bottom; 3 px resting / 6 px expanded; chapter gaps |
| Menus | Right 12 px, bottom 62 px; row 48 px, padding 8 px, submenu header 57 px; black 60% |
| Text | Roboto fallback/title; named CSS roles and 400/500/700/900 weights in `text_styles` |
| Feedback | 78 px circle / 54 px icon; separate top percentage; 24 px Bold signed seeks |
| Autoplay / gear | 30 × 18 px track, 14 px knob; gear turns 30° |

| Motion | Timing / shared curve |
| --- | --- |
| Hover, timeline, tooltip, knob | 0.2 s; cubic-bezier(0.05,0,0,1) |
| Volume panel | 0.2 s; enter (0,0,0.2,1), leave (0.4,0,1,1) |
| Waves / autoplay track | About 0.25 s around pivots (18,12)/(22,12); track 0.08 s leave curve |
| Gear / compact arrow | 0.1 s leave curve / 0.3 s modern curve |
| Feedback | 1 s; fade/grow first 25%, hold to 75%, shrink/fade; modern curve |
| Menu fade / page travel | 0.1 s enter/leave / 0.25 s (0.4,0,0.2,1), pointer guard |
| Control visibility | Default 0.25 s enter / 0.1 s leave; configurable |
| Arrow seek | About 1.2 s; fade, outward chevron, hold, fade; shared easing approximation |

`ui.motion.duration` and its curves own these values; `ui.draw` owns painting.
Retargeting samples the current value and prunes unused tracks. Modern play/pause
and CC glyphs switch directly; surrounding feedback/highlights animate.
The browser's held-click helper returns after release, so the live 2× badge was
not captured during a hold; native press/release/restoration is tested.

Native limits remain explicit: chapters use a popup, bitmap preview corners stay
square, caption styling uses MPV's single backing layer, and video tracks replace
a streaming-quality selector. Browser blur, window-manager motion and rasterization
can differ. Matching outlines/spacing is not proof of identical screenshot pixels.

## References and licensing

Technical references: [MPV API](https://mpv.io/manual/stable/#lua-scripting),
[ModernZ](https://github.com/Samillion/ModernZ),
[mpv-osc-youtube-ui](https://github.com/eatsu/mpv-osc-youtube-ui).
No code/assets were copied from those reference projects. Player outlines were
transcribed from the live YouTube player; screenshots remain their owners' property.
Source uses MIT; bundled Roboto uses Apache 2.0.
