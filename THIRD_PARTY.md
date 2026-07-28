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

## Assets

The app ships no third-party artwork, brush files, sound files or fonts.
Sample/preset files sourced from other applications must never be
committed or bundled.
