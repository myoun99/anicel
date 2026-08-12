import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_rows_scroll_body.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

/// ㉘ (user, 2026-08-12): 「카메라 행에 프레임을 추가하면 즉시 갱신이 안 된다
/// — 다른 레이어로 이동해야 보인다」.
///
/// The camera row's cells mirror `cut.camera`, not the camera LAYER, so
/// adding a key left every field the painter compares untouched: the same
/// Layer instance, the same `exposureStateForLayer` tear-off, the same cel
/// revision. The row rebuilt (its memo keys on the camera track) and then
/// the painter honestly answered "nothing changed" — and the baked
/// substrate tile said the same, so even a forced repaint would have served
/// the picture from before the key.
void main() {
  // A stand-in for the cut's camera track: the row's coverage lives HERE,
  // outside the layer, which is the whole shape of the bug.
  var cameraKeys = <int>{0};

  // A TOP-LEVEL-style tear-off: a fresh closure per build would make the
  // painter re-record for the wrong reason and hide what is being tested.
  TimelineCellExposureState cameraExposure(Layer layer, int frameIndex) =>
      cameraKeys.contains(frameIndex)
      ? TimelineCellExposureState.drawingStart
      : TimelineCellExposureState.uncovered;

  final cameraLayer = Layer(
    id: const LayerId('camera'),
    name: 'Camera',
    kind: LayerKind.camera,
    frames: const [],
    timeline: const {},
  );

  Widget body({required Object? cameraTrack}) => MaterialApp(
    home: Material(
      child: SizedBox(
        width: 700,
        height: 200,
        child: TimelineFrameRowsScrollBody(
          rows: [TimelineDisplayRow.layer(cameraLayer, layerIndex: 0)],
          activeLayerId: null,
          playbackFrameCount: 24,
          frameStartIndex: 0,
          frameEndIndexExclusive: 24,
          leadingFrameSpacerWidth: 0,
          trailingFrameSpacerWidth: 0,
          totalFrameContentWidth: 24 * 24,
          metrics: const TimelineGridMetrics(),
          exposureStateForLayer: cameraExposure,
          memoAux: TimelineRowMemoAux(cameraTrack: cameraTrack),
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
        ),
      ),
    ),
  );

  TimelineRowCellsPainter painterOf(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<TimelineRowCellsPainter>()
      .single;

  setUp(() => cameraKeys = <int>{0});

  testWidgets('a camera key added to the CUT repaints the camera row — the '
      'layer it belongs to never changed', (tester) async {
    await tester.pumpWidget(body(cameraTrack: 'keys:0'));
    final before = painterOf(tester);
    expect(
      before.cellModelAt(6).exposureState,
      TimelineCellExposureState.uncovered,
    );

    // The key lands on the cut's camera. The LAYER is the same instance and
    // the exposure resolver is the same function — which is exactly why
    // this used to repaint nothing.
    cameraKeys = {0, 6};
    await tester.pumpWidget(body(cameraTrack: 'keys:0,6'));

    final after = painterOf(tester);
    expect(
      identical(after.layer, before.layer),
      isTrue,
      reason: 'the premise: nothing about the layer moved',
    );
    expect(
      after.exposureStateForLayer,
      before.exposureStateForLayer,
      reason: 'and the resolver is the same function',
    );
    expect(
      after.shouldRepaint(before),
      isTrue,
      reason: 'so the coverage identity is the only thing that can say the '
          'row has to be drawn again',
    );
  });

  testWidgets('an unchanged camera row still repaints nothing', (tester) async {
    // The other half: this must not become "repaint always".
    await tester.pumpWidget(body(cameraTrack: 'keys:0'));
    final before = painterOf(tester);

    await tester.pumpWidget(body(cameraTrack: 'keys:0'));

    expect(painterOf(tester).shouldRepaint(before), isFalse);
  });
}
