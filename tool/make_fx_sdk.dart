// Packs the Anicel fx plugin SDK into the one zip the site offers
// (fx-plugin-sdk-publish: the site's developer page and an SDK zip, no link
// to this repository):
//
//   dart tool/make_fx_sdk.dart <folder>
//
// writes <folder>/anicel-fx-sdk-<spec>.zip — the files of sdk/fx git
// tracks, as this checkout holds them, under one folder: the spec crate,
// the example, the README and the LICENSE, lying as they lie here, so the
// example's path to the crate holds in the zip as in the repository. The
// spec is the crate's own SPEC_VERSION.
//
// ↩️It was sdk/fx/make_sdk.cmake while the spec was a C header; the SDK is
// Rust now (유저 Q9 · 옛 플러그인 없음, 2026-11-07), and this repository's
// tools are Dart.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The SDK's folder in the repository.
const sdkFolder = 'sdk/fx';

/// Where the spec crate's source lies in the SDK.
const specCrateSource = 'anicel-fx/src/lib.rs';

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

/// The SDK zip of [files] — each one's path in the SDK and its bytes —
/// under one folder named for the spec its crate says.
({String name, Uint8List bytes}) sdkZip(Map<String, List<int>> files) {
  final crate = files[specCrateSource];
  if (crate == null) throw StateError('no $specCrateSource in the SDK');
  final name = sdkName(specOf(utf8.decode(crate)));
  final archive = Archive();
  for (final MapEntry(key: path, value: bytes) in files.entries) {
    archive.addFile(ArchiveFile.bytes('$name/$path', bytes));
  }
  return (name: '$name.zip', bytes: ZipEncoder().encodeBytes(archive));
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart tool/make_fx_sdk.dart <folder>');
    exit(64);
  }
  final listed = Process.runSync('git', ['ls-files', '-z', '--', sdkFolder]);
  if (listed.exitCode != 0) {
    stderr.writeln('git ls-files: ${listed.stderr}');
    exit(1);
  }
  final files = {
    for (final path in '${listed.stdout}'.split('\x00'))
      if (path.isNotEmpty)
        path.substring(sdkFolder.length + 1): File(path).readAsBytesSync(),
  };
  final zip = sdkZip(files);
  final out = File('${args.single}/${zip.name}');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(zip.bytes);
  stdout.writeln(out.path);
}
