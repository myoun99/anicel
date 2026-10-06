import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🗣️유저 2026-08-29: 「픽커는 어떤플랫폼이든 어떤 확장자던 선택할수
/// 있게하고, 대응만 지원안되는 확장자면 그 때 해당 파일 지원안된다고 안내창
/// 띄우게」.
///
/// The dialog that offers EVERY file is one call with an empty filter, so
/// writing it again is three lines — and the brush presets and the brush
/// tips each did, a filter-less dialog and a read of the bytes apiece. The
/// text tool's fonts would have been the third (R9-rest, 2026-10-06), which
/// is the number that made them one (`pickAnyFile`).
///
/// ⛔What this keeps is the count of places the dialog is opened from. A new
/// import takes its file through one of the two below; a third way to ask
/// for a file is a decision somebody writes here, with its reason.
void main() {
  test('the dialog that offers every file is opened from two places: one '
      'that hands back bytes, one that hands back paths', () {
    final unfiltered = RegExp(
      r'\bopenFiles?\(\s*acceptedTypeGroups:\s*const\s*\[\]',
    );
    final sites = <String>{
      for (final file in dartFilesUnder('lib'))
        if (unfiltered.hasMatch(file.readAsStringSync())) libPath(file),
    };

    expect(sites, {
      // The file's BYTES, for every import that reads a file itself: a
      // brush pack, a tip's image, a font.
      'lib/src/ui/brush/picked_file.dart',
      // PATHS, judged by their extension and refused with a notice: the
      // windows that take files where they lie.
      'lib/src/ui/dialogs/open_file_flow.dart',
    });
  });
}
