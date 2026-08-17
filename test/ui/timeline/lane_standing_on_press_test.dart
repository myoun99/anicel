import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// 🚨C6 (2026-08-17): STANDING on an fx header/member row is the CELLS'
/// press law — 「일반 행은 해당 인덱스에 서고 → 범위」, and the fx rows do
/// the same now. A pen/mouse press on a lane band stands on the DOWN
/// (playhead + current row), whether or not a range drag follows; whether
/// it CLEARS is still `standOnRow`'s one T10 question, so a press inside
/// the lane selection stands without wiping the move it is starting.
void main() {
  const drawId = LayerId('stand-draw');
  const cellWidth = timelineFrameCellWidth;
  const rowHeight = timelineLayerRowHeight;

  Project project() => Project(
    id: const ProjectId('stand-project'),
    name: 'Standing Press',
    createdAt: DateTime.utc(2026, 8, 17),
    tracks: [
      Track(
        id: const TrackId('stand-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('stand-cut'),
            name: 'Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: drawId,
                name: 'A',
                frames: const [],
                transformTrack: TransformTrack.empty().copyWith(
                  position: PropertyTrack<CanvasPoint>()
                      .withKey(0, CanvasPoint(x: 0, y: 0))
                      .withKey(8, CanvasPoint(x: 9, y: 9)),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<EditorSessionManager> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  Future<void> openTransformLanes(WidgetTester tester) async {
    for (final key in [
      'timeline-lane-toggle-${drawId.value}',
      'timeline-lane-group-toggle-${drawId.value}-transform-group',
    ]) {
      final toggle = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
  }

  Finder band(String laneId) => find.byKey(
    ValueKey<String>('timeline-lane-range-layer-${drawId.value}-$laneId'),
  );

  Offset bandPoint(WidgetTester tester, String laneId, double frame) =>
      tester.getTopLeft(band(laneId)) +
      Offset(frame * cellWidth, rowHeight / 2);

  testWidgets('a mouse press on an fx MEMBER band stands on the DOWN — '
      'pointer still held, no release, no drag', (tester) async {
    final s = await pumpHost(tester);
    await openTransformLanes(tester);

    final gesture = await tester.startGesture(
      bandPoint(tester, 'position', 4.5),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(
      s.currentRow,
      const LaneRowAddress(drawId, 'position'),
      reason: 'the press took the lane as the current row, on the down',
    );
    expect(
      s.currentFrameIndex,
      4,
      reason: 'and parked the playhead on the pressed cell',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the fx GROUP HEADER stands too, and a range drag from it '
      'ranges FROM the stood index — stand first, then range', (tester) async {
    final s = await pumpHost(tester);
    await openTransformLanes(tester);

    final gesture = await tester.startGesture(
      bandPoint(tester, 'transform-group', 2.5),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(s.currentRow, const LaneRowAddress(drawId, 'transform-group'));
    expect(s.currentFrameIndex, 2);

    await gesture.moveBy(const Offset(2 * cellWidth, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final selection = s.laneRangeSelection.value;
    expect(selection, isNotNull, reason: 'the drag still ranges');
    expect(selection!.startIndex, 2);
    expect(
      s.currentFrameIndex,
      2,
      reason: 'the standing index is the anchor the press stood on',
    );
  });

  testWidgets('T10 holds: a press INSIDE the lane selection stands WITHOUT '
      'clearing it, and the move it starts still commits', (tester) async {
    final s = await pumpHost(tester);
    await openTransformLanes(tester);

    // SELECT frames 8..9 on the position band.
    final key8 = bandPoint(tester, 'position', 8.5);
    await tester.dragFrom(
      key8,
      const Offset(26, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(s.laneRangeSelection.value, isNotNull);

    // PRESS inside it: the down stands and HOLDS the selection.
    final gesture = await tester.startGesture(
      key8,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      s.laneRangeSelection.value,
      isNotNull,
      reason: 'the T10 guard: a press inside the selection never clears it',
    );
    expect(s.currentRow, const LaneRowAddress(drawId, 'position'));

    // …and the drag that follows MOVES the keys, as it always did.
    await gesture.moveBy(const Offset(cellWidth, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(cellWidth, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final track = s.layers
        .firstWhere((layer) => layer.id == drawId)
        .transformTrack;
    expect(track.position.keyAt(10), isNotNull, reason: 'the move committed');
    expect(track.position.keyAt(8), isNull);
  });

  test('the guard asks on the axis the span lives on: a track-SE lane span '
      'is stored GLOBAL, and a window-frame press inside it reads inside', () {
    const seId = LayerId('stand-se');
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('stand-global'),
        name: 'Global Guard',
        createdAt: DateTime.utc(2026, 8, 17),
        tracks: [
          Track(
            id: const TrackId('stand-track-2'),
            name: 'Video',
            seLayers: [
              Layer(
                id: seId,
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(
                    id: const FrameId('stand-sound'),
                    duration: 4,
                    strokes: const [],
                  ),
                ],
                timeline: {
                  11: const TimelineExposure.drawing(
                    FrameId('stand-sound'),
                    length: 4,
                  ),
                },
              ),
            ],
            cuts: [
              Cut(
                id: const CutId('stand-cut-1'),
                name: 'Cut 1',
                duration: 10,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: const LayerId('stand-cel-1'),
                    name: 'A',
                    frames: const [],
                  ),
                ],
              ),
              Cut(
                id: const CutId('stand-cut-2'),
                name: 'Cut 2',
                duration: 6,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: const LayerId('stand-cel-2'),
                    name: 'A',
                    frames: const [],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);

    // Park in cut 2 (global 10..16) — window frame 2 is global 12.
    seekStoryboardGlobalFrame(s, 12);
    expect(s.activeCutId, const CutId('stand-cut-2'));

    // A window-frame drag on the SE row's name-tag lane: the session
    // stores the span GLOBAL (its own translation).
    s.updateLaneRangeSelectionDrag(
      layerId: seId,
      laneId: seNameTagSizeLaneId,
      anchorIndex: 1,
      headIndex: 3,
    );
    final span = s.laneRangeSelection.value!;
    expect(span.startIndex, 11);
    expect(span.endIndexExclusive, 14);

    // The guard answers with the SAME translation: window frame 2 (global
    // 12) is inside; window frame 5 (global 15) is not.
    const row = LaneRowAddress(seId, seNameTagSizeLaneId);
    expect(s.standingInsideSelection(row, 2), isTrue);
    expect(s.standingInsideSelection(row, 5), isFalse);
    // And the storyboard's global-frame form asks unshifted.
    expect(s.standingInsideSelection(row, 12, true), isTrue);
    expect(s.standingInsideSelection(row, 15, true), isFalse);
  });
}
