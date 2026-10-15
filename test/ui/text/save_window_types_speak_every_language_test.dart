import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    show XTypeGroup;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/persistence/file_type_groups.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';

import '../../helpers/dart_sources.dart';

/// Every file type a save window is handed has a name in every translated
/// table (F-273, 2026-10-14: the brush export's window said 「Anicel brush」
/// whatever the app spoke).
///
/// The types are FOUND, not listed: every `acceptedTypeGroups:` in lib that
/// names a group is a save window's (an opening one passes none —
/// `every_picker_shows_every_file_test`).
///
/// ⚠️「Tabled」 is asked with a fallback no row can equal, never as 「differs
/// from English」.
void main() {
  /// The groups by the name lib hands them over by. ★A save window handed a
  /// group not here goes red until it is added — and then it is asked.
  const groupsByName = {
    'anicelProject': FileTypeGroups.anicelProject,
    'wav': FileTypeGroups.wav,
    'anicelBrush': FileTypeGroups.anicelBrush,
  };

  final handed = <String>{
    for (final file in dartFilesUnder('lib'))
      for (final line in file.readAsStringSync().split('\n'))
        if (line.trim().startsWith('acceptedTypeGroups:'))
          for (final named in RegExp(
            r'FileTypeGroups\.(\w+)',
          ).allMatches(line))
            named.group(1)!,
  };

  test('the save windows are found, and every group they are handed is '
      'known here', () {
    expect(handed, hasLength(greaterThanOrEqualTo(3)));
    expect(handed.difference(groupsByName.keys.toSet()), isEmpty);
  });

  const untabled = ' ';
  for (final language in const [
    AppLanguage.ja,
    AppLanguage.ko,
    AppLanguage.fr,
    AppLanguage.zhHans,
  ]) {
    test('${language.name} names every type a save window is handed', () {
      expect([
        for (final name in handed)
          if (XTypeGroup(
                label: untabled,
                extensions: groupsByName[name]?.extensions,
              ).labelledFor(language).label ==
              untabled)
            name,
      ], isEmpty);
    });
  }
}
