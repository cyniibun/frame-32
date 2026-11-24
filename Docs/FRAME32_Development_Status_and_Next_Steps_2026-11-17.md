# FRAME32 Development Status and Next Steps

17 November 2026 · Current build 0.4.1  
Prepared for Joseph Cannatelli

## Build 0.5.0 source update

All 15 remaining effects now have source baselines, registry-driven custom controls and named-preset persistence. This adds the eight creative directions and seven original effects to the selector, for 24 effects plus CLEAN. Build/signature and persistence checks pass. Native Metal compilation, pixel tests, live visual acceptance, performance and export acceptance remain pending because this execution session cannot access Metal or launch the native app. The report below records the earlier 0.4.1 accepted baseline and its historical inventory; it does not verify 0.5.0. See [the implementation report](FRAME32_Effects_Implementation_0_5_0.md) for current details.

## Previous native verification record and roadmap (0.4.1)

### Prior recommendation

Our next visible milestone is **RASTER//RELIEF**, followed by **CONTOUR//FLOW** and **VECTOR//HATCH**. All eight signature directions are planned, including PARTICLE//SKIN, FLUID//GHOST, INK//GROWTH, PAINT//FLOW and CELLS//SHATTER. See [Creative Effects Backlog](FRAME32_Creative_Effects_Backlog.md) for their controls, dependencies and acceptance criteria. Five commit-pinned source snapshots are now available under References; they add no app runtime dependency.

The app currently has **nine implemented effects plus CLEAN SIGNAL**. The original fourteen-preset list has seven implemented entries and seven remaining; GLITCH//WAVE and MATRIX//RAIN are additional options. Implemented means the code is present and applicable functional checks have passed. It does not mean the app has passed sustained DAW, recording or release acceptance.

The latest native report identifies FRAME32 0.4.1 and records a pass at **3:53 PM EST on 17 November** for nine effects, bypass, orientation, contours, halftone, MATRIX, ghost fade and ink colors. The latest recorded non-GPU checks also passed. This report audits those results and current source; it does not claim a new performance benchmark or another test run.

## Current product status

| Area | Present and verified | Still open |
| --- | --- | --- |
| Native camera app | FaceTime HD preview, camera selection, single-window AppKit shell and Metal processing | Reconnection, sleep/wake and camera capability negotiation need hardening |
| Custom interface | SIGNAL//LOSS controls, embedded scrolling effects browser, COLOR and contextual TUNE inspectors | Compact/multi-display/accessibility acceptance and consistency polish |
| Camera-only mode | Command-U hides/restores interface; prior inspector state has been exercised | More interruption and recording combinations need testing |
| Color controls | Eleven global controls, numeric entry and range validation | Preview-to-export color comparison and broader live-footage tuning |
| Named presets | Save new, recall, update, rename, recoverable delete; effect tuning and global color snapshots | Import/export, favorites and persistent trash browsing |
| MATRIX additions | Camera reveal, ghost half-life, trail strength, expanded palettes and custom hue | Further artistic tuning and sustained-load measurements |
| Recording | Shared processed-buffer H.264 writer exists, source timestamps and no audio by default | Valid export, color, timing, finishing/error cases and editor compatibility are not accepted yet |
| Resource bounds | Two GPU submissions in flight, buffer allocation threshold and active-effect scratch/history | Shared full-resolution history service, allocation accounting and stage-specific diagnostics |
| Automated checks | Registry/settings/preset tests and native synthetic GPU checks pass | Cadence-independent full-resolution feedback, sorting, ring-history and inference checks are not built yet |

Named preset behavior is deliberately scoped: recalling a saved look restores its selected effect, tuning and global color while preserving your unrelated effect tunings. Factory reset and named-preset update are separate actions. Recoverable deletion exists in storage; the current Undo UI targets the last deletion in that session, rather than providing a complete trash browser.

Current on-disk footprint is approximately **728 KiB for the app bundle** and **258 MiB for local build/cache files**. These are disk measurements, not runtime RAM or GPU usage. The lightweight-under-DAW-load claim remains pending the benchmark milestone.

## Effect inventory

| Effect | Current status | Completion work or next dependency |
| --- | --- | --- |
| CLEAN SIGNAL | Present | Keep as the color-adjusted bypass/reference |
| CHROMA//SHIFT | Baseline implemented | Zero separation, direction control and independent tuning; motion reaction later |
| POSTER//8 | Baseline implemented | Exact eight-color/named palettes; present mode is per-channel quantization |
| SCAN//CRT | Baseline implemented | Separate the currently coupled curvature/depth controls; brightness and aliasing acceptance |
| GLITCH//WAVE | Implemented additional preset | Retain and share utilities with other corruption effects |
| SOLAR//NEG | Implemented | Broader visual tuning; prior selection crash was addressed and selection rechecked |
| DISPLACE//NOISE | Implemented | Broader visual tuning and measured cadence/cost |
| EDGE//VECTOR | Implemented | Wider live-footage tuning and measured cadence/cost |
| HALFTONE//PRINT | Implemented | Moire/preview-scale evaluation and measured cadence/cost |
| MATRIX//RAIN | Implemented additional preset | Continue style tuning; verify performance across glyph sizes |
| ECHO//FRAME | Not implemented | Reusable full-resolution ping-pong history |
| BLOCK//ERROR | Not implemented | Tile state, held imagery and time-based expiry |
| ASCII//GRID | Not implemented | Coverage-ranked glyph selection and cell analysis |
| PIXEL//SORT | Not implemented | Bounded GPU sorting with segment qualification |
| MOTION//SLIT | Not implemented | Timestamped full-resolution ring history |
| MOSH//FLOW | Not implemented | Block-motion analysis, advection and gated refresh |
| DATAVEIL | Not implemented | Luma-mask feedback first; asynchronous person masks later |

MATRIX does not replace ASCII//GRID. MATRIX selects changing code characters and uses camera brightness/motion to reveal the image. ASCII//GRID will select characters by measured ink coverage to reconstruct image tone. Likewise, MATRIX's small per-cell ghost buffer is not a full-color camera feedback engine.

## Current creative milestones

Follow the eight individually shippable milestones in the Creative Effects Backlog. Shared history and diagnostics support these milestones; the original seven unfinished effects remain scheduled work. No new creative effect is implemented by adding references or this document.

## Original-bank work packages (retained; not the current priority order)

### Batch 1 Shared history plus Echo and Block Error

**Deliverable:** two new effects, custom controls, saved-preset integration and native temporal tests in one build.

- Extract frame timing, resource-generation/reset handling and active-effect allocation into a reusable temporal service. Keep source timestamps authoritative and retain resources until dependent GPU work completes.
- Build ECHO//FRAME with full-resolution ping-pong history, linear-light accumulation, exponential half-life and optional zoom, rotation and drift. Keep UI and final grain outside recursive history.
- Build BLOCK//ERROR with persistent per-tile hold/expiry/displacement decisions and actual held image content. Add residual quantization only after holds are correct; a fresh random displacement every frame is not a frozen block.
- Add local counters for capture drops, GPU admission/pool exhaustion, GPU failure, stale generations and writer backpressure separately. Begin logging GPU p50/p95 and explicit texture bytes, without per-frame console spam.

**Completion gate:** decay stays consistent at 15/20/24/30 fps; held tiles expire at the requested times; repeated effect switches do not retain inactive resources; Command-U preserves active history; one full build and native report cover both effects.

**Memory planning:** two 1080p RGBA16Float ECHO histories are approximately 31.6 MiB. BLOCK's two RGBA8 image stores are approximately 15.8 MiB plus tile state. These are estimates for additional resources, not app RSS or simultaneous allocations for every preset. Keep only the selected effect's history active.

### Batch 2 ASCII and completion of existing color and display presets

**Deliverable:** ASCII//GRID and more useful, accurately labeled controls for the existing bank.

- Reuse MATRIX's atlas infrastructure for ASCII, but add measured glyph coverage, per-cell luma/RGB analysis and tone-ranked glyph selection. Offer monochrome, colored ink and source-color styles.
- Make CHROMA separation reach an actual zero; add direction and separate radial/drift settings. Defer motion-reactive chroma until motion analysis is available to share.
- Add a true eight-color POSTER mode and named palettes. Preserve the existing per-channel style as its own option rather than changing saved looks unexpectedly.
- Separate CRT scanline depth, spacing, curvature, phosphor strength and flicker. Preserve output-pixel sizing when the window is resized.
- Add parameter-version migration if the semantics of saved values change.

**Completion gate:** grayscale ramps select monotonically denser ASCII glyphs; exact-palette output stays within the selected colors when dithering is disabled; zero chroma displacement is clean; saved 0.4.1 looks remain loadable.

### Batch 3 Pixel Sort

**Deliverable:** PIXEL//SORT with horizontal and vertical bounded sorting.

- Implement tile/row windows of 32, 64, 128 and 256 pixels, luma-threshold-qualified runs and a GPU bitonic network.
- Preserve excluded pixels, run boundaries and deterministic equal-key ordering. Handle partial windows safely.
- Check per-pipeline threadgroup and memory limits. Keep CPU reference sorting confined to tests.

**Completion gate:** GPU output matches a reference within the declared rules; pixels do not cross run boundaries; both axes work at odd dimensions; the longest mode receives a measured cadence tier.

**Risk:** maximum segment length has many compare-exchange stages. It cannot inherit the cost label or frame-rate expectation of a simple one-pass shader.

### Batch 4 Slit Scan

**Deliverable:** MOTION//SLIT with direction, axis, time depth and temporal sampling controls.

- Add a timestamped history ring and age-based sample lookup. Each output band selects the intended source moment, rather than an arbitrary frame index.
- Start with up to sixteen full-resolution RGBA8 slices and a declared history sampling rate. Clamp warmup to valid history; reset on discontinuities.
- Preserve selected detail and history mode. Offer smaller memory modes explicitly rather than reducing image resolution silently.

**Completion gate:** numbered/timecoded source frames prove correct band ages through ring wrap, dropped frames and cadence changes; memory plateaus; switching away retires the ring safely.

**Memory planning:** sixteen 1080p RGBA8 slices are approximately 126.6 MiB before output/staging resources. This is the next major memory milestone and deserves its own allocation gate.

### Batch 5 Motion Smearing

**Deliverable:** MOSH//FLOW with controllable motion feedback.

- Use small luma analysis maps and bounded block matching, then convert backward displacement into full-resolution UVs.
- Advect full-resolution history, gate current-frame refresh by residual/confidence and reset after hard cuts.
- Reuse the temporal service and expose flow amount, persistence, refresh and block-field style.

**Completion gate:** translated test patterns produce vectors with the correct sign/scale; static input does not drift indefinitely; occlusion and exposure changes refresh safely; actual cost is measured under concurrent DAW load.

This remains a real-time datamosh-inspired effect. Compressed-stream I/P-frame editing is a separate offline feature.

### Batch 6 Dataveil

**Deliverable:** DATAVEIL, first with GPU luma masks, then optional local person segmentation.

- Combine threshold mask, morphology, outline, restrained glow and decaying feedback using the existing contour and temporal services.
- Add reduced-resolution person segmentation on a separate bounded worker. Keep one request active and only the latest waiting source; render continues independently.
- Detect stale/failed masks and expose a defined luma fallback in the inspector.

**Completion gate:** correct mask orientation and alignment; no camera queue waits for inference; stale-mask fallback works; allocations remain bounded; the declared render and mask rates are measured separately.

This is last because inference adds a distinct workload and memory footprint. Transparent export is not required to use an opaque DATAVEIL effect.

## Work that remains outside the effect bank

| Priority | Work | Acceptance required |
| --- | --- | --- |
| During Batch 1 | Stage-specific performance/error diagnostics | Useful counters and p50/p95 timings; no unbounded logging |
| During upcoming batches | Camera and history recovery | Device disconnect, permission changes, sleep/wake and PTS gaps reset safely |
| After effects, per current priority | Processed recording acceptance | Valid UI-free files; effect/Command-U changes; timestamps; color; editor playback; safe finish |
| Before calling the app lightweight under load | DAW coexistence benchmark | Ten-minute recording and thirty-minute DAW/screen-recorder soak; cadence, memory, thermals and audible underruns documented |
| Product completion | Snapshot PNG, gallery/reveal workflow and countdown | Working actions and file handling, not decorative inactive controls |
| Preset completion | Import/export, favorites and trash browser | Schema validation, name conflicts and safe recovery |
| UI acceptance | Compact sizing, multiple displays, keyboard focus and VoiceOver | Every control reachable; offscreen-window recovery; no chrome in camera-only output |
| Distribution | Signed release packaging and notarization if distributing | Fresh-machine launch, permissions and update strategy |

Do not add microphone capture, raw dual encoding, 60 fps, virtual-camera integration or alpha export to the next batch. They remain later scope and would make it harder to assess the core camera/effect workload. Full Xcode is still optional for the current compiler workflow; advanced profiling tools may justify it when the performance milestone begins.

## Findings that affect the next implementation

### The shared temporal service is still incomplete

Stable IDs, validated per-effect settings, a relative source clock, generation checks and MATRIX's small history are present. The processor's temporal reset currently targets MATRIX; it does not yet own the generic full-resolution history/ring resources needed by ECHO, MOSH, SLIT and DATAVEIL. Extend that service before copying independent history systems into each effect.

### Camera mode selection needs to become explicit

The capture code requests 1080p where supported and otherwise falls back to the camera's high preset. It does not yet expose a complete user-selected 1080p/720p mode and fixed/adaptive cadence contract. Report actual delivered dimensions and cadence. Avoid implying that every connected camera is already running at 1080p30.

### Recording exists but is not an accepted workflow

The writer consumes shared processed buffers and checks readiness/PTS. Remaining acceptance should include draining or deliberately accounting for GPU frames submitted before Stop, rejecting stale callbacks across recording sessions, disk-full/interruption behavior and completion/error states. These are audit targets, not observed export failures.

The working shader texture uses sRGB processing while the writer declares Rec.709 output properties. Explicit buffer attachments and intended conversion/tagging must agree; validate with known patches in preview and the actual editor rather than assuming the tags alone establish a match.

### Error reporting and profiling need more separation

Several capture/GPU/writer conditions currently feed a combined drop count, and some per-frame GPU failures return no image. Separate these cases so a frozen preview or low delivered cadence has an identifiable cause. Allocation thresholds prevent one form of backlog; they do not establish that total process memory is small or stable.

### Preset storage is ahead of preset workflow polish

The storage model supports recoverable records and protects incompatible files. Add a persistent trash browser, import/export and favorites after the immediate effects work. Keep existing preset IDs and old values valid when controls change.

### Documentation needs a current status page

The original effects plan is an algorithm reference with a historical implementation snapshot. Its missing-effect table and some README parameter/memory summaries predate the latest features. Use this report as the current status snapshot; consolidate those stale descriptions in the next documentation pass rather than treating the old missing list as current.

## How we should run the next cycle

Each batch should produce one reviewable app build, all custom controls and preset persistence wiring, applicable synthetic tests, one version-tagged native report and a concise status update. Run independent checks together and fix failures before reporting completion. Do not require a user response between every routine code/build step.

The remaining constraint is native desktop access: the restricted shell cannot discover a Metal device, while checks inside the app can. Use the existing native verification entry point and timestamped report; if desktop launch remains unavailable, collect the necessary user-run verification into one handoff per batch rather than repeating it for individual effects.

No calendar completion estimate is committed here. The current evidence supports the order and acceptance gates above; motion analysis, inference and real DAW measurements can change effort materially.

## Evidence and scope

- Current local implementation inspected: EffectRegistry.swift, SignalProcessor.swift, SpatialKernels.swift, GlyphAtlas.swift, Interface.swift, UserPresets.swift, PresetPanel.swift, FrameClock.swift, main.swift and the verification/test entry points relevant to the status above.
- Latest native evidence: FRAME32 0.4.1 report dated 17 November 2026 at 20:53:06 UTC, equivalent to 15:53:06 EST. It records PASS for nine effects plus the listed synthetic categories.
- Latest recorded build/non-GPU evidence: successful build and registry/settings/preset/coverage checks in the local checks log. A restricted-shell GPU run is correctly marked NOT RUN; the separate native report supplies the GPU evidence.
- Planning references: FRAME32 Development Spec v2 SIGNAL LOSS and FRAME32 Remaining Effects Development Plan v1.0, read for this review. Their earlier phase ordering is refined by the user's effects-first direction and the implementation already delivered.

This is a development status and priority report. No application code was changed and no new runtime performance claims were introduced while preparing it.
