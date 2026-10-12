# Features and controls

MPVTube keeps YouTube-style controls and adds native MPV tools. Playback settings apply for the current session. Shortcut edits are saved to the
skin’s own keymap; native playback configuration stays under MPV’s control.

## Mouse and keyboard

Click the video to play/pause; double-click for fullscreen. Hold a playing video
for 0.35 seconds to use 2× speed; release restores the previous speed. The bottom
72 logical pixels are a safe area: empty-space clicks, right clicks, double clicks
and holds do not change playback. One outside click closes menus; left-clicked
bottom controls still perform their actions.

**Tab / Shift+Tab** cycles available visible controls. A white outline shows focus.
Enter or Space activates the focused button; arrows navigate controls or adjust a
focused slider. Menu Up/Down scrolls to selectable rows; Left and Esc step back.
The speed menu's Up/Down changes speed by 0.05×. Home/End selects list edges or
slider minimum/maximum. Shift/Ctrl arrows also navigate UI while focused.

**Backspace clears menus and focus immediately**, resetting Tab to the first
button. Clicking the canvas also clears focus, then performs its usual video
click. Standard playback keys resume as soon as focus clears. Resize/file changes
release focus when its target disappears. Pointer movement switches to mouse use.

| Key, without UI focus | Action |
| --- | --- |
| Space | Play/pause |
| Left / Right | Short seek, default ±10 seconds |
| Shift+Left / Right | Precise seek, default ±3 seconds |
| Ctrl+Left / Right | Medium seek, default ±60 seconds |
| Ctrl+Alt+Left / Right | Long seek, default ±300 seconds |
| 0–9; comma / period | Seek 0%–90%; previous/next frame |
| Up / Down; M | Volume ±5%; mute |
| N / P, also Shift+N / Shift+P | Next/previous playlist video |
| [ / ] | Previous/next chapter |
| `v` / `Alt+v` | Next/previous subtitle track |
| `b` / `B` (Shift+b) | Next/previous audio track |
| `c`; `u` | Toggle captions; toggle clean subtitle styling |
| `Alt+c`; `C` (Shift+c); `a`; Ctrl+, | Subtitle selector; chapter list; audio selector; Settings |
| `g` / `h` | Subtitles 50 ms earlier/later |
| `j` / `k` | Audio 50 ms earlier/later |
| Ctrl+Shift+K | Reset both synchronization offsets |
| < / > | Speed ±0.25× |
| `f`; `i` | Fullscreen; mini player |
| Ctrl+P; Ctrl+Shift+P | Native MPV menu; native property inspector |
| F1 | Interactive shortcut guide |
| `s`; backtick; `q` | Screenshot; native MPV console; quit |

Letters are lowercase unless Shift is stated. Seek distances use VLC’s
3/10/60/300-second sizes; MPVTube assigns the 10-second jump to plain arrows.
Configure `seek_precise`, `seek_short`, `seek_medium`, `seek_long`, in seconds.
`volume_step` sets volume key/wheel increments in percentage points;
`sync_step` sets audio/subtitle increments in seconds, default 0.05 (50 ms).
`keyboard=no` disables general skin mappings, including Tab/Backspace; mouse
controls and menu arrow/Enter/Esc navigation remain, and native keys are released.

## Bottom bar and menus

Play/pause, volume, elapsed/remaining time, captions, Settings and fullscreen use
shared hover geometry and styling. The timer grows with both timestamps, including
hours; clicking toggles elapsed/remaining time without seeking. Hovering the
speaker expands its slider, with one hover area for both. Pointer volume/mute
changes do not start central feedback; keyboard changes do.

Volume reaches **200% by default** through the slider, wheel and keys. Set
`volume_max=100` for no amplification, or another ceiling up to 1000. The skin sets
MPV's software `volume-max`; 100% is the unamplified level. Higher values can clip.
External changes to the native ceiling are respected. Shutdown restores the
original ceiling if it is still the value owned by the skin.

The bar uses one subtitle selector and one audio selector, with small previous/next
arrows alongside each when space allows. Playlist and chapter step buttons appear
in wide players. The current chapter label is the single chapter-list button;
compact players reach chapters through Settings. Tooltips show effective shortcut
assignments and update after edits. Tab follows the bar’s left-to-right order,
then visits MPV Menu and information at the top right.
Both icons open their track menus; `c` toggles subtitles without opening a menu,
and `Alt+c` opens the subtitle menu. Settings, CC and Audio share one rule: when
any settings view is open, clicking any of these three closes it. With no view
open, each opens its own view. This also applies to appearance and shortcut pages.
**More controls** groups chapters/playlist,
subtitles, audio, playback, synchronization and window/tools, including screenshots
and MPV's console. **Export tracks** has a direct entry near the top of Settings.
Compact Expand reveals audio/CC/Settings/fullscreen.


Settings includes speed, audio, captions, available video tracks, export, loop,
playlist, autoplay, More controls, the shortcut guide and media information. Speed presets
are 1, 1.25, 1.5 and 2×; dragging adjusts 0.25–2× in 0.05× steps. Held sliders update
continuously through reversals and movement outside their bounds. Menus open, change pages and scroll immediately, without slide/fade input delays.
Ordinary panels stay near the gear; the shortcut editor is larger and centered.
Tall lists scroll, with tighter rows in small windows. Checkmarks/labels follow accepted native values, including external changes.
Available shortcuts appear beside option names, including in More controls and
Synchronization. Hints use the effective saved assignment and update after edits;
unassigned or overridden shortcuts are not advertised.

Playback and setting changes reuse on-screen feedback: subtitle on/off and track
name, audio/video selection, speed, caption appearance, loop/autoplay, seeking,
frame steps, synchronization, fullscreen/mini player and screenshots. Unavailable
actions report their reason. Mouse volume/mute retains feedback in its controls;
keyboard volume uses the percentage card. Opening/navigating a menu is shown by
the menu and focus, and native tools provide their own interface.

## Chapters, playlists and media

Chapter metadata splits the timeline and supplies a current-title capsule. Its
menu marks the current chapter and scrolls it into view. Selecting a chapter
seeks to its start, starts playback and keeps the list open. Previous/next chapter
controls seek adjacent chapters while preserving pause. Boundary buttons are
disabled; shortcuts at boundaries report that no adjacent chapter exists. Chapters use a scrollable popup.

Open multiple files with `mpv "one.mp4" "two.mp4"`. Playlist selection preserves
pause. Autoplay Off sets `keep-open=always`, pausing at file ends; On restores the
previous policy. It does not find another online video. Loop repeats the current
file and takes precedence. The autoplay override is restored on shutdown unless
another command changed it.

Audio-only files retain playback, seeking, time, volume, speed and track/playlist
controls. Use `--force-window=yes` if MPV opens no window. Information shows
**Audio only**; no video thumbnails are generated. Media information also shows
resolution, codecs, frame rate and duration. Fullscreen shows the title;
`title=no` hides the top title/information button, retaining Settings information.

## Tracks, captions and synchronization

Track menus use MPV's titles, languages and stable IDs. Subtitle/audio cycling
wraps through loaded tracks, including dynamically added external files. Off
hides captions while remembering the selected track, exactly like toggling them
off with `c`. Toggling back on selects the first track if necessary. The CC button
opens this selector, is filled when visible, outlined when off and disabled when none
exists. Drop `.srt`, `.vtt` or `.ass` onto MPV, or use native `sub-add`; menus update.
Video selection chooses loaded streams, not every online resolution. HD/4K badges
identify the loaded stream and have no selection action.

**Subtitles/CC → Options** customizes font family (including Roboto), color, size,
font/background opacity and None/Drop shadow/Outline edges. Colors include white,
yellow, green, cyan, blue, magenta, red and black. Sizes range from 50% to 400% of startup size, with 5% steps around
80%–130%; opacity choices are 0%, 25%, 50%, 75%, 100%. Reset restores startup
settings. Plain option rows, including Reset, share one text inset.

**Clean subtitle style**, in the subtitle menu or `u`, strips authored ASS/SRT text
styles through `sub-ass-override=strip`, using regular white Roboto with a black
outline and no background. Toggle off to restore the pre-toggle appearance. If MPV started in strip mode,
Off re-enables authored styles; Reset still restores the startup preference.
Further customization remains available while enabled. The clean-style toggle stays pinned below the subtitle list, with a separator,
so scrolling tracks cannot hide it. Startup styles are preserved until you make a choice. Appearance changes can override authored
layouts; bitmap and burned-in subtitles cannot become restylable text. MPV's
single backing layer supports either a box or a drop shadow.

**More controls → Adjust delays** shows audio/subtitle delays and offers earlier,
later and Reset actions. Positive offsets delay that stream; negative subtitle
offsets advance subtitles, while negative audio offsets delay the video. These
are native `sub-delay`/`audio-delay`, independent of caption styling. The offsets
are not baked into exports. **Reset synchronization** is also directly available
under More controls.

`raise_subtitles=yes` temporarily lifts ordinary bottom captions above visible
controls, then restores their position. Authored layouts may position themselves.
For permanent native styling, use `mpv.conf`; for example:

```ini
sub-font=Roboto
sub-color="#FFFFFFFF"
sub-outline-color="#FF000000"
sub-outline-size=1.65
sub-border-style=outline-and-shadow
sub-shadow-offset=0
```

Colors use alpha then RGB, with `FF` fully opaque. See
[MPV subtitle options](https://mpv.io/manual/stable/#subtitles).

## Track export

Open **Settings → Export tracks**. Export the selected subtitle/audio track,
or all supported embedded tracks of that type. The export entry is disabled when
FFmpeg is unavailable. Exports require **FFmpeg** and a local media file; `ffmpeg_path` selects its executable. No separate muxing UI is
needed. Remote/unsupported tracks have no export action. Selected local external
tracks can be exported too; All embedded excludes them.

One asynchronous worker copies packets without re-encoding. Outputs go beside
the video, for example `film.sub-2.eng.ass` and `film.audio-1.spa.m4a`. Language/ID
suffixes distinguish tracks. Existing files are never overwritten; rename/move
an earlier export before retrying. Status reports progress, completion, unsupported
tracks skipped in a batch, or failure. MPV's log contains extraction errors.
Failed or interrupted exports may leave an incomplete output; remove it before
retrying. Closing MPV cancels the worker. Switching media leaves a pending batch tied to
its original source and destination.

| Source codec | Output |
| --- | --- |
| SubRip, WebVTT, ASS/SSA | `.srt`, `.vtt`, `.ass`/`.ssa` |
| PGS subtitles | `.sup` |
| AAC / ALAC | `.m4a` |
| Opus, Vorbis | `.opus`, `.ogg` |
| MP3, FLAC, PCM | `.mp3`, `.flac`, `.wav` |
| AC-3, E-AC-3, DTS | `.ac3`, `.eac3`, `.dts` |

Unsupported formats are skipped, never converted silently. Container compatibility
can still prevent a copy; export status must report that failure. Original media
is read only. This uses [FFmpeg stream copying](https://ffmpeg.org/ffmpeg.html#Streamcopy),
not an MPV-core track-extraction API.

## MPV tools and shortcut guide

Ctrl+P and the MPV Menu button at the top right, beside information, open MPV's built-in `select/menu`, retaining its
file/configuration handling. Ctrl+Shift+P opens `select/show-properties`. These
require MPV's default `load-select=yes` and `load-console=yes`; the skin does not
replace those components. Disabling them disables the corresponding GUI actions.
Esc closes native panels using their own bindings. These panels retain MPV's native
layout and fonts; the skin's custom drawers use its shared Roboto styles.

**More controls → Take screenshot**, or `s`, captures the current frame using MPV's
`screenshot-directory`, `screenshot-template` and `screenshot-format` settings.
The skin reports the result; MPV chooses the filename and format. **MPV console**,
or the backtick key, opens MPV's built-in command console. Both work without extra
helpers. `q` quits the player.

F1 or Settings → Shortcut guide opens a centered, categorized editor. Related
subtitle/audio actions stay together, separated by category headings. Select an
action, choose **Record new shortcut** or press Enter, then press a key combination.
Save gains focus automatically; choose **Save changes** or press Enter again.
Saving reveals the updated key and returns focus to Record.
Esc cancels recording; **Use default** and **Unassign shortcut** provide alternatives
that also require saving. Current/new keys use muted labels and larger values,
without boxes, hover or focus. A separator introduces the actions, which use the
same full-width rows, text and hover styling as the outer menu. Save stays dimmed
until a new key is ready. A fixed status card
stays visible while scrolling: blue guidance, red errors and green successful saves.
Conflicts identify the occupied action. Blocked native bindings cause no conflict
in the default mode; effective native/user bindings are checked in compatible mode.
Rechecking on Save catches later binding changes.

Successful edits apply immediately and persist to `mpvtube-keys.json` in MPV’s
configuration folder. `keymap_path` can choose another existing folder. The skin
preserves `input.conf` and other playback settings. Unwritable folders or externally
changed keymaps report a save failure and retain the current mapping. Esc/Enter remain
reserved for menu navigation; mouse gestures are not editable keyboard shortcuts.
**Reset all shortcuts** opens a confirmation view. Confirming restores every built-in
MPVTube assignment, including unassigned keys, and clears saved overrides. Cancel or Esc
keeps everything. The whole reset is checked and saved together; conflicts or write
failures keep all current keys. Other MPV configuration and scripts remain unchanged.

| `shortcut_policy` | Ownership |
| --- | --- |
| `mpvtube`, default | MPVTube owns the keyboard; native/input.conf fallback is blocked, including remapped/disabled keys |
| `compatible` | `input.conf` can override skin assignments; the editor marks overridden keys |
| `exclusive` | Legacy alias of `mpvtube` |

Unassigned keys remain inactive after closing menus or clearing focus. Native tools
opened explicitly by MPVTube temporarily use their own navigation, then return
ownership to the skin. Playback settings in `mpv.conf` are still honored.
These modes control MPV’s input sections, not OS shortcuts or future forced
bindings installed by another script. Remove competing controller scripts when
using the skin. **Input diagnostics** helps when an input acts unexpectedly: select
a key or mouse action to see its actual command, owning script/section and priority.
For example, it can identify another script intercepting a key, or explain a mouse
or temporary menu-navigation route that is absent from the editable action list.
It is read-only and shows live routing; the guide edits saved MPVTube assignments.
Users whose controls work normally can ignore it. Shadowed native bindings are
absent in the default policy; change external bindings in their owning configuration.
Track mappings lists loaded tracks and lets you select them. `shortcut_width=900` sets the editor’s maximum
guide/inspector width; the simpler rebinding form caps its width at 620 logical
pixels. All panels fit the current window.

## Previews, motion and window effects

Hover/drag the timeline for a timestamp and current chapter. The label keeps one
position with or without a bitmap. Gray timeline segments represent native cache
ranges, or cached-duration fallback, not guaranteed downloaded files.

`thumbnails=auto` prefers thumbfast, otherwise FFmpeg for local video with a known
duration. Remote images need a network-enabled thumbfast. FFmpeg serves the latest
position asynchronously, then warms two neighbors; bounded caching prevents a
background scan. Defaults: zero request delay, two-second samples, 200 px width,
64 cached frames. When FFmpeg is absent, its backend stays disabled and timestamps
remain available; thumbfast can still supply pictures. Cold decoding depends on
hardware/media; cached images are immediate. Missing helpers/metadata gracefully fall back to labels.

Roboto styles, vector icons, colors, spacing and hover/toggle geometry are shared.
Menus are translucent black; controls retain YouTube-style capsules. Hovers,
sliders, tooltips and switch knobs share 0.2 s transitions. Menus paint immediately.
Volume waves, gear rotation and seek/volume feedback use `ui.motion`, retarget
smoothly and stop scheduling when settled.
Central feedback keeps its icon centered in a circle; percentages, synchronization,
track names and other messages share a separate text card above it. Long messages
truncate inside the player margins; small windows use smaller cards/icons. Tooltips
reuse the same measured background and text-padding helper. Central playback
feedback stays hidden while a centered shortcut workspace owns that space.
The OS cursor is retained without overlays.

Controls auto-hide after three seconds while playing; pause, hover, focus, menus
or drags keep them open. Reveal uses configurable `fade_duration=0.25`; hiding
uses 40% of that. Zero disables visibility fading, retaining other transitions.

Fullscreen uses MPV's native window. Mini player, button or I, exits fullscreen,
requests a small borderless window near bottom-right and enables stay-on-top.
Default `pip_width=480`; media aspect ratio is preserved. Toggle again, or enter
fullscreen, to restore saved size/border/pinning/sizing options. `pip=no` disables
it. Placement/DPI depend on the window manager; restoration does not re-enter an
old fullscreen state. No additional playback window is created.

## Configuration and limits

Use `mpv.conf` for native settings, the grouped `script-opts/mpvtube.conf` for skin
options and F1 for shortcuts. `input.conf` keys require compatible mode. Restart
after configuration edits; F1 saves apply immediately. Public show/hide/toggle/menu
messages remain available; see [Development](DEVELOPMENT.md#script-messages).

MPVTube installs no helpers, downloads/translates no subtitles and has no accounts,
casting or streaming-quality selector. URL playback uses separate yt-dlp.
Native validation covers macOS/MPV 0.41; Linux/Windows need platform testing.
Browser/libass rasterization, bitmap preview corners and native window motion can
differ. Geometry/property tests do not prove identical pixels.
