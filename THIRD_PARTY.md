# Third-party components

Anicel itself is **all rights reserved** (see `LICENSE`). The
components listed here are other people's work and keep their own
licenses — those licenses govern those components, not this project.

## Dart / Flutter packages

Declared in `pubspec.yaml` and resolved by `pub`. They are NOT vendored
into this repository; each package carries its own license in the pub
cache, and `flutter pub deps` lists the full set. The Flutter SDK and
Dart SDK are licensed by Google under the BSD 3-Clause license.

## Rust crates (the GPU engine)

Declared in `packages/gpu_engine/rust`'s manifests and resolved into its
`Cargo.lock`; they are NOT vendored (but Symphonia's four, below) — cargo
fetches each from crates.io. Every registry crate the engine's library
carries on a target of its `rust-toolchain.toml` is listed, under the
licence text it ships, in `assets/licenses/rust_crates.json`, and the
app's About ▸ licenses screen shows that list. `tool/crate_notices.dart`
writes it from the lock — run it again when the lock changes;
`test/every_crate_the_engine_ships_is_noticed_test.dart` turns red until
then. A crate that ships no licence file is listed under the Apache-2.0
text of a crate declaring the same licence; one under a licence that
offers no Apache-2.0 stops the tool for a person to look at.

## Vendored native sources

### Symphonia (four crates, modified)

The Rust audio decoders of the engine's audio crate
(`packages/gpu_engine/rust/native/audio`): `symphonia-core`,
`symphonia-codec-aac`, `symphonia-bundle-mp3` and `symphonia-codec-vorbis`
**0.6.1**, as published on crates.io from
`github.com/pdeljanov/Symphonia` commit
`ee35874b571a35a9a6e15d3bc9a3aaf8f11fbeee` (each folder's
`.cargo_vcs_info.json`). Vendored at `packages/gpu_engine/rust/vendor/` and
used through the workspace's `[patch.crates-io]`; symphonia's other crates
come from crates.io unmodified. **Mozilla Public License 2.0** — the text
is each folder's `LICENSE`.

**Modified** (유저 native-to-rust-Q14, 2026-11-07), so that a sound decodes
to the same samples on every device: fifteen source files call the `libm`
crate where they called Rust's float methods (`sin` · `cos` · `tan` ·
`powf` · `exp` · `atan`, which use the device's maths library); the four
`lib.rs` read `QA_CHECKOUT` as every crate of the workspace does; the four
`Cargo.toml` depend on `libm`. Each modified source file says so under its
MPL header. As MPL-2.0 asks, the source of these files is offered with the
app: it is this repository, which the release links to (유저 Q14).

Not in a shipped binary yet — the audio crate is linked into the engine in
the connection round. That round adds an MPL-2.0 entry to the app's
About ▸ licenses screen, saying where the source is.

> When native third-party sources are vendored into `native/` (or into a
> platform plugin package), each one gets an entry here with: what it is,
> where it came from, its version/commit, and its license text or a path
> to it. A component whose license requires a notice in shipped binaries
> must also appear in the app's about/licenses screen.

## Downloaded native binaries

### PDFium

Chromium's PDF rendering engine. Its upstream `LICENSE` carries a
**BSD 3-Clause notice followed by the Apache License 2.0**; the full
text is bundled at `assets/licenses/LICENSE-PDFium.txt` and surfaced in
the app's About ▸ licenses screen (binary redistribution requires the
notice to ship). Not vendored:
the `pdfrx` package's build hook downloads prebuilt binaries at build
time — `pdfium.dll` / `libpdfium.so` / `libpdfium.dylib` from
`github.com/bblanchon/pdfium-binaries` releases (Android, Windows,
Linux, macOS), and an XCFramework from
`github.com/espresso3389/pdfium-xcframework` (iOS/macOS via
CocoaPods/SwiftPM) — and bundles them with the app. The pinned release
tag lives in the `pdfium_dart`/`pdfium_flutter` package versions in
`pubspec.lock`. License text:
<https://pdfium.googlesource.com/pdfium/+/main/LICENSE>. The pdfrx
packages themselves are MIT (covered by the pub-packages section
above).

### Wasmtime

The Bytecode Alliance's WebAssembly runtime — the sandbox the fx
plugins' modules run in (I-132). **Apache License 2.0 with LLVM
exceptions**; the full text is bundled at
`assets/licenses/LICENSE-Wasmtime.txt` and surfaced in the app's
About ▸ licenses screen. Not vendored: the engine's CMake build
(`packages/qa_native/src/CMakeLists.txt`) downloads the official
prebuilt C API release once per machine — version and SHA-256 pinned
there (`QA_WASMTIME_VERSION`) — from
`github.com/bytecodealliance/wasmtime` releases, and links its static
library into the engine. Windows x64 only for now.

### DirectX Shader Compiler

Microsoft's shader compiler — `dxcompiler.dll`, which the GPU engine
compiles its DX12 shaders with (gpu-engine-feasibility-Q4 · Q5), ships
beside the engine on Windows (x64 and ARM64). Not vendored: the engine's
`packages/gpu_engine/rust/build.rs` downloads the release zip
`dxc_2026_09_29.zip` (v1.9.2609) from
`github.com/microsoft/DirectXShaderCompiler` releases — the zip's and
each DLL's SHA-256 pinned there — and the build hook bundles the DLL.
The zip ships three licence texts and does not say which file each
covers: **the LLVM Release License (University of Illinois/NCSA), an
MIT License (© Microsoft Corporation) and the Microsoft Software
License Terms for the DirectX Shader Compiler**. All three are bundled
as the zip has them, at `assets/licenses/LICENSE-DXC-LLVM.txt`,
`LICENSE-DXC-MIT.txt` and `LICENSE-DXC-MS.txt`, and surfaced together in
the app's About ▸ licenses screen; `build.rs` pins each text's digest, so
a newer zip with other texts fails the build until they are bundled.
The DLL itself is read as under the LLVM licence, as Microsoft labels its
NuGet package of it, and the Microsoft terms as the closed-source
`dxil.dll`'s, which the app does not ship — so the three texts are its
notice and no agreement to the terms is asked (유저 2026-11-07,
gpu-engine-feasibility-Q6).

## Assets

### Bundled fonts (`assets/fonts/`)

Three OFL families ship. Two are **the app's own** (유저 확정 2026-08-28):
BIZ UDPGothic draws Japanese, Latin, French accents and kanji; 나눔고딕 draws
Hangul behind it. The conte PDF embeds the same two into exported files
(2026-09-25; it used to ship M PLUS 1p and IBM Plex Sans KR for that). The
third, Noto Sans SC, draws the Chinese UI in front of those two (유저
2026-11-05).

All are licensed under the **SIL Open Font License 1.1** (OFL), obtained
from the Google Fonts collection (`github.com/google/fonts`, `ofl/` tree):

| File | Family | Copyright | Role |
| --- | --- | --- | --- |
| `BIZUDPGothic-Regular.ttf` | BIZ UDPGothic | The BIZ UDGothic Project Authors | 앱 UI · 콘티 PDF |
| `BIZUDPGothic-Bold.ttf` | BIZ UDPGothic | The BIZ UDGothic Project Authors | 앱 UI · 콘티 PDF |
| `NanumGothic-Regular.ttf` | Nanum Gothic | NHN Corporation | 앱 UI · 콘티 PDF |
| `NanumGothic-Bold.ttf` | Nanum Gothic | NHN Corporation | 앱 UI · 콘티 PDF |
| `NotoSansSC-Variable.ttf` | Noto Sans SC | Adobe (Reserved Font Name 'Source') | 중국어 앱 UI |

**The two `BIZUDPGothic-*.ttf` files are a modified version**: U+007E is taken
out of their cmaps, so that 나눔고딕 draws the keyboard's `~` in the middle of a
line (유저 2026-11-01, F-524-Q1) — the glyphs and every other table are as
obtained. BIZ UDPGothic declares no reserved font name.

`NotoSansSC-Variable.ttf` is Google Fonts' `NotoSansSC[wght].ttf` as obtained,
renamed only; its license text is `OFL-NotoSansSC.txt`, the `OFL.txt` beside
it there.

The OFL permits bundling and embedding; the fonts remain under their own
license, and their reserved font names are not used for any derivative.
License text: <https://openfontlicense.org>.

Beyond those fonts the app ships no third-party artwork, brush files or
sound files. Sample/preset files sourced from other applications must
never be committed or bundled.
