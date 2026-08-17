import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_row_span_resolver.dart';

/// 🚨C3 (2026-08-17): the SE row's NAME-TAG fx lanes obey the SAME range
/// laws as the transform lanes — the span across member rows is the group's
/// own display order ([seNameTagLaneSpan], the "complete twin of
/// transformLaneSpan" the session's span switch never consulted), and a
/// drag that leaves the member rows JOINS the cells law through
/// [resolveLaneSpanEscalation] exactly as a transform anchor does (B4-④).
/// 「멤버 행 안에서만, 바깥 확장 불가」 was the disease, one family over.
void main() {
  const seLayerId = LayerId('nts-se');

  Project project() => Project(
    id: const ProjectId('nts-project'),
    name: 'Name Tag Span',
    createdAt: DateTime.utc(2026, 8, 17),
    tracks: [
      Track(
        id: const TrackId('nts-track'),
        name: 'Video',
        seLayers: [
          Layer(
            id: seLayerId,
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              Frame(
                id: const FrameId('nts-sound'),
                duration: 5,
                name: 'Bang!',
                strokes: const [],
              ),
            ],
            timeline: {
              1: const TimelineExposure.drawing(
                FrameId('nts-sound'),
                length: 5,
              ),
            },
          ),
        ],
        cuts: [
          Cut(
            id: const CutId('nts-cut'),
            name: 'Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: const LayerId('nts-cel'),
                name: 'A',
                frames: const [],
                timeline: const {},
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

  Future<void> openNameTagLanes(WidgetTester tester) async {
    final laneToggle = find.byKey(
      ValueKey<String>('timeline-lane-toggle-${seLayerId.value}'),
    );
    await tester.ensureVisible(laneToggle);
    await tester.pumpAndSettle();
    await tester.tap(laneToggle);
    await tester.pumpAndSettle();
    final groupToggle = find.byKey(
      ValueKey<String>(
        'timeline-lane-group-toggle-${seLayerId.value}-$seNameTagGroupLaneId',
      ),
    );
    await tester.ensureVisible(groupToggle);
    await tester.pumpAndSettle();
    await tester.tap(groupToggle);
    await tester.pumpAndSettle();
  }

  Finder band(String laneId) => find.byKey(
    ValueKey<String>('timeline-lane-range-layer-${seLayerId.value}-$laneId'),
  );

  group('the pure laws, stated on the name-tag family', () {
    test('seNameTagLaneSpan is consulted by the session span switch: a '
        'member→member drag covers the display-ordered run', () {
      final s = EditorSessionManager(initialProject: project());
      addTearDown(s.dispose);

      s.updateLaneRangeSelectionDrag(
        layerId: seLayerId,
        laneId: seNameTagSizeLaneId,
        anchorIndex: 2,
        headIndex: 4,
        headLaneId: seNameTagBoldLaneId,
      );

      final selection = s.laneRangeSelection.value;
      expect(selection, isNotNull);
      expect(selection!.spanLaneIds, [
        seNameTagSizeLaneId,
        seNameTagTrackingLaneId,
        seNameTagBoldLaneId,
      ]);
    });

    test('the group HEADER anchors the whole group by the ordinary range '
        'rule — the transform header\'s own law', () {
      final s = EditorSessionManager(initialProject: project());
      addTearDown(s.dispose);

      s.updateLaneRangeSelectionDrag(
        layerId: seLayerId,
        laneId: seNameTagGroupLaneId,
        anchorIndex: 2,
        headIndex: 2,
        headLaneId: seNameTagShowLineLaneId,
      );

      expect(
        s.laneRangeSelection.value!.spanLaneIds,
        seNameTagLaneSelectionOrder,
      );
    });

    test('resolveLaneSpanEscalation is family-agnostic: a name-tag anchor '
        'crossing out of its layer joins the cells law like a transform '
        'anchor', () {
      final draw = Layer(
        id: const LayerId('esc-draw'),
        name: 'A',
        frames: const [],
      );
      final se = Layer(
        id: seLayerId,
        name: 'S1',
        kind: LayerKind.se,
        frames: const [],
      );
      final rows = buildTimelineDisplayRows(
        layers: [draw, se],
        expandedLayerIds: {seLayerId},
        lanesForLayer: (layer) => layer.id == seLayerId
            ? [
                for (final laneId in [
                  seNameTagGroupLaneId,
                  seNameTagSizeLaneId,
                  seNameTagBoldLaneId,
                ])
                  PropertyLaneRow(
                    laneId: laneId,
                    label: laneId,
                    keyedFrames: const {},
                  ),
              ]
            : const [],
      );

      // Inside the SE layer's own lane group: the lane law keeps the drag.
      expect(
        resolveLaneSpanEscalation(
          rows: rows,
          layerId: seLayerId,
          laneId: seNameTagSizeLaneId,
          rowDelta: 1,
        ),
        isNull,
      );
      // Out of the member rows onto the SE cells row and beyond: escalates
      // with the display-row slice a cells anchor would report.
      final escalation = resolveLaneSpanEscalation(
        rows: rows,
        layerId: seLayerId,
        laneId: seNameTagSizeLaneId,
        rowDelta: -3,
      )!;
      expect(escalation.headLayerId, const LayerId('esc-draw'));
      expect(escalation.spanRows, [
        const LayerRowAddress(LayerId('esc-draw')),
        const LayerRowAddress(seLayerId),
        const LaneRowAddress(seLayerId, seNameTagGroupLaneId),
        const LaneRowAddress(seLayerId, seNameTagSizeLaneId),
      ]);
    });
  });

  group('REAL input on the rail', () {
    testWidgets('a mouse drag across the name-tag MEMBER rows selects the '
        'swept members — not the one row it started on', (tester) async {
      final s = await pumpHost(tester);
      await openNameTagLanes(tester);
      const rowHeight = timelineLayerRowHeight;

      final sizeBand = band(seNameTagSizeLaneId);
      expect(sizeBand, findsOneWidget);
      final start =
          tester.getTopLeft(sizeBand) + Offset(2.5 * 24, rowHeight / 2);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(0, rowHeight));
      await tester.pump();
      await gesture.moveBy(const Offset(0, rowHeight));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final selection = s.laneRangeSelection.value;
      expect(selection, isNotNull, reason: 'the drag made a lane selection');
      expect(
        selection!.spanLaneIds,
        [seNameTagSizeLaneId, seNameTagTrackingLaneId, seNameTagBoldLaneId],
        reason: 'the span is the display-ordered member run, T13\'s law',
      );
    });

    testWidgets('a mouse drag anchored on a member row leaves the group '
        'UPWARD onto the cells row — the escalation, for real', (tester) async {
      final s = await pumpHost(tester);
      await openNameTagLanes(tester);
      const rowHeight = timelineLayerRowHeight;

      final sizeBand = band(seNameTagSizeLaneId);
      final start =
          tester.getTopLeft(sizeBand) + Offset(2.5 * 24, rowHeight / 2);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      // Up past the group header (1) onto the SE cells row (2).
      await gesture.moveBy(const Offset(0, -rowHeight));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -rowHeight));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final cells = s.frameRangeSelection.value;
      expect(cells, isNotNull, reason: 'the drag joined the cells law');
      expect(
        cells!.coversRow(const LayerRowAddress(seLayerId)),
        isTrue,
        reason: 'the span reached OUTSIDE the member rows',
      );
      expect(
        cells.coversRow(const LaneRowAddress(seLayerId, seNameTagSizeLaneId)),
        isTrue,
        reason: 'the anchor member row is in the swept run',
      );
      expect(
        s.laneRangeSelection.value,
        isNull,
        reason: 'one selection: the cells law owns the crossed span',
      );
    });

    testWidgets('and vice versa: a drag anchored on the SE CELLS row sweeps '
        'INTO the member rows freely', (tester) async {
      final s = await pumpHost(tester);
      await openNameTagLanes(tester);
      const rowHeight = timelineLayerRowHeight;

      final gestureLayer = find.byKey(
        ValueKey<String>('timeline-range-gesture-${seLayerId.value}'),
      );
      final start =
          tester.getTopLeft(gestureLayer) + Offset(2.5 * 24, rowHeight / 2);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      // Down over the group header onto the Size member row.
      await gesture.moveBy(const Offset(0, rowHeight));
      await tester.pump();
      await gesture.moveBy(const Offset(0, rowHeight));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final cells = s.frameRangeSelection.value;
      expect(cells, isNotNull);
      expect(
        cells!.coversRow(const LaneRowAddress(seLayerId, seNameTagSizeLaneId)),
        isTrue,
        reason: 'the member rows are swept, not stepped over',
      );
    });
  });
}
