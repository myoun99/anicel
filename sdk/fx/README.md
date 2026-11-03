# Anicel fx plugin SDK — spec 1

Write effects for Anicel in C. A plugin is one C
source built as a WebAssembly module (`.wasm`), which Anicel runs on every
device it runs on — Windows, Mac, Linux, Android and iPad — in a sandbox
with no files, no network and no environment. A desktop can also take a
native build of the same source and run that instead.

| Here | What it is |
| --- | --- |
| `include/anicel_fx_plugin.h` | The spec: the one header a plugin is built against. Read it first — this page only walks around it. |
| `example/shadow.c` | A plugin that draws the picture over a coloured shadow of itself. |
| `example/CMakeLists.txt` | Builds the example as `plugin.wasm` and as this machine's native library, and packs both into `shadow.anifx`. |
| `LICENSE` | MIT — for the files of this SDK. It does not cover the Anicel app. |

## Build the example

You need CMake 3.20 or later and a clang with the `wasm32` target and
`wasm-ld` beside it: LLVM's own release, WASI SDK's, or the Android NDK's.
Apple's clang has no `wasm32` target; on a Mac use LLVM (Homebrew `llvm`)
or WASI SDK. The native build uses this machine's usual C compiler.

```sh
cmake -S example -B build -DANICEL_FX_CLANG=/path/to/clang
cmake --build build --config Release
```

`build/shadow.anifx` is the plugin. Add `-DANICEL_FX_NATIVE=OFF` for a file
with the module alone — every device runs it.

The example uses no C library, so plain clang builds it. A plugin that
wants one (`malloc`, `sinf`, …) builds against WASI SDK's:

```sh
cmake -S example -B build \
  -DANICEL_FX_CLANG=<wasi-sdk>/bin/clang \
  -DANICEL_FX_WASI_SYSROOT=<wasi-sdk>/share/wasi-sysroot
```

The module is then a WASI reactor: Anicel starts its C library
(`_initialize`) before asking it anything, and links WASI with nothing
behind it — a plugin that opens a file or reads the clock finds none.

## Install it in Anicel

Open the `.anifx` with Anicel's **Open**, as any file. Before anything is
installed the app asks `plugin.wasm` who it is — in its sandbox — and shows
its name, maker and parameters; a native build in the file is never opened
before you say yes. Installed, the plugin is offered in the timeline's
**Add effect** menu under a heading of its own, and its parameters are keyed,
graphed and linked as the app's own effects are.

## Writing a plugin

A plugin exports four functions, and a `.wasm` two things more. The header
says each in full; in short:

- `anicel_fx_spec` — `ANICEL_FX_SPEC_VERSION`, the spec it was built for.
- `anicel_fx_describe` — its description: UTF-8 JSON with its id, name,
  maker, version, what it can do (`"can"`) and its parameters. The kinds are
  the app's own: number, angle, color, point, checkbox, menu and layer. A
  description the header's rules reject is no plugin — the app makes
  nothing up for it.
- `anicel_fx_reach` — how many pixels past its input the effect draws (a
  shadow, a glow, a blur). The next render's input is that much wider each
  way, so the effect has room.
- `anicel_fx_render` — every pixel of `frame->output` from `frame->input`,
  the values and the layers. Return 0; anything else draws the row as if the
  effect were off.
- A `.wasm` also exports its memory as `memory`, and `anicel_fx_alloc` for
  the room the app writes a frame into — `ANICEL_FX_DEFINE_ALLOC()` once
  in one source is one.

Things every plugin meets:

- **Pixels are premultiplied** 8-bit RGBA, rows top to bottom: no colour is
  above its alpha. Mix in that space.
- **Nothing is a pointer.** Every place in the frame is a byte distance from
  the frame; reach pictures and values through `anicel_fx_pixels`,
  `anicel_fx_values` and `anicel_fx_layers`.
- **Values are canvas pixels; pictures are output pixels.** A draft renders
  at a `scale` below 1 — multiply a distance by `frame->scale`, as the
  example does.
- **A layer parameter** hands the plugin another row's picture: its value is
  that picture's place in the frame's layers, or -1 while no row is picked.
  Its `left` and `top` place it on the same canvas as the input.
- **Frames come in any order** — the app renders the frame a person moves
  to. A render that depends on the one before it is wrong on the next jump.
- **Speed.** A desktop, Android and a Mac compile the module to machine
  code as it opens. An iPad makes no machine code as it runs, so it
  interprets the module — many times slower: keep the inner loop plain, and
  ship a native build where a desktop should be fastest.

## The file

An `.anifx` is a zip:

| Entry | |
| --- | --- |
| `plugin.wasm` | The module. Every file has it. |
| `native/windows-x64.dll`, `native/windows-arm64.dll` | Windows builds, each where the plugin has one. |
| `native/macos.dylib` | A Mac build — one file for both chips (a universal library). |
| `native/linux-x64.so`, `native/linux-arm64.so` | Linux builds. |

A device with a native build of its own runs that, and every other device
the module. Both are the same source, so both answer the same.

## Versions

Spec 1 does not change once published: an app that speaks it runs every
spec-1 plugin. What comes later comes as spec 2 — in the frame's
`reserved` room, new kinds and keys in the description, new formats a
plugin names in `"can"` — and a spec-1 plugin still runs.
