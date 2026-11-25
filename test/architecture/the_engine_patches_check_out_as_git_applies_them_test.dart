import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/git_attributes.dart';

/// 🚨A patch handed back with CRLF does not apply.
///
/// The Flutter engine Anicel builds for itself is Flutter's own at a pinned
/// version with the patches of `tool/flutter_engine/<version>` laid on it
/// (🗣️유저 2026-11-22, board a-real-gpu-reset-went-unheard-on-the-main-pc:
/// the engine is mended, and laying the patches on again at each upgrade is
/// a cost taken). `git apply` reads a patch's context lines byte for byte
/// and the engine's sources are LF in git, while `core.autocrlf` is on for
/// this checkout — so git would hand a patch back with Windows line endings
/// and every hunk of it would be refused.
///
/// The rule lives in `.gitattributes`; this checks it covers every patch
/// kept there, as the plugin registrants' test does for its files.
void main() {
  test('every patch of the engine Anicel builds checks out as LF', () {
    final patches = <String>[
      for (final file in filesUnder('tool/flutter_engine'))
        if (file.path.endsWith('.patch')) file.path.replaceAll(r'\', '/'),
    ];
    expect(
      patches,
      isNotEmpty,
      reason: 'fixture: tool/flutter_engine keeps the engine\'s patches',
    );

    final eolOf = eolRulesOf('.gitattributes');
    expect(
      [
        for (final path in patches)
          if (eolOf(path) != 'lf') '$path: eol=${eolOf(path)}',
      ],
      isEmpty,
      reason: '`git apply` refuses a patch whose context lines end in CRLF '
          'against LF sources — cover it with the patch rule of '
          '`.gitattributes`',
    );
  });
}
