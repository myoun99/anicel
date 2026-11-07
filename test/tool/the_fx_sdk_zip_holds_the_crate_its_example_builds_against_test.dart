import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/make_fx_sdk.dart';
import '../helpers/temp_dir.dart';

/// tool/make_fx_sdk.dart: the SDK zip as a maker unpacks it — sdk/fx as
/// committed under one folder named for the spec, the example's path to the
/// spec crate leading to the crate.
void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('fx-sdk'));
  tearDown(() => deleteTempQuietly(folder));

  test('the zip is sdk/fx, the example beside the crate it names', () {
    final zip = File(makeSdk(folder.path));
    final name = sdkName(specOf(File(specCrateSource).readAsStringSync()));
    expect(zip.uri.pathSegments.last, '$name.zip');
    final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    final files = {
      for (final file in archive.files)
        if (file.isFile) file.name,
    };
    final committed = Process.runSync('git', [
      'ls-tree',
      '-r',
      '--name-only',
      'HEAD',
      '$sdkFolder/',
    ]).stdout as String;
    expect(files, {
      for (final path in const LineSplitter().convert(committed))
        '$name/${path.substring(sdkFolder.length + 1)}',
    });
    expect(
      files,
      containsAll([
        '$name/anicel-fx/src/lib.rs',
        '$name/example/src/lib.rs',
        '$name/README.md',
        '$name/LICENSE',
      ]),
    );
    final manifest = utf8.decode(
      archive.findFile('$name/example/Cargo.toml')!.readBytes()!,
    );
    final path = RegExp(
      r'^anicel-fx = \{ path = "([^"]+)" \}',
      multiLine: true,
    ).firstMatch(manifest)![1]!;
    final crate = Uri.parse('$name/example/').resolve('$path/Cargo.toml');
    expect(files, contains(crate.path));
  });

  test('the spec is the number the crate says', () {
    expect(specOf('//! x\npub const SPEC_VERSION: u32 = 7;\r\nfn y() {}'), 7);
    expect(() => specOf('pub const SPEC: u32 = 1;'), throwsStateError);
  });
}
