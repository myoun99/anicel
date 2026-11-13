import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/crate_notices.dart';
import '../../tool/crates_for_host.dart';
import '../helpers/dart_sources.dart';
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

    test('gives its manifest\'s licence and repository and the files beside '
        'it', () {
      File('${folder.path}/Cargo.toml').writeAsStringSync(
        '[package]\nname = "a"\nversion = "1.0.0"\n'
        'license = "MIT OR Apache-2.0"\nreadme = "README.md"\n'
        'repository = "https://example.org/a"\n',
      );
      File('${folder.path}/LICENSE-MIT').writeAsStringSync('mit\n');
      File('${folder.path}/LICENSE-APACHE').writeAsStringSync('apache\n');
      File('${folder.path}/README.md').writeAsStringSync('read me\n');
      final licence = licenceIn(folder);
      expect(licence.expression, 'MIT OR Apache-2.0');
      expect(licence.repository, 'https://example.org/a');
      expect(licence.files, {'LICENSE-APACHE': 'apache\n', 'LICENSE-MIT': 'mit\n'});
      expect(licence.files.keys, ['LICENSE-APACHE', 'LICENSE-MIT']);
    });
  });

  group('the notices', () {
    CrateLicence licence(
      String? expression, [
      Map<String, String>? files,
      String? repository,
    ]) => (
      expression: expression,
      repository: repository,
      files: files ?? const {},
    );

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

    test('order two entries of one first crate by their texts', () {
      // Its files are read by name, so its Apache text comes first.
      final notices = noticesOf({
        'a 1.0.0': licence('MIT OR Apache-2.0', {
          'LICENSE-APACHE': 'zz apache',
          'LICENSE-MIT': 'Copyright A',
        }),
      });
      expect(notices.map((n) => n.text), ['Copyright A', 'zz apache']);
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

    test('list a crate with no file under its repository\'s pinned texts, '
        'ahead of a lent one', () {
      const pinned = {
        'https://example.org/family': ['statement', 'terms'],
      };
      final notices = noticesOf({
        // A sibling would lend it its Apache text: the repository's own
        // comes first.
        'bare 1.0.0': licence('Zlib OR Apache-2.0 OR MIT', null,
            'https://example.org/family'),
        'kin 1.0.0': licence('Zlib OR Apache-2.0 OR MIT', {
          'LICENSE-APACHE': 'apache kin',
        }),
        // MIT alone, which nothing lends: the pinned texts are its.
        'core 1.0.0': licence('MIT', null, 'https://example.org/family'),
        // A file of its own wins over its repository's.
        'own 1.0.0': licence('MIT', {'LICENSE': 'Copyright Own'},
            'https://example.org/family'),
      }, pinned: pinned);
      expect(
        {for (final n in notices) n.text: n.crates},
        {
          'apache kin': ['kin 1.0.0'],
          'Copyright Own': ['own 1.0.0'],
          'statement': ['bare 1.0.0', 'core 1.0.0'],
          'terms': ['bare 1.0.0', 'core 1.0.0'],
        },
      );
      // Another repository's crate is not listed under them.
      expect(
        () => noticesOf({
          'stranger 1.0.0': licence('MIT', null, 'https://example.org/other'),
        }, pinned: pinned),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('stranger 1.0.0 (MIT)'),
        )),
      );
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

    // ↩️The copies were left unnoticed till 2026-11-13 (`shippable`).
    test('give a crate built from the workspace\'s copy the licence in that '
        'copy, and owe a notice for it as for the registry\'s', () {
      final copy = Directory('${registry.path}/vendor/wgpu-hal')
        ..createSync(recursive: true);
      File('${copy.path}/Cargo.toml')
          .writeAsStringSync('[package]\nlicense = "MIT OR Apache-2.0"\n');
      File('${copy.path}/LICENSE.MIT').writeAsStringSync('Copyright W');
      final (:read, :missing) = licencesOf(
        {'wgpu-hal 30.0.1': ['a']},
        [registry],
        copies: {'wgpu-hal 30.0.1': copy},
      );
      expect(missing, isEmpty);
      expect(read.values.single.files, {'LICENSE.MIT': 'Copyright W'});
      final lock = lockPackages(
        '\n[[package]]\nname = "engine"\nversion = "0.1.0"\n'
        '\n[[package]]\nname = "wgpu-hal"\nversion = "30.0.1"\n',
      );
      expect(shippable(lock, {'wgpu-hal 30.0.1'}), {'wgpu-hal 30.0.1'});
      expect(shippable(lock, const {}), isEmpty);
    });
  });

  test('the pinned licences are the files tool/crate_licences/ holds', () {
    final held = [
      for (final file in filesUnder('tool/crate_licences'))
        file.path.replaceAll(r'\', '/'),
    ]..sort();
    final named = [
      for (final MapEntry(key: repository, value: files)
          in pinnedLicences.entries)
        for (final name in files.keys) '${pinnedFolder(repository)}/$name',
    ]..sort();
    expect(held, named);
    expect(
      held,
      contains('tool/crate_licences/github.com/madsmtm/objc2/LICENSE.md'),
    );
    for (final texts in pinnedTexts().values) {
      for (final text in texts) {
        expect(text, isNotEmpty);
      }
    }
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
