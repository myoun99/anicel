import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';

/// F-16 — an UNMOVABLE row (camera, transition) takes the row drag's fork like
/// every other row: inside the selection it is picked up, and it settles
/// where it was.
///
/// 유저: 「추가로 드래그로직도 작동은 하도록. 어차피 결과적으로 이동될곳 없어서
/// 이동은 안되지만 통일감 내고싶음」, then F-16-Q1 = visual — 「잡히고 들리기만
/// — 캐럿은 없고 아무 데도 안 간다」.
///
/// ⚠️Driven on the real rail: the camera row reaches its select-only target
/// through the mount every surface uses, not through a hand-built target.
void main() {
  TimelineRowDragHooks hooks(List<String> events, {required bool inSelection}) =>
      TimelineRowDragHooks(
        drag: ValueNotifier<LayerRowDragState?>(null),
        onBegin: (_) => events.add('begin'),
        onUpdate: (_, _, {pointerInRow}) => events.add('update'),
        onRowTarget: (_, _, _) => events.add('rowTarget'),
        onEffectUpdate: (_, _, _) {},
        onEnd: () => events.add('end'),
        onCancel: () => events.add('cancel'),
        isInRowSelection: (_) => inSelection,
        onSelectBegin: (_) => events.add('selectBegin'),
        onSelectEnd: () => events.add('selectEnd'),
      );

  Future<void> pump(WidgetTester tester, TimelineRowDragHooks rowDragHooks) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 260,
              child: LayerTimelineGrid(
                hooks: TimelineGridHooks(
                  activeLayerId: const LayerId('layer-2'),
                  frameCursor: ValueNotifier<int>(0),
                  playbackFrameCount: 12,
                  exposureStateForLayer: (_, _) =>
                      TimelineCellExposureState.uncovered,
                  onSelectLayer: (_) {},
                  onSelectFrame: (_) {},
                  onToggleLayerVisibility: (_) {},
                  onLayerOpacityChanged: (_, _) {},
                  onToggleLayerTimesheet: (_) {},
                  onLayerMarkSelected: (_, _) {},
                  rowDragHooks: rowDragHooks,
                  onRowSelectionSpan: (_, _) {},
                ),
                layers: [
                  Layer(
                    id: const LayerId('layer-1'),
                    name: 'Camera',
                    kind: LayerKind.camera,
                    frames: const [],
                  ),
                  Layer(
                    id: const LayerId('layer-2'),
                    name: 'A',
                    frames: [
                      Frame(
                        id: const FrameId('frame-2'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  final unmovableTarget = find.byWidgetPredicate(
    (widget) => widget is LayerRowDragTarget && !widget.canReorder,
  );

  /// The look the row wears: the fade a lifted row takes.
  double rowOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find.descendant(of: unmovableTarget, matching: find.byType(Opacity)).first,
      )
      .opacity;

  Future<TestGesture> hold(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('timeline-layer-row-layer-1')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 26));
    await tester.pump();
    return gesture;
  }

  testWidgets('⛔fixture premise: the camera row mounts the select-only '
      'target', (tester) async {
    await pump(tester, hooks(<String>[], inSelection: true));
    expect(unmovableTarget, findsOneWidget);
    expect(rowOpacity(tester), 1);
  });

  testWidgets('inside the selection the camera row is picked up — and goes '
      'nowhere', (tester) async {
    final events = <String>[];
    await pump(tester, hooks(events, inSelection: true));

    final gesture = await hold(tester);

    expect(rowOpacity(tester), lessThan(1), reason: 'it wears the lift');
    expect(events, isNot(contains('selectBegin')), reason: 'not a new band');
    expect(events, isNot(contains('begin')), reason: 'no move starts');

    await gesture.moveBy(const Offset(0, 52));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(rowOpacity(tester), 1, reason: 'it settles where it was');
    expect(events, isEmpty);
  });

  testWidgets('⛔outside the selection it still selects', (tester) async {
    final events = <String>[];
    await pump(tester, hooks(events, inSelection: false));

    final gesture = await hold(tester);

    expect(events, contains('selectBegin'));
    expect(rowOpacity(tester), 1);

    await gesture.up();
    await tester.pump();
    expect(events, contains('selectEnd'));
  });
}
