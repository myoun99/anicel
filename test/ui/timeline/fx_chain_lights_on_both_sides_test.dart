import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// F-25 — **the fx chain lights on both sides of the splitter.**
///
/// 유저 2026-08-24: 「레이어 영역은 fx멤버에 서있을경우 레이어/헤더/멤버 3군데가
/// 바탕이 강조색되는데 프레임영역은 그러지 않으니 통일」.
///
/// The RAIL half has read the standing row since 2026-08-07 — 「layer ▸ Blur ▸
/// Radius all lit」 — through `currentRowIsLane` / `currentRowIsInsideGroup`,
/// which exist so no surface invents its own test. The FRAME half never asked.
void main() {
  const layerId = LayerId('fx-layer');
  const host = Color(0xFF101214);
  final layer = Layer(
    id: layerId,
    name: 'FX',
    frames: const [],
    timeline: const {},
  );

  Future<Color> bandColour(
    WidgetTester tester, {
    required TimelineRowAddress? standing,
    String laneId = 'position',
    bool groupHeader = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineGridLaw(
            ground: host,
            framesPerSecond: 24,
            child: SizedBox(
              width: 600,
              height: 40,
              child: TimelineLaneFrameRow(
                layer: layer,
                lane: PropertyLaneRow(
                  laneId: laneId,
                  label: laneId,
                  keyedFrames: const {},
                  isGroupHeader: groupHeader,
                ),
                frameStartIndex: 0,
                frameEndIndexExclusive: 12,
                leadingFrameSpacerWidth: 0,
                trailingFrameSpacerWidth: 0,
                metrics: const TimelineGridMetrics(
                  frameCellWidth: 24,
                  layerRowHeight: 28,
                ),
                currentRow: ValueNotifier<TimelineRowAddress?>(standing),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = find.byKey(
      ValueKey<String>('timeline-lane-grid-fx-layer-$laneId'),
    );
    final decorated = tester.widget<DecoratedBox>(
      find.ancestor(of: grid, matching: find.byType(DecoratedBox)).first,
    );
    return (decorated.decoration as BoxDecoration).color!;
  }

  testWidgets('standing ON the lane lights its band', (tester) async {
    final resting = await bandColour(tester, standing: null);
    final lit = await bandColour(
      tester,
      standing: const LaneRowAddress(layerId, 'position'),
    );

    expect(
      lit,
      isNot(resting),
      reason: 'the rail half of this very row lights; the frame half is the '
          'same row',
    );
    expect(
      lit,
      Color.alphaBlend(
        timelineActiveRowWashColor(
          ThemeData.light().colorScheme,
        ),
        resting,
      ),
      reason: 'and it is the SAME wash the layer row\'s frame half wears, '
          'over the band\'s own ground — not a colour invented here',
    );
    expect(
      lit.a,
      1.0,
      reason: 'still opaque, so it still occludes the buried grid (F-7)',
    );
  });

  testWidgets('standing on a MEMBER lights the group header too', (
    tester,
  ) async {
    final resting = await bandColour(
      tester,
      standing: null,
      laneId: 'transform-group',
      groupHeader: true,
    );
    final lit = await bandColour(
      tester,
      // A member of the transform group, not the header itself.
      standing: const LaneRowAddress(layerId, 'position'),
      laneId: 'transform-group',
      groupHeader: true,
    );

    expect(
      lit,
      isNot(resting),
      reason: '「layer ▸ Blur ▸ Radius all lit」 — the header is the middle '
          'link of the chain, and it lights on the rail already',
    );
  });

  testWidgets('a lane of ANOTHER layer leaves it alone', (tester) async {
    final resting = await bandColour(tester, standing: null);
    final other = await bandColour(
      tester,
      standing: const LaneRowAddress(LayerId('somewhere-else'), 'position'),
    );

    expect(other, resting);
  });

  testWidgets('and with no standing row at all it rests', (tester) async {
    final resting = await bandColour(tester, standing: null);
    expect(
      resting,
      Color.alphaBlend(AppColors.washDown.withValues(alpha: 0.6), host),
      reason: 'the F-7 ground, unchanged',
    );
  });
}
