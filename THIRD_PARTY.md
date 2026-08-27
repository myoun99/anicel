# Third-party components

Anicel itself is **all rights reserved** (see `LICENSE`). The
components listed here are other people's work and keep their own
licenses — those licenses govern those components, not this project.

## Dart / Flutter packages

Declared in `pubspec.yaml` and resolved by `pub`. They are NOT vendored
into this repository; each package carries its own license in the pub
cache, and `flutter pub deps` lists the full set. The Flutter SDK and
Dart SDK are licensed by Google under the BSD 3-Clause license.

## Vendored native sources

None yet.

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

## Assets

### Bundled fonts (`assets/fonts/`)

Four OFL families ship, in two roles. **The app UI's own** (유저 확정
2026-08-28) — BIZ UDPGothic draws Japanese, Latin, French accents and
kanji; 나눔고딕 draws Hangul behind it. **The conte PDF's**, embedded into
exported files only — M PLUS 1p and IBM Plex Sans KR.

All are licensed under the **SIL Open Font License 1.1** (OFL), obtained
from the Google Fonts collection (`github.com/google/fonts`, `ofl/` tree):

| File | Family | Copyright | Role |
| --- | --- | --- | --- |
| `BIZUDPGothic-Regular.ttf` | BIZ UDPGothic | The BIZ UDGothic Project Authors | 앱 UI |
| `BIZUDPGothic-Bold.ttf` | BIZ UDPGothic | The BIZ UDGothic Project Authors | 앱 UI |
| `NanumGothic-Regular.ttf` | Nanum Gothic | NHN Corporation | 앱 UI |
| `NanumGothic-Bold.ttf` | Nanum Gothic | NHN Corporation | 앱 UI |
| `MPLUS1p-Regular.ttf` | M PLUS 1p | The M+ FONTS Project Authors | 콘티 PDF |
| `MPLUS1p-Bold.ttf` | M PLUS 1p | The M+ FONTS Project Authors | 콘티 PDF |
| `IBMPlexSansKR-Regular.ttf` | IBM Plex Sans KR | IBM Corp. | 콘티 PDF |

The OFL permits bundling and embedding; the fonts remain under their own
license, and their reserved font names are not used for any derivative.
License text: <https://openfontlicense.org>.

Beyond those fonts the app ships no third-party artwork, brush files or
sound files. Sample/preset files sourced from other applications must
never be committed or bundled.
