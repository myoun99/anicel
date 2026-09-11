import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🚨A FILE LET GO ON THE LAYER AREA IS A NEW LAYER AT THE GAP (유저
/// 2026-09-11, 미디어 배치 라운드: 「레이어 영역(가로선) → 새 레이어」). While
/// it hovers, the rail shows its OWN caret there — the line a moved row
/// draws — and a sound raises none (round 6 sends it to the SE rows).
void main() {
  Layer row(String id, {LayerKind kind = LayerKind.animation, String? ridesOn}) =>
      Layer(
        id: LayerId(id),
        name: id,
        frames: const [],
        timeline: const {},
        kind: kind,
        attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
      );

  group('the gap a new row may take', () {
    test('the drawing section only — never above the camera', () {
      final a = row('A');
      final b = row('B');
      final camera = row('Cam', kind: LayerKind.camera);
      final stack = [a, b, camera];
      // The rail runs the stack top-down.
      final shown = [camera, b, a];

      expect(
        newRowInsertionForSlot(stack: stack, displayRows: shown, slot: 0),
        isNull,
        reason: 'above the camera is the camera section',
      );
      expect(
        newRowInsertionForSlot(stack: stack, displayRows: shown, slot: 1),
        2,
      );
      expect(
        newRowInsertionForSlot(stack: stack, displayRows: shown, slot: 2),
        1,
      );
      expect(
        newRowInsertionForSlot(stack: stack, displayRows: shown, slot: 3),
        0,
      );
    });

    test('never between a base and its rider', () {
      final base = row('Base');
      final rider = row('Rider', ridesOn: 'Base');

      expect(
        newRowInsertionForSlot(
          stack: [base, rider],
          displayRows: [rider, base],
          slot: 1,
        ),
        isNull,
      );
    });
  });

  EditorSessionManager twoRows() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('gap-project'),
        name: 'Gap Project',
        createdAt: DateTime.utc(2026, 9, 12),
        tracks: [
          Track(
            id: const TrackId('gap-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('gap-cut'),
                name: 'Gap Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [row('A'), row('B')],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  group('the caret and the spot', () {
    testWidgets('a picture raises the placement caret at a legal gap; a '
        'sound raises none', (tester) async {
      final s = twoRows();
      final shown = [row('B'), row('A')];

      s.layerRowDragVerbs.showPlacementCaret(shown, 1, 'bg.png');
      expect(
        s.layerRowDragVerbs.inFlight.value?.subject,
        const MediaPlacementSubject(),
      );
      expect(s.layerRowDragVerbs.inFlight.value?.caretSlot, 1);

      s.layerRowDragVerbs.showPlacementCaret(shown, 1, 'door.wav');
      expect(s.layerRowDragVerbs.inFlight.value, isNull);

      s.layerRowDragVerbs.showPlacementCaret(shown, 1, 'bg.png');
      s.layerRowDragVerbs.showPlacementCaret(shown, 5, 'bg.png');
      expect(
        s.layerRowDragVerbs.inFlight.value,
        isNull,
        reason: 'a gap that names no place takes the line away',
      );
    });

    testWidgets('clearing the placement caret leaves a row drag\'s alone', (
      tester,
    ) async {
      final s = twoRows();
      const moving = LayerRowDragState(
        subject: LayerRowSubject(LayerId('A')),
        caretSlot: 0,
        legal: true,
      );
      s.layerRowDragVerbs.inFlight.value = moving;

      s.layerRowDragVerbs.clearPlacementCaret();

      expect(s.layerRowDragVerbs.inFlight.value, same(moving));
    });

    testWidgets('the spot: a new layer at that gap for a picture, the SE '
        'rule for a sound', (tester) async {
      final s = twoRows();
      final shown = [row('B'), row('A')];

      expect(s.layerSlotSpotFor(shown, 1, 'bg.png'), const LayerSlotSpot(1));
      expect(s.layerSlotSpotFor(shown, 0, 'bg.png'), const LayerSlotSpot(2));
      expect(
        s.layerSlotSpotFor(shown, 1, 'door.wav'),
        const AboveActiveLayerSpot(),
      );
    });
  });

  testWidgets('a picture held over the layer area raises the rail\'s own '
      'caret at the gap under the pointer — and letting go reports that gap '
      'and takes the caret away', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const png = r'C:\art\bg.png';
    const dragSourceKey = ValueKey<String>('test-media-drag-source');
    (List<LayerId>, int, String)? placed;
    final s = twoRows();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 40,
                child: Draggable<MediaAssetDragData>(
                  data: const MediaAssetDragData(path: png, name: 'bg.png'),
                  // The pool row's own anchor: a target reads the pointer.
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: const SizedBox(width: 8, height: 8),
                  child: Container(
                    key: dragSourceKey,
                    width: 40,
                    height: 40,
                    color: const Color(0xFF888888),
                  ),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: s,
                  builder: (context, _) => TimelineTabHost(
                    session: s,
                    orientation: TimelineOrientation.horizontal,
                    onOrientationChanged: (_) {},
                    pixelsPerFrame: 48,
                    onPixelsPerFrameChanged: (_) {},
                    showSeconds: false,
                    onShowSecondsChanged: (_) {},
                    onPlaceMediaAssetBetweenLayers: (layers, slot, path) =>
                        placed = ([for (final layer in layers) layer.id], slot,
                            path),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Just inside A's rail row: the nearest gap is its top edge, between B
    // above it and A.
    const a = LayerId('A');
    final railRowA = find.byKey(ValueKey<String>('timeline-rail-row-$a-row'));
    expect(railRowA, findsOneWidget);
    final at = tester.getTopLeft(railRowA) + const Offset(24, 3);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(at);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-A')),
      findsOneWidget,
      reason: 'the line a moved row draws, on A\'s top edge',
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('timeline-layer-placement-entrance'),
        ),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
      reason: 'the caret is the answer — the entrance lights no border',
    );

    // A's bottom edge is the strip's end: the trailing gap, drawn under A.
    await gesture.moveTo(
      tester.getBottomLeft(railRowA) + const Offset(24, -3),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-after-A')),
      findsOneWidget,
    );
    await gesture.moveTo(at);
    await tester.pump();

    await gesture.up();
    await tester.pumpAndSettle();

    final (layers, slot, path) = placed!;
    expect(path, png);
    expect(layers[slot], a);
    expect(layers[slot - 1], const LayerId('B'));
    expect(s.layerRowDragVerbs.inFlight.value, isNull);
    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-A')),
      findsNothing,
    );
  });

  testWidgets('a picture that wanders off the layer area takes its caret '
      'with it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const dragSourceKey = ValueKey<String>('test-media-drag-source');
    final s = twoRows();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 40,
                child: Draggable<MediaAssetDragData>(
                  data: const MediaAssetDragData(
                    path: r'C:\art\bg.png',
                    name: 'bg.png',
                  ),
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: const SizedBox(width: 8, height: 8),
                  child: Container(
                    key: dragSourceKey,
                    width: 40,
                    height: 40,
                    color: const Color(0xFF888888),
                  ),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: s,
                  builder: (context, _) => TimelineTabHost(
                    session: s,
                    orientation: TimelineOrientation.horizontal,
                    onOrientationChanged: (_) {},
                    pixelsPerFrame: 48,
                    onPixelsPerFrameChanged: (_) {},
                    showSeconds: false,
                    onShowSecondsChanged: (_) {},
                    onPlaceMediaAssetBetweenLayers: (_, _, _) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final railRowA = find.byKey(
      ValueKey<String>('timeline-rail-row-${const LayerId('A')}-row'),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getTopLeft(railRowA) + const Offset(24, 3));
    await tester.pump();
    expect(s.layerRowDragVerbs.inFlight.value, isNotNull);

    await gesture.moveTo(tester.getCenter(find.byKey(dragSourceKey)));
    await tester.pump();

    expect(s.layerRowDragVerbs.inFlight.value, isNull);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the sheet\'s header strip is the same entrance turned on its '
      'side — the gap runs along x', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const png = r'C:\art\bg.png';
    const dragSourceKey = ValueKey<String>('test-media-drag-source');
    (List<LayerId>, int, String)? placed;
    final s = twoRows();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 40,
                child: Draggable<MediaAssetDragData>(
                  data: const MediaAssetDragData(path: png, name: 'bg.png'),
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: const SizedBox(width: 8, height: 8),
                  child: Container(
                    key: dragSourceKey,
                    width: 40,
                    height: 40,
                    color: const Color(0xFF888888),
                  ),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: s,
                  builder: (context, _) => TimelineTabHost(
                    session: s,
                    orientation: TimelineOrientation.vertical,
                    onOrientationChanged: (_) {},
                    pixelsPerFrame: 48,
                    onPixelsPerFrameChanged: (_) {},
                    showSeconds: false,
                    onShowSecondsChanged: (_) {},
                    onPlaceMediaAssetBetweenLayers: (layers, slot, path) =>
                        placed = ([for (final layer in layers) layer.id], slot,
                            path),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entrance = find.byKey(
      const ValueKey<String>('xsheet-layer-placement-entrance'),
    );
    expect(entrance, findsOneWidget);
    // The sheet lists the stack raw, left to right: A, then B — so one
    // column in is the edge between them.
    final strip = tester.getRect(entrance);
    final at = Offset(strip.left + timelineLayerRowHeight + 2, strip.center.dy);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(at);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-B')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    final (layers, slot, path) = placed!;
    expect(path, png);
    expect(layers[slot], const LayerId('B'));
    expect(layers[slot - 1], const LayerId('A'));
  });
}
