import 'package:flutter/gestures.dart';
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

/// 🚨★★★**THE WHEEL SCROLLS THE LAYERS ON BOTH SHEETS.**
///
/// 🗣️유저 2026-09-18 (F-159): 「x시트에서 **레이어 영역의 휠을 통한 스크롤이
/// 작동안함**. **타임라인이랑 법 통일**해서 적용」.
///
/// ⛔**THE AXIS IS THE WHOLE DIFFERENCE.** Layers run DOWN the timeline and
/// ACROSS the x-sheet, so the sheet's layer viewport scrolls horizontally —
/// and a wheel arrives as a VERTICAL delta, which a horizontal `Scrollable`
/// ignores. The timeline's layer viewport is vertical and gets it free.
///
/// ⚠️**BOTH HALVES, and the second is not decoration.** 🧪Two wrong places
/// were measured before the right one: wrapping the whole layer viewport
/// turned the SHEET's wheel into a layer scroll, and `handleWheelUnlessScrolling`
/// did not save it (it asks `Scrollable.maybeOf`, which searches above the
/// widget rather than under the pointer). Without the control below, both
/// of those builds pass.
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

  final layers = <Layer>[
    for (var i = 0; i < 30; i += 1) layer('draw-$i', LayerKind.animation),
  ];

  Future<void> pumpSheet(WidgetTester tester) async {
    // Narrow on purpose: the columns must overflow or nothing scrolls.
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

  final layerViewport = find.byKey(
    const ValueKey<String>('xsheet-layer-horizontal-viewport'),
  );

  /// The HEADER BLOCK — the layer area 유저 named. Aimed by its own widget
  /// rather than by a fraction of the viewport: the viewport holds the
  /// header AND the sheet, which is how the first attempt aimed at the
  /// sheet while believing it was aiming at the header.
  final headerBlock = find.byKey(
    const ValueKey<String>('xsheet-layer-header-wheel'),
  );

  ScrollController controllerOf(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(layerViewport).controller!;

  /// One notch of the wheel at [at].
  Future<void> wheelAt(WidgetTester tester, Offset at, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(at);
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pumpAndSettle();
  }

  testWidgets('🚨a wheel over the x-sheet\'s LAYER HEADERS scrolls the '
      'layers', (tester) async {
    await pumpSheet(tester);
    final controller = controllerOf(tester);
    expect(
      controller.position.maxScrollExtent,
      greaterThan(0),
      reason: '⛔전제: the columns really do overflow',
    );
    final before = controller.offset;

    await wheelAt(tester, tester.getCenter(headerBlock), 120);

    expect(
      controller.offset,
      greaterThan(before),
      reason:
          '🚨유저: 「x시트에서 레이어 영역의 휠을 통한 스크롤이 작동안함 … '
          '타임라인이랑 법 통일해서」',
    );
  });

  testWidgets('⛔and a wheel over the SHEET leaves the layers alone', (
    tester,
  ) async {
    // 🚨THE CONTROL. The frame axis is a vertical scroller and the wheel is
    // its own notch there — a build that turned every notch into a layer
    // scroll passes the pin above and breaks the sheet.
    await pumpSheet(tester);
    final controller = controllerOf(tester);
    final before = controller.offset;

    // Below the header block, inside the viewport: the cells.
    final header = tester.getRect(headerBlock);
    final viewport = tester.getRect(layerViewport);
    final sheetPoint = Offset(
      header.center.dx,
      (header.bottom + viewport.bottom) / 2,
    );
    expect(
      sheetPoint.dy,
      greaterThan(header.bottom),
      reason: '⛔전제: the probe really is below the header block',
    );
    await wheelAt(tester, sheetPoint, 120);

    expect(
      controller.offset,
      before,
      reason: '프레임 축이 자기 노치를 지킨다',
    );
  });
}
