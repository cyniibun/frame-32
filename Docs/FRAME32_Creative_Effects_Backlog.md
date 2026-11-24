# FRAME//32 Creative Effects Backlog

17 November 2026 · Build 0.5.0 · Source baselines added; native GPU acceptance pending

All eight directions below now have native Swift/Metal source baselines, custom controls and named-preset support in build 0.5.0. The seven remaining original effects also have source baselines. Swift build and persistence checks pass. Metal is unavailable in this shell: shader compilation on a real device, rendered-pixel checks, visual tuning, performance and export acceptance are pending. The earlier nine-effect GPU pass applies only to build 0.4.1. References remain algorithm research, not app dependencies.

## 1. RASTER//RELIEF

**Visual:** Raised scanlines, wire surfaces and oscilloscope portraits.

**Implementation:** GPU grid vertices displaced by camera luminance; perspective and bounded geometry history.

**Controls:** Line/point/mesh mode, density, extrusion, perspective, palette, trail half-life.

**References:** v002-Rutt-Etra; pinned paths and file hashes are in `References/repositories.json`.

**Estimated cost:** Medium (relative GPU cost; unmeasured).

**Acceptance:** Flat gray produces a flat surface; ramps produce ordered depth; motion bends geometry; trails decay by elapsed time.

## 2. CONTOUR//FLOW

**Visual:** Smooth facial contours with luminous ink trails.

**Implementation:** Smoothed structure tensor and edge-tangent field feeding flow-guided difference-of-Gaussians lines.

**Controls:** Coherence, line width, threshold, ink/background colors, glow, persistence.

**References:** GPU-Based-Image-Processing-Tools; pinned paths and file hashes are in `References/repositories.json`.

**Estimated cost:** Medium (relative GPU cost; unmeasured).

**Acceptance:** Contours follow curved structure without unstable line flipping; flat areas stay clean; persistence clears correctly.

## 3. VECTOR//HATCH

**Visual:** Engraving, technical drawing and animated pen shading.

**Implementation:** Orient coherent procedural strokes along the structure field; tone controls density and crosshatching.

**Controls:** Stroke length, spacing, thickness, crosshatch angle, ink/paper colors, persistence.

**References:** GPU-Based-Image-Processing-Tools, PixelFlow; pinned paths and file hashes are in `References/repositories.json`.

**Estimated cost:** Medium (relative GPU cost; unmeasured).

**Acceptance:** Stable strokes track structure; darker ramps gain ink monotonically; crosshatch direction remains coherent.

## 4. PARTICLE//SKIN

**Visual:** Camera-colored particles scatter with movement and reassemble.

**Implementation:** Persistent GPU particle position/velocity buffers; motion forces and damped spring attraction to camera-grid anchors.

**Controls:** Particle count, size, scatter, return stiffness, drag, color mode, trails.

**References:** PixelFlow; pinned paths and file hashes are in `References/repositories.json`.

**Estimated cost:** Medium–High (relative GPU cost; unmeasured).

**Acceptance:** Motion scatters particles; stillness reassembles the portrait; particle counts stay bounded and behavior is cadence independent.

## 5. FLUID//GHOST

**Visual:** Liquid ribbons, smoke and colored image wakes.

**Implementation:** Advect ping-pong camera feedback through a low-resolution motion field; optional bounded pressure projection.

**Controls:** Flow strength, refresh, diffusion, decay, vorticity, palette, camera reveal.

**References:** PixelFlow; pinned paths and file hashes are in `References/repositories.json`.

**Estimated cost:** Medium–High (relative GPU cost; unmeasured).

**Acceptance:** Motion drives directional wakes; decay has a measured half-life; no NaNs or energy runaway during prolonged stillness.

## 6. INK//GROWTH

**Visual:** Organic ink, veins and metallic patterns seeded by the face.

**Implementation:** Bounded Gray–Scott reaction–diffusion textures seeded by edges/motion; palette and optional gradient relief shading.

**Controls:** Growth/feed/kill presets, diffusion, seed threshold, simulation scale, palette, relief, camera reveal.

**References:** reaction-diffusion; pinned paths and file hashes are in `References/repositories.json`.

**Estimated cost:** Medium–High (relative GPU cost; unmeasured).

**Acceptance:** Camera seeds reproducible growth; reset is deterministic; solver stays stable with bounded time steps and iterations.

## 7. PAINT//FLOW

**Visual:** Directional painted regions with coherent ink contours.

**Implementation:** Anisotropic Kuwahara using shared structure field; optional flow contours and restrained temporal persistence.

**Controls:** Brush radius, anisotropy, sector sharpness, contour amount, palette, persistence.

**References:** Post-Processing, GPU-Based-Image-Processing-Tools; pinned paths and file hashes are in `References/repositories.json`.

**Estimated cost:** High (relative GPU cost; unmeasured).

**Acceptance:** Directional smoothing preserves major boundaries; brush radius has a hard limit; temporal persistence avoids obvious dragging.

## 8. CELLS//SHATTER

**Visual:** Irregular camera cells separate with motion and settle back.

**Implementation:** Persistent Voronoi sites with camera sampling, motion displacement and damped spring return; GPU nearest-site field.

**Controls:** Site count, seed, separation, return, cell borders, palette, trails.

**References:** PixelFlow; pinned paths and file hashes are in `References/repositories.json`.

**Estimated cost:** Medium–High (relative GPU cost; unmeasured).

**Acceptance:** Site identities persist; motion separates cells; stillness returns them without jitter; seed/reset are reproducible.

## Rapid development milestones

1. **RASTER//RELIEF:** ship a distinctive line/point portrait first, then mesh and fading trails. Add shared temporal resource accounting as needed.
2. **CONTOUR//FLOW:** establish one reusable structure field and flow-guided contour pipeline; ship and validate independently.
3. **VECTOR//HATCH:** reuse that field for anchored strokes and crosshatching.
4. **PARTICLE//SKIN:** add bounded GPU particle buffers and shared motion estimation.
5. **FLUID//GHOST:** reuse motion and feedback resources; start with advection and add solver complexity only if the visual benefit warrants it.
6. **INK//GROWTH:** introduce a bounded simulation with presets and stable stepping.
7. **PAINT//FLOW:** reuse structure and contour passes; cap filter radius and benchmark before expanding.
8. **CELLS//SHATTER:** persistent site identities, nearest-site lookup and spring reconstruction.

Each milestone produces a separately reviewable app build. ECHO//FRAME infrastructure can be developed alongside temporal milestones; remaining original effects ECHO//FRAME, BLOCK//ERROR, ASCII//GRID, PIXEL//SORT, MOTION//SLIT, MOSH//FLOW and DATAVEIL stay in the backlog. Motion analysis can serve MOSH and FLUID, but they remain visually distinct effects. DATAVEIL remains silhouette/mask feedback, not compressed-bitstream datamoshing.

## Shared requirements and lightweight limits

- Native Swift and Metal only; no Processing/Java, Unity, browser runtime or Python runtime added to the app.
- Allocate only selected-effect resources; bound particle/site counts, solver steps, history and analysis dimensions. Expose quality choices; do not silently lower output resolution.
- Shared source timestamps, generation-safe cleanup, reset on camera/size/time discontinuities, orientation and color contracts.
- Per-effect custom controls, numeric ranges, intensity bypass, named-preset persistence and meaningful color choices. Trails use elapsed-time decay and explicit reset.
- Motion estimation must reject low-confidence regions and avoid camera-noise-driven motion. Structure fields need sign-consistent sampling and temporal stability.
- GPU tests cover synthetic ramps, flat fields, moving shapes, orientation, bypass, parameter extremes and reset. Native camera acceptance includes effect switching and Command-U; export acceptance covers the shared processed output.
- Measure GPU p50/p95, texture/buffer bytes and dropped frames at 720p/1080p, then a representative DAW coexistence run. Cost labels above are estimates, not performance claims.
- Verify per-file permissions before porting and retain attribution. Rutt/Etra is visual reference pending license review; inherited shader notices require review even where the repository root is MIT.
- No true SVG tracing, physical 3D face reconstruction or true compressed-bitstream datamoshing is implied.

## Reference inventory

- [diwi/PixelFlow](https://github.com/diwi/PixelFlow) · `3db49397164bc76373ff7e15c0a31dadb0037801` · MIT_root_license_retained
- [RaymondMcGuire/GPU-Based-Image-Processing-Tools](https://github.com/RaymondMcGuire/GPU-Based-Image-Processing-Tools) · `e720cf883c7926904824124d588f12f96a47eb37` · MIT_root_with_inherited_shader_notice_review
- [GarrettGunnell/Post-Processing](https://github.com/GarrettGunnell/Post-Processing) · `871a7ffcc44174f237b4c0127db51026c438d7a4` · MIT_root_license_retained
- [linusmossberg/reaction-diffusion](https://github.com/linusmossberg/reaction-diffusion) · `f4a7ffbbae22648a67350dd8a10d96632ca8ed61` · MIT_root_license_retained
- [v002/v002-Rutt-Etra](https://github.com/v002/v002-Rutt-Etra) · `8b4feb5ebbf94141f053a19ee1c03ebaabd00456` · review_required_external_terms

## Current implementation and acceptance

See [build 0.5.0 implementation report](FRAME32_Effects_Implementation_0_5_0.md) for delivered algorithms, deliberate limits and the remaining acceptance gates. Milestones above now describe the order for native verification and artistic refinement. Baseline source presence is not a GPU pass.
