import 'package:flutter_test/flutter_test.dart';

import '../../helpers/dart_sources.dart';

/// 🗣️F-254 — 유저 2026-10-01: 「전체 잘라내기 … 그림없는곳에선 아무메시지
/// 안뜨는데 뜨도록. 내용은 잘라낼 대상이 존재하지 않습니다.」 · 2026-10-08:
/// 「잘라내기도구로 빈 곳에 그렸을때도 동일하게 법 통일해서 적용」.
///
/// Three doors put a piece in the cut tool's hand — the whole cut, an
/// outline on the canvas, an outline on a viewer's page — and until the
/// second request each decided for itself what a cut that found nothing
/// did. What each door does is pinned where it is driven
/// (`the_whole_cut_takes_the_standing_picture_test`, `cut_tool_drag_test`,
/// the two viewer files). This pins that the answer has ONE writer: a door
/// added tomorrow that says it by itself is a second law, however alike the
/// two read today.
void main() {
  test('the notice that a cut found nothing is said in one place: '
      '`cutIntoTheHand`', () {
    final sayers = [
      for (final file in dartFilesUnder('lib'))
        if (file.readAsStringSync().contains('.noticeNothingToCut'))
          file.path.replaceAll('\\', '/'),
    ];
    expect(
      sayers,
      [endsWith('lib/src/ui/brush/cut_into_the_hand.dart')],
      reason: 'a door that shows it by itself is a copy of the law — route '
          'its piece through cutIntoTheHand',
    );
  });
}
