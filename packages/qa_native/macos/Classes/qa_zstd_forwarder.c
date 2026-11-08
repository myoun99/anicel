// CocoaPods compiles Classes/ only; the real source lives in src/ shared
// with every other platform. Same pattern as the sibling forwarders.
//
// The single-file zstd amalgamation qa_media_span.c links against. Its own
// quoted includes (zstd.h, zdict.h) resolve beside it, as every forwarded
// source's do. 🚨It was missing from 2026-08-30 to 2026-09-13, beside the
// C compressor's forwarder, and an iPad opened no project a desktop had
// saved; `native_sources_reach_every_platform_test` pins it now.
// ↩️qa_compress.c linked against it too until the connection round
// (connection-round-checklist H) moved the compressor into the Rust engine.
#include "../../src/third_party/zstd/zstd.c"
