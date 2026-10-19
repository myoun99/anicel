import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show CameraInstructionDef, CameraInstructionSet, InstructionEvent;
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/property_track.dart'
    show KeySidesEdit, KeyTypePick;
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineFrameRangeSelection;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_panel.dart'
    show
        StoryboardCameraRowPainter,
        StoryboardCutStartsPainter,
        StoryboardPanel;
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_block_word.dart'
    show TimelineBlockText;
import 'package:anicel/src/ui/timeline/timeline_double_tap.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneKeysLine, timelineKeysLineGaps;
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart'
    show TimelineSection;
import 'package:anicel/src/ui/timeline/timeline_span_name.dart'
    show TimelineSpanName;
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformTrackWithLaneKeysWritten;

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
/// camera keys 0, 12 (named IN), 20 and 30 — the last past its end; b's 2
/// (named OUT), 6 and 12; c has none. With the O.L, a 12-frame span at
/// [18, 30) joins a and b: a is drawn to 30, b from 18 — and b's key 12
/// plays at 30, the first frame past the O.L.
void main() {
  const trackId = TrackId('t1');
  const a = CutId('a');
  const b = CutId('b');
  final cameraRow = LayerRowAddress(trackCameraRowId(trackId));

  /// A camera keyed at [frames], the keys at [names]' frames named so on
  /// every lane they hold — the name the camera row's union prints — and
  /// at [held]'s its position held where its other lanes are not: the
  /// union's members disagree there.
  CutCamera keyed(
    List<int> frames, {
    Map<int, String> names = const {},
    Set<int> held = const {},
  }) {
    var track = CutCamera(
      keyframes: {
        for (final frame in frames)
          frame: CameraPose(center: CanvasPoint(x: 320.0 + frame, y: 180)),
      },
    ).track;
    for (final MapEntry(key: frame, value: name) in names.entries) {
      for (final laneId in const [
        'anchor-point',
        'position',
        'scale',
        'rotation',
        'opacity',
      ]) {
        track =
            transformTrackWithLaneKeysWritten(
              track,
              laneId: laneId,
              frames: {frame},
              naming: (name: name, preferredFrame: null),
            ) ??
            track;
      }
    }
    track =
        transformTrackWithLaneKeysWritten(
          track,
          laneId: 'position',
          frames: held,
          pick: const KeyTypePick(sides: KeySidesEdit.hold),
        ) ??
        track;
    return CutCamera.fromTrack(track);
  }

  Cut cutOf(
    String id,
    int duration,
    List<int> keys, {
    int gap = 0,
    Map<int, String> names = const {},
    Set<int> held = const {},
  }) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    camera: keyed(keys, names: names, held: held),
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

  /// The film, each cut's camera held at [held]'s frames for its name.
  Project film({
    List<int> cKeys = const [],
    Map<String, Set<int>> held = const {},
  }) => Project(
    id: const ProjectId('camera-row'),
    name: 'Camera row',
    createdAt: DateTime.utc(2026, 10, 9),
    tracks: [
      Track(
        id: trackId,
        name: 'V1',
        cuts: [
          cutOf(
            'a',
            24,
            [0, 12, 20, 30],
            names: {12: 'IN'},
            held: held['a'] ?? const {},
          ),
          cutOf(
            'b',
            24,
            [2, 6, 12],
            names: {2: 'OUT'},
            held: held['b'] ?? const {},
          ),
          cutOf('c', 12, cKeys, gap: 4),
        ],
      ),
    ],
  );

  /// The 12-frame O.L across a|b.
  const ol = {18: InstructionEvent(instructionId: 'ol', length: 12)};

  Future<EditorSessionManager> pumpPanel(
    WidgetTester tester, {
    Set<TimelineSection> hiddenSections = const {},
    Map<int, InstructionEvent> transitions = const {},
    List<int> cKeys = const [],
    Map<String, Set<int>> held = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: film(cKeys: cKeys, held: held),
    );
    addTearDown(session.dispose);
    if (transitions.isNotEmpty) {
      session.transitions.updateTransitionInstructions(transitions);
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

  double ppf(WidgetTester tester) => tester
      .widget<StoryboardPanel>(find.byType(StoryboardPanel))
      .pixelsPerFrame;

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
  Rect markRect(WidgetTester tester, String camera, int frame) => tester
      .getRect(
        key('storyboard-camera-lane-key-span-$camera-transform-group-$frame'),
      );

  /// The line between [camera]'s keys, as the row hands it its course.
  TimelineLaneKeysLine lineOf(WidgetTester tester, String camera) => tester
      .widget<TimelineLaneKeysLine>(key('storyboard-camera-line-$camera'));

  /// A painted PATH that runs across from [top] to [bottom] — a line that
  /// steps; a straight one is painted as a line, not a path.
  PaintPatternPredicate pathBetween(double top, double bottom) =>
      (method, arguments) {
        if (method != #drawPath) {
          return false;
        }
        final bounds = (arguments.first as Path).getBounds();
        return (bounds.top - top).abs() < 0.01 &&
            (bounds.bottom - bottom).abs() < 0.01;
      };

  /// The row's ground, as its painter lays it down.
  StoryboardCameraRowPainter ground(WidgetTester tester) =>
      tester.widget<CustomPaint>(key('storyboard-camera-ground-t1')).painter!
          as StoryboardCameraRowPainter;

  /// Where the row dashes each cut's start, row-local x.
  List<double> cutStartsOf(WidgetTester tester) =>
      (tester
                  .widget<CustomPaint>(key('storyboard-camera-cut-starts-t1'))
                  .painter!
              as StoryboardCutStartsPainter)
          .cutStarts();

  /// The stretches two cuts share on the ground, in frames.
  List<(double, double)> sharedFrames(WidgetTester tester) => [
    for (final (from, to) in ground(tester).sharedMiddles())
      (from.dx / ppf(tester), to.dx / ppf(tester)),
  ];

  /// A point on the camera row at [globalFrame]'s cell, [across] of the way
  /// down it.
  Offset at(WidgetTester tester, int globalFrame, {double across = 0.5}) {
    final row = tester.getRect(cameraStrip);
    return Offset(
      row.left + (globalFrame + 0.5) * ppf(tester),
      row.top + row.height * across,
    );
  }

  List<int> keysOf(EditorSessionManager session, CutId cutId) => [
    ...session.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .singleWhere((cut) => cut.id == cutId)
        .camera
        .keyframes
        .keys,
  ];

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

      expect(marksOf(tester, 'a-cam'), [0, 12, 20]);
      expect(marksOf(tester, 'b-cam'), [26, 30, 36], reason: 'b stands at 24');
      expect(marksOf(tester, 'c-cam'), isEmpty);
      expect(lineOf(tester, 'b-cam').endsAtKey, isTrue);
      expect(lineOf(tester, 'b-cam').crossFraction, 0.5, reason: 'one line');
      expect(lineOf(tester, 'b-cam').steps, isEmpty);
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
      expect(
        lineOf(tester, 'a-cam').endsAtKey,
        isFalse,
        reason: 'the line runs to the box\'s edge, past the last mark',
      );
    });

    testWidgets('a key\'s name is printed on the one line, and left off where '
        'two lines share the row', (tester) async {
      Finder word(String text) => find.descendant(
        of: cameraStrip,
        matching: find.byWidgetPredicate(
          (widget) => widget is TimelineBlockText && widget.text == text,
        ),
      );

      await pumpPanel(tester);
      expect(word('IN'), findsOneWidget, reason: 'a\'s key 12, one line');
      expect(word('OUT'), findsOneWidget, reason: 'b\'s key 2, one line');

      await pumpPanel(tester, transitions: ol);
      expect(word('IN'), findsOneWidget, reason: 'still before the O.L');
      expect(
        word('OUT'),
        findsNothing,
        reason: 'b\'s key 2 plays at 20, on the lower of two lines',
      );
      expect(
        key('storyboard-camera-lane-key-span-b-cam-transform-group-2'),
        findsOneWidget,
        reason: 'its mark is still there',
      );
    });

    testWidgets('🚨a cut whose keys all lie past its own end has neither a '
        'line nor a mark', (tester) async {
      await pumpPanel(tester, cKeys: [14, 20]);

      expect(key('storyboard-camera-line-c-cam'), findsNothing);
      expect(marksOf(tester, 'c-cam'), isEmpty);
    });

    testWidgets('a dashed line where each cut begins', (tester) async {
      await pumpPanel(tester);

      expect(cutStartsOf(tester), [0.0, 24 * 12.0, 52 * 12.0]);
      expect(ground(tester).noriShiroWashes(), isEmpty, reason: 'no のりしろ');
      expect(ground(tester).sharedMiddles(), isEmpty);
    });

    testWidgets('a のりしろ into a gap is washed on the whole row — no '
        'neighbour shares it', (tester) async {
      // An O.L across c's start, where only the gap stands before it.
      await pumpPanel(
        tester,
        transitions: const {
          50: InstructionEvent(instructionId: 'ol', length: 4),
        },
      );

      final row = tester.getRect(cameraStrip);
      final px = ppf(tester);
      expect(ground(tester).noriShiroWashes(), [
        Rect.fromLTRB(50 * px, 0, 52 * px, row.height),
      ]);
      expect(sharedFrames(tester), isEmpty);
    });

    testWidgets('🎯a ring stands between two pieces of its cut\'s line, as big '
        'as it is drawn on the line its cut is on there (I-89 ②)', (
      tester,
    ) async {
      // a's 12 in the middle, a's 20 on the upper line, b's 6 (at 24) on
      // the lower — the O.L's — and a's 30, past a's own end, drawn nowhere.
      await pumpPanel(
        tester,
        transitions: ol,
        held: {
          'a': {12, 20, 30},
          'b': {6},
        },
      );
      for (final (camera, frames) in [
        ('a-cam', [12, 20]),
        ('b-cam', [6]),
      ]) {
        final box = tester.getRect(key('storyboard-camera-line-$camera'));
        final gaps = [
          for (final gap in timelineKeysLineGaps(
            lineOf(tester, camera),
            along: box.width,
            across: box.height,
          ))
            (from: box.left + gap.from, to: box.left + gap.to),
        ]..sort((x, y) => x.from.compareTo(y.from));
        expect(gaps, hasLength(frames.length), reason: camera);
        for (final (index, frame) in frames.indexed) {
          final ring = tester.getRect(
            find.descendant(
              of: key(
                'storyboard-camera-lane-key-span-$camera-transform-group-'
                '$frame',
              ),
              matching: find.byType(CustomPaint),
            ),
          );
          expect(
            [gaps[index].from, gaps[index].to],
            [
              moreOrLessEquals(ring.left, epsilon: 1e-6),
              moreOrLessEquals(ring.right, epsilon: 1e-6),
            ],
            reason: '$camera at $frame',
          );
        }
      }
    });

    testWidgets('🚨a mark keeps the row\'s height and narrows with its cell, '
        'as the band\'s do (F-367-Q4)', (tester) async {
      await pumpPanel(tester);
      final span = key(
        'storyboard-camera-lane-key-span-a-cam-transform-group-12',
      );
      final drawn = tester.getRect(
        find.descendant(of: span, matching: find.byType(CustomPaint)),
      );
      final cell = ppf(tester);
      expect(tester.getRect(span).height, greaterThan(cell), reason: '⛔전제');
      expect(drawn.width, moreOrLessEquals(cell), reason: 'the cell\'s width');
      expect(
        drawn.height,
        moreOrLessEquals(tester.getRect(span).height),
        reason: 'the row\'s height',
      );
    });

    testWidgets('🚨an O.L splits the row — the leaving cut above, the arriving '
        'below, each のりしろ washed on its own half', (tester) async {
      await pumpPanel(tester, transitions: ol);

      final row = tester.getRect(cameraStrip);
      // a's key 12 is before the O.L: the one line, in the middle.
      expect(
        markRect(tester, 'a-cam', 12).center.dy,
        closeTo(row.center.dy, 1),
      );
      // a's key 20 is inside it: a leaves, above.
      expect(markRect(tester, 'a-cam', 20).center.dy, lessThan(row.center.dy));
      // b's own frame 2 plays at 20, inside it too: b arrives, below.
      expect(marksOf(tester, 'b-cam'), [20, 24, 30]);
      expect(
        markRect(tester, 'b-cam', 2).center.dy,
        greaterThan(row.center.dy),
      );
      // a's key 30 is still past a's own frames — a is drawn to 30, not on it.
      expect(
        key('storyboard-camera-lane-key-span-a-cam-transform-group-30'),
        findsNothing,
      );

      // a's line starts in the middle and steps up where a starts to leave;
      // b's starts on the lower line and steps to the middle where the O.L
      // ends — at the leading edge of its last key's cell, counted from its
      // own first.
      expect(lineOf(tester, 'a-cam').crossFraction, 0.5);
      expect(lineOf(tester, 'a-cam').steps, [(edge: 18, to: 0.27)]);
      expect(lineOf(tester, 'a-cam').endsAtKey, isFalse);
      expect(lineOf(tester, 'b-cam').crossFraction, 0.73);
      expect(lineOf(tester, 'b-cam').steps, [(edge: 10, to: 0.5)]);
      // …and each line is painted as it is handed: a's climbs from the
      // middle to the upper line, b's from the lower to the middle.
      expect(
        key('storyboard-camera-line-a-cam'),
        paints..something(pathBetween(row.height * 0.27, row.height * 0.5)),
      );
      expect(
        key('storyboard-camera-line-b-cam'),
        paints..something(pathBetween(row.height * 0.5, row.height * 0.73)),
      );

      final washes = ground(tester).noriShiroWashes();
      final px = ppf(tester);
      expect(washes, [
        // a's tail, 24..30, on the upper half.
        Rect.fromLTRB(24 * px, 0, 30 * px, row.height / 2),
        // b's head, 18..24, on the lower half.
        Rect.fromLTRB(18 * px, row.height / 2, 24 * px, row.height),
      ]);
      expect(sharedFrames(tester), [(18.0, 30.0)]);
      expect(
        cutStartsOf(tester),
        [0.0, 24 * px, 52 * px],
        reason: 'b begins at its place, not where its のりしろ is drawn from',
      );
    });
  });

  group('while a drag is in flight', () {
    testWidgets('🚨a cut\'s end dragged takes the key on its last frame along, '
        'live — 🗣️I-73-camera-row-Q4', (tester) async {
      // c [52, 64), keyed on its first frame and its last.
      final session = await pumpPanel(tester, cKeys: [0, 11]);
      expect(marksOf(tester, 'c-cam'), [52, 63], reason: '⛔전제');

      expect(
        session.edgeDrag.beginCutEdgeDrag(
          cutId: const CutId('c'),
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
        reason: '⛔전제',
      );
      session.edgeDrag.updateCutEdgeDrag(3);
      await tester.pumpAndSettle();
      expect(marksOf(tester, 'c-cam'), [52, 66], reason: 'with the end');

      session.edgeDrag.cancelCutEdgeDrag();
      await tester.pumpAndSettle();
      expect(marksOf(tester, 'c-cam'), [52, 63]);
    });

    testWidgets('🚨an O.L\'s edge dragged moves the stretch it splits, live', (
      tester,
    ) async {
      final session = await pumpPanel(tester, transitions: ol);
      expect(sharedFrames(tester), [(18.0, 30.0)], reason: '⛔전제');

      expect(
        session.edgeDrag.beginTransitionEdgeDrag(
          spanStartIndex: 18,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
        reason: '⛔전제',
      );
      session.edgeDrag.updateTransitionEdgeDrag(2);
      await tester.pumpAndSettle();
      expect(sharedFrames(tester), [(18.0, 32.0)], reason: 'a leaves later');

      session.edgeDrag.cancelTransitionEdgeDrag();
      await tester.pumpAndSettle();
      expect(sharedFrames(tester), [(18.0, 30.0)]);
    });

    testWidgets('🚨…and where it is let go, it stays', (tester) async {
      final session = await pumpPanel(tester, transitions: ol);

      session.edgeDrag.beginTransitionEdgeDrag(
        spanStartIndex: 18,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateTransitionEdgeDrag(2);
      session.edgeDrag.endTransitionEdgeDrag();
      await tester.pumpAndSettle();

      expect(
        sharedFrames(tester),
        [(18.0, 32.0)],
        reason: 'the cuts did not move, but the track\'s transitions did',
      );
    });

    testWidgets('🚨a cut\'s end dragged carries the O.L it crosses, live', (
      tester,
    ) async {
      final session = await pumpPanel(tester, transitions: ol);

      expect(
        session.edgeDrag.beginCutEdgeDrag(
          cutId: a,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
        reason: '⛔전제',
      );
      session.edgeDrag.updateCutEdgeDrag(2);
      await tester.pumpAndSettle();
      expect(
        sharedFrames(tester),
        [(20.0, 32.0)],
        reason: 'the O.L follows the boundary it crosses',
      );

      session.edgeDrag.cancelCutEdgeDrag();
      await tester.pumpAndSettle();
      expect(sharedFrames(tester), [(18.0, 30.0)]);
    });
  });

  group('the camera\'s moves — I-73 ⑤', () {
    /// The moves the row writes, by [camera] — the frames each word stands
    /// over on the track, and the word.
    List<(int, int, String)> wordsOf(WidgetTester tester, String camera) {
      final row = tester.getRect(cameraStrip);
      final prefix = 'storyboard-camera-lane-stretch-word-$camera-';
      return [
        for (final element in find
            .byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(prefix),
            )
            .evaluate())
          () {
            final rect = tester.getRect(find.byWidget(element.widget));
            final name = tester.widget<TimelineSpanName>(
              find.descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(TimelineSpanName),
              ),
            );
            return (
              ((rect.left - row.left) / ppf(tester)).round(),
              ((rect.right - row.left) / ppf(tester)).round(),
              name.text,
            );
          }(),
      ]..sort((x, y) => x.$1.compareTo(y.$1));
    }

    testWidgets('🎯each stretch a cut\'s camera moves along is named over its '
        'line, at the cut\'s own place — the last held to the cut', (
      tester,
    ) async {
      await pumpPanel(tester);

      expect(wordsOf(tester, 'a-cam'), [
        (0, 13, 'PAN'),
        (12, 21, 'PAN'),
        (20, 24, 'PAN'),
      ], reason: 'a\'s keys 0 · 12 · 20 · 30, the last past its end');
      expect(wordsOf(tester, 'b-cam'), [(26, 31, 'PAN'), (30, 37, 'PAN')]);
    });

    testWidgets('🚨over an O.L a move is named only where its cut runs on the '
        'one line — two lines leave no room for a word', (tester) async {
      await pumpPanel(tester, transitions: ol);

      expect(wordsOf(tester, 'a-cam'), [
        (0, 13, 'PAN'),
        (12, 18, 'PAN'),
      ], reason: 'a leaves on the upper line from 18');
      expect(wordsOf(tester, 'b-cam'), [
        (30, 31, 'PAN'),
      ], reason: 'b arrives on the lower line until 30');
    });

    testWidgets('the name is the vocabulary\'s', (tester) async {
      final session = await pumpPanel(tester);
      final vocabulary = session.repository.requireProject().cameraInstructions;
      session.camera.updateCameraInstructionSet(
        CameraInstructionSet(
          defs: [
            for (final def in vocabulary.defs)
              if (def.id == 'pan')
                const CameraInstructionDef(
                  id: 'pan',
                  name: 'パン',
                  iconKey: 'pan',
                )
              else
                def,
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(wordsOf(tester, 'b-cam'), [(26, 31, 'パン'), (30, 37, 'パン')]);
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
      final session = await pumpPanel(tester, transitions: ol);

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

  group('a double click on the row — the timeline camera row\'s own', () {
    setUp(TimelineDoubleTapGate.reset);

    Future<void> clickTwice(WidgetTester tester, Offset point) async {
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
    }

    testWidgets('on an empty cell, keys it', (tester) async {
      final session = await pumpPanel(tester);

      await clickTwice(tester, at(tester, 28));

      expect(
        keysOf(session, b),
        [2, 4, 6, 12],
        reason: 'b\'s own frame at 28',
      );
      expect(keysOf(session, a), [0, 12, 20, 30]);
    });

    testWidgets('on a key, opens its name', (tester) async {
      final session = await pumpPanel(tester);

      await clickTwice(tester, at(tester, 30));

      expect(find.text(AppText.strings.renameKeyTitle), findsOneWidget);
      expect(keysOf(session, b), [2, 6, 12], reason: 'nothing made');
    });
  });

  group('a sweep on the row — the timeline camera row\'s range, held to the '
      'cut', () {
    /// A mouse pressed at [from] and let go at [to] — two points on the row.
    Future<void> sweep(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    TimelineFrameRangeSelection? selectionOf(EditorSessionManager session) =>
        session.frameRangeSelection.value;

    /// The selection's band, piece by piece, row-local — one piece a line.
    List<Rect> bandOf(WidgetTester tester) {
      final row = tester.getRect(cameraStrip);
      return [
        for (final element in find
            .byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'storyboard-camera-range-selection-',
                  ),
            )
            .evaluate())
          tester
              .getRect(find.byWidget(element.widget))
              .shift(-row.topLeft),
      ];
    }

    testWidgets('🚨selects the frames of the cut it began in, on that cut\'s '
        'camera — and stops at the cut\'s last frame', (tester) async {
      final session = await pumpPanel(tester);

      await sweep(tester, at(tester, 26), at(tester, 58));

      final selection = selectionOf(session)!;
      expect(session.activeCutId, b);
      expect(selection.layerId, const LayerId('b-cam'));
      expect(
        (selection.startIndex, selection.endIndexExclusive),
        (2, 24),
        reason: 'b\'s own 2 to its last, not on into c',
      );
      final band = bandOf(tester).single;
      final row = tester.getRect(cameraStrip);
      expect(band.left, closeTo(26 * ppf(tester), 0.01));
      expect(band.right, closeTo(48 * ppf(tester), 0.01));
      expect((band.top, band.height), (0, row.height));
    });

    testWidgets('🚨over an O.L the line it begins on names the cut, and the '
        'band stands on that line', (tester) async {
      final session = await pumpPanel(tester, transitions: ol);
      final row = tester.getRect(cameraStrip);

      await sweep(
        tester,
        at(tester, 20, across: 0.8),
        at(tester, 22, across: 0.8),
      );
      var selection = selectionOf(session)!;
      expect(selection.layerId, const LayerId('b-cam'));
      expect((selection.startIndex, selection.endIndexExclusive), (2, 5));
      var band = bandOf(tester).single;
      expect(band.left, closeTo(20 * ppf(tester), 0.01));
      expect((band.top, band.height), (row.height / 2, row.height / 2));

      await sweep(
        tester,
        at(tester, 20, across: 0.2),
        at(tester, 22, across: 0.2),
      );
      selection = selectionOf(session)!;
      expect(selection.layerId, const LayerId('a-cam'));
      expect((selection.startIndex, selection.endIndexExclusive), (20, 23));
      band = bandOf(tester).single;
      expect(band.left, closeTo(20 * ppf(tester), 0.01));
      expect((band.top, band.height), (0, row.height / 2));
    });

    testWidgets('a band that runs out of an O.L steps to the middle with its '
        'line', (tester) async {
      final session = await pumpPanel(tester, transitions: ol);
      final row = tester.getRect(cameraStrip);

      await sweep(
        tester,
        at(tester, 26, across: 0.8),
        at(tester, 33, across: 0.8),
      );

      final selection = selectionOf(session)!;
      expect(selection.layerId, const LayerId('b-cam'));
      expect((selection.startIndex, selection.endIndexExclusive), (8, 16));
      final pieces = bandOf(tester)..sort((x, y) => x.left.compareTo(y.left));
      expect(pieces, hasLength(2));
      expect(
        (pieces[0].left / ppf(tester), pieces[0].right / ppf(tester)),
        (26, 30),
        reason: 'the stretch b shares with a: the lower half',
      );
      expect(
        (pieces[0].top, pieces[0].height),
        (row.height / 2, row.height / 2),
      );
      expect(
        (pieces[1].left / ppf(tester), pieces[1].right / ppf(tester)),
        (30, 34),
      );
      expect((pieces[1].top, pieces[1].height), (0, row.height));
    });

    testWidgets('🚨a sweep begun on another cut selects there, even on a frame '
        'its number shares with the selection', (tester) async {
      final session = await pumpPanel(tester);
      await sweep(tester, at(tester, 26), at(tester, 30));
      expect(selectionOf(session)!.layerId, const LayerId('b-cam'));

      await sweep(tester, at(tester, 3), at(tester, 5));

      final selection = selectionOf(session)!;
      expect(selection.layerId, const LayerId('a-cam'));
      expect((selection.startIndex, selection.endIndexExclusive), (3, 6));
      expect(keysOf(session, b), [2, 6, 12], reason: 'nothing moved');
    });

    testWidgets('a tap on the row lets the selection go', (tester) async {
      final session = await pumpPanel(tester);
      await sweep(tester, at(tester, 26), at(tester, 30));
      expect(selectionOf(session), isNotNull, reason: '⛔전제');

      await tester.tapAt(at(tester, 40), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(selectionOf(session), isNull);
    });

    testWidgets('🚨a sweep inside the frames another row of the cut has '
        'selected selects the camera\'s — it moves nothing of that row', (
      tester,
    ) async {
      final session = await pumpPanel(tester);
      session
        ..selectCut(b)
        ..updateFrameRangeSelectionDrag(
          layerId: const LayerId('b-cel'),
          anchorIndex: 0,
          headIndex: 20,
        );
      await tester.pumpAndSettle();
      expect(selectionOf(session)!.layerId, const LayerId('b-cel'));

      await sweep(tester, at(tester, 26), at(tester, 30));

      final selection = selectionOf(session)!;
      expect(selection.layerId, const LayerId('b-cam'));
      expect((selection.startIndex, selection.endIndexExclusive), (2, 7));
      expect(keysOf(session, b), [2, 6, 12]);
    });

    testWidgets('a selection the timeline made past the cut\'s end draws no '
        'band here', (tester) async {
      final session = await pumpPanel(tester);
      session
        ..selectCut(b)
        ..updateFrameRangeSelectionDrag(
          layerId: const LayerId('b-cam'),
          anchorIndex: 26,
          headIndex: 28,
        );
      await tester.pumpAndSettle();
      expect(selectionOf(session)!.layerId, const LayerId('b-cam'));

      expect(bandOf(tester), isEmpty);
    });

    testWidgets('🚨a drag from inside the selection moves its keys along the '
        'cut\'s own frames', (tester) async {
      final session = await pumpPanel(tester);
      await sweep(tester, at(tester, 26), at(tester, 30));
      final held = selectionOf(session)!;
      expect(
        (held.startIndex, held.endIndexExclusive),
        (2, 7),
        reason: '⛔전제: b\'s keys 2 and 6 held',
      );

      await sweep(tester, at(tester, 27), at(tester, 30));

      expect(keysOf(session, b), [5, 9, 12]);
      expect(keysOf(session, a), [0, 12, 20, 30]);
    });

    testWidgets('a gap takes no sweep: nothing is selected there', (
      tester,
    ) async {
      final session = await pumpPanel(tester);

      await sweep(tester, at(tester, 49), at(tester, 51));

      expect(selectionOf(session), isNull);
    });
  });
}
