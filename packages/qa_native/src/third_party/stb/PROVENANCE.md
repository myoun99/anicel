# stb — vendored, unmodified

- Source: https://github.com/nothings/stb
- Files: `stb_vorbis.c` (v1.22)
- Commit: `31c1ad37456438565541f4919958214b6e762fb4`
- License: dual **MIT / public domain (Unlicense)** — same family as the
  dr_libs and miniaudio bundles beside it; no attribution obligation, no
  copyleft.
- Modifications: **none**. Updates must stay a straight overwrite of the
  upstream files at a pinned commit, recorded here.

Why stb_vorbis is here: the EXPORT-AUDIO round removed ffmpeg from every
audio path. ogg was the one format the vendored dr_libs family does not
read (there is no dr_ogg), so the ffmpeg waveform fallback existed for it
alone. stb_vorbis closes that gap natively — decoded once at import like
every other format, waveforms on tablets included.

↩️`stb_image_write.h` (v1.16, the same pin) stood here for the export
window's JPG output (EX4) until the connection round
(connection-round-checklist H, 2026-11-08): its JPEG writer is the GPU
engine's now, ported byte for byte (`packages/gpu_engine/rust/native/
image_encode`, which says why it is native).
