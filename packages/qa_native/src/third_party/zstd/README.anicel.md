# zstd (vendored)

**v1.5.6**, single-file amalgamation, generated from the official script.

- Source: https://github.com/facebook/zstd, tag `v1.5.6` (commit `794ea1b`)
- Generated with `build/single_file_libs/combine.sh -r ../../lib -x legacy/zstd_legacy.h -o zstd.c zstd-in.c`
- License: BSD-3-Clause (`LICENSE`), the same terms as the other vendored
  libraries here (miniaudio, rnnoise, stb, dr_libs).

## Why it is here

Cel blobs are compressed once per save and decompressed **on the main
isolate, in frame time**, every time a cold cel is promoted to hot
(`BrushFrameStore` line ~266). Measured on a real 22.8MB project:

| | median cel | largest cel |
|---|---|---|
| deflate -9 | 3.35ms | 70ms |
| zstd -9 | **0.11ms** | 55ms |

Smaller *and* faster — 30× on the cel size that actually occurs. deflate
was not a bad choice; it is simply older than the problem.

## ⛔What was rejected, and why

- **xz / LZMA** — 30% smaller than deflate but the slowest to decompress
  of everything measured. The cost would land on the promotion path.
- **OpenZL** (Meta, 2025) — format-aware and genuinely aimed at data like
  ours, but its README says the compressed format *will* change, and it
  needs C++17 in a native build that is C today. A project file is the
  wrong place to take a moving format. Worth measuring again when it
  settles.
- **A newer general codec** — there is not one that beats zstd on the axis
  that binds us (decompress speed at a good ratio).

## Updating

Re-run the amalgamation script against a new tag and replace `zstd.c` and
`zstd.h`. ⚠️Nothing here is patched, on purpose: a local edit would have to
be re-applied by hand every update, and the next person would not know.
