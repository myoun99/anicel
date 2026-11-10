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
        onToggleLayerMute: (_) {},
        onLayerTotalVolumeChangeEnd: (_, _) {},
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

  // 🗣️F-577 (유저 2026-11-10): 「s행은 블렌드행이 비어있으니 그 행 왼쪽에
  // 사운드버튼두고, 그 오른쪽에 총 볼륨 막대 둠 … 불투명도막대랑 완전 동일한
  // 디자인/크기. 블렌드영역의 중앙정렬로」. ↩️The speaker ended the name
  // (F-443) and opened a mixer holding the Total.
  testWidgets('🚨the speaker and then the Total stand in the sound\'s blend '
      'column, centred under the legend\'s blend, and the name keeps no room '
      'for them', (tester) async {
    await pumpRail(tester);
    final speaker = part(tester, 'mute', sound);
    final total = part(tester, 'total-volume', sound);
    final column = legend(tester, 'blend');
    expect(
      total.left,
      closeTo(speaker.right, 0.01),
      reason: 'the bar right after the speaker',
    );
    expect(
      speaker.left - column.left,
      closeTo(column.right - total.right, 0.01),
      reason: 'the two, centred in the blend\'s room',
    );
    expect(speaker.left, greaterThanOrEqualTo(column.left - 0.01));
    expect(
      speaker.left,
      greaterThan(part(tester, 'name', sound).right),
      reason: 'out of the name',
    );
    expect(
      part(tester, 'name', sound).right,
      closeTo(part(tester, 'name', picture).right, 0.01),
      reason: 'the name\'s room is one extent on every row',
    );
    expect(
      part(tester, 'opacity', sound).left -
          part(tester, 'visibility', sound).right,
      closeTo(layerControlChipGap / 2, 0.01),
      reason: 'the sound\'s opacity bar right after the eye, as a picture\'s',
    );
  });

  testWidgets('the opacity bar and the blend chip stand a chip gap apart, '
      'and the bar half of one off the column before it', (tester) async {
    await pumpRail(tester);
    final eye = part(tester, 'visibility', picture);
    final bar = part(tester, 'opacity', picture);
    final blend = part(tester, 'blend', picture);
    expect(blend.left - bar.right, closeTo(layerControlChipGap, 0.01));
    expect(bar.left - eye.right, closeTo(layerControlChipGap / 2, 0.01));
    expect(
      legend(tester, 'opacity').left,
      closeTo(bar.left, 0.01),
      reason: 'the master bar stands where the rows\' bars do',
    );
  });

  // 🗣️F-443 (유저 2026-10-23): 「합성모드버튼의 오른쪽에 쓸데없는 패딩이 너무
  // 큰데, 다른 패딩이랑 규칙 통일해서 적용. 예를들어 불투명도랑 블렌드모드
  // 사이의 공간정도만」.
  testWidgets('🚨the blend chip stands off the row\'s end as far as it '
      'stands off the bar, and the legend\'s over it', (tester) async {
    await pumpRail(tester);
    final row = part(tester, 'row', picture);
    final bar = part(tester, 'opacity', picture);
    final blend = part(tester, 'blend', picture);
    // Inside the row's 1px border.
    expect(row.right - 1 - blend.right, closeTo(blend.left - bar.right, 0.01));
    expect(legend(tester, 'blend').right, closeTo(blend.right, 0.01));
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

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('at $scale× the Total is the opacity bar\'s size and the '
        'speaker the eye\'s, both whole in the blend column', (tester) async {
      await pumpRail(tester, scale: scale);
      expect(
        part(tester, 'total-volume', sound).size,
        part(tester, 'opacity', sound).size,
        reason: 'F-577 「불투명도막대랑 완전 동일한 디자인/크기」',
      );
      expect(
        part(tester, 'mute', sound).size,
        part(tester, 'visibility', sound).size,
        reason: 'F-409: no button in a narrower box than the eye\'s',
      );
      final column = legend(tester, 'blend');
      expect(
        part(tester, 'mute', sound).left,
        greaterThanOrEqualTo(column.left - 0.01),
      );
      expect(
        part(tester, 'total-volume', sound).right,
        lessThanOrEqualTo(column.right + 0.01),
      );
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
