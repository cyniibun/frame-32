# Upstream research snapshots

The public repository omits the v002-Rutt-Etra and GPU-Based-Image-Processing-Tools snapshots pending license review. Their pinned upstream links and file hashes remain documented here and in `repositories.json`. The snapshot verification script requires a local copy of all five snapshots.

Five selected-source snapshots are pinned below. These are not full clones: no Git history, large assets or upstream runtimes are included. They are not compiled or bundled in FRAME32. All 56 source files preserve upstream bytes; the manifest records Git blob and SHA-256 hashes. Run `python3 scripts/verify_references.py` to verify them.

- **PixelFlow**: https://github.com/diwi/PixelFlow @ `3db49397164bc76373ff7e15c0a31dadb0037801`; MIT_root_license_retained. Files: `Upstream/PixelFlow/`.
- **GPU-Based-Image-Processing-Tools**: https://github.com/RaymondMcGuire/GPU-Based-Image-Processing-Tools @ `e720cf883c7926904824124d588f12f96a47eb37`; MIT_root_with_inherited_shader_notice_review. Files: `Upstream/GPU-Based-Image-Processing-Tools/`.
- **Post-Processing**: https://github.com/GarrettGunnell/Post-Processing @ `871a7ffcc44174f237b4c0127db51026c438d7a4`; MIT_root_license_retained. Files: `Upstream/Post-Processing/`.
- **reaction-diffusion**: https://github.com/linusmossberg/reaction-diffusion @ `f4a7ffbbae22648a67350dd8a10d96632ca8ed61`; MIT_root_license_retained. Files: `Upstream/reaction-diffusion/`.
- **v002-Rutt-Etra**: https://github.com/v002/v002-Rutt-Etra @ `8b4feb5ebbf94141f053a19ee1c03ebaabd00456`; review_required_external_terms. Files: `Upstream/v002-Rutt-Etra/`.

See `../Docs/FRAME32_Creative_Effects_Backlog.md` for all eight planned effects and reference mapping. Port only the needed algorithms into Metal after per-file license review; retain attribution. Rutt/Etra remains reference-only until its external terms are resolved. The image-processing collection contains inherited shader notices requiring separate review. No app dependency or executable is installed by this directory.
