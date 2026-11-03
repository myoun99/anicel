// CocoaPods compiles Classes/ only; the real source lives in src/ shared
// with every other platform. Same pattern as the sibling forwarders.
//
// The fx plugin host (I-132), with the WebAssembly engine the podspec links
// (QA_FX_WASM).
#include "../../src/qa_fx_plugin.c"
