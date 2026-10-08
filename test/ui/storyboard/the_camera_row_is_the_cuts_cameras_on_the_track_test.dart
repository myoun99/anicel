import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_panel.dart'
    show StoryboardCameraRowPainter, StoryboardPanel;
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart'
    show TimelineSection;

/// 🗣️I-73 ④ (유저 2026-10-08): 「그리고 카메라는 로컬이랑 똑같이 최상단행.
/// cam섹션의 제일 위」 · 「카메라 행 범위는 키표시/이동/레인 등 모든거
/// 콘티패널에서 가능. 컷 클램핑만 되도록」 · 「카메라행은 ol떄 2줄로 만드는거
/// ok」 · 「컷 클리핑하는거 사이 점선으로 만드는거 좋네」.
///
/// The storyboard draws the cuts' camera layers as ONE row at the top of the
/// track's CAM section, each cut's keys over the cut's own frames: the
/// timeline's camera row, laid on the track's axis.
///
/// Cuts a [0, 24) and b [24, 48), four frames of gap, then c [52, 64). a's
/// camera keys 0, 12 and 30 — the last past its end; b's 2 and 6; c has
/// none.
void main() {
  const trackId = TrackId('t1');
  const a = CutId('a');
  const b = CutId('b');
  final cameraRow = LayerRowAddress(trackCameraRowId(trackId));

  CutCamera keyed(List<int> frames) => CutCamera(
    keyframes: {
      for (final frame in frames)
        frame: CameraPose(center: CanvasPoint(x: 320.0 + frame, y: 180)),
    },
  );

  Cut cutOf(String id, int duration, List<int> keys, {int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    camera: keyed(keys),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  Project film() => Project(
    id: const ProjectId('camera-row'),
    name: 'Camera row',
    createdAt: DateTime.utc(2026, 10, 9),
    tracks: [
      Track(
        id: trackId,
        name: 'V1',
        cuts: [
          cutOf('a', 24, [0, 12, 30]),
          cutOf('b', 24, [2, 6]),
          cutOf('c', 12, const [], gap: 4),
        ],
      ),
    ],
  );

  Future<EditorSessionManager> pumpPanel(
    WidgetTester tester, {
    Set<TimelineSection> hiddenSections = const {},
    bool withOl = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    if (withOl) {
      // A 12-frame O.L across a|b: a is drawn to 30, b from 18.
      session.transitions.updateTransitionInstructions({
        18: const InstructionEvent(instructionId: 'ol', length: 12),
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
              hiddenSections: hiddenSections,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));
  final cameraStrip = key('storyboard-camera-row-t1');

  double ppf(WidgetTester tester) =>
      tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)).pixelsPerFrame;

  /// The frames [camera]'s marks stand on, as the row lays them out: the
  /// cell each mark's span is laid over, on the track's axis.
  List<int> marksOf(WidgetTester tester, String camera) {
    final row = tester.getRect(cameraStrip);
    final prefix = 'storyboard-camera-lane-key-span-$camera-transform-group-';
    return [
      for (final element in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(prefix),
          )
          .evaluate())
        ((tester.getRect(find.byWidget(element.widget)).center.dx - row.left) /
                ppf(tester))
            .floor(),
    ]..sort();
  }

  /// [camera]'s mark for its own [frame], on screen.
  Rect markRect(WidgetTester tester, String camera, int frame) => tester.getRect(
    key('storyboard-camera-lane-key-span-$camera-transform-group-$frame'),
  );

  /// The row's ground, as its painter lays it down.
  StoryboardCameraRowPainter ground(WidgetTester tester) =>
      tester.widget<CustomPaint>(key('storyboard-camera-ground-t1')).painter!
          as StoryboardCameraRowPainter;

  /// A point on the camera row at [globalFrame]'s cell, [across] of the way
  /// down it.
  Offset at(WidgetTester tester, int globalFrame, {double across = 0.5}) {
    final row = tester.getRect(cameraStrip);
    return Offset(
      row.left + (globalFrame + 0.5) * ppf(tester),
      row.top + row.height * across,
    );
  }

  group('where the row stands', () {
    testWidgets('it heads the track\'s CAM section, above the transition row '
        '— label and strip on one line', (tester) async {
      await pumpPanel(tester);

      final label = tester.getRect(key('storyboard-camera-label-t1'));
      final transitionLabel = tester.getRect(
        key('storyboard-transition-label-t1'),
      );
      final strip = tester.getRect(cameraStrip);
      final transitionStrip = tester.getRect(
        key('storyboard-transition-row-t1'),
      );
      expect(label.bottom, lessThanOrEqualTo(transitionLabel.top + 0.5));
      expect(strip.bottom, lessThanOrEqualTo(transitionStrip.top + 0.5));
      expect(label.top, closeTo(strip.top, 0.5), reason: 'one line');
      expect(label.height, closeTo(strip.height, 0.5));
    });

    testWidgets('the camera section\'s toggle takes it with the transition '
        'row', (tester) async {
      await pumpPanel(tester, hiddenSections: {TimelineSection.camera});

      expect(key('storyboard-camera-label-t1'), findsNothing);
      expect(cameraStrip, findsNothing);
      expect(key('storyboard-section-zone-t1-camera'), findsNothing);
      expect(key('storyboard-track-row-t1'), findsOneWidget);
    });
  });

  group('what the row draws', () {
    testWidgets('each cut\'s keys at the cut\'s own place on the track, '
        'joined from its first to its last', (tester) async {
      await pumpPanel(tester);

      expect(marksOf(tester, 'a-cam'), [0, 12]);
      expect(marksOf(tester, 'b-cam'), [26, 30], reason: 'b stands at 24');
      expect(marksOf(tester, 'c-cam'), isEmpty);
      expect(key('storyboard-camera-line-a-cam'), findsOneWidget);
      expect(key('storyboard-camera-line-b-cam'), findsOneWidget);
      expect(
        key('storyboard-camera-line-c-cam'),
        findsNothing,
        reason: 'no two keys to join',
      );
    });

    testWidgets('🚨a key outside its cut\'s own frames is not drawn — the line '
        'runs out to the cut\'s end instead', (tester) async {
      await pumpPanel(tester);

      expect(
        key('storyboard-camera-lane-key-span-a-cam-transform-group-30'),
        findsNothing,
        reason: 'a ends at 24; its key at 30 would stand on b',
      );
      final line = tester.getRect(key('storyboard-camera-line-span-a-cam'));
      final row = tester.getRect(cameraStrip);
      expect(
        line.right - row.left,
        closeTo(24 * ppf(tester), 0.5),
        reason: 'to a\'s end, not to the key past it',
      );
    });

    testWidgets('a dashed line where each cut begins', (tester) async {
      await pumpPanel(tester);

      expect(ground(tester).cutStarts(), [0.0, 24 * 12.0, 52 * 12.0]);
      expect(ground(tester).noriShiroWashes(), isEmpty, reason: 'no のりしろ');
      expect(ground(tester).sharedMiddles(), isEmpty);
    });

    testWidgets('🚨an O.L splits the row — the leaving cut above, the arriving '
        'below, each のりしろ washed on its own half', (tester) async {
      await pumpPanel(tester, withOl: true);

      final row = tester.getRect(cameraStrip);
      // a's key 12 is before the O.L: the one line, in the middle.
      expect(markRect(tester, 'a-cam', 12).center.dy, closeTo(row.center.dy, 1));
      // b's own frame 2 plays at 20, inside the O.L: the lower line.
      expect(marksOf(tester, 'b-cam'), [20, 24]);
      expect(markRect(tester, 'b-cam', 2).center.dy, greaterThan(row.center.dy));
      // a's key 30 is still past a's own frames — a is drawn to 30, not on it.
      expect(
        key('storyboard-camera-lane-key-span-a-cam-transform-group-30'),
        findsNothing,
      );

      final washes = ground(tester).noriShiroWashes();
      final px = ppf(tester);
      expect(washes, [
        // a's tail, 24..30, on the upper half.
        Rect.fromLTRB(24 * px, 0, 30 * px, row.height / 2),
        // b's head, 18..24, on the lower half.
        Rect.fromLTRB(18 * px, row.height / 2, 24 * px, row.height),
      ]);
      expect(ground(tester).sharedMiddles(), [
        (Offset(18 * px, row.height / 2), Offset(30 * px, row.height / 2)),
      ]);
    });
  });

  group('pressing the row', () {
    testWidgets('stands the session in the cut, on its camera — the '
        'timeline\'s camera row', (tester) async {
      final session = await pumpPanel(tester);

      await tester.tapAt(at(tester, 30));
      await tester.pumpAndSettle();

      expect(session.selectedRow, cameraRow);
      expect(session.activeCutId, b);
      expect(session.activeLayerId, const LayerId('b-cam'));
      expect(session.currentFrameIndex, 6, reason: 'b\'s own frame at 30');
    });

    testWidgets('🚨over an O.L the line pressed names the cut', (tester) async {
      final session = await pumpPanel(tester, withOl: true);

      await tester.tapAt(at(tester, 20, across: 0.8));
      await tester.pumpAndSettle();
      expect(session.activeCutId, b, reason: 'the lower line is b\'s');
      expect(session.activeLayerId, const LayerId('b-cam'));
      expect(session.currentFrameIndex, 2, reason: 'b\'s own frame at 20');

      await tester.tapAt(at(tester, 20, across: 0.2));
      await tester.pumpAndSettle();
      expect(session.activeCutId, a, reason: 'the upper line is a\'s');
      expect(session.activeLayerId, const LayerId('a-cam'));
      expect(session.currentFrameIndex, 20);
    });

    testWidgets('a gap stands on the row and parks there', (tester) async {
      final session = await pumpPanel(tester);

      await tester.tapAt(at(tester, 50));
      await tester.pumpAndSettle();

      expect(session.selectedRow, cameraRow);
      expect(session.activeCutOrNull, isNull);
      expect(session.editingGlobalFrame, 50);
    });
  });
}
