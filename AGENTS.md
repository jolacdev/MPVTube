# MPVTube

Lua/ASS on-screen controller for MPV 0.40+, targeting macOS, Linux and Windows.

## UI and behavior

- Build on the current player features and supplied screenshots, retaining the YouTube-inspired visual style. Use local fixtures for UI regression; no live website/video comparison is required. Reference repositories guide code, not design.
- Verify affected icons' outlines/sizes/centering, text, margins, hovers, active/disabled states, tooltips and transitions in narrow, wide and fullscreen layouts. Measure; report MPV limitations honestly.
- Keep the bottom 72 logical pixels a safe area: background left/right clicks, double clicks and holds cannot toggle playback, fullscreen or 2×. One outside left/right click closes menus without pausing; left-clicked controls retain their actions.
- Share drawing/hit geometry. Volume hover includes its slider; time capsules fit changing/hour-long timestamps and toggle elapsed/remaining without seeking. Held sliders update continuously through reversals and out-of-bounds movement.
- Match font family, CSS size and weight through `ui.draw.text_styles`; use bundled Roboto and its CSS-to-ASS conversion. Keep timer measurements consistent with the rendered weight.
- Retain shared feedback, chapters, auto-hide and hold-to-2× behavior; notify accepted playback/setting changes and unavailable actions. Advanced shortcuts use documented VLC-inspired mappings. Mouse volume controls do not start central feedback.
- Menus open/navigate/scroll immediately, without animation input guards. Use a larger centered shortcut workspace and pin subtitle styling outside the track scroll. Separate plain information from actions; reuse ordinary menu row styles for actions, without boxes for information. Settings/CC/Audio close any open view; otherwise open their own. Show effective shortcut hints beside options. Menus reflect accepted MPV values, including external changes; observe canonical properties and refresh labels/checkmarks immediately. Plain rows, including Reset, share one text inset; reserve columns only for icons/checkmarks. Unavailable features have no fake actions.
- Keep hover previews fast: asynchronous generation, latest-position priority, bounded caching and graceful fallback.
- Central feedback labels use a separate, bounded text card, shared with volume percentages/tooltips; center icons and prevent overlap in compact windows.
- Reuse `ui.motion` easing/timings and `ui.draw` hover/toggle/spacing helpers. Keep shared animations coherent; retarget smoothly and stop scheduling settled transitions.
- Support embedded and dynamically added external subtitles. Preserve existing styles; retain customization and white outlined captions without a background. CC states follow track availability/visibility.
- Use native cursors, never overlays; pointer only with native OS support. Window modes reuse MPV's window and restore settings.
- Tab navigation and menu controls share hit geometry; clear-to-player releases focus bindings synchronously. Esc steps back; canvas clicks/Backspace reset focus. Sort focus visually. MPVTube owns keys by default: remapped/disabled keys never fall back to native bindings. Filter shadowed sections when checking conflicts; keep editor status in a fixed, passive card with error/success colors. Group related controls; CC/audio open their selectors, retaining the subtitle-toggle shortcut.
- Export local tracks asynchronously with native stream indices and codec-aware stream copy. Never overwrite files, silently transcode, or pretend MPV has a native extraction API. Retain authored subtitle styles until an explicit, reversible override.

## Code

- Keep code simple, robust, reusable, with few files/lines; readability wins over compression. Use meaningful names and brief comments explaining modules, major blocks and non-obvious reasons.
- Keep one script package, `scripts/mpvtube/main.lua`, with cohesive `core/` and `ui/` modules loaded through `require`. Avoid needless splits, abstractions or dependencies.
- Prefer MPV APIs; keep commands out of drawing modules. Minimize polling/redraws; clean up timers, workers and temporary files. Preserve user configuration and unrelated edits.

## Documentation and checks

- Update `README.md` for setup, `docs/FEATURES.md` for every changed feature/native effect, `docs/DEVELOPMENT.md` for architecture/tests. Read relevant sections only. Explain steps, options, dependencies and limitations concisely for beginners.
- No em dashes in comments/docs; use commas, semicolons or periods, consistent with es_ES punctuation.
- Batch light edits before the final regression; use focused checks during substantial logic changes. Lua changes: `luac -p` affected files; `luajit tests/regression.lua`. Interaction changes: `python3 tests/integration.py` and screenshot review. Run from root; generated artifacts stay in ignored `tests/output/`.
- Test behavior/edge cases: held sliders, resizing, missing metadata, external subtitles and audio-only media. Keep fixture generators in Git, generated media ignored. Report checks and limitations; geometry tests do not prove pixel identity. Skip redundant tests and code tests for docs-only edits.
