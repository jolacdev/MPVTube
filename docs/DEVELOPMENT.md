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
| `core/player.lua` | Shared native actions, menus, amplification and temporary window settings |
| `core/shortcuts.lua` | Shared action registry, ownership, conflict checks and persistent key editor |
| `core/export.lua` | Codec-aware export planning and one asynchronous stream-copy worker |
| `core/input.lua` | Mouse gestures, Tab focus, synchronous key routing, 2× holds and tooltips |
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
  changes. Focused/menu key capture ends synchronously on dismissal, before the next key event.
  Tab stores hit IDs/pages, resolves fresh geometry after resize and skips unavailable controls.
  Esc steps back; Backspace clears menus/focus and resets the Tab starting point.
- Property changes coalesce into a frame. Hidden playback skips frequent time/
  cache redraws; settled animations stop scheduling frames.
- Caption choices read back successful writes and observe native outline options.
  Border aliases can miss change notifications. The native names are available
  throughout our supported MPV 0.40+ range.
- `ui.draw.metrics`, `Canvas:hover`, `Canvas:toggle` and `ui.view.volume_hover`
  share spacing, highlights and expanded-volume behavior. `Canvas:badge` shares measured, clipped text backgrounds for tooltips and all
  central feedback labels; compact feedback scales to leave space around the icon.
  `ui.motion` owns timing;
  player actions do not create separate animation timers.
- Plain menu rows share a text inset, including Reset; only icons/checkmarks
  reserve an extra column. Menu width estimates reuse the rendered inset and
  value spacing, rounded up to avoid fractional clipping of short labels.
- Menus paint current geometry immediately, without retaining old pages or blocking
  clicks. Shortcut tools use a centered wide panel. Subtitle style is a pinned row
  outside the scroll range. Shortcut notices use the same pinned geometry with a
  fixed height, semantic colors and no action. Editor information uses plain text
  roles, separated from actions by a divider. Editor commands reuse ordinary menu
  typography, hover, click and focus geometry, without a separate button renderer.

### Typography and assets

`ui.draw.text_styles` defines named CSS sizes/weights; `Canvas:label` uses them.
`Canvas:text` converts CSS em sizes to ASS ascent/descent sizes: Roboto uses
`(2146+555)/2048` from its OS/2/head tables. Arial has its own conversion; unknown
fonts use native ASS sizing. Explicit weight/italic/tracking avoids inherited OSD
styles. See [libass font metrics](https://github.com/libass/libass/blob/master/libass/ass_font.c).

Timers and feedback cards use a hidden [compute_bounds overlay](https://mpv.io/manual/stable/#command-interface)
to measure the same font/weight being drawn. Its small cache resets on font/window/
scale changes; a warm-up frame handles the VO's previous dimensions. Menu labels
use a cheaper width estimate.

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

## Focus, shortcuts and export ownership

`core/shortcuts.lua` defines key/action/label/category tuples once. Mouse descriptors
and keyboard handlers call `player.action`; tooltip hints derive from effective
assignments. The default `mpvtube` policy owns an exclusive section. An `UNMAPPED`
ignore keeps unassigned keys inactive even if every action is disabled. Avoid
`ANY_UNICODE` here: MPV checks it before assigned letters, regardless of priority.
`exclusive` remains an alias; `compatible` explicitly permits native/user bindings.
Focus routes activate above playback bindings and deactivate synchronously;
registered callbacks forward already queued events after focus clears.

The editor groups owned actions; Input diagnostics exposes live routes through
MPV’s weak/strong and section-priority rules. MPV's binding property still reports
priorities for shadowed sections: `shortcuts.effective` filters below the ownership
section before resolving conflicts, labels or queued focus events. Key capture uses a temporary exclusive
section with native key names, retaining mouse routes. Candidate and Save both
check canonical assignments and external active bindings, excluding temporary UI
routes. Esc cancels, Enter stays reserved for activation. Only valid saved changes
rebuild the playback section. Successful edits update shared menu/tooltip hints immediately.
The form initially focuses Record, then reveals/focuses Save after a valid candidate.
Both reuse the menu's ordinary row-focus path; Enter activates the focused action.
Toolbar hit flags make Settings, CC and Audio close any open panel before opening
their own view on a later click. Top MPV Menu reuses normal button drawing and
hit geometry; Tab visits the playback bar before the top tools, from left to right.

The owned JSON keymap has a version and ID/key dictionary. Saving detects external
changes, writes a sibling temporary file and renames it into place. Windows uses a
recoverable rename fallback. Failed writes keep the active mapping. Native input
files are untouched. Tests use a temporary `keymap_path`, never the user’s keymap.
Reset all uses the same writer, checks all defaults together before saving and
applies them only after success. Old swapped assignments do not create false conflicts;
effective external routes still do. Cancel, write failures and concurrent file edits
leave active keys intact. Diagnostics shows owners/commands/priorities and explains
its read-only troubleshooting purpose in a pinned notice.
Track mappings use native IDs and the common property action.

Discrete changes share player feedback and read accepted native values. Subtitle
Off and toggle both use `sub-visibility`, retaining `sid`; the bar opens the selector.
Caption writes aggregate success before reporting a result. The registry, wheel,
focused volume control and synchronization menu reuse configurable step values.

Exports resolve the selected/all embedded native `ff-index` and an explicit codec/
container table. Remote paths and unsupported formats are unavailable. Metadata
only contributes sanitized filename suffixes. FFmpeg receives argument arrays,
`-map`, `-c copy`, an explicit muxer and `-n`, never shell text or transcoding.
One asynchronous executable probe enables exports and the FFmpeg preview backend; one export worker runs at a
time. Batches snapshot their source/track paths and may finish after file changes.
Generation tokens ignore late shutdown callbacks. No output file is overwritten
or removed by the worker; failed/interrupted copies can leave incomplete exports,
which the user must remove before retrying. Existing media is never modified.

Clean subtitle styling snapshots native caption properties, uses
`sub-ass-override=strip`, and restores the pre-toggle snapshot when switched off.
Appearance changes retain strip while enabled; Reset restores startup style.
Amplification sets native `volume-max`, respects subsequent external changes and
restores its original ceiling only while still owning the value.

## Script messages

Use `script-message-to mpvtube show`, `hide` or `toggle` for visibility.
`script-message-to mpvtube menu PAGE` toggles a page. Supported pages:
`settings`, `speed`, `audio`, `sub`, `video`, `chapters`, `playlist`,
`info`, `captions`, `controls`, `sync`, `exports`, `shortcuts`, `shortcut-reset`, `bindings`, `mappings`; subtitle choice pages are `caption-font`, `caption-color`,
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

Parse every runtime file with:

```sh
for file in $(rg --files scripts/mpvtube -g '*.lua'); do luac -p "$file"; done
```

Native checks need MPV, FFmpeg/ffprobe, Python 3 and a macOS/Linux desktop. `--no-config`
keeps them separate from user settings. Physical window/terminal input is disabled
for these launches; IPC injects the tested gestures, so normal computer use cannot
change the fixture. The main launch avoids focus stealing using the supported option name; short
ownership checks request fresh windows. `tests/player.py` is the shared JSON IPC
client, not another suite. Windows needs the Lua check and the
[manual checklist](../README.md#5-open-media-and-check-the-controls); this harness
uses Unix sockets. UI checks use generated local media and need no website access.

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
They verify formatting, missing metadata, bounds, focus, styling, animations and
hit capture. A fake `mp` records native writes/workers and lets tests trigger
callbacks immediately or defer property notifications, including delayed clicks, aborted prefetch, provider handoff and stale file/track completions.
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
clicks/double-clicks, held video clicks, seeks, dynamic hour/remaining timers, mini player/fullscreen, playlists,
long chapters, audio-only MP3/WAV, external SRT, caption styles/Reset/CC/clean override, amplification, synchronization, exports,
Tab focus/clear/step-back, shortcut editing/conflicts/persistence, no fallback for
remapped/disabled keys, fixed editor notices, categorized controls and all ownership
policies, disabled FFmpeg actions, native MPV tools,
auto-hide and lifecycle cleanup. Preview checks measure cold/cached/hidden-control
uploads and verify the selected video track. The log confirms all four Roboto faces. Export checks read SRT output and probe
AAC containers for native codecs, and verify ASS exports retain authored fonts; collisions must preserve original output bytes.
A small 1 fps fixture validates the configurable 3/10/60/300-second seek modifiers;
the sparse ten-hour fixture only tests timestamp layout because its frame gaps are ten minutes.
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

The generator also creates styled ASS for authored/clean caption comparisons and
a small seek fixture with whole-second frames, MP3/WAV without video/subtitles and a second-video
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

## Visual geometry and motion

The current skin and generated local fixtures are the UI baseline. Live website
or reference-video audits are not required. Keep the existing rounded dark cards,
Roboto roles, vector icons and shared geometry coherent when adding controls.

| Element | Shared geometry |
| --- | --- |
| Bar capsules / hovers | 40 px high; 12 px side / 8 px bottom inset; black 30%; white hover 10% |
| Icons | Standard 24 px; track arrows 16 px in 24 px slots |
| Time | Measured dynamic width; equal 16 px padding; 14 px Medium |
| Menus | Black 60%, radius 12 px; ordinary right 12 / bottom 62 px; shortcut workspace centered |
| Rows | Ordinary 48 px, shortcut 40 px, compact 30 px; padding 8 px; pinned subtitle-style footer |
| Feedback | Centered circle/icon, bounded separate top text card; compact sizing |

`ui.motion` owns hover, tooltip, switch, wave and feedback transitions. Menu
opening/closing, navigation and scrolling have no animation delay or pointer guard.
Retarget from current values and prune settled tracks. Visibility still uses
`fade_duration`; menu painting has full opacity independently of the bar fade.

Native limits: preview corners stay square, subtitle backing styles use MPV’s
single layer, bitmap captions cannot be restyled, and placement depends on the
window manager. Geometry checks need native screenshot review.

## References and licensing

Technical references: [MPV API](https://mpv.io/manual/stable/#lua-scripting),
[ModernZ](https://github.com/Samillion/ModernZ),
[mpv-osc-youtube-ui](https://github.com/eatsu/mpv-osc-youtube-ui).
No code/assets were copied from those reference projects.
Source uses MIT; bundled Roboto uses Apache 2.0.
