// CocoaPods compiles Classes/ only; the real source lives in src/ shared
// with every other platform. Same pattern as the sibling forwarders.
//
// 🚨Missing from 2026-08-30 (#1373, cels compress with zstd) to
// 2026-09-13: the CMake list gained qa_compress.c and zstd.c, the Apple
// pods did not, so `qa_zstd_*` never existed in an iPad or Mac binary and
// every .anicel a desktop had saved — its manifest is zstd too — opened
// with 「compressed with zstd and no engine is available to read it」.
// `native_sources_reach_every_platform_test` now pins that every source
// the CMake library compiles has a forwarder in BOTH Apple pods.
#include "../../src/qa_compress.c"
