import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A BLOCK'S WORD KEEPS ITS TYPE AT EVERY ZOOM (유저 2026-09-24,
/// `block-word-size-at-zoom-Q1` 답 B): 「글자크기 그냥 유지하고 블록의 모든
/// 공간 쓸수있게하고, 블록보다 작아지면 가로크기만 줄인다」 — and 「법같은거
/// 최대한 통일하면서. 컷블록의 텍스트든 se텍스트든 뭐든」.
///
/// The shrink the words used to take (`timelineFittedGlyphFontSize`, R26
/// #38) stays for what cannot be narrowed on one axis — a key MARK is a
/// square (D39-2) — and for the rulers' numbers, which are no block's
/// writing. ⛔A behaviour test can only prove the surfaces it knows about
/// keep their type; this scan proves nothing ELSE reaches for the shrink.
void main() {
  const shrink = 'timelineFittedGlyphFontSize(';
  const allowed = {
    // Its home.
    'lib/src/ui/timeline/timeline_cell_style.dart',
    // A key mark's size (D39) — a mark, not a word.
    'lib/src/ui/timeline/timeline_lane_rows.dart',
    // The rulers' numbers (R9 #4 · I-22) — the frame axis, not a block.
    'lib/src/ui/timeline/timeline_frame_ruler_painter.dart',
    'lib/src/ui/timeline/xsheet_timeline_grid.dart',
  };

  List<String> callers() => [
    for (final file in dartFilesUnder('lib'))
      if (_callsOutsideComments(file, shrink)) libPath(file),
  ];

  test('premise: the scan sees the callers it allows', () {
    expect(
      callers(),
      containsAll(allowed.difference({
        'lib/src/ui/timeline/timeline_cell_style.dart',
      })),
      reason: 'an empty scan must not pass for nothing',
    );
  });

  test('no block word is sized by the shrink', () {
    expect(
      callers().where((path) => !allowed.contains(path)),
      isEmpty,
      reason: 'a word keeps its type and narrows into its block instead '
          '(timelineBlockWordLayout / TimelineBlockWord / wordFit)',
    );
  });
}

bool _callsOutsideComments(File file, String call) {
  for (final line in file.readAsLinesSync()) {
    final code = line.trimLeft();
    if (code.startsWith('//')) {
      continue;
    }
    if (code.contains(call)) {
      return true;
    }
  }
  return false;
}
