// CocoaPods compiles Classes/ only; the real source lives in src/ shared
// with every other platform. Same pattern as the sibling forwarders.
//
// The single-file zstd amalgamation qa_compress.c links against. Its own
// quoted includes (zstd.h, zdict.h) resolve beside it, as every forwarded
// source's do. See qa_compress_forwarder.c for why this was missing.
#include "../../src/third_party/zstd/zstd.c"
