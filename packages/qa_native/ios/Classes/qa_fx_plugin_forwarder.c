// CocoaPods compiles Classes/ only; the real source lives in src/ shared
// with every other platform. Same pattern as the sibling forwarders.
//
// The fx plugin host (I-132). No WebAssembly engine is linked on Apple
// yet (QA_FX_WASM is undefined, so 0): a plugin's module answers 「no
// engine」 here until one is, and a Mac opens a native build.
#include "../../src/qa_fx_plugin.c"
