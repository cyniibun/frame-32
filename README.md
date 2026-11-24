# FRAME//32 — development build 0.6.6

Native Apple Silicon macOS 14+ facecam. Swift, AppKit, AVFoundation, Core Image and Metal. No third-party runtime or package dependencies.

## Build

```sh
./scripts/build.sh
open build/FRAME32.app
```

The installed Command Line Tools are sufficient. Build caches stay in `.build`. A compiler-local filesystem overlay hides a duplicate legacy SwiftBridging module map on this Mac; system files are unchanged.

## Interface and effects

- Custom drawn black/white SIGNAL//LOSS shell, geometric icons, button states, framing marks and in-window cached-camera effect cards.
- CLEAN SIGNAL, CHROMA//SHIFT (RGB displacement), POSTER//8 (palette quantization with ordered dithering), SCAN//CRT (phosphor mask, scanlines and curvature), GLITCH//WAVE (animated tear bands and channel corruption).
- COLOR inspector: exposure, contrast, saturation, hue, gamma, temperature, highlights, shadows, sharpen, grain and dither.
- TUNE inspector: intensity plus effect-specific scalar, choice, seed and color controls. Custom tracks support dragging, arrow keys and accessibility increment/decrement; double-click restores the factory default. Inspector scrolls at smaller sizes.
- Stable effect IDs and registry-driven inspectors/cards; independent per-effect values, global color settings and versioned JSON save/restore.
- SOLAR//NEG with solar/negative/split curves, thresholds, chroma retention and hue. DISPLACE//NOISE with seeded two-octave noise, tear bands, phase jitter, pixel amplitude and frozen speed-zero mode.
- EDGE//VECTOR: Scharr mask, separable dilation with fractional stroke widths, paper/original/poster surfaces and dark/light ink. Allocates one R16Float and one RG16Float scratch image only while active, about 11.9 MiB at 1080p.
- HALFTONE//PRINT: rotated CMYK screens, corrected coverage-to-radius lookup, antialiased dots, ink density and registration offset. Lookup is 1 KiB; no frame history.
- MATRIX//RAIN: cached 32-glyph terminal atlas, procedural falling columns, source-luma face reveal and change-reactive brightness. Glyph width, rain speed, trail length, green/monochrome/source ink and camera reveal controls. Two tiny per-cell RG16Float history textures, about 108 KiB at default 1080p cell size, plus a 12 KiB atlas. Speed zero freezes rain; source motion can still affect brightness.
- Parameter values support numeric entry; enum/seed controls are custom drawn. The embedded browser now scrolls as the bank grows.
- PRESETS in the header (Command-P) opens a custom in-window named-preset manager. SAVE NEW snapshots selected-effect tuning and global color. Select a row to recall; UPDATE writes the current look into the selected preset; RENAME uses the name field; DELETE hides a preset and UNDO restores the last deletion. Soft-deleted records are retained on disk; no permanent-delete flow is exposed.
- Named presets have stable UUIDs, validated unique names and atomic writes in Application Support/FRAME32/presets.json. Recall preserves unrelated effect tunings. Files with invalid/future schemas are preserved rather than overwritten. Unsaved session tuning remains separately stored in settings.json.
- Standard Edit menu supports text editing shortcuts in preset/numeric fields.
- Command-U removes/restores chrome within the same window. Command-E opens effects; Command-K opens color. Escape closes inspectors/browser.
- Camera selection and always-on-top in View menu.

## Pipeline

Native YUV capture where supported → Core Image GPU color pass → fused custom Metal signal kernel → shared processed buffer → preview and optional H.264 writer. Two GPU frames in flight; bounded pixel pool allocations; no normal CPU pixel readback. Shader pipelines compile once on initialization. Cached thumbnails render once after camera warmup, using a separate low-resolution processor.

## Verification

- Release compilation and app bundle signature passed.
- Runtime shader compilation and all five reference effect thumbnails observed on GPU.
- Live FaceTime HD preview verified. A vertical inversion introduced by the Metal texture path was corrected at the sampling boundary and the upright preview visually verified after restart.
- Custom browser and color inspector observed in accessibility and native UI.
- Native View > Run GPU Effect Checks passed after the 0.4 build: all nine non-clean effects change pixels, intensity-zero bypass, opaque alpha, upright orientation, photographic negative, reproducible seeds, seed variation, zero-amplitude identity, displacement freeze and exposure. EDGE passes uniform-frame/no-contour and increased-stroke-width checks. HALFTONE passes white-paper and solid-black checks. MATRIX passes green-glyph/background-space, speed-zero freeze and inactive-resource release checks.
- Named preset save, rename, recall and soft delete were exercised in the native UI. Store-level update, undo across reload, failed-write protection, duplicate names and recall isolation passed automated checks.
- MATRIX was selected and visually inspected in the native app with its custom inspector. User tuning was preserved while testing.
- `Tests/ParameterChecks/main.swift` passed: stable IDs, parameter isolation, finite/range validation, threshold ordering, reset scopes, JSON round-trip, UInt32 seeds, corrupt/future-schema protection, source clock, named preset CRUD/recall/recovery/failed writes, and halftone coverage LUT inversion.
- `./scripts/checks.sh` builds/signs the app and runs tests. Restricted-shell GPU device discovery still returns nil; the script reports that run as NOT RUN, not as a pass. Native GPU checks above executed inside the actual app.
- Reproduced SOLAR-selection crash report pointed to AppKit font-descriptor copying during custom button drawing. Replaced the custom drawing helper with cached fixed-face CoreText fonts; SOLAR selection and inspector opening verified afterward.
- Command-U twice verified with the DISPLACE inspector: controls disappear and return with the same parameters.
- App binary replacement is now atomic to avoid truncating a running executable during development builds.

## Remaining acceptance

- Verify all effect/color parameter ranges with live footage; subjective tuning remains.
- Camera-only restoration was verified; multi-display and compact resize acceptance remain.
- Processed recording implementation uses shared GPU output buffers. Export playback/color/timing and effect changes during recording remain pending, behind effects/UI work.
- Snapshot/gallery, native acceptance of the added effects, camera reconnect/sleep recovery and distribution signing remain. Registry and persistence foundations are delivered; the full E0 temporal resource contract is still to be implemented.
- No microphone, screen capture or desktop audio. No recovery guarantee for interrupted MOV files.
- Final acceptance: ten-minute valid UI-free export and thirty-minute DAW/screen-recorder coexistence soak with measured cadence, drops, memory and audio behavior.

## Next effects

PIXEL//SORT, ECHO//FRAME, MOSH//FLOW, BLOCK//ERROR, ASCII//GRID, MOTION//SLIT and DATAVEIL now have 0.5.0 source baselines awaiting native GPU acceptance. MATRIX is an additional preset, not a substitute for the planned luminance-ranked ASCII camera. Existing CHROMA/POSTER/CRT refinement remains in the development plan. No sustained 1080p/DAW performance claim follows from the small synthetic pixel tests.

## Ghost trail and ink update 0.4.1

MATRIX adds GHOST FADE HALF LIFE (0–3 seconds; zero disables lingering history), CAMERA TRAIL strength, seven additional ink palettes and CUSTOM HUE. Existing ink IDs 0–2 remain unchanged. Scalar per-cell luminance and motion histories decay using source elapsed time. History uses two per-cell RGBA16Float textures (about 216 KiB at the default 1080p glyph size), not a full-resolution frame stack. The inspector scroll hint exposes additional controls. Named presets retain the fade, strength and custom hue values.

Build, signature, pure Swift checks and native GPU checks pass. The FRAME32 0.4.1 report from 17 November 2026 at 15:53 EST confirms all nine effects, bypass, orientation, EDGE, HALFTONE, MATRIX, ghost fade and ink color checks. View > Run GPU Effect Checks writes a timestamped version-tagged report to Application Support/FRAME32/verification-report.txt. Command-line --verify-effects runs the same synthetic checks on launch; --verification-report PATH optionally redirects the report. The tests check trail decay after movement, longer half-life retention, hot-pink ink and custom blue hue as well as prior effect acceptance checks. The report verifies synthetic pixel behavior, including shorter versus longer ghost half-life and custom color output. Sustained DAW coexistence performance remains a separate acceptance gate.


## Creative effects roadmap — 17 November 2026

All eight signature directions have source baselines documented in [the creative backlog](Docs/FRAME32_Creative_Effects_Backlog.md). Native verification and refinement begin with RASTER//RELIEF, CONTOUR//FLOW and VECTOR//HATCH. [Pinned research sources](References/README.md) contain selected upstream files only, with no runtime dependency. Machine-readable status is in Docs/effects-backlog.json; all 15 additions are selectable, with native GPU acceptance pending.


## Effects expansion 0.5.0

The selector now has 24 effects plus CLEAN. [Implementation report](Docs/FRAME32_Effects_Implementation_0_5_0.md) lists all 15 additions, algorithms and limits. New passes include GPU vertex portraits, structure fields, bounded motion estimation, reaction–diffusion, anisotropic Kuwahara, persistent Voronoi sites, full-frame feedback, bitonic sorting and eight timestamped slit-scan slices. TUNE adds a custom CLEAR HISTORY / RESEED control; RESET also clears temporal state. Command-U does not reset history. All new tunings round-trip through named presets.

Build, ad hoc signature and non-GPU tests pass. This session cannot access Metal or launch the native app, so **0.5.0 Metal compilation and GPU checks are NOT RUN**. The older 0.4.1 native pass must not be read as verification of the new effects. In a native session, run View > Run GPU Effect Checks before accepting these baselines. Camera footage, recording across effect/Command-U changes, timing and DAW coexistence remain acceptance gates. No Java, Unity, browser, model weights or additional runtime is bundled.


## Visual tuning 0.5.3

- RASTER//RELIEF replaces luminance-dependent radial magnification with fixed grid columns, consistent surface tilt and lightly smoothed luma extrusion. The stored perspective key is retained for saved-look compatibility; its UI label is now SURFACE TILT.
- CONTOUR//FLOW adds CAMERA COLOR → MONOCHROME. This desaturates the camera layer under the ink while preserving its selected glow hue; zero intensity remains the original clean bypass.
- VECTOR//HATCH adds STROKE SCALE (0.5–12×), wider spacing/width/length ranges and coarser defaults. Pattern dimensions follow a 1080p reference scale, keeping thumbnails and live output consistent. Existing tuning is preserved; the new scale defaults to 3×.

The native 0.5.2 report passed all 24 effects at 18:10 EST on 17 November 2026. That pass predates these visual changes. New native checks cover monochrome camera blending and bypass plus stroke-scale response; 0.5.3 GPU acceptance remains pending.


## Creative controls 0.6.0

| Effect | New behavior and controls |
| --- | --- |
| PARTICLE//SKIN | Directional inertial flight replaces spring return. Each slot has one bounded flying fragment with captured launch color, plus an anchored replacement that fades in and grows. FLIGHT LIFETIME, REPLACEMENT GROW TIME, FLIGHT DRAG and LAUNCH SPEED control the lifecycle. The obsolete return-stiffness value is no longer used. |
| FLUID//GHOST | Tint/hue modes removed from both the inspector and feedback loop, including old saved tint settings. Original camera-color advection remains. |
| INK//GROWTH | MOTION REACTIVITY seeds the simulation from measured movement. GROWTH DIRECTION selects outward/inward radial transport; PROPAGATION controls transport speed. Inward is actual chemical-state advection, not a palette inversion. |
| PAINT//FLOW | PAINT THRESHOLD, MASK SOFTNESS and inverse selection choose how much of the tone range is painted. PAINT FILL offers paint, hue ink, greenscreen, bluescreen and white. Key-fill interiors remain exact green/blue at partial intensity before optional global grain/dither; soft boundaries blend into the camera. Key fills bypass paint persistence. |
| CELLS//SHATTER | 8–160 columns; Voronoi, square, diamond, hexagon and round cells. Diamond and hexagon use distinct staggered lattices; changing shape rebuilds cell state. |
| ECHO//FRAME | ECHO INK adds monochrome, tint, negative, poster, thermal, chroma split and contours. ECHO INK AMOUNT and HUE affect only the historical layer; the incoming camera remains unchanged. |
| BLOCK//ERROR | STANDARD, CRUSHED, POSTER DAMAGE, CHROMA LOSS and RESIDUAL HEAT recipes set RESIDUAL LEVELS to 8/2/4/6/12 and update the visible slider. Manual level adjustments survive save/load and normalization. Existing held blocks refresh at their next hold-period boundary. |
| ASCII//GRID | DARK PAPER is an exact RGB inverse of LIGHT PAPER. Existing polarity IDs remain unchanged. |
| PIXEL//SORT | Up to 256-pixel segments, luminance/red/saturation/hue keys, and SORT/STRETCH/COMB/SHRED styles. STREAK STRETCH makes the sorted runs visibly smear; excluded pixels remain separators. Threadgroup width follows segment size. |
| MOTION//SLIT | INK modes: camera, monochrome, tint, negative, poster and thermal, with INK HUE and AMOUNT. Coloring is applied to sampled history slices. |
| MOSH//FLOW | KEYFRAME INTERVAL (zero disables the schedule), SMEAR HOLD TIME, REFRESH WINDOW and REFRESH CADENCE. Advected feedback continues during holds; scheduled keyframes refresh the camera image. |
| DATAVEIL | DRIFT ANGLE rotates the feedback translation direction. |

All custom inspectors and named looks use the expanded 16-parameter binding contract. Old parameter IDs stay intact except for the deliberately removed Fluid tint and replaced Particle spring behavior; their unused stored keys do not prevent loading saved looks. Active resources stay bounded: particle lifecycle/color textures are per-cell; Ink now also retains a previous camera frame for motion analysis. No runtime dependencies or downloaded models are added.

Build/signature and non-GPU tests cover all new controls, preset/slider coupling and preservation of manual residual adjustments. Native checks add particle inertia after an impulse, exact partial-intensity key fills, paint coverage, paper inversion, echo-only ink, slit ink, cell shapes, Mosh timing and drift direction. **0.6.0 native Metal/GPU acceptance and live visual tuning are pending** in this restricted session.


## Camera framing 0.6.1

Command-U hides the app controls while retaining 01 / LIVE INPUT, the selected effect label and FRAME//32 branding. A static pixel-stepped bezel uses sharp blocks, broken corner brackets and index ticks, with dark label backplates for readability. The overlay passes pointer events through to the preview. The camera/recording pipeline remains 32-bit BGRA; this window overlay is visible in screen/window capture and is not burned into processed camera recordings.


## Regression gate and diagnostics 0.6.2

This is a diagnostic build, not a verified fix for the 0.6 effect-bank failure. The previous check script incorrectly returned success when native GPU execution was unavailable; it now exits 2 (NOT ACCEPTED) unless an exact-source native pass exists. A SHA-256 fingerprint covers the registry, processors, kernels, glyph atlas and native verification suite. Old version reports cannot approve modified sources.

On native launch, a source fingerprint without a prior native pass automatically runs the GPU suite. Reports include that fingerprint. Initialization, encoding and command-buffer failures also save their full diagnostics to Application Support/FRAME32/gpu-error-report.txt; the viewport's short status line is not the only evidence anymore. No new effect algorithms were changed in this diagnostic build. Current build/signature/non-GPU checks pass; native regression acceptance is blocked, and the new-effect failure remains unresolved pending its current error report.


## Shared-bank compiler regression 0.6.3

The 0.6.2 native diagnostic reproduced the bank failure: boundedSort declared threadgroup_position_in_grid as uint2 but threads_per_threadgroup as uint3. Metal rejected the entire AdvancedEffects library because these vector dimensions must match. 0.6.3 changes only the position declaration to uint3, retaining its existing x/y indexing. The captured compiler failure is the red regression case. Native automatic verification must pass for the new source fingerprint before this correction is accepted; Swift/preset tests alone are insufficient.


## Original interface appearance 0.6.4

Restores the 0.5.0 StageMarks drawing: plain 01 / LIVE INPUT and effect-name text, plus the original small corner brackets. Removes the later text backplates, bottom-right FRAME//32 badge and pixel-stepped perimeter border. Retains the newer Command-U behavior that keeps those original labels/marks visible. Effect algorithms, custom tuning controls, presets and automatic regression checks are unchanged.

The latest native 0.6.3 report confirms the previous compiler failure is no longer blocking the suite, but reports a Hatch stroke-scale assertion failure. That pre-existing result is not a native acceptance pass for 0.6.4; this appearance-only change does not alter the GPU source fingerprint or attempt an effect fix.


## Optional camera labels 0.6.5

Command-Shift-H toggles the 01 / LIVE INPUT label, effect name and corner marks using View > Show Camera Labels & Marks. The preference stays in place across Command-U toggles for the current app session. Command-H retains the standard Hide App action. GPU processing, saved effect tuning and recording pixels are unchanged.


## Fill Window 0.6.6

Command-Shift-F (View > Fill Window) toggles centered aspect-fill presentation. The image scales proportionally and crops excess width/height to cover the preview without letterboxing or pillarboxing at any window shape. Toggle off to restore fit. This preference persists between launches and works independently of Command-U and Command-Shift-H. Only presentation changes: camera resolution, GPU effect processing, 32-bit BGRA format and recording dimensions remain unchanged.
