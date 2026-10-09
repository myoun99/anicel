import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart'
    show FlipHudAxis;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard/storyboard_rows_channel.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart'
    show TimelineSection;

/// 🗣️I-73 ④ (유저 2026-10-08): 「그리고 카메라는 로컬이랑 똑같이 최상단행.
/// cam섹션의 제일 위」 — and the drawn proposal: 「머리는 타임라인의 카메라
/// 행 머리 부품 그대로(칩 · 아이콘 · Camera · fx · 눈 · 값)」.
///
/// The camera row's head is the timeline's own camera row, on the camera
/// layer of the cut the session stands in: its eye is the camera VIEW and
/// its slider the view's DIM, as on the timeline's rail. The rail's other
/// readers — the filter, the ↑/↓ walk, the flip window, the standing wash,
/// the section toggle — take the row as one of the track's rows.
///
/// Cuts a [0, 24) and b [24, 48), four frames of gap, then c [52, 64).
void main() {
  const trackId = TrackId('t1');
  const b = CutId('b');
  final cameraRow = LayerRowAddress(trackCameraRowId(trackId));

  Cut cutOf(String id, int duration, {int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    camera: CutCamera(
      keyframes: {0: CameraPose(center: CanvasPoint(x: 320, y: 180))},
    ),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera $id',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  Project film() => Project(
    id: const ProjectId('camera-head'),
    name: 'Camera head',
    createdAt: DateTime.utc(2026, 10, 9),
    tracks: [
      Track(
        id: trackId,
        name: 'V1',
        cuts: [cutOf('a', 24), cutOf('b', 24), cutOf('c', 12, gap: 4)],
      ),
    ],
  );

  Future<EditorSessionManager> pumpPanel(
    WidgetTester tester, {
    ValueNotifier<bool>? cameraView,
    ValueNotifier<double>? cameraDim,
    TimelineRowFilter rowFilter = TimelineRowFilter.none,
    StoryboardRowsChannel? rowsChannel,
    void Function(EditorSessionManager session)? before,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    before?.call(session);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([
              session,
              session.railView.hiddenSections,
            ]),
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
              rowFilter: rowFilter,
              rowsChannel: rowsChannel,
              hiddenSections: session.railView.hiddenSections.value,
              // The workspace's own toggle: the set, then the hand-off of a
              // stand the hidden section took (F-169).
              onToggleSection: (section) {
                final hidden = session.railView.hiddenSections.value;
                session.railView.hiddenSections.value = hidden.contains(
                      section,
                    )
                    ? ({...hidden}..remove(section))
                    : {...hidden, section};
                session.standing.keepStandingShown();
              },
              cameraViewEnabled: cameraView,
              cameraDimOpacity: cameraDim,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));
  final label = key('storyboard-camera-label-t1');

  TimelineLayerControlsRow head(WidgetTester tester) =>
      tester.widget<TimelineLayerControlsRow>(
        find.descendant(
          of: label,
          matching: find.byType(TimelineLayerControlsRow),
        ),
      );

  void standIn(EditorSessionManager session, int globalFrame) =>
      session.standOnRow(
        cameraRow,
        panel: WorkingPanel.storyboard,
        globalFrameIndex: globalFrame,
      );

  group('the head', () {
    testWidgets('is the timeline\'s camera row, on the camera of the cut the '
        'session stands in', (tester) async {
      final session = await pumpPanel(
        tester,
        before: (session) => standIn(session, 30),
      );

      expect(session.activeCutId, b, reason: '⛔전제');
      expect(head(tester).layer.id, const LayerId('b-cam'));
      expect(head(tester).keyPrefix, 'storyboard');
      expect(head(tester).active, isTrue, reason: 'the row stood on is lit');
      expect(
        find.descendant(of: label, matching: find.text('Camera b')),
        findsOneWidget,
      );
    });

    testWidgets('🚨it is lit only while its row is stood on, and a press on '
        'it stands there', (tester) async {
      final session = await pumpPanel(
        tester,
        before: (session) => session
          ..selectCut(b)
          ..selectRow(const LayerRowAddress(LayerId('b-cel'))),
      );
      expect(session.activeCutId, b, reason: '⛔전제');
      expect(head(tester).active, isFalse, reason: 'another row is stood on');

      await tester.tap(
        find.descendant(of: label, matching: find.text('Camera b')),
      );
      await tester.pumpAndSettle();

      expect(session.selectedRow, cameraRow);
      expect(head(tester).active, isTrue);
    });

    testWidgets('its eye and its slider are the camera view\'s', (
      tester,
    ) async {
      final view = ValueNotifier<bool>(false);
      final dim = ValueNotifier<double>(0.4);
      addTearDown(view.dispose);
      addTearDown(dim.dispose);
      await pumpPanel(
        tester,
        cameraView: view,
        cameraDim: dim,
        before: (session) => standIn(session, 30),
      );

      expect(head(tester).layer.isVisible, isFalse, reason: 'the view is off');
      expect(head(tester).opacityOverride, same(dim));

      await tester.tap(key('storyboard-layer-visibility-b-cam'));
      await tester.pumpAndSettle();
      expect(view.value, isTrue, reason: 'the eye turned the VIEW on');
      expect(head(tester).layer.isVisible, isTrue);
    });

    testWidgets('in a gap it keeps its slots and the kind\'s name', (
      tester,
    ) async {
      await pumpPanel(tester, before: (session) => standIn(session, 50));

      expect(label, findsOneWidget);
      expect(
        find.descendant(
          of: label,
          matching: find.byType(TimelineLayerControlsRow),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: label, matching: find.text('Camera')),
        findsOneWidget,
      );
    });
  });

  group('the rail\'s other readers', () {
    testWidgets('the filter judges it by its head, and spares the row stood '
        'on', (tester) async {
      await pumpPanel(
        tester,
        rowFilter: const TimelineRowFilter(kinds: {LayerKind.se}),
      );
      expect(label, findsNothing, reason: 'a camera is no SE row');
      expect(
        key('storyboard-camera-row-t1'),
        findsNothing,
        reason: 'nor its strip',
      );
    });

    testWidgets('…and the row stood on stays', (tester) async {
      await pumpPanel(
        tester,
        rowFilter: const TimelineRowFilter(kinds: {LayerKind.se}),
        before: (session) => standIn(session, 30),
      );
      expect(label, findsOneWidget);
      expect(key('storyboard-camera-row-t1'), findsOneWidget);
    });

    testWidgets('…and in a gap, with no head, it is judged by its kind', (
      tester,
    ) async {
      void standInTheGap(EditorSessionManager session) => session.standOnRow(
        const TrackRowAddress(trackId),
        panel: WorkingPanel.storyboard,
        globalFrameIndex: 50,
      );

      final session = await pumpPanel(
        tester,
        rowFilter: const TimelineRowFilter(kinds: {LayerKind.se}),
        before: standInTheGap,
      );
      expect(session.activeCutOrNull, isNull, reason: '⛔전제');
      expect(label, findsNothing);

      await pumpPanel(
        tester,
        rowFilter: const TimelineRowFilter(kinds: {LayerKind.camera}),
        before: standInTheGap,
      );
      expect(label, findsOneWidget, reason: 'LIVENESS: its own kind passes');
    });

    testWidgets('the ↑/↓ walk and the flip window take it first in its group',
        (tester) async {
      final channel = StoryboardRowsChannel();
      final session = await pumpPanel(
        tester,
        rowsChannel: channel,
        before: (session) => standIn(session, 30),
      );

      expect(channel.rows.first, cameraRow);
      expect(
        channel.rows[1],
        LayerRowAddress(
          session.repository.requireProject().tracks.single.transitionLayer.id,
        ),
        reason: 'the transition row under it',
      );
      final snapshot = channel.snapshotFor(FlipHudAxis.row)!;
      expect(snapshot.rows.first.name, 'Camera b');
      expect(
        snapshot.rows.first.runs,
        isEmpty,
        reason: 'the timeline\'s camera row\'s window draws no blocks either',
      );
      expect(snapshot.rowIndex, 0, reason: 'the row stood on');
    });

    testWidgets('the standing wash covers its one cell', (tester) async {
      await pumpPanel(tester, before: (session) => standIn(session, 30));

      final row = tester.getRect(key('storyboard-camera-row-t1'));
      final wash = tester.getRect(key('storyboard-standing-wash'));
      expect(wash.top, closeTo(row.top, 0.5));
      expect(wash.height, closeTo(row.height, 0.5));
      expect(wash.left - row.left, closeTo(30 * 12.0, 0.5));
      expect(wash.width, closeTo(12, 0.5), reason: 'a key is one cell');
    });

    testWidgets('🚨hiding the CAM section hands the stand to the V row', (
      tester,
    ) async {
      final session = await pumpPanel(
        tester,
        before: (session) => standIn(session, 30),
      );
      expect(session.storyboardStandingRow, cameraRow, reason: '⛔전제');

      await tester.tap(find.byKey(const ValueKey<String>('legend-sections')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('legend-section-camera')),
      );
      await tester.pumpAndSettle();

      expect(
        session.railView.hiddenSections.value,
        contains(TimelineSection.camera),
        reason: '⛔전제',
      );
      expect(session.storyboardStandingRow, const TrackRowAddress(trackId));
    });
  });
}
