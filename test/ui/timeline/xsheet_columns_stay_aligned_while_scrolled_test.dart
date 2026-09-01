import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// 🚨F-32 (유저): 「트랜지션·카메라 레이어만 **스크롤에 따라** 위치가
/// 어긋난다」.
///
/// ⚠️THE SHOTS SAY WHICH VIEW. Both images on the card are the **transposed
/// x-sheet** — rows are COLUMNS there, and transition/camera are the
/// rightmost ones. Two earlier measurements answered 「no drift」 while
/// probing the horizontal `LayerTimelineGrid`, which is a different widget
/// ([[never-guess-when-a-shot-exists]]).
///
/// So the comparison is per-COLUMN and across the HORIZONTAL offset: the
/// header block and the cell block are two scrollers fed by one controller,
/// and if they ever disagree the column and its name come apart.
///
/// ⛔EVERY kind, not just the two reported — a pair that checks only camera
/// and transition passes the day the SE column breaks instead.
void main() {
  Layer layer(String id, LayerKind kind) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: kind == LayerKind.animation
        ? [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])]
        : const [],
    timeline: const {},
  );

  /// The shot's shape: a run of drawing columns, then the SE / direction /
  /// transition / camera columns on the right.
  final layers = <Layer>[
    for (var i = 0; i < 30; i += 1) layer('draw-$i', LayerKind.animation),
    layer('folder-1', LayerKind.folder),
    layer('se-1', LayerKind.se),
    layer('se-2', LayerKind.se),
    layer('instructions', LayerKind.instruction),
    layer('transitions', LayerKind.transition),
    layer('cam', LayerKind.camera),
  ];

  Future<void> pumpSheet(WidgetTester tester) async {
    // Narrow on purpose: the columns must overflow or nothing scrolls.
    // 🚨FRACTIONAL RATIO. The device-pixel quantiser is the IDENTITY at
    // 1.0, so a probe at the default ratio cannot see a quantisation seam
    // at all — the trap this repo has stepped in before:
    // 「이음매 테스트는 소수 배율에서」.
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(560, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePanel(
            layers: layers,
            activeLayerId: const LayerId('draw-0'),
            frameCursor: cursor,
            playbackFrameCount: 12,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            orientation: TimelineOrientation.vertical,
            onOrientationChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollController controllerOf(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(
        find.byKey(const ValueKey<String>('xsheet-layer-horizontal-viewport')),
      )
      .controller!;

  testWidgets('every column keeps its header over its cells, at rest and at '
      'every horizontal offset', (tester) async {
    await pumpSheet(tester);

    final controller = controllerOf(tester);
    expect(
      controller.position.maxScrollExtent,
      greaterThan(0),
      reason: 'the fixture must overflow, or nothing can scroll at all',
    );

    // ⚠️Fractional offsets on purpose: a drift of exactly one column width
    // hides at multiples of the column width, and the report is small — the
    // size of a rounding that only shows between device pixels.
    final offsets = <double>[
      0,
      1,
      3,
      17,
      controller.position.maxScrollExtent / 3,
      controller.position.maxScrollExtent / 2,
      controller.position.maxScrollExtent,
    ];

    // 🚨A green that compared nothing looks exactly like a green that
    // compared everything. Count the comparisons and demand them.
    var compared = 0;

    for (final offset in offsets) {
      controller.jumpTo(offset);
      await tester.pumpAndSettle();
      for (final row in layers) {
        final id = row.id.value;
        final header = find.byKey(ValueKey<String>('xsheet-layer-row-$id'));
        final cells = find.byKey(ValueKey<String>('xsheet-column-$id-cells'));
        if (header.evaluate().isEmpty || cells.evaluate().isEmpty) {
          // Scrolled out of the window — windowing is not what this is about.
          continue;
        }
        compared += 1;
        expect(
          tester.getRect(cells).left,
          moreOrLessEquals(tester.getRect(header).left, epsilon: 0.01),
          reason:
              '$id (${row.kind.name}) drifted at offset $offset — this is '
              'F-32: 「트랜지션·카메라 레이어만 스크롤에 따라 위치가 '
              '어긋난다」',
        );
      }
    }

    expect(
      compared,
      greaterThanOrEqualTo(offsets.length * 2),
      reason:
          'every offset must have compared real columns, or this test is '
          'measuring an empty window',
    );
  });
}
