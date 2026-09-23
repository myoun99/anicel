import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_audio_lane.dart' show seAudioLaneId;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_sheet.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// F-25 — **the fx chain lights on both sides of the splitter.**
///
/// 유저 2026-08-24: 「레이어 영역은 fx멤버에 서있을경우 레이어/헤더/멤버 3군데가
/// 바탕이 강조색되는데 프레임영역은 그러지 않으니 통일」.
///
/// The RAIL half has read the standing row since 2026-08-07 — 「layer ▸ Blur ▸
/// Radius all lit」 — through `currentRowIsLane` / `currentRowIsInsideGroup`,
/// which exist so no surface invents its own test. The FRAME half never asked.
///
/// I-44: the frame half's ground is the grid sheet's now, answered by ONE
/// function for every row kind ([timelineRowGround]) — so it is asked here,
/// and the sheet is asked whether it follows the standing row.
void main() {
  const layerId = LayerId('fx-layer');
  const host = Color(0xFF101214);
  final scheme = ThemeData.light().colorScheme;
  final layer = Layer(
    id: layerId,
    name: 'FX',
    frames: const [],
    timeline: const {},
  );
  TimelineDisplayRow laneRow(String laneId, {bool groupHeader = false}) =>
      TimelineDisplayRow.lane(
        layer,
        PropertyLaneRow(
          laneId: laneId,
          label: laneId,
          keyedFrames: const {},
          isGroupHeader: groupHeader,
        ),
        layerIndex: 0,
      );
  Color groundOf(TimelineDisplayRow row, TimelineRowAddress? standing) =>
      timelineRowGround(row, (
        hostGround: host,
        activeLayerId: null,
        standing: standing,
        colorScheme: scheme,
      ));

  test('standing ON the lane lights its row', () {
    final row = laneRow('position');
    final resting = groundOf(row, null);
    final lit = groundOf(row, const LaneRowAddress(layerId, 'position'));

    expect(
      lit,
      isNot(resting),
      reason: 'the rail half of this very row lights; the frame half is the '
          'same row',
    );
    expect(
      lit,
      Color.alphaBlend(timelineActiveRowWashColor(scheme), resting),
      reason: 'and it is the SAME wash the layer row\'s frame half wears, '
          'over the lane\'s own ground — not a colour invented here',
    );
    expect(lit.a, 1.0, reason: 'opaque: the sheet draws its lines on it');
  });

  test('standing on a MEMBER lights the group header too', () {
    final header = laneRow('transform-group', groupHeader: true);
    expect(
      // A member of the transform group, not the header itself.
      groundOf(header, const LaneRowAddress(layerId, 'position')),
      isNot(groundOf(header, null)),
      reason: '「layer ▸ Blur ▸ Radius all lit」 — the header is the middle '
          'link of the chain, and it lights on the rail already',
    );
  });

  test('the Audio lane lights like every lane — its rail half always did', () {
    final audio = laneRow(seAudioLaneId);
    expect(
      groundOf(audio, const LaneRowAddress(layerId, seAudioLaneId)),
      isNot(groundOf(audio, null)),
      reason: 'the one lane nobody had handed the standing row',
    );
  });

  test('a lane of ANOTHER layer leaves it alone', () {
    final row = laneRow('position');
    expect(
      groundOf(
        row,
        const LaneRowAddress(LayerId('somewhere-else'), 'position'),
      ),
      groundOf(row, null),
    );
  });

  test('and with no standing row at all it rests on the lane ground', () {
    expect(
      groundOf(laneRow('position'), null),
      Color.alphaBlend(AppColors.washDown.withValues(alpha: 0.6), host),
      reason: 'the F-7 ground, unchanged',
    );
  });

  testWidgets('the SHEET follows the standing row; the band paints nothing', (
    tester,
  ) async {
    final standing = ValueNotifier<TimelineRowAddress?>(null);
    addTearDown(standing.dispose);
    final rows = [
      TimelineDisplayRow.layer(layer, layerIndex: 0),
      laneRow('position'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineGridLaw(
            ground: host,
            framesPerSecond: 24,
            child: SizedBox(
              width: 600,
              height: 56,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TimelineRowsGridSheet(
                      rows: rows,
                      rowExtent: 28,
                      frameCellExtent: 16,
                      activeLayerId: null,
                      standing: standing,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 28,
                    width: 600,
                    height: 28,
                    child: TimelineLaneFrameRow(
                      layer: layer,
                      lane: rows[1].lane!,
                      frameStartIndex: 0,
                      frameEndIndexExclusive: 12,
                      leadingFrameSpacerWidth: 0,
                      trailingFrameSpacerWidth: 0,
                      metrics: TimelineGridMetrics.defaults,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    TimelineGridSheetPainter sheet() =>
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(TimelineRowsGridSheet),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as TimelineGridSheetPainter;

    expect(sheet().rows.rows[1].ground, groundOf(rows[1], null));
    standing.value = const LaneRowAddress(layerId, 'position');
    await tester.pump();
    expect(
      sheet().rows.rows[1].ground,
      groundOf(rows[1], const LaneRowAddress(layerId, 'position')),
      reason: 'a stand is a pointer-down claim — the sheet has to hear it, '
          'not wait for the next rebuild of the grid',
    );

    // ⛔The band itself carries no ground: a coloured box here would bury
    // the sheet's lines again (D43-2's whole story).
    final band = find.byType(TimelineLaneFrameRow);
    final grounds = [
      ...tester
          .widgetList<ColoredBox>(
            find.descendant(of: band, matching: find.byType(ColoredBox)),
          )
          .map((box) => box.color),
      ...tester
          .widgetList<DecoratedBox>(
            find.descendant(of: band, matching: find.byType(DecoratedBox)),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.color)
          .whereType<Color>(),
    ];
    expect(grounds, isEmpty);
  });
}
