# FRAME32 Remaining Effects Development Plan

Version 1.2 · 17 November 2026  
Prepared for Joseph Cannatelli and FRAME32 implementation  
Scope: seven remaining original presets, eight additional creative effects, existing-preset refinements and shared engine work.

## Build 0.5.0 implementation update

Source baselines now exist for all 15 remaining effects, including all eight creative directions. Swift build, signature and tuning/preset persistence checks pass; native Metal compilation and rendered output have not been verified in this restricted execution session. The original specification below retains its target contracts and earlier inventory for reference. Current implementation details and explicit limits are in [the 0.5.0 implementation report](FRAME32_Effects_Implementation_0_5_0.md).

## 1 Purpose and implementation status

The current creative roadmap prioritizes RASTER//RELIEF, then CONTOUR//FLOW and VECTOR//HATCH, followed by particles, fluid feedback, growth, painting and shattering. All eight are planned; none is omitted. See [Creative Effects Backlog](FRAME32_Creative_Effects_Backlog.md) for milestones, controls, acceptance and pinned research sources. The original detailed algorithm sections below remain technical specifications, not current delivery status. Effects and the approved custom SIGNAL//LOSS interface remain ahead of recording feature expansion. Preview and recording must consume the same processed image; neither UI visibility nor inspector state may change that image.

This plan is grounded in the current local Swift source, not the original feature list alone. An algorithm in source is an implementation baseline, not proof that its visual tuning, performance or export acceptance has passed. No performance figure below is a measurement unless explicitly identified as one.

| Requested preset | Current source status | Remaining work |
| --- | --- | --- |
| CHROMA//SHIFT | Baseline present | Direction controls, parameter separation and optional motion reactivity |
| EDGE//VECTOR | Implemented | Broader tuning and measured cost |
| POSTER//8 | Baseline present | Named palettes, exact eight-color option, refined dithering |
| PIXEL//SORT | Missing | Bounded GPU sorting |
| ECHO//FRAME | Missing | Shared history system and feedback |
| MOSH//FLOW | Missing | Motion analysis, advection and gated refresh |
| BLOCK//ERROR | Missing | Persistent per-block state and residual corruption |
| SCAN//CRT | Baseline present | Independent controls and aliasing/brightness validation |
| ASCII//GRID | Missing | Cell analysis and cached glyph atlas |
| HALFTONE//PRINT | Implemented | Moire and performance acceptance |
| DISPLACE//NOISE | Implemented | Broader tuning and measured cost |
| SOLAR//NEG | Implemented | Broader tuning and measured cost |
| MOTION//SLIT | Missing | Timestamped full-resolution history ring |
| DATAVEIL | Missing | Mask pipeline, feedback, glow and optional person segmentation |

GLITCH//WAVE exists outside the supplied list. Keep it as a separate preset and extract its shared band-noise utilities. It does not satisfy MOSH//FLOW, PIXEL//SORT or persistent BLOCK//ERROR behavior.

### Current integration points

The stable EffectRegistry and per-effect typed settings, named UserPresets, SpatialKernels, FrameClock, custom Interface and native EffectVerification are now present. SignalProcessor owns active-effect scratch resources and bounded submissions; main.swift shares processed buffers with preview and recording. Native v0.4.1 verification passed nine effects, bypass, orientation, edge, print, MATRIX, fade and ink/color checks. Performance and export acceptance remain open.

The following architecture and original-effect sections describe target contracts; some foundational work is now implemented. They should not be read as a claim that the registry or custom controls are still missing.

## 2 Shared architecture before adding presets

### 2.1 Replace positional modes with effect definitions

Add an `EffectID` backed by a stable string, such as `edge.vector`, `echo.frame` or `mosh.flow`. Keep the existing integers only as a temporary shader binding detail. Introduce an `EffectDefinition` registry containing title, bank, parameter descriptors, defaults, state requirements, pipeline entry point and declared cost tier. Build the browser and inspector from that registry so shader IDs, card labels and parameter controls cannot drift apart.

Store values separately for each effect. Switching from ECHO to PIXEL SORT must not interpret an echo half-life as a sorting threshold. Define parameter types as scalar, integer, enum, toggle, color or seed; ranges, units, default and display precision belong to each descriptor. Validate all values, including NaN and infinity, before GPU binding. Persist versioned JSON in Application Support with schema version, stable IDs and per-effect values. Import/export and favorites can follow after basic save/restore.

Every preset gets a common intensity control from 0 to 1, independent of its contextual parameters. Intensity zero must produce the globally color-adjusted clean image, including any intentionally enabled global grain/dither. The stateful algorithm may keep its state warm while selected; intensity must not be used as an allocation or hidden quality switch.

### 2.2 Keep a small explicit pipeline

Use a short effect-specific pass plan rather than building a general visual graph editor. The common order is:

1. Capture and normalize orientation exactly once.
2. Apply global exposure, white balance, contrast, saturation, hue, gamma, highlight/shadow and sharpening controls.
3. Run the selected effect's analysis and spatial/temporal passes.
4. Blend the effect with the clean color-adjusted frame using intensity.
5. Apply global grain/dither once and encode into the shared processed output buffer.
6. Hand that buffer to preview and optional recording after GPU completion.

Allocate analysis and history only for the active effect. Preserve full output dimensions and the chosen effect precision. An intentionally low-resolution analysis map is part of an effect's declared design, not a silent runtime downgrade. Changing analysis resolution, sorting length or slit history capacity requires explicit user selection; reduce processing cadence first under load.

Retain the existing Core Image color pass initially. Extract the Metal source into bundled source files and compile/cache factory pipelines before selection. Runtime compilation remains valid with the present tools; precompiled metallib packaging is a later toolchain optimization. Do not compile a shader in a frame callback.

### 2.3 Define orientation and color contracts

The recent vertical-flip regression shows that coordinate transforms need an explicit boundary. Normalize camera input to an upright canonical working texture once. All new spatial kernels, motion vectors, masks, glyphs and history textures use that convention. Audit the existing `uv.y` flip when extracting kernels so we do not flip twice. Keep output orientation consistent for preview, thumbnail generation and recording.

MVP remains opaque SDR. Use the current sRGB-encoded working color for stylized quantization and a documented display-luma proxy `Y = 0.2126 R + 0.7152 G + 0.0722 B`. Decode transfer functions explicitly for operations requiring linear-light accumulation. For feedback, convert samples to linear light, accumulate in RGBA16Float and encode on output; keep coordinate/color conversion shared rather than duplicated inconsistently in every kernel. Do not treat camera YUV range, sRGB and Rec.709 transfer functions as interchangeable. Matching export tagging remains a later recording acceptance gate.

### 2.4 Add bounded resource and temporal services

Create a texture allocator keyed by size, format and usage; a `TemporalState` owner per active effect; and a `FrameContext` containing source PTS, elapsed time, dimensions, frame sequence and effect generation. Use one Metal command queue with ordinary serial encoders and tracked resources initially. Read history A and write history B; never sample and overwrite the same history image in one pass.

Encode temporal frames in source order. Two submitted frames may be in flight, but a later feedback frame must read the earlier frame's completed GPU writes through queue ordering and tracked hazards. Track dependency order, not just CPU callback order. Use explicit barriers for threadgroup sorting stages. Confirm threadgroup size against each pipeline's limits and device threadgroup-memory capacity [2, 3].

When changing effects or cameras, publish a new resource generation at a frame boundary. Retain old textures until all command buffers referencing them complete. Ignore stale generation callbacks. Reset history after source change, dimension/orientation change, nonmonotonic PTS, sleep/wake, explicit reset, or a PTS gap over 0.5 seconds. UI toggles and opening the browser never reset history. Pure appearance parameter changes normally preserve history; structural changes such as slit capacity or block-grid dimensions reset it explicitly.

Use elapsed time, not frame count. For half-life `h`, retained history weight is `d = exp2(-dt / h)`. Clamp invalid `dt` and reset after discontinuities. Keep shader time based on a session epoch with a phase accumulator; the present hourly modulo must not introduce an animation jump or invalidate temporal age calculations.

### 2.5 Add lightweight analysis services

Provide shared downsample, luma, gradient, mask dilation, separable blur, deterministic integer hashing and UV-warp utilities. Compute analysis only when the active effect requests it. Stateless noise uses an explicit seed plus a PTS-derived event tick, so replaying identical input with the same seed/times gives the same output. Do not use wall-clock time or fresh CPU randomness per frame.

Keep capture callbacks free of waits for Vision, CPU sorting, disk or GPU readback. GPU completion owns resource release. Expose an error state rather than silently leaving the previous preset active when shader/resource initialization fails.

### 2.6 Preserve the approved interface

All effects appear in the existing in-window browser; no new effect windows or stock visible sliders/buttons. COLOR remains global. TUNE shows common intensity and two to five contextual controls, with secondary advanced controls in the same inspector when needed. Use custom enum/toggle controls as well as custom numeric tracks; offer precise numeric entry and factory reset. Only system dialogs and menus keep their native system appearance.

Cache representative thumbnails on demand. Do not allocate live temporal simulations for every card. For temporal presets, render a short synthetic sequence on one low-resolution thumbnail worker, cache the final image and release its history. Camera thumbnails stay local and transient. Show cost/cadence information in the inspector, not baked into footage. Command-U hides all UI while preserving settings, selected effect and temporal state.

## 3 Performance and memory contract

The following budgets are starting engineering targets on the M1 Max at 1920 by 1080. They refer to incremental effect GPU work, excluding capture, the shared color pass, final preview presentation and encoding. They are not speed promises. Profile p50/p95 and delivered cadence alongside the actual DAW and screen recorder.

| Class | Initial incremental p95 target | Intended processing cadence | Policy if target fails |
| --- | --- | --- | --- |
| Low | Up to 2 ms | 30 fps | Optimize/fuse passes, then declare a lower cadence if needed |
| Low to medium | Up to 5 ms | 30 fps | Measure total pipeline before assigning 24 fps |
| Medium | Up to 8 ms | 30 or 24 fps | Assign an explicit measured tier |
| Medium to high | Up to 15 ms | 30, 24 or 20 fps | Preserve selected algorithm and output detail; reduce cadence |
| High | Up to 20 ms GPU work plus separate ML workload | 24, 20 or 15 fps | Separate mask rate from render rate; report both |

At 30 fps the entire processing cycle has 33.3 ms, not 33.3 ms per pass. Vision wall time and GPU contention must be measured separately. CPU and GPU usage percentages cannot be promised in advance.

One 1080p RGBA8 image is approximately 7.91 MiB; RGBA16Float is 15.82 MiB; R8 is 1.98 MiB; R16Float is 3.96 MiB. Values exclude allocation padding. Current common input/output pooling has an allocation threshold of eight buffers, roughly 63.3 MiB at 1080p BGRA before other resources; it is not a total app memory cap. The estimates below describe additional effect resources, not process RSS.

Set an initial additional persistent-resource cap of 160 MiB for the active effect. SLIT uses at most 16 full-resolution RGBA8 slices, approximately 126.6 MiB. No inactive effect keeps history. Report allocation failures and preserve the last valid image; offer a smaller explicit history mode instead of silently shrinking it.

## 4 Development specification for each missing effect

### 4.1 Edge Vector

**Preset:** EDGE//VECTOR · **ID:** `edge.vector` · **Cost:** Low to medium.

**Visual goal.** Clean ink contours around the face, clothing and background geometry, with adjustable stroke thickness and optional flat poster color. This is raster contour rendering; it does not create editable SVG paths.

**GPU algorithm.** Read the color-adjusted frame, derive display luma and apply a normalized 3 by 3 Scharr operator. Store gradient magnitude in R16Float. Convert magnitude to a soft edge mask using `smoothstep(threshold-softness, threshold+softness, magnitude)`. Expand that mask with a bounded 1D horizontal max filter followed by a vertical max filter; radius zero bypasses dilation. Map requested stroke width to adjacent integer dilation radii and interpolate masks for even/fractional widths, rather than silently rounding a two-pixel stroke into three. Composite ink against paper, original camera color or a small fixed quantized palette. Keep the gradient normalization fixed so thresholds behave predictably across resolutions.

**Passes and resources.** Gradient/mask pass, optional two dilation passes, then composition. Two full-resolution R16Float scratch textures total about 7.9 MiB; reuse them by pass lifetime. No history. Start without blur; if low-light noise produces unstable edges, add an explicit denoise option using a small separable blur before Scharr.

| Control | Range | Initial default |
| --- | --- | --- |
| Threshold | 0 to 1 normalized gradient | 0.18 |
| Softness | 0.005 to 0.20 | 0.04 |
| Stroke width | 1 to 7 output pixels | 2 |
| Surface | Paper, original, poster palette | Paper |
| Polarity | Dark ink, light ink | Dark ink |

**Build tasks.** Add `EdgeVector.metal`, reusable mask-dilation kernels and the registry entry. First validate a single-pixel diagonal edge, then enable thickness, then add the surface modes. Do not derive stroke width from window size.

**Acceptance and failures.** A uniform frame yields no edges; a known black/white step yields an aligned contour; increasing width expands without shifting the contour center. Check diagonals, glasses, hair and low-light noise. At the largest radius, verify border clamping and absence of reads outside the image. Intensity zero matches clean input. UI resizing must not change edge thickness in the file.

### 4.2 Pixel Sort

**Preset:** PIXEL//SORT · **ID:** `pixel.sort` · **Cost:** Medium to high.

**Visual goal.** Coherent brightness-sorted streaks inside selected light/dark regions. The first release deliberately uses bounded segments; full-frame global sorting is excluded.

**GPU algorithm.** Divide each row into fixed windows of 32, 64, 128 or 256 pixels. Compute a qualification mask from lower/upper luma thresholds and a segment ID that changes at every qualification boundary. Each GPU threadgroup loads one complete window into threadgroup memory. Sort lexicographically by segment ID, luma key and original index using a bitonic network. Give each excluded pixel a singleton segment so it remains fixed. Ascending/descending applies to the luma key, not segment order. This sorts qualifying runs without moving pixels across a dark/light boundary. Pad the last window with sentinel records that sort behind valid pixels.

Use a power-of-two threadgroup. Every participating thread reaches every barrier, including padded lanes. A 256-entry record containing packed RGBA, luma key, segment ID and original position occupies about 4 KiB at 16 bytes per record. Query device and pipeline limits before dispatch. Bitonic sorting at 256 entries has 36 compare-exchange stages, so maximum length is a measured expensive option, not a free setting.

**Direction.** Horizontal is direct. For vertical, map group/thread coordinates onto columns using the same network and write back to the original coordinates. Start without diagonal sorting or transpose textures; profile strided access before adding a tiled transpose implementation.

| Control | Range | Initial default |
| --- | --- | --- |
| Direction | Horizontal, vertical | Horizontal |
| Lower luma | 0 to 1 | 0.20 |
| Upper luma | 0 to 1, not below lower | 0.85 |
| Window length | 32, 64, 128, 256 pixels | 64 |
| Order | Bright first, dark first | Bright first |

**Passes and resources.** One sorting pass after color normalization; a later composition pass can share the common intensity/grain stage. No full-frame sort buffer or history. Threadgroup memory is per active GPU group, not one allocation per image row. Expected cadence is 30/24 fps for short segments and potentially 20/15 fps for the largest setting, subject to measurements.

**Build tasks.** Implement a CPU reference only in tests; add the GPU network and padding tests; add segment qualification; add vertical mode. Never perform production CPU sorting or read back frames for threshold detection.

**Acceptance and failures.** Verify monotonic luma within each qualifying run, preservation of the pixel multiset, stable equal-key ordering via original index, unchanged excluded pixels, and safe odd frame widths. Accept visible seams at fixed window boundaries as part of this bounded version and document them in the inspector. Test threshold extremes, all-equal colors and rows shorter than a window.

### 4.3 Echo Frame

**Preset:** ECHO//FRAME · **ID:** `echo.frame` · **Cost:** Low to medium.

**Visual goal.** Transparent trails and recursive ghosts that hold still smoothly and pull outward, rotate or drift when transformed.

**GPU algorithm.** Seed history from the first color-adjusted frame. Decode current and history samples to linear light. Warp the previous history by an affine transform whose zoom, rotation and translation scale with `dt`. Form the internal state `Hnew = (1-d) * current + d * warpedHistory`, where `d = exp2(-dt/halfLife)`. Encode the internal state to the output working transfer function; blend against clean using common intensity. Feedback reads the unblended internal state, not UI overlays or the final global grain pass. This avoids accumulating grain and prevents intensity adjustments from changing the underlying decay.

**Passes and resources.** Two RGBA16Float ping-pong history textures, about 31.6 MiB at 1080p. A feedback pass updates the next history; the common output pass reads it. A tightly coupled implementation may write both history and final output in one compute pass with separate texture bindings. Never alias read/write history.

| Control | Range | Initial default |
| --- | --- | --- |
| Half-life | 0.05 to 3 seconds | 0.40 s |
| Zoom velocity | Minus 0.15 to plus 0.15 per second | 0.025 |
| Rotation velocity | Minus 20 to plus 20 degrees per second | 0 |
| Horizontal drift | Minus 200 to plus 200 pixels per second | 0 |
| Vertical drift | Minus 200 to plus 200 pixels per second | 0 |

**Build tasks.** Implement/reset ping-pong ownership; prove an unwarped exponential decay; add time-scaled transforms; then tune blend and border behavior. Use black outside the transformed image instead of edge smearing; expose any alternative border mode only later.

**Acceptance and failures.** A moving bright test square must decay to half its contribution after the configured half-life at 15, 20, 24 and 30 fps, within an agreed numeric tolerance. A static frame converges without brightness growth. No stale frame should appear after effect reset, camera change or sleep. Command-U and browser operations preserve history. Check that large `dt` triggers reset rather than a transform jump.

### 4.4 Mosh Flow

**Preset:** MOSH//FLOW · **ID:** `mosh.flow` · **Cost:** Medium to high.

**Visual goal.** Faces and background blocks drag into each other as old image content follows movement. This is a real-time motion-feedback approximation; it never edits codec I/P-frame structures.

**Motion analysis.** Start with block matching on a 480 by 270 R16Float luma image derived from the full-resolution working frame. Store current and previous luma. Use 8 by 8 analysis blocks and a bounded hierarchical search: evaluate nine candidates at each of three search spacings, plus an optional center refinement. Compute mean absolute difference over a fixed sample grid per block; choose the minimum and derive confidence from best/second-best separation and residual error. Match each current block against previous-frame locations, so the result is a backward displacement used to sample prior history. Convert analysis-pixel displacements into full-resolution UV offsets explicitly.

**Advection and refresh.** Smooth/confidence-weight the block field without averaging across large motion discontinuities. Warp the previous RGBA16Float history with the backward field. Decode incoming color to linear light. Inject current imagery where confidence is poor, residual is large or the seeded refresh gate fires. Keep a positive minimum refresh floor to avoid a permanently frozen image. A frame-wide residual reduction can trigger a full reset after an abrupt scene change; keep that decision on GPU in a small analysis buffer.

| Control | Range | Initial default |
| --- | --- | --- |
| Flow exaggeration | 0 to 3 times measured displacement | 1.3 |
| History half-life | 0.10 to 3 seconds | 0.80 s |
| Refresh rate | 0.2 to 12 events per second | 2 Hz |
| Motion sensitivity | 0 to 1 | 0.55 |
| Block field style | Crisp, smoothed | Crisp |

**Passes and resources.** Luma downsample, block search, optional vector smoothing, advection/refresh, then output. Two full-resolution RGBA16Float histories use about 31.6 MiB; two quarter-scale R16Float luma maps about 0.49 MiB; vector/confidence fields are much smaller. Reserve under 40 MiB additional persistent resources initially. Declared analysis resolution is fixed for the preset mode; start at a 24 fps processing tier until profiling justifies 30.

**Build tasks.** First ship advection using a synthetic constant vector field; then implement block matching; then confidence/refresh; finally scene-change reset and parameter tuning. This sequence isolates feedback errors from motion-estimation errors.

**Acceptance and failures.** A translated checkerboard must produce backward vectors of the correct sign and scale. Verify zero motion on a static scene, reset on a hard cut and bounded output on noisy low light. Test hands crossing the face and camera exposure changes. Occlusions must refresh rather than smear indefinitely. Reject full-resolution dense optical flow as the initial implementation; it is unnecessary cost for the desired broken-block aesthetic.

### 4.5 Block Error

**Preset:** BLOCK//ERROR · **ID:** `block.error` · **Cost:** Low for displacement; low to medium with persistent holds/residuals.

**Visual goal.** Rectangular blocks freeze, jump and lose color/residual detail independently, resembling damaged compressed video without manipulating a codec.

**GPU algorithm.** Divide the full-resolution image into 8 to 96 pixel tiles. Each tile owns a compact state record: seeded event counter, held flag, expiry PTS and displacement. An update kernel changes those records using a PTS-derived event tick and a bounded error probability. For a triggered hold, copy the current tile into a persistent full-resolution hold texture. Do not overwrite held regions until expiry; unheld tiles may refresh their stored content. A later composition pass chooses current, displaced current or stored tile, then optionally quantizes the signed residual against the previous reference image.

Hold texture reads/writes occur in separate ordered passes. All pixels of a tile follow the same state decision. Keep tile events reproducible from seed and event tick. Reuse GLITCH//WAVE hashing/channel-offset utilities, but do not call a random displaced sample a held historical block.

| Control | Range | Initial default |
| --- | --- | --- |
| Tile size | 8 to 96 output pixels | 32 |
| Error probability | 0 to 1 per update event | 0.18 |
| Hold duration | 0 to 1.5 seconds | 0.25 s |
| Displacement | 0 to 96 pixels | 18 px |
| Residual levels | Off, 4, 8, 16, 32 | 8 |

**Passes and resources.** Small tile-state update; tile capture/reference update; output composite. One RGBA8 held-frame texture and one previous-reference texture total about 15.8 MiB. Small per-tile state fits well below 1 MiB at typical tile sizes. Fuse state evaluation into composition when holds are disabled.

**Acceptance and failures.** Held tiles remain identical for their configured duration even as the source moves. Expired tiles return to live content. The same seed and timestamp sequence reproduces the same pattern. Changing tile size resets state at a frame boundary. Tile edges must not read unrelated old memory, and sustained errors must not increase allocations.

### 4.6 ASCII Grid

**Preset:** ASCII//GRID · **ID:** `ascii.grid` · **Cost:** Medium.

**Visual goal.** A readable glyph mosaic in monochrome or camera-derived color. The glyph grid stays attached to output pixels, independent of window size.

**GPU algorithm.** Build a small atlas once from a bundled licensed monospace font or a purpose-built bitmap glyph set. Rasterize glyphs off the frame path, calculate each glyph's actual ink coverage and sort the ramp by coverage; character order must not be guessed from appearance. Cache atlas texture, per-glyph bounds and coverage LUT. The per-frame analysis pass computes mean luma and mean RGB per cell with bounded GPU reduction. Select the nearest coverage glyph after contrast adjustment. A full-frame render pass identifies the cell and atlas UV for each output pixel, samples glyph coverage and composites ink/paper. Use a single shader-rendered grid initially rather than thousands of CPU text calls or draw calls.

| Control | Range | Initial default |
| --- | --- | --- |
| Cell width | 6 to 32 output pixels | 12 px |
| Glyph ramp | Minimal, dense, symbols | Dense |
| Ink mode | White, green, source color | White |
| Contrast | 0.5 to 3 | 1.3 |
| Polarity | Light ink, dark ink | Light ink |

**Passes and resources.** Cell reduction plus atlas composite. A 512 by 512 R8 atlas is about 0.25 MiB; cell RGB/luma data is well below 1 MiB at the default grid. Derive cell height from the chosen font aspect ratio, not a square assumption. No temporal history.

**Build tasks.** Package/license the glyph asset, verify coverage ordering, build the CPU reference atlas, implement cell reduction and then rendering. Atlas CPU work is initialization-only. Additional font choices rebuild/copy the atlas outside capture processing.

**Acceptance and failures.** A grayscale ramp must select monotonically denser glyphs. A uniform field must select the same glyph across cells. Check incomplete edge cells, glyph padding, narrow windows and output scaling. Ensure ink color changes do not alter the coverage metric. The final video must contain glyphs rather than the UI's status text or font labels.

### 4.7 Halftone Print

**Preset:** HALFTONE//PRINT · **ID:** `halftone.print` · **Cost:** Medium.

**Visual goal.** A stylized CMYK-like print screen with rotated colored dot lattices, visible paper and controlled registration offset. This is creative rendering, not color-managed press separation.

**GPU algorithm.** Convert the display-encoded RGB image to a bounded approximate CMYK separation: `K = min(1-R, 1-G, 1-B) * blackGeneration`, then subtract K from the C/M/Y demands and clamp. Use fixed initial channel angles C 15 degrees, M 75 degrees, Y 0 degrees and K 45 degrees, plus an overall rotation control. In each channel's rotated coordinate system, sample tone at the corresponding cell center, not at each output pixel; one dot must respond to one cell-level demand. Convert tone to dot area. Build a small cached coverage-to-radius lookup from the area of a circle intersecting its square unit cell, with radius from zero to half the cell diagonal; this covers dot overlap correctly and reaches full coverage at tone one. Use the lookup to choose radius, then antialias the circle boundary analytically using output-pixel footprint. Composite ink absorption over the selected paper tone. Do not use the simple isolated-circle area formula at high coverage, where it leaves unprinted corners.

| Control | Range | Initial default |
| --- | --- | --- |
| Dot pitch | 4 to 24 output pixels | 8 px |
| Ink density | 0 to 1.5 | 1 |
| Screen rotation | Minus 45 to plus 45 degrees | 0 |
| Black generation | 0 to 1 | 0.6 |
| Registration offset | 0 to 6 pixels | 0.8 px |

**Passes and resources.** One procedural full-resolution pass sampling the existing source texture; no persistent frame resource. Add a small cached channel-density map only if measurements show repeated sampling is more expensive than a reduction pass. Do not use CPU print filters.

**Acceptance and failures.** Test black/white fields, RGB primaries, neutral gray and a smooth ramp. Verify white paper at zero coverage, stable neutral tones, and smooth tone progression. Inspect moire at preview scales separately from the native-resolution output. Small pitches must use antialiasing; do not silently increase pitch to reduce rendering cost.

### 4.8 Displace Noise

**Preset:** DISPLACE//NOISE · **ID:** `displace.noise` · **Cost:** Low.

**Visual goal.** Analog-looking signal swim, horizontal tearing and phase instability, with a continuous noise field rather than only random block offsets.

**GPU algorithm.** Extract the deterministic hash and band-displacement utilities from GLITCH//WAVE. Evaluate two low-cost octaves of interpolated value noise in UV/time coordinates. Compute horizontal displacement from the field; add occasional horizontal tear bands whose event decisions are seeded by band index and PTS tick. Add a separate small phase-jitter term. Sample the source at the resulting UV; handle wrap/clamp as a defined style choice. Keep this as a stateless spatial effect: no hidden frame feedback or held blocks.

| Control | Range | Initial default |
| --- | --- | --- |
| Displacement amplitude | 0 to 64 output pixels | 12 px |
| Noise frequency | 1 to 40 cycles over image height | 8 |
| Tear density | 0 to 1 | 0.25 |
| Animation speed | 0 to 4 cycles per second | 0.8 |
| Seed | Unsigned 32-bit integer | 3201 |

**Passes and resources.** One fused signal pass, no history. Compute two noise octaves procedurally; do not allocate or upload a new noise bitmap per frame. Budget under 2 ms incremental GPU time as an initial target.

**Build tasks.** Factor shared utilities without altering GLITCH//WAVE output; implement continuous displacement; add tear events; add seed and speed controls. Keep GLITCH//WAVE the harsher digital preset and DISPLACE//NOISE the continuously unstable signal preset.

**Acceptance and failures.** Zero amplitude produces clean sampling. Speed zero freezes the displacement field. Identical seed/time reproduces it, and changing the seed changes the field. Test image borders, single-pixel source marks and animation continuity across cadence changes. Avoid hard resets caused by modulo time wrapping.

### 4.9 Solar Negative

**Preset:** SOLAR//NEG · **ID:** `solar.neg` · **Cost:** Low.

**Visual goal.** Threshold-controlled solarization, photographic negative and split-tone inversion that can retain recognizable facial structure.

**GPU algorithm.** Compute display luma Y. Define a soft gate `g = smoothstep(low, high, Y)` with a minimum threshold separation of 0.005. Negative mode uses `1-RGB`; split-negative blends that result using g; solar mode uses `Ysolar = mix(Y, 1-Y, g)`, which rises below the threshold region and reverses above it. Reconstruct `scaled = RGB * Ysolar / max(Y, 0.001)`, clamp it, then blend between `float3(Ysolar)` and scaled color with chroma retention. Apply the same chroma-retention blend to the negative modes, using their resulting luma, and apply optional hue rotation after inversion. Clamp output and keep the gate stable when the frame is nearly black. Common intensity handles the final clean/effect mix.

| Control | Range | Initial default |
| --- | --- | --- |
| Lower threshold | 0 to 0.995 | 0.35 |
| Upper threshold | Lower plus 0.005 to 1 | 0.65 |
| Curve | Solar, negative, split negative | Solar |
| Chroma retention | 0 to 1 | 0.75 |
| Hue offset | Minus 180 to plus 180 degrees | 0 |

**Passes and resources.** One fused pass with no history or extra full-frame allocation. Reuse global hue math but keep the effect's hue offset separate from the COLOR inspector's global hue value.

**Acceptance and failures.** A grayscale ramp produces the expected continuous or deliberately kinked solar curve. Negative mode maps black to white and white to black. Verify finite values near zero luma, minimum threshold separation and no unexpected alpha changes. Global color resets must not reset this effect's thresholds.

### 4.10 Motion Slit

**Preset:** MOTION//SLIT · **ID:** `motion.slit` · **Cost:** Medium to high, principally memory/bandwidth.

**Visual goal.** Different horizontal or vertical portions of the face show different moments, creating stretched time ribbons rather than translucent echo trails.

**GPU algorithm.** Allocate a 2D-array history texture with a fixed maximum of 16 full-resolution RGBA8 slices. Insert the color-adjusted source at a declared 15 Hz history sampling rate, independent of render cadence. Each slice has an actual PTS in a small metadata buffer. The ring holds 16 samples, spanning approximately one second at steady 15 Hz. Use timestamp-based sample scheduling; do not assume a 30 fps source or insert duplicated frames after a gap.

For an output coordinate q along the chosen axis, compute `age = depth * profile(q)`; target source time is `currentPTS - age`. Search the small timestamp array for the nearest sample at or before that target. Optionally interpolate between bracketing temporal samples as an explicit mode. During warmup, clamp requested ages to the oldest valid sample. Reverse direction changes profile(q), not the orientation of the camera image.

| Control | Range | Initial default |
| --- | --- | --- |
| Time depth | 0 to 1 second | 0.60 s |
| Axis | Horizontal bands, vertical bands | Horizontal bands |
| Direction | Forward, reverse | Forward |
| Time profile | Linear, center outward | Linear |
| Temporal sampling | Nearest, blended | Nearest |

**Passes and resources.** One history insertion blit/pass when a sample is due, then one full-resolution gather pass and common output composition. Sixteen RGBA8 slices consume about 126.6 MiB. An explicit LIGHT HISTORY option may use eight full-resolution slices with a shorter declared span; it must not silently halve the history image resolution. Release all slices when leaving the effect after in-flight commands complete.

**Build tasks.** Implement ring/timestamp metadata; prove history insertion; add linear gather; add axis/reverse; then optional temporal interpolation. Keep the array slice currently being written outside the read set until command ordering makes the write visible. Two in-flight frames must not overwrite a slice still needed by an earlier gather.

**Acceptance and failures.** Feed frames with visible timecodes or numbered color bands and verify every output band uses the intended age at 15/20/24/30 fps. Test ring wrap, warmup, dropped frames and PTS discontinuities. Memory must plateau after allocation. Switching away must release history once GPU references retire. No camera upside-down transform may be introduced by the gather stage.

### 4.11 Dataveil

**Preset:** DATAVEIL · **ID:** `dataveil` · **Cost:** High with person masks; medium with luma masks.

**Visual goal.** A thresholded human silhouette or luma shape, outlined and surrounded by controlled glowing feedback. Default output remains opaque; person masking does not imply transparent export.

**First implementation.** Build an entirely GPU luma-mask mode before adding Vision. Derive a threshold mask from the current color-adjusted frame, apply a small softness band, form an edge by subtracting eroded from dilated mask, and combine with a restrained glow. Store mask/outline feedback in two R16Float histories and apply time-based half-life decay. Use separable blur on an explicitly half-resolution glow field; reconstruct the glow at full output dimensions while the silhouette edge remains full resolution.

**Optional person masks.** Add `VNGeneratePersonSegmentationRequest` on a separate serial worker at a maximum initial request rate of 8 Hz. Preprocess an upright 384 by 216 image and retain the exact scale/crop mapping. Start with `.balanced` quality and request R8 output after querying supported formats [1]. Keep one request running plus one replaceable latest candidate; never queue every captured frame. Publish the newest successful mask with its source PTS and generation. Render and encode continue independently of inference. Map mask orientation and coordinates back into the canonical working image before thresholding.

If a mask is more than 250 ms old, blend to luma-mask fallback over 100 ms; expose the active source in the inspector. Unsupported Vision revision/format, failed inference or camera change also uses the declared luma fallback. Do not automatically select a cheaper Vision quality setting during a recording. Permission to access the camera does not require a second permission for local person segmentation, but no frames or masks leave the app.

| Control | Range | Initial default |
| --- | --- | --- |
| Mask source | Luma, person | Luma |
| Mask threshold | 0 to 1 | 0.5 |
| Edge width | 1 to 8 output pixels | 2 |
| Glow radius | 0 to 24 output pixels | 8 |
| Feedback half-life | 0.05 to 2 seconds | 0.5 s |

**Passes and resources.** Mask normalization/threshold, morphology/edge, separable half-scale glow, feedback and composite. Two R16Float histories use about 7.9 MiB; full-size mask scratch and two half-size blur fields bring explicit shader resources to roughly 16–24 MiB depending on reuse. Vision adds framework-managed model/working memory that must be measured; the shader allocation estimate is not a total DATAVEIL memory promise. Begin with a declared 24/20 fps render tier for person mode, 8 Hz masks, and profile before promoting it.

**Build tasks.** Luma silhouette → edge → glow → feedback → asynchronous person mask → stale-mask fallback → diagnostics. Reuse ECHO decay utilities and EDGE morphology, but use a scalar mask history rather than an unnecessarily expensive RGBA color history.

**Acceptance and failures.** Check clean silhouette boundaries, hair and glasses, hands crossing the face, low light and moving backgrounds. Verify scale/orientation with a subject at each image corner. Simulate slow/failed inference: camera preview must continue, mask work must stay bounded and fallback must be visible in the inspector. Confirm Command-U hides diagnostics without removing the mask effect. No alpha codec is introduced by this milestone.

## 5 Completion work for existing presets

### 5.1 Chroma Shift

Keep the existing displaced R/G/B sampling, radial term and time drift. Replace the generic parameter labels with separation in output pixels, direction in degrees, radial strength and drift rate, plus common intensity. Separation zero must really be zero; the present formula has a fixed minimum offset. Expand negative/positive direction through a vector rather than restricting displacement to horizontal.

Motion reactivity is not implemented. Add it only after the shared MOSH analysis exists: use block-flow magnitude/confidence to scale a bounded offset, with static radial behavior as the explicit nonreactive mode. Do not run optical flow solely to make the basic low-cost chroma preset move. Test neutral gray, image borders, separation zero and output-resolution consistency.

### 5.2 Poster Eight

The current kernel quantizes each RGB channel into a variable number of levels and applies a 4 by 4 Bayer pattern. That is not an exact eight-color palette. Add a palette enum with the existing per-channel mode plus a true eight-color factory palette. For eight colors, compute nearest palette entry directly in a bounded loop; for larger optional palettes, cache a small lookup texture. Implement palette selection, dither amount, dither cell size and color-space style as independent contextual controls.

Keep display-encoded quantization as default. An explicit linear-light style decodes before quantization and re-encodes afterward. Palette assets must be bundled/versioned. Blue-noise dither is a later option using one cached tile, not a new random texture every frame. Test exact palette membership with dither disabled, correct eight-color cardinality and clean intensity bypass.

### 5.3 Scan CRT

Keep barrel warp, scanline modulation, RGB phosphor mask, vignette and small temporal flicker. Split coupled controls into scanline depth, line spacing, curvature, phosphor strength and flicker amount, with common intensity. Avoid a control labeled curvature that also silently changes line darkness.

Validate brightness on uniform fields and aliasing at all preview scales. Frequencies are defined in output pixels, never window points. Flicker is off or very subtle by default and does not affect recording timestamps. Verify that intensity zero does not retain an unavoidable vignette, mask or border crop.

## 6 Proposed file structure and implementation interfaces

| Proposed file or area | Responsibility |
| --- | --- |
| `Engine/EffectDefinition.swift` | Stable IDs, registry, banks, descriptor types and defaults |
| `Engine/EffectParameters.swift` | Typed validated per-effect values and persistence migration |
| `Engine/FrameContext.swift` | Source PTS, dt, dimensions, generation and seed |
| `Engine/TextureResources.swift` | Pools, format/size keys and allocation accounting |
| `Engine/TemporalState.swift` | Ping-pong ownership, ring metadata and reset rules |
| `Engine/EffectEncoder.swift` | Explicit per-effect pass plans and resource bindings |
| `Engine/MaskWorker.swift` | Asynchronous Vision requests, generation checks and mask age |
| `Shaders/Shared` | Color transfer, sampling orientation, luma, hash, noise, blur and morphology |
| `Shaders/Effects` | One named shader source per effect, composed from shared utilities |
| Existing custom UI | Registry-driven cards and contextual controls; no parallel label arrays |
| `Tests/EffectChecks` | Synthetic spatial tests, temporal sequences, reference comparisons and resource checks |

Use a small interface: `prepare(device, dimensions, parameters)`, `encode(frameContext, input, output, commandBuffer)` and `reset(reason)`. Preparation allocates/compiles outside the hot path. Encoding binds existing resources and records passes. Reset changes generation and seeds history from the next valid frame. Keep recording independent of effect subclasses.

## 7 Development milestones and completion gates

These estimates describe focused implementation effort, not guaranteed calendar delivery. Each milestone includes its custom inspector/card wiring and functional checks. Recording feature work stays outside this sequence except that every effect must preserve shared output-buffer delivery.

| Milestone | Deliverable | Gate | Effort estimate |
| --- | --- | --- | --- |
| E0 | Registry, typed parameters, canonical coordinates, resource generations and GPU test entry point | Existing four presets unchanged visually; settings isolated; orientation tests pass | 1–2 days |
| E1 | SOLAR//NEG and DISPLACE//NOISE | Deterministic controls, custom cards, no additional history | 1 day |
| E2 | EDGE//VECTOR and HALFTONE//PRINT | Correct contours, stable dot tones and output-pixel controls | 1–2 days |
| E3 | ECHO//FRAME and BLOCK//ERROR | Cadence-independent decay, real held tiles, bounded state and reset behavior | 2 days |
| E4 | ASCII//GRID and existing preset completion | Licensed atlas, measured coverage ramp, exact poster palette, independent CRT/chroma controls | 1–2 days |
| E5 | PIXEL//SORT | Reference-equivalent bounded sorting in both axes; padding/barrier tests pass | 1–2 days |
| E6 | MOTION//SLIT | Correct timestamp selection, full-resolution ring, measured memory plateau | 1–2 days |
| E7 | MOSH//FLOW | Correct vector direction, controllable refresh, stable feedback and hard-cut reset | 2–3 days |
| E8 | DATAVEIL luma then person mode | Responsive renderer with bounded inference and visible stale-mask fallback | 2–3 days |
| E9 | Preset tuning and DAW coexistence | Declared measured cadence/cost per mode, memory and GPU traces, regression suite | 1–2 days |

Total planning range: approximately 13–21 focused engineering days, including shared work and acceptance tuning. Ship incremental usable banks after E1, E3 and E6; do not wait for segmentation to make inexpensive effects available. If a heavy effect misses its tier, keep it experimental and state its measured limits rather than changing image detail silently.

## 8 Verification required before calling an effect complete

### Spatial and color checks

Use generated ramps, checkerboards, single-pixel marks, asymmetric corner labels and moving color bars. Verify identity/bypass, alpha, finite values, image boundaries, odd dimensions and deterministic seeds. Compare GPU output to a simple CPU reference where useful, with an explicit tolerance for filtering and color conversion. Test all actual control ranges and invalid preset input. Keep CPU reference code out of production capture.

### Temporal and state checks

Replay the same timestamped sequence at multiple cadences. Check half-life, vector direction, held-block expiry, ring age selection and reset behavior. Test preset changes while two GPU frames are in flight. Repeat 100 preset switches and confirm that active allocations return to the declared resource set after command completion; process RSS may remain cached and is not the sole leak criterion.

### Native interface checks

Verify every effect is selectable in the embedded grid, contextual numeric values have correct units, reset affects the correct scope, keyboard adjustments work and VoiceOver can identify/adjust controls. Resize the window with the inspector open, scroll to every parameter and toggle Command-U twice. The same selected effect/settings/history must return. No status labels, guides or buttons may appear in the processed image.

### Performance checks

For each preset at its declared settings, record p50/p95 GPU effect time, CPU submission time, processing latency, actual delivered frames, pool exhaustion, GPU failures and explicit texture allocations. Run at least a 10-minute session and a 30-minute DAW plus screen-recorder soak for heavy presets. Measure baseline and effect deltas; evaluate audible DAW underruns in the real project. Run GPU checks in a native environment with Metal available. A skipped or unexecuted test is not a pass.

### Completion record

For each effect, save its visual reference, parameter defaults, measured cadence tier, memory estimate versus measured allocation, known limitations and test results. Only then move its registry status from experimental to accepted. Recording/export acceptance remains a separate final workflow gate after the effect/UI work requested here.

## 9 Platform references

Implementation choices and ranges above are FRAME32 engineering decisions. These Apple sources establish platform behavior, not performance promises.

1. Apple Vision person segmentation and supported mask formats: https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest and https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest/outputpixelformat . Query supported output formats at runtime; R8 is the initial selection. Retrieved 17 November 2026.
2. Apple Metal compute threadgroup limits: https://developer.apple.com/documentation/metal/mtldevice/maxthreadsperthreadgroup and https://developer.apple.com/documentation/metal/mtldevice/maxthreadgroupmemorylength . Validate per-pipeline thread limits as well as device limits. Retrieved 17 November 2026.
3. Apple Metal resource synchronization: https://developer.apple.com/documentation/metal/resource-synchronization . Use the synchronization model supported by the macOS 14 deployment target; this plan does not depend on Metal 4-only APIs. Retrieved 17 November 2026.
4. Apple Metal texture hazard tracking, reviewed through Context7 documentation for Metal: tracked resources provide dependency safeguards; they do not replace within-threadgroup barriers or safe cross-queue lifetime ownership. Retrieved 17 November 2026.

Source snapshot: local `SignalProcessor.swift`, `Interface.swift`, `main.swift` and `Tests/EffectChecks/main.swift` inspected for this plan on 17 November 2026. No application code was changed as part of writing this document.
