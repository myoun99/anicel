// Packs the Anicel fx plugin SDK into the one zip the site offers
// (fx-plugin-sdk-publish: the site's developer page and an SDK zip, no link
// to this repository):
//
//   dart run tool/make_fx_sdk.dart <folder>
//
// writes <folder>/anicel-fx-sdk-<spec>.zip — sdk/fx of the commit checked
// out, every file as committed, under one folder: the spec crate, the
// example, the README and the LICENSE, lying as they lie here, so the
// example's path to the crate holds in the zip as in the repository. The
// spec is the crate's own SPEC_VERSION.
//
// ↩️It was sdk/fx/make_sdk.cmake while the spec was a C header; the SDK is
// Rust now (유저 Q9 · 옛 플러그인 없음, 2026-11-07), and this repository's
// tools are Dart.

import 'dart:io';

/// The SDK's folder in the repository.
const sdkFolder = 'sdk/fx';

/// Where the spec crate's source lies in the repository.
const specCrateSource = '$sdkFolder/anicel-fx/src/lib.rs';

/// The spec version [crateSource] — the spec crate's lib.rs — says.
int specOf(String crateSource) {
  final said = RegExp(
    r'^pub const SPEC_VERSION: u32 = (\d+);\r?$',
    multiLine: true,
  ).firstMatch(crateSource);
  if (said == null) throw StateError('$specCrateSource says no SPEC_VERSION');
  return int.parse(said[1]!);
}

/// The zip's folder, and the file's name without `.zip`.
String sdkName(int spec) => 'anicel-fx-sdk-$spec';

/// What git is asked to write [out]: the SDK folder of [commit], each file
/// as committed — not as this checkout's line endings make it — under the
/// zip's [folder].
List<String> archiveArguments(String commit, String folder, String out) => [
  '-c',
  'core.autocrlf=false',
  'archive',
  '--format=zip',
  '--prefix=$folder/',
  '-o',
  out,
  '$commit:$sdkFolder',
];

String _git(List<String> arguments) {
  final run = Process.runSync('git', arguments);
  if (run.exitCode != 0) {
    throw ProcessException('git', arguments, '${run.stderr}', run.exitCode);
  }
  return '${run.stdout}';
}

/// Writes the SDK zip of [commit] into [folder]; its path.
String makeSdk(String folder, {String commit = 'HEAD'}) {
  final spec = specOf(_git(['show', '$commit:$specCrateSource']));
  final name = sdkName(spec);
  final out = '$folder/$name.zip';
  File(out).parent.createSync(recursive: true);
  _git(archiveArguments(commit, name, out));
  return out;
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/make_fx_sdk.dart <folder>');
    exit(64);
  }
  stdout.writeln(makeSdk(args.single));
}
