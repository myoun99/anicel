import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/crate_notices.dart';
import '../helpers/temp_dir.dart';

/// tool/crate_notices.dart: which targets, which files, which text a crate
/// is listed under, and the file's shape both ways.
void main() {
  test('the targets are the toolchain file\'s', () {
    const toml = '[toolchain]\nchannel = "1.99.1"\ntargets = [\n'
        '  "aarch64-linux-android",\n  "x86_64-pc-windows-msvc",\n]\n';
    expect(toolchainTargets(toml), [
      'aarch64-linux-android',
      'x86_64-pc-windows-msvc',
    ]);
    expect(() => toolchainTargets('[toolchain]\n'), throwsFormatException);
  });

  test('a licence file is named as crates name one', () {
    for (final name in [
      'LICENSE',
      'LICENSE-MIT',
      'license-apache.txt',
      'LICENCE',
      'COPYING',
      'COPYRIGHT',
      'NOTICE',
      'UNLICENSE',
    ]) {
      expect(isLicenceFile(name), isTrue, reason: name);
    }
    for (final name in ['README.md', 'Cargo.toml', 'src', 'CHANGELOG.md']) {
      expect(isLicenceFile(name), isFalse, reason: name);
    }
  });

  group('a crate\'s source', () {
    late Directory folder;
    setUp(() => folder = Directory.systemTemp.createTempSync('crate-source'));
    tearDown(() => deleteTempQuietly(folder));

    test('gives its manifest\'s licence and the files beside it', () {
      File('${folder.path}/Cargo.toml').writeAsStringSync(
        '[package]\nname = "a"\nversion = "1.0.0"\n'
        'license = "MIT OR Apache-2.0"\nreadme = "README.md"\n',
      );
      File('${folder.path}/LICENSE-MIT').writeAsStringSync('mit\n');
      File('${folder.path}/LICENSE-APACHE').writeAsStringSync('apache\n');
      File('${folder.path}/README.md').writeAsStringSync('read me\n');
      final licence = licenceIn(folder);
      expect(licence.expression, 'MIT OR Apache-2.0');
      expect(licence.files, {'LICENSE-APACHE': 'apache\n', 'LICENSE-MIT': 'mit\n'});
      expect(licence.files.keys, ['LICENSE-APACHE', 'LICENSE-MIT']);
    });
  });

  group('the notices', () {
    CrateLicence licence(String? expression, [Map<String, String>? files]) =>
        (expression: expression, files: files ?? const {});

    test('list a crate under each text it ships, and a text once', () {
      final notices = noticesOf({
        'two 1.0.0': licence('MIT OR Apache-2.0', {
          'LICENSE-APACHE': '\n  apache  \n',
          'LICENSE-MIT': 'Copyright Two\n',
        }),
        'one 1.0.0': licence('Apache-2.0', {'LICENSE': 'apache'}),
        // The same text in two files of one crate names the crate once.
        'twice 1.0.0': licence('Apache-2.0', {
          'LICENSE': 'apache',
          'LICENSE-APACHE': 'apache\n',
        }),
      });
      expect(notices.map((n) => n.crates), [
        ['one 1.0.0', 'twice 1.0.0', 'two 1.0.0'],
        ['two 1.0.0'],
      ]);
      expect(notices.map((n) => n.text), ['apache', 'Copyright Two']);
    });

    test('list the crates of one text under one entry, by first crate', () {
      final notices = noticesOf({
        'zeta 1.0.0': licence('MIT', {'LICENSE': 'Copyright Zeta'}),
        'beta 2.0.0': licence('MIT', {'LICENSE': 'Copyright Alpha'}),
        'alpha 1.0.0': licence('MIT', {'LICENSE': 'Copyright Alpha'}),
      });
      expect(notices.map((n) => n.crates), [
        ['alpha 1.0.0', 'beta 2.0.0'],
        ['zeta 1.0.0'],
      ]);
      expect(notices.map((n) => n.text), ['Copyright Alpha', 'Copyright Zeta']);
    });

    test('lend a crate with no file the first sibling\'s Apache text alone', () {
      final notices = noticesOf({
        'bare 1.0.0': licence('MIT OR Apache-2.0'),
        'b 1.0.0': licence('MIT OR Apache-2.0', {
          'LICENSE-APACHE': 'apache b',
          'LICENSE-MIT': 'Copyright B',
        }),
        'a 1.0.0': licence('MIT OR Apache-2.0', {
          'LICENSE-APACHE': 'apache a',
          'LICENSE-MIT': 'Copyright A',
        }),
      });
      final bare = notices.singleWhere((n) => n.crates.contains('bare 1.0.0'));
      expect(bare.crates, ['a 1.0.0', 'bare 1.0.0']);
      expect(bare.text, 'apache a');
    });

    test('lend a crate with no file the one file of Apache alone', () {
      final notices = noticesOf({
        'bare 1.0.0': licence('Apache-2.0 WITH LLVM-exception'),
        'family 1.0.0': licence('Apache-2.0 WITH LLVM-exception', {
          'LICENSE': 'apache with llvm',
        }),
      });
      expect(notices.single.crates, ['bare 1.0.0', 'family 1.0.0']);
      expect(notices.single.text, 'apache with llvm');
    });

    test('lend no text that may carry another crate\'s copyright', () {
      for (final (bare, kin) in [
        // BSD: every text names its own owner.
        (licence('BSD-3-Clause'), licence('BSD-3-Clause', {'COPYING': 'bsd'})),
        // A choice whose sibling's one file may be its MIT text.
        (
          licence('MIT OR Apache-2.0'),
          licence('MIT OR Apache-2.0', {'LICENSE': 'Copyright Kin'}),
        ),
      ]) {
        expect(
          () => noticesOf({'bare 1.0.0': bare, 'kin 1.0.0': kin}),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('bare 1.0.0 (${bare.expression})'),
          )),
        );
      }
    });

    test('refuse a crate no text can be found for', () {
      expect(
        () => noticesOf({
          'orphan 1.0.0': licence('Apache-2.0'),
          // Another licence's Apache file is not this licence's text.
          'other 1.0.0': licence('MIT OR Apache-2.0', {'LICENSE-APACHE': 'a'}),
        }),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('orphan 1.0.0 (Apache-2.0)'),
        )),
      );
    });
  });

  group('the registry\'s sources', () {
    late Directory registry;
    setUp(() => registry = Directory.systemTemp.createTempSync('crate-src'));
    tearDown(() => deleteTempQuietly(registry));

    test('give each crate found under its folder its licence, and count by '
        'target the crates not here', () {
      final source = Directory('${registry.path}/index.crates.io-x')
        ..createSync();
      // A version that holds `-1.1.0`, and a name that holds `-5`.
      final crate = Directory('${source.path}/toml_edit-0.25.18+spec-1.1.0')
        ..createSync();
      File('${crate.path}/Cargo.toml')
          .writeAsStringSync('[package]\nlicense = "MIT"\n');
      File('${crate.path}/LICENSE').writeAsStringSync('Copyright T');
      final (:read, :missing) = licencesOf({
        'toml_edit 0.25.18+spec-1.1.0': ['a', 'b'],
        'md-5 0.10.6': ['a'],
      }, [Directory('${registry.path}/elsewhere'), source]);
      expect(read.keys, ['toml_edit 0.25.18+spec-1.1.0']);
      expect(read.values.single.expression, 'MIT');
      expect(read.values.single.files, {'LICENSE': 'Copyright T'});
      expect(missing, {'a': 1});
      expect(folderOf('md-5 0.10.6'), 'md-5-0.10.6');
    });
  });

  test('the file reads back what was written', () {
    final file = noticesFile(
      ['x86_64-pc-windows-msvc'],
      [
        (crates: ['a 1.0.0', 'b 1.0.0'], text: 'one'),
        (crates: ['a 1.0.0', 'c 1.0.0'], text: 'two'),
      ],
      {'z 1.0.0', 'y 1.0.0'},
    );
    final read = noticedCrates(file);
    expect(read.targets, ['x86_64-pc-windows-msvc']);
    // A crate under two texts is one crate noticed.
    expect(read.noticed, ['a 1.0.0', 'b 1.0.0', 'c 1.0.0']);
    expect(read.unshipped, ['y 1.0.0', 'z 1.0.0']);
  });
}
