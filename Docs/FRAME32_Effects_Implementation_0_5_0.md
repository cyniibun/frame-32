# FRAME//32 Effects Implementation — 0.5.0

17 November 2026 · Source baselines delivered; native GPU acceptance pending

The app now registers 24 effects plus CLEAN. All eight creative directions and the seven unfinished original effects have native source implementations, custom parameter inspectors and named-preset persistence. No upstream project is compiled or bundled; reference snapshots remain separate.

## Added effects

| Effect | Delivered baseline | Main controls and deliberate limits |
| --- | --- | --- |
| RASTER//RELIEF | Bufferless GPU vertex generation for luma-displaced lines, wire grid and points; perspective and fading geometry history | Density, extrusion, perspective, geometry mode, trail half-life, hue. A 2.5D brightness portrait, not reconstructed facial depth. |
| CONTOUR//FLOW | Smoothed structure tensor, tangent field, normal DoG responses integrated along sign-aligned tangents; ink history and halo | Line scale, threshold, coherence, half-life, hue, paper/dark and glow. Raster contours, not SVG paths. |
| VECTOR//HATCH | Structure-oriented tone-controlled strokes, crosshatching and bounded stroke-length gating | Spacing, width, crosshatch, tone depth, hue, paper/dark, stroke length. Visual stability still needs live-footage tuning. |
| PARTICLE//SKIN | Persistent GPU position/velocity textures; block-motion forces and damped spring return; camera-colored GPU points | Particle columns, scatter, stiffness, point size, half-life, hue, camera/tint. Default 96 columns gives about 5,184 particles at 16:9. |
| FLUID//GHOST | Motion-field advection of linear-light feedback, diffusion, controlled camera refresh and analytic curl displacement | Flow, refresh, diffusion, half-life, swirl, hue, camera/tint. No pressure-projected fluid solver in this baseline. |
| INK//GROWTH | Camera-edge-seeded Gray–Scott reaction–diffusion in ping-pong simulation textures, palette and gradient relief | Feed, kill, seeding, growth rate, hue, camera reveal, relief. At most eight stable simulation steps per submitted frame. |
| PAINT//FLOW | Four directional Kuwahara sectors, structure-aligned elliptical sampling, variance weighting and flow contours | Radius capped at six pixels, directionality, sharpness, ink, persistence, saturation. High-cost candidate pending profiling. |
| CELLS//SHATTER | Persistent jittered Voronoi sites, motion displacement, spring return, nearest/second-nearest cell borders | Cell columns, separation, return, border width/hue and seed. Bounded 5×5 neighboring-site lookup with constrained displacement. |
| ECHO//FRAME | Full-resolution linear-light ping-pong feedback with elapsed-time decay, zoom, rotation and drift | Half-life, zoom, rotation, drift, history mix. Recursive history excludes final grain, UI and intensity blending. |
| BLOCK//ERROR | Seeded tile events with actual held historical content and period boundaries; displaced, quantized refresh | Tile size, event density, hold period, displacement, residual levels and seed. State uses image history and deterministic event periods. |
| ASCII//GRID | Sixteen samples per cell, initialization-time measured glyph coverage ranking, cached atlas rendering | Glyph width, contrast, camera/mono/tint, hue, polarity. Uses the existing 32-glyph atlas; density/tonal matching needs artistic acceptance. |
| PIXEL//SORT | Threadgroup bitonic sort with 64 lanes and stable tie keys; excluded pixels separate contiguous eligible runs | Segment length 8–64, low/high luma, horizontal/vertical, ascending/descending. No full-frame or CPU sort. |
| MOTION//SLIT | Eight full-resolution timestamped texture-array slices; nearest historical sample per row, column or radius | History span 0.1–2 seconds, direction and camera blend. Eight slices are explicit; longer spans produce coarser temporal steps. |
| MOSH//FLOW | Reduced-map block search, motion-vector feedback advection, difference-gated refresh and keyframe leak | Motion multiplier, refresh threshold, leak, block size, half-life. Datamosh-inspired rendering, not compressed-bitstream datamoshing. |
| DATAVEIL | Luminance silhouette, contour reinforcement, tinted drift/decay feedback and neighborhood glow | Threshold, softness, half-life, drift, hue, reveal. Luma-mask fallback only; Vision person segmentation is not implemented. |

## Shared behavior and footprint

- Existing typed registry supplies the custom cards, scrolling inspector, numeric/choice/seed controls and saved-look persistence.
- CLEAR HISTORY / RESEED clears active simulation/history without resetting tuning. RESET restores tuning and clears history. Command-U preserves history.
- Resource ownership follows the serial capture queue. Old state survives until dependent command buffers finish. Camera/effect changes and timestamp discontinuities reset history; seed or structural grid changes replace relevant state.
- Analysis width is at most 320 pixels. Motion search is bounded to 25 offsets with nine samples per candidate; low-confidence improvements are suppressed. Fast motion beyond the search radius remains a visual limitation.
- Spring updates use bounded stable substeps. Solver steps, particle/site counts, paint radius, sort length and slit capacity have hard limits.
- Full-resolution feedback allocates two RGBA16Float images only where needed. Other effects use one output image. Motion effects additionally retain one BGRA8 source image. RASTER and particles add a geometry target. Slit scan adds eight BGRA8 slices.
- At 1080p, one RGBA16Float image is about 15.8 MiB, one BGRA8 image about 7.9 MiB, and the eight-slice bank about 63.3 MiB. These are texture-size calculations, not measured total process memory. Active-effect byte accounting is exposed to verification code.
- The rebuilt app bundle occupies about 828 KiB at this checkpoint, compared with about 728 KiB before this batch. Build caches, runtime GPU memory and disk size are separate quantities.
- No Java, Unity, Python, browser runtime or machine-learning weights are added. All live processing remains on Metal; CPU pixel readback is limited to diagnostics and initialization-time glyph measurement.

## Verification and remaining work

**Passed:** optimized Swift build, ad hoc signature verification, registry uniqueness/ranges, settings normalization, all 15 new-effect settings round trips, named-look persistence/recall and the existing non-GPU checks.

**Not run:** native Metal compilation and rendered-pixel checks. Metal device discovery is unavailable in this execution session, the offline Metal compiler is absent, and Launch Services returns error -10827 when opening the app. The earlier 0.4.1 native report does not verify any 0.5.0 additions.

The native suite now covers all 24 effects, bypass, opaque output, first-frame history behavior, sorting order and excluded runs, Echo decay/reset, geometry extrusion, simulation extremes, discontinuity resets and inactive-resource release. Run **View → Run GPU Effect Checks** in the native app. A pass is still required before calling these GPU implementations accepted.

Next acceptance milestones:

1. Native shader compilation and synthetic suite; resolve any runtime/compiler errors first.
2. Live visual acceptance in creative order: relief, contours, hatching, particles, fluid, growth, paint, cells; refine defaults and controls from real camera footage.
3. Original-bank tuning, including ASCII tone matching, held blocks, sorting separators and timestamped slit behavior.
4. Measure GPU p50/p95, dropped frames and process/resource memory at 720p/1080p; tune high-cost effects before claiming DAW-friendly performance.
5. Verify recording across effect changes and Command-U, color/orientation consistency, then a sustained DAW coexistence run.

Existing CHROMA/POSTER/CRT refinement, optional Vision segmentation, recovery, snapshot/gallery and distribution signing remain open. This build supplies effect baselines; it is not a completed release acceptance milestone.
