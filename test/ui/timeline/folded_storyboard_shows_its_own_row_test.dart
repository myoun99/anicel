import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

/// D15 (유저 2026-08-21): 「①트랙이 보여야 하는데 프레임이 보임 ②심지어
/// 수정 전 구버전 간편오버레이가 보임 — 설마 사본 멋대로 만든 건가?」
///
/// 🎯**There was no copy.** One widget, one call site: the fold let either
/// tab through and then built the TIMELINE's row unconditionally, so a
/// folded storyboard showed the timeline's row — which is exactly what
/// "an old version of the overlay" looks like from the outside. ① and ②
/// were one cause with two faces, and the fix is a branch, never a second
/// overlay.
///
/// The two halves both mount the panel's OWN widgets — the track label row
/// and the cut-blocks painter's shared builder — so 「썸네일 띄움 ·
/// 텍스트같은것도 같은 규칙따라서 위치 맞춤」 (③) is not implemented here at
/// all: it arrives with the picture.
Future<void> _pumpFolded(
  WidgetTester tester, {
  required bool storyboard,
}) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
  if (storyboard) {
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
  }
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -420),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('floating-bottom-collapse')),
  );
  await tester.pumpAndSettle();
}

Finder _cutBlocks() => find.descendant(
  of: find.byType(CollapsedRowOverlay),
  matching: find.byKey(
    const ValueKey<String>('collapsed-storyboard-cut-blocks'),
  ),
);

void main() {
  testWidgets('a folded STORYBOARD shows the track row — its cuts, not the '
      'timeline\'s frames', (tester) async {
    await _pumpFolded(tester, storyboard: true);

    expect(find.byType(CollapsedRowOverlay), findsOneWidget);
    expect(
      _cutBlocks(),
      findsOneWidget,
      reason: 'D15 ①: the frame half is the CUT blocks',
    );
    expect(
      find.descendant(
        of: find.byType(CollapsedRowOverlay),
        matching: find.byType(TimelineLayerControlsRow),
      ),
      findsNothing,
      reason:
          'D15 ②: the timeline\'s rail row is what made the folded '
          'storyboard read as "an old version" — it was never this panel\'s',
    );
    final rail = tester.widget<StoryboardTrackLabelRow>(
      find.descendant(
        of: find.byType(CollapsedRowOverlay),
        matching: find.byType(StoryboardTrackLabelRow),
      ),
    );
    expect(
      rail.chromeless,
      isTrue,
      reason:
          'the folded row keeps no ground — 「chromeless는 셀이 아니라 '
          '행의 성질」, so the storyboard\'s rail row reads it too',
    );
  });

  testWidgets('the folded row is as tall as the row it folded — the V '
      'splitter\'s height on the storyboard, a layer row on the timeline', (
    tester,
  ) async {
    await _pumpFolded(tester, storyboard: true);
    final folded = tester.widget<CollapsedRowOverlay>(
      find.byType(CollapsedRowOverlay),
    );
    expect(
      folded.height,
      StoryboardPanel.defaultTrackLaneHeight,
      reason:
          'D15 ④ (유저: 「높이도 해당 행 높이에따라서 맞춤」) — a V track '
          'is as tall as its own splitter left it',
    );
    // …and the picture is drawn at that same height, not at the constant
    // the overlay used to carry.
    final painter =
        tester.widget<CustomPaint>(_cutBlocks()).painter!
            as StoryboardCutBlocksPainter;
    expect(painter.crossAxisExtent, folded.height);
    expect(
      tester.getSize(find.byType(CollapsedRowOverlay)).height,
      folded.height,
      reason:
          'the space the fold reserves is the same number the row draws '
          'at — one height, read everywhere (유저: 「그래야 수정했을때 '
          '아무것도 안고치고 반영되니까」)',
    );
  });

  testWidgets('D15 ③: thumbnails are ON in the folded row, because the same '
      'painter draws them in the open one', (tester) async {
    await _pumpFolded(tester, storyboard: true);
    final painter =
        tester.widget<CustomPaint>(_cutBlocks()).painter!
            as StoryboardCutBlocksPainter;
    expect(painter.showThumbnails, isTrue);
    expect(painter.thumbnailFor, isNotNull);
  });

  testWidgets('a folded TIMELINE is untouched — it still shows its own rail '
      'row and its own height', (tester) async {
    await _pumpFolded(tester, storyboard: false);

    expect(_cutBlocks(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CollapsedRowOverlay),
        matching: find.byType(TimelineLayerControlsRow),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<CollapsedRowOverlay>(find.byType(CollapsedRowOverlay))
          .height,
      CollapsedRowOverlay.defaultHeight,
    );
  });
}
