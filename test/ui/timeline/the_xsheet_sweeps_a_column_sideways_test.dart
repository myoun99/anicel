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

/// 🚨★★★THE X-SHEET SWEEPS A COLUMN TOO — SIDEWAYS.
///
/// 유저 2026-08-29: 「그건 **버튼이면 다 가능**하도록」·「**로직적으로 다른
/// 규칙 두지말고 통일**」.
///
/// The layer rail and the storyboard rail got the bulk-drag; this sheet
/// mounted the same four toggles and swept none of them, because the sweep
/// only knew how to run downwards. The x-sheet is that rail TRANSPOSED —
/// layers are columns — so the same gesture runs ACROSS.
///
/// ⛔What must NOT happen is a second implementation. This drives the same
/// [RailColumnSwipe] the two rails use, with `axis: Axis.horizontal`; if the
/// sweep ever needs its own detector here, the law has been broken.
void main() {
  Layer layer(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
  );

  final layers = <Layer>[for (var i = 0; i < 5; i += 1) layer('draw-$i')];

  Future<Map<LayerId, bool>> pumpSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final visible = <LayerId, bool>{for (final l in layers) l.id: true};
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: TimelinePanel(
              layers: [
                for (final l in layers)
                  visible[l.id]! ? l : l.copyWith(isVisible: false),
              ],
              activeLayerId: const LayerId('draw-0'),
              frameCursor: cursor,
              playbackFrameCount: 12,
              exposureStateForLayer: (_, _) =>
                  TimelineCellExposureState.uncovered,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onAddLayer: () {},
              onToggleLayerVisibility: (id) =>
                  setState(() => visible[id] = !visible[id]!),
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              orientation: TimelineOrientation.vertical,
              onOrientationChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return visible;
  }

  Finder eyeOf(String id) =>
      find.byKey(ValueKey<String>('xsheet-layer-visibility-$id'));

  List<bool> visibilityOf(Map<LayerId, bool> visible) => [
    for (final l in layers) visible[l.id]!,
  ];

  testWidgets('🚨a drag ACROSS the eyes hides every column it crosses', (
    tester,
  ) async {
    final visible = await pumpSheet(tester);
    for (final id in const ['draw-0', 'draw-4']) {
      expect(eyeOf(id), findsOneWidget, reason: 'the fixture mounts $id');
    }
    expect(
      visibilityOf(visible),
      [true, true, true, true, true],
      reason: 'all visible to start, or the sweep proves nothing',
    );

    final first = tester.getCenter(eyeOf('draw-0'));
    final last = tester.getCenter(eyeOf('draw-4'));
    expect(
      (last.dx - first.dx).abs(),
      greaterThan((last.dy - first.dy).abs()),
      reason:
          '🚨THE AXIS ITSELF: the eyes are laid out SIDEWAYS here. If this '
          'ever reads the other way the sheet has stopped being transposed '
          'and the rest of this case means nothing',
    );

    final gesture = await tester.startGesture(first);
    for (var step = 1; step <= 8; step += 1) {
      await gesture.moveTo(
        Offset(first.dx + (last.dx - first.dx) * step / 8, first.dy),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      visibilityOf(visible),
      [false, false, false, false, false],
      reason:
          '유저 I-1: 「탭 다운 한 채로 드래그하면 해당 다른 레이어들도 같은 '
          '버튼조작되도록」 — turning the sheet on its side does not make it '
          'a different surface',
    );
  });

  testWidgets('⛔a drag that starts OFF the column paints nothing', (
    tester,
  ) async {
    // The control. Without it a band that swallowed the whole header would
    // pass the case above — including the day it swallows the column name.
    final visible = await pumpSheet(tester);
    final eye = tester.getRect(eyeOf('draw-0'));
    final header = tester.getRect(
      find.byKey(const ValueKey<String>('xsheet-layer-row-draw-0')),
    );
    final from = Offset(eye.center.dx, header.top + 8);
    expect(
      eye.contains(from),
      isFalse,
      reason: 'the press must genuinely miss the eye',
    );

    final gesture = await tester.startGesture(from);
    for (var step = 1; step <= 8; step += 1) {
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(visibilityOf(visible), [
      true,
      true,
      true,
      true,
      true,
    ], reason: 'a swipe only runs from a column it has');
  });
}
