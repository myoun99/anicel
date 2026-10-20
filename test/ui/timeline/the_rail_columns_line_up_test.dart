import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/text/text_measure.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/named_finders.dart';

/// 🚨F-409 (유저 2026-10-19), the rail's columns:
///
/// * 「레이어영역의 레전드의 왼쪽 버튼(섹션버튼,색라벨버튼)이랑 밑의 색라벨이랑
///   테이크등의 위치가 어긋나서 행/열 구조란 느낌이 안듬」 — the legend's
///   colour label stood over the middle of the label PAIR, on the seam
///   between the colour label and the take;
/// * 「버튼별로 미묘하게 패딩 다른거같은데 다 같도록 통일. 특히 … 비지블버튼이랑
///   음소거랑 불투명도랑 그 공간만 이상하게 좁다」, 「불투명도랑 합성모드
///   버튼이랑 이상하게 얘네만 딱붙어있음」 — the speaker stood in a narrower
///   box than every other button, and the two plates filled their slots to
///   the edge;
/// * 「불투명도 바, 너무 김. … 100이라는 숫자가 딱 들어갈 정도면 됨」.
///
/// ⚠️In the app's face and theme: the bar's width is the width of 「100」 in
/// it.
void main() {
  setUpAll(loadTheAppFaces);

  final picture = Layer(
    id: const LayerId('pic'),
    name: 'pic',
    kind: LayerKind.animation,
    frames: const [],
  );
  final sound = Layer(
    id: const LayerId('se'),
    name: 'se',
    kind: LayerKind.se,
    frames: const [],
  );

  Widget row(Layer layer, TimelineGridMetrics metrics) =>
      TimelineLayerControlsRow(
        layer: layer,
        active: false,
        metrics: metrics,
        onSelectLayer: (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        onOpenLayerMixer: (_, _) {},
        onLayerBlendModeSelected: (_, _) {},
      );

  /// The legend over a picture's row and a sound's, laid with the columns
  /// the rail takes at [scale] — as a host lays them.
  Future<void> pumpRail(WidgetTester tester, {double scale = 1}) async {
    await tester.binding.setSurfaceSize(const Size(900, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (context) {
                final columns = layerRailColumnWidthsIn(context);
                final metrics = TimelineGridMetrics.defaults.copyWith(
                  layerControlsWidth: timelineLayerControlsWidthFor(columns),
                  railColumns: columns,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TimelineLayerControlsHeader(
                      metrics: metrics,
                      optionalColumns: (onion: false, blend: true),
                    ),
                    row(picture, metrics),
                    row(sound, metrics),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect legend(WidgetTester tester, String cell) =>
      tester.getRect(find.byKey(ValueKey<String>('legend-$cell')));
  Rect part(WidgetTester tester, String part, Layer layer) =>
      tester.getRect(find.named('timeline-layer-$part-${layer.id}'));

  testWidgets('the legend\'s colour label stands over the colour label, not '
      'over the pair — the take\'s half under it holds no heading', (
    tester,
  ) async {
    await pumpRail(tester);
    final heading = legend(tester, 'mark');
    final plate = part(tester, 'mark', picture);
    expect(
      part(tester, 'take', picture).left,
      closeTo(plate.right, 0.5),
      reason: '⛔전제: the take stands right after the colour label',
    );
    expect(heading.left, closeTo(plate.left, 0.5));
    expect(heading.width, closeTo(plate.width, 0.5));
  });

  testWidgets('the speaker stands in the box the eye does', (tester) async {
    await pumpRail(tester);
    expect(
      part(tester, 'mute', sound).size,
      part(tester, 'visibility', sound).size,
    );
  });

  testWidgets('the opacity bar and the blend chip stand a chip gap apart, '
      'and the bar half of one off the column before it', (tester) async {
    await pumpRail(tester);
    final eye = part(tester, 'visibility', picture);
    final bar = part(tester, 'opacity', picture);
    final blend = part(tester, 'blend', picture);
    expect(blend.left - bar.right, closeTo(layerControlChipGap, 0.01));
    // The mute column is reserved and empty on a picture's row.
    expect(
      bar.left - eye.right,
      closeTo(layerMuteSlotWidth + layerControlChipGap / 2, 0.01),
    );
    expect(
      legend(tester, 'opacity').left,
      closeTo(bar.left, 0.01),
      reason: 'the master bar stands where the rows\' bars do',
    );
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('at $scale× the bar is as wide as 「100」 between its insets, '
        'with less than a point to spare', (tester) async {
      await pumpRail(tester, scale: scale);
      final bar = part(tester, 'opacity', picture);
      final where = tester.element(find.byType(TimelineLayerControlsRow).first);
      final hundred = TextMeasure(
        where,
        FieldSlider.valueStyleIn(where),
      ).size('100').width;
      final room = bar.width - 2 * FieldSlider.inset;

      expect(hundred, greaterThan(20), reason: 'measured in the app\'s face');
      expect(hundred, lessThanOrEqualTo(room), reason: 'it fits');
      expect(room - hundred, lessThan(1), reason: 'and no more than that');
    });
  }

  testWidgets('a member lane stands its navigator right after the section '
      'band (「이거 다 왼쪽정렬로 왼쪽에 붙어있도록」)', (tester) async {
    final lane = PropertyLaneRow(
      laneId: 'position',
      label: 'Position',
      keyMarks: const {0: KeyMark.linear},
      valueLabel: (_) => '0, 0',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: TimelineLaneControlsRow(
              layer: picture,
              lane: lane,
              metrics: TimelineGridMetrics.defaults,
              width: TimelineGridMetrics.defaults.layerControlsWidth,
              height: TimelineGridMetrics.defaults.layerRowHeight,
              leadingInset: layerSectionLabelSlotWidth,
              laneEdit: PropertyLaneEditCallbacks(
                onToggleKeyAt: (_, _, _) {},
                onSetValue: (_, _, _, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    final cell = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-lane-label-pic-position')),
    );
    final previous = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-lane-prev-key-pic-position')),
    );
    // The cell's half-pixel hairline, then the section band.
    expect(
      previous.left,
      closeTo(cell.left + 0.5 + layerSectionLabelSlotWidth, 0.01),
    );
  });
}
