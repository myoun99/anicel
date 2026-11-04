// The WebAssembly engine's headers, as every file here includes them — only
// where the build found the engine (QA_FX_WASM).
#ifndef QA_WASMTIME_H
#define QA_WASMTIME_H

// wasm.h asserts its types with static_assert, and this core is C99
// (CMakeLists.txt) and refuses a call to anything undeclared on every
// compiler (/we4013, -Werror=implicit-function-declaration). The two
// families disagree on the word (measured 2026-11-04): MSVC's C takes
// static_assert as it is and refuses _Static_assert, while gcc and clang
// take only C11's _Static_assert, which <assert.h> names static_assert from
// C11 on — so the Android build refused wasm.h and Windows never said so.
#include <assert.h>
#if !defined(__cplusplus) && !defined(static_assert) && defined(__GNUC__)
#define static_assert _Static_assert
#endif

#include <wasi.h>
#include <wasm.h>
#include <wasmtime.h>

#endif
