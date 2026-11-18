# Anicel fx plugin SDK — spec 1

Write effects for Anicel in Rust. A plugin is one Rust source built as a
WebAssembly module (`.wasm`), which Anicel runs on every device it runs on —
Windows, Mac, Linux, Android, iPad and iPhone — in a sandbox with no files,
no network and no environment. A desktop can also take a native build of
the same source and run that instead.

| Here | What it is |
| --- | --- |
| `anicel-fx/` | The spec: the one crate a plugin is built against. Its documentation (`cargo doc --open` in that folder) is the spec in full — this page only walks around it. |
| `example/` | A plugin that draws the picture over a coloured shadow of itself. Copy the folder to start your own. |
| `LICENSE` | MIT — for the files of this SDK. It does not cover the Anicel app. |

## Build the example

You need Rust 1.85 or later (`rustup`), and its WebAssembly target once:

```sh
rustup target add wasm32-unknown-unknown
```

In `example/`:

```sh
cargo build --release --target wasm32-unknown-unknown
cargo build --release
```

The first is the module, `target/wasm32-unknown-unknown/release/shadow.wasm`;
the second this machine's native library in `target/release/` —
`shadow.dll`, `libshadow.dylib` or `libshadow.so`. A Mac's file serves
both chips when it is built for each and joined:

```sh
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
lipo -create -output libshadow.dylib \
  target/aarch64-apple-darwin/release/libshadow.dylib \
  target/x86_64-apple-darwin/release/libshadow.dylib
```

## Make the file

An `.anifx` is a zip of the module, named `plugin.wasm`, and the native
builds under `native/`, each named for its machine:

| Entry | |
| --- | --- |
| `plugin.wasm` | The module. Every file has it. |
| `native/windows-x64.dll`, `native/windows-arm64.dll` | Windows builds, each where the plugin has one. |
| `native/macos.dylib` | A Mac build — one file for both chips. |
| `native/linux-x64.so`, `native/linux-arm64.so` | Linux builds. |

On Linux x64, for example, in `example/`:

```sh
mkdir -p pack/native
cp target/wasm32-unknown-unknown/release/shadow.wasm pack/plugin.wasm
cp target/release/libshadow.so pack/native/linux-x64.so
(cd pack && zip -r ../shadow.anifx plugin.wasm native)
```

On Windows x64, in PowerShell — Windows' own `tar` writes the zip, its
entries named with `/` as the app reads them:

```powershell
New-Item -ItemType Directory -Force pack\native
Copy-Item target\wasm32-unknown-unknown\release\shadow.wasm pack\plugin.wasm
Copy-Item target\release\shadow.dll pack\native\windows-x64.dll
tar -C pack --format=zip -cf shadow.anifx plugin.wasm native
```

A file with the module alone is a plugin too — every device runs it. A
device with a native build of its own runs that, and every other device
the module. Both are the same source, so both answer the same.

## Install it in Anicel

Open the `.anifx` with Anicel's **Open**, as any file. Before anything is
installed the app asks `plugin.wasm` who it is — in its sandbox — and shows
its name, maker and parameters; a native build in the file is never opened
before you say yes. Installed, the plugin is offered in the timeline's
**Add effect** menu under a heading of its own, and its parameters are keyed,
graphed and linked as the app's own effects are.

## Writing a plugin

A plugin is a type that is an `anicel_fx::Effect`, exported once with
`anicel_fx::export!`:

- `DESCRIPTION` — UTF-8 JSON with its id, name, maker, version, what it can
  do (`"can"`) and its parameters. The kinds are the app's own: number,
  angle, color, point, checkbox, menu and layer. A description the spec's
  rules reject is no plugin — the app makes nothing up for it.
- `reach` — how many pixels past its input the effect draws (a shadow, a
  glow, a blur). The next render's input is that much wider each way, so
  the effect has room.
- `render` — every pixel of `job.output` from `job.input`, the values and
  the layers. `Err(Failed)` draws the row as if the effect were off; so
  does a panic.

`export!` writes the functions the spec names — and, built as WebAssembly,
the room the app writes a frame into — and checks each frame's spec and
format before your code sees it.

Things every plugin meets:

- **Pixels are premultiplied** 8-bit RGBA, rows top to bottom: no colour is
  above its alpha. Mix in that space.
- **Values are canvas pixels; pictures are output pixels.** A draft renders
  at a `scale` below 1 — multiply a distance by `job.moment.scale`, as the
  example does.
- **A layer parameter** hands the plugin another row's picture:
  `job.values[i].layer()` is its place in `job.layers`, or `None` while no
  row is picked. Its `left` and `top` place it on the same canvas as the
  input, so `Picture::at` reads both at the same canvas place.
- **Frames come in any order** — the app renders the frame a person moves
  to. A render that depends on the one before it is wrong on the next jump.
- **No clock.** A frame draws the same picture whenever it is asked for:
  use `job.moment.time`, never the system's time.
- **Speed.** A desktop, Android and a Mac compile the module to machine
  code as it opens. An iPad or an iPhone makes no machine code as it runs,
  so it interprets the module — many times slower: keep the inner loop
  plain, and ship a native build where a desktop should be fastest.

## Versions

Spec 1 does not change once published: an app that speaks it runs every
spec-1 plugin. What comes later comes as spec 2 — in the frame's
`reserved` room, new kinds and keys in the description, new formats a
plugin names in `"can"` — and a spec-1 plugin still runs.
