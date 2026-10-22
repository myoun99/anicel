import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A BLOCK'S WORD KEEPS ITS TYPE AT EVERY ZOOM (유저 2026-09-24,
/// `block-word-size-at-zoom-Q1` 답 B): 「글자크기 그냥 유지하고 블록의 모든
/// 공간 쓸수있게하고, 블록보다 작아지면 가로크기만 줄인다」 — and 「법같은거
/// 최대한 통일하면서. 컷블록의 텍스트든 se텍스트든 뭐든」.
///
/// The shrink the words used to take (`timelineFittedGlyphFontSize`, R26
/// #38) stays for the rulers' numbers, which are no block's writing.
/// ⛔A behaviour test can only prove the surfaces it knows about keep their
/// type; this scan proves nothing ELSE reaches for the shrink.
///
/// ↩️A key MARK was allowed it too, as a square that cannot narrow on one
/// axis (D39-2), until F-367 (유저 2026-10-16: 「칸 그냥 차지는
/// 마름모라던가」): a mark fills its cell, so the cell is its size.
///
/// ↩️The in-between DOT was allowed it too (D39-2, 유저 2026-09-24: 「a
/// mark, not a word」) until F-297 (유저 2026-10-05): 「중간나누기 점도
/// 하나의 글자로 인식해서 … 점 지금 줌 낮아지면 크기 자체가 작아지는데
/// 그게아니라 글자랑 똑같이 법 통일해서 가로가 작아지도록」. It keeps its
/// size and narrows along the frame axis now (`timelineInbetweenMarkSize`),
/// so its painter is one more file this scan holds.
void main() {
  const shrink = 'timelineFittedGlyphFontSize(';
  const allowed = {
    // Its home.
    'lib/src/ui/timeline/timeline_cell_style.dart',
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
          '(timelineBlockWordLayout / TimelineBlockText / wordFit)',
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
