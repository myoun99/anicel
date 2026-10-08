import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';

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
///
/// 🗣️유저 2026-09-26: the bands wear the cut's LABEL (「블록도 색라벨에맞춰서
/// 프레임블록 칠하는거마냥」). The ground is still carried: every word stands
/// in a band, and a band's colour is known without looking at a pixel.
///
/// ↩️The conte blocks' words stood in a pair of bands of their own, in the
/// storyboard layer's label (「안쪽띠, 콘티블록 라벨 반영」), until I-73 (유저
/// 2026-10-08: 「띠 둘만 이사로 가자」) made them the conte row's frame blocks
/// — whose words stand on their own paper, as every frame block's do.
void main() {
  final conte = layerMarkColor(const LayerMark(process: LayerProcess.conte));
  final art = layerMarkColor(const LayerMark(process: LayerProcess.art));
  final paper = layerMarkColor(LayerMark.none);

  StoryboardCutBlockVisual visual({
    required Color cutLabel,
    bool isRangeSelected = false,
  }) => StoryboardCutBlockVisual(
    cutId: const CutId('cut-x'),
    rect: const Rect.fromLTWH(0, 0, 120, 96),
    isRangeSelected: isRangeSelected,
    isHovered: false,
    isStanding: false,
    title: '1',
    total: '12',
    thumbnails: const [],
    cells: const [],
    topBand: const Rect.fromLTWH(0, 0, 120, 13),
    strip: const Rect.fromLTWH(0, 13, 120, 70),
    bottomBand: const Rect.fromLTWH(0, 83, 120, 13),
    cutLabel: cutLabel,
  );

  test('carried writing asks nothing about the picture — it has no argument '
      'for one', () {
    // The signature is the assertion: a ground that cannot be told about
    // thumbnails cannot diverge when they are switched on.
    expect(storyboardCarriedWritingGround(visual(cutLabel: paper)), isNotNull);
  });

  test('the cut\'s bands ARE its label, whatever the label', () {
    for (final label in [paper, conte, art]) {
      expect(storyboardCarriedWritingGround(visual(cutLabel: label)), label);
    }
  });

  test('the `+` of a cut with no conte layer reads the PLATE, never a '
      'picture', () {
    final plate = storyboardCutBlockBackgroundColor(
      ThemeData.dark().colorScheme,
      hovered: false,
    );
    expect(
      timelineTextOnColor(plate),
      isNot(timelineTextOnColor(storyboardPanelPictureGroundColor)),
      reason: 'the `+` once read the picture\'s white while it stood in the '
          'strip — on this black plate that ink would vanish. If these two '
          'ever agree, this test stops proving anything and should be '
          're-read, not deleted',
    );
  });

  test('a range selection tints the bands, and the writing reads against '
      'the tint', () {
    expect(
      storyboardCarriedWritingGround(
        visual(cutLabel: art, isRangeSelected: true),
      ),
      isNot(storyboardCarriedWritingGround(visual(cutLabel: art))),
      reason: 'a cut selection colours what is not the picture',
    );
  });
}
