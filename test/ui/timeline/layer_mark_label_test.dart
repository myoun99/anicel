import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show LayerSectionBandCell, layerMarkColor, layerMarkSlotWidth;
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineTextOnColor;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// A6 (2026-08-17): the layer colour label — 「①위치 = 레이어 영역 맨 왼쪽
/// ②동그라미 → 세로로 꽉 채우는 심플 사각형, 패딩 절대 금지 ③가로폭 =
/// 세로의 절반 ④가로쓰기 세로표시로 색 이름 텍스트 ⑤클릭 로직 그대로
/// ⑥텍스트 색은 프레임블록의 휘도 법(#1109) 그대로」.
Layer _layer(String id, LayerKind kind, {LayerMark mark = LayerMark.none}) {
  return Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    mark: mark,
    frames: kind == LayerKind.camera
        ? const []
        : [Frame(id: FrameId('$id-frame'), duration: 1, strokes: const [])],
    timeline: const {},
  );
}

Widget _panel() {
  final layers = [
    _layer('a', LayerKind.animation, mark: LayerMark.yellow),
    _layer('b', LayerKind.animation, mark: LayerMark.purple),
    _layer('plain', LayerKind.animation),
    _layer('cam', LayerKind.camera),
  ];
  return MaterialApp(
    home: Scaffold(
      body: TimelinePanel(
        layers: layers,
        activeLayerId: const LayerId('a'),
        frameCursor: ValueNotifier<int>(0),
        playbackFrameCount: 12,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onAddLayer: () {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        orientation: TimelineOrientation.horizontal,
        onOrientationChanged: (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('the label is a full-height, half-width plate leading the '
      'layer area (A6 ①②③)', (tester) async {
    await tester.pumpWidget(_panel());

    final chip = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );
    final row = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-row-a')),
    );

    expect(
      chip.height,
      closeTo(row.height, 1.0),
      reason:
          'A6 ②: the plate fills the row height, no padding — at most the '
          'row\'s own bottom divider hairline stays outside it',
    );
    expect(
      chip.width,
      moreOrLessEquals(layerMarkSlotWidth),
      reason: 'A6 ③: width is half the canonical 28px row height',
    );
    expect(
      chip.top,
      moreOrLessEquals(row.top),
      reason: 'A6 ②: flush with the row edge — no vertical padding',
    );
    final sectionCell = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-row-a')),
        matching: find.byType(LayerSectionBandCell),
      ),
    );
    expect(
      chip.left,
      moreOrLessEquals(sectionCell.right),
      reason:
          'A6 ①: the layer area\'s FIRST cell, FLUSH against the section '
          'zone — leftmost, before the twirl, zero gap',
    );
  });

  testWidgets('the colour name stands upright and takes its ink from the '
      'luminance law (A6 ④⑥, #1109)', (tester) async {
    await tester.pumpWidget(_panel());

    TextStyle? styleUnder(String key) {
      final label = tester.widget<VerticalWritingText>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(VerticalWritingText),
        ),
      );
      return label.style;
    }

    // The ink is the LAW's answer, not a constant: whatever
    // timelineTextOnColor says for this plate is what the label wears.
    // (On today's palette the whole set inks black — 보라도 검정 5.4:1,
    // the #1109 record; the law's white branch is pinned by the block
    // text tests, not re-proven here.)
    expect(
      styleUnder('timeline-layer-mark-a')?.color,
      timelineTextOnColor(layerMarkColor(LayerMark.yellow)),
    );
    expect(
      styleUnder('timeline-layer-mark-b')?.color,
      timelineTextOnColor(layerMarkColor(LayerMark.purple)),
    );
  });

  testWidgets('the none plate stays bare — paper colour, no name', (
    tester,
  ) async {
    await tester.pumpWidget(_panel());

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-mark-plain')),
        matching: find.byType(VerticalWritingText),
      ),
      findsNothing,
      reason: 'the paper colour has no name to announce; the plate alone '
          'keeps the tap target discoverable',
    );
    // The plate itself is still there — the click logic is untouched (⑤).
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-mark-plain')),
      findsOneWidget,
    );
  });
}
