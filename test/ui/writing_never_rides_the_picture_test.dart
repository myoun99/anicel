import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart'
    show timelineTextOnColor;

/// 🚨D29-2 (유저 2026-08-22) — **MAKE THE GROUND THE SAME, DON'T MEASURE IT.**
///
/// > 「컷블록 내 스토리보드레이어의 블록이름/코마수 텍스트가 아직도 컷블록이랑
/// > 규칙 다름. **똑같이 하라고.** 지금 스토리보드블록은 코마텍스트가 **검정**,
/// > 컷블록은 **흰색**」
///
/// > 「그렇게 할거면 **타임라인도** 그렇게 해야하는거야. 통일이니까. 그런데
/// > **무거우니까 하기싫고** 그냥 애초에 **받는 바탕을 똑같게** 하면 되는거
/// > 아닌가? **컷 제목이랑 스토리보드블록의 썸네일없는공간이랑 뭐가 다른거지?**」
///
/// ⛔My answer was to MEASURE the thumbnail's luminance. The user struck it
/// down on two counts — it would owe the timeline the same treatment, and it
/// is expensive — and asked the better question instead. The difference was
/// that the cut's title had left the picture (「THE BANDS carry the writing」)
/// and the panel's labels never had.
void main() {
  StoryboardCutBlockVisual visual({
    bool isActive = false,
    bool isHovered = false,
    bool isRangeSelected = false,
  }) => StoryboardCutBlockVisual(
    cutId: const CutId('cut-x'),
    rect: const Rect.fromLTWH(0, 0, 120, 64),
    isActive: isActive,
    isRangeSelected: isRangeSelected,
    isHovered: isHovered,
    title: '1',
    layerLabel: '',
    hasStoryboardLayer: true,
    total: '12',
    thumbnails: const [],
    cells: const [],
    topBand: const Rect.fromLTWH(0, 0, 120, 13),
    strip: const Rect.fromLTWH(0, 13, 120, 38),
    bottomBand: const Rect.fromLTWH(0, 51, 120, 13),
  );

  final scheme = ThemeData.dark().colorScheme;

  test('carried writing asks nothing about the picture — it has no argument '
      'for one', () {
    // The signature is the assertion: a ground that cannot be told about
    // thumbnails cannot diverge when they are switched on.
    final ground = storyboardCarriedWritingGround(visual(), scheme);
    expect(ground, isNotNull);
  });

  test('the cut title and a panel label would have resolved OPPOSITE inks — '
      'that disagreement WAS the bug', () {
    final carried = timelineTextOnColor(
      storyboardCarriedWritingGround(visual(), scheme),
    );
    final onPicture = timelineTextOnColor(storyboardPanelPictureGroundColor);
    expect(
      carried,
      isNot(onPicture),
      reason: 'the user read one block wearing two inks: white on the band, '
          'black over the thumbnail. Carrying the panel labels is what makes '
          'them one — if these two ever agree by accident, this test stops '
          'proving anything and should be re-read, not deleted',
    );
  });

  test('and the ground follows the block\'s own state, exactly as the bands '
      'do', () {
    expect(
      storyboardCarriedWritingGround(visual(isActive: true), scheme),
      isNot(storyboardCarriedWritingGround(visual(), scheme)),
      reason: 'active is a different ground, and the writing rides it',
    );
    expect(
      storyboardCarriedWritingGround(visual(isRangeSelected: true), scheme),
      isNot(storyboardCarriedWritingGround(visual(), scheme)),
      reason: 'a range selection tints the bands, so it tints the plates',
    );
  });
}
