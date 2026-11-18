import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/make_fx_sdk.dart';
import '../helpers/dart_sources.dart';

/// tool/make_fx_sdk.dart: the SDK zip as a maker unpacks it — the SDK's
/// files under one folder named for the spec, the example's path to the
/// spec crate leading to the crate.
void main() {
  test('the zip is the SDK, the example beside the crate it names', () {
    final files = {
      for (final file in filesUnder('sdk/fx'))
        file.path.replaceAll(r'\', '/').substring('sdk/fx/'.length):
            file.readAsBytesSync(),
    };
    final zip = sdkZip(files);
    final crate = File('sdk/fx/anicel-fx/src/lib.rs').readAsStringSync();
    final name = sdkName(specOf(crate));
    expect(zip.name, '$name.zip');
    final entries = {
      for (final file in ZipDecoder().decodeBytes(zip.bytes).files)
        if (file.isFile) file.name: file.readBytes(),
    };
    expect(entries.keys.toSet(), {
      for (final path in files.keys) '$name/$path',
    });
    for (final MapEntry(key: path, value: bytes) in files.entries) {
      expect(entries['$name/$path'], bytes, reason: path);
    }
    expect(
      entries.keys,
      containsAll([
        '$name/anicel-fx/src/lib.rs',
        '$name/example/src/lib.rs',
        '$name/README.md',
        '$name/LICENSE',
      ]),
    );
    final manifest = utf8.decode(entries['$name/example/Cargo.toml']!);
    final path = RegExp(
      r'^anicel-fx = \{ path = "([^"]+)" \}',
      multiLine: true,
    ).firstMatch(manifest)![1]!;
    final named = Uri.parse('$name/example/').resolve('$path/Cargo.toml');
    expect(entries.keys, contains(named.path));
  });

  test('the spec is the number the crate says', () {
    expect(specOf('//! x\npub const SPEC_VERSION: u32 = 7;\r\nfn y() {}'), 7);
    expect(() => specOf('pub const SPEC: u32 = 1;'), throwsStateError);
    expect(() => sdkZip({'README.md': [1]}), throwsStateError);
  });
}
