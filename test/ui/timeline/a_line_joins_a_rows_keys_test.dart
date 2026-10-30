import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/key_side.dart' show KeySideKind;
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart' show sizedAlong;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show TimelineGridLaw;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineJoiningLineWidth;
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// THE LINE BETWEEN A ROW'S KEYS (I-73, 유저 2026-10-08).
///
/// 「슬슬 키가 2개이상일땐 키 끼리 선으로 이어주는거? … 점선말고
/// 이어진선으로하자 … 그 선을 fx나 카메라나 동일하게 적용되는거 맞지? 아무튼
/// 키에도 적용. se 글로벌행도 타임라인패널에서 똑같이」 — and where it runs:
/// 「첫 키 앞은 비움. 근데 키 하나면 여전히 선 안넣고, 두개일때만 처음이랑
/// 마지막 사이에 선 그리도록하자. 즉 마지막 키 뒷부분은 선 안그림. se행이든
/// 트랜스폼이든 카메라든 전부 동일. 즉 사이만 존재하도록」.
///
/// One drawing ([TimelineLaneKeysLine]) for every row that marks keys on
/// the frame axis: a lane's band — a member's and a group header's, along
/// the timeline and down the sheet — and the camera row's summary.
void main() {
  final layer = Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: const [],
  );
  const cell = 20.0;
  const metrics = TimelineGridMetrics(frameCellWidth: cell);

  /// A lane keyed at [keys], each key straight but where [marks] gives it
  /// another mark.
  PropertyLaneRow laneOf(
    Set<int> keys, {
    bool header = false,
    Map<int, KeyMark> marks = const {},
  }) => PropertyLaneRow(
    laneId: header ? 'transform-group' : 'position',
    label: header ? 'Transform' : 'Position',
    keyMarks: {
      for (final frame in keys) frame: marks[frame] ?? KeyMark.linear,
    },
    isGroupHeader: header,
  );

  Future<void> pumpBand(
    WidgetTester tester,
    PropertyLaneRow lane, {
    int frameStartIndex = 0,
    int frameEndIndexExclusive = 20,
    Axis axis = Axis.horizontal,
    Color? ground,
  }) async {
    Widget band = TimelineLaneFrameRow(
      layer: layer,
      lane: lane,
      frameStartIndex: frameStartIndex,
      frameEndIndexExclusive: frameEndIndexExclusive,
      leadingFrameSpacerWidth: 0,
      trailingFrameSpacerWidth: 0,
      metrics: metrics,
      axis: axis,
    );
    if (ground != null) {
      band = TimelineGridLaw(
        ground: ground,
        framesPerSecond: 24,
        child: band,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: sizedAlong(axis, along: 480, across: 40, child: band),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final line = find.byType(TimelineLaneKeysLine);

  /// What the one line on screen strokes, in the screen's coordinates —
  /// and the boxes it is kept out of while it does.
  _Stroke strokeOf(WidgetTester tester) {
    final paint = find.descendant(of: line, matching: find.byType(CustomPaint));
    final spy = _StrokeSpy();
    tester
        .widget<CustomPaint>(paint)
        .painter!
        .paint(spy, tester.getSize(paint));
    final origin = tester.getTopLeft(paint);
    final stroke = theOne(spy.strokes);
    return (
      from: stroke.from + origin,
      to: stroke.to + origin,
      width: stroke.width,
      color: stroke.color,
      clearOf: [for (final box in stroke.clearOf) box.shift(origin)],
    );
  }

  /// The box [laneId]'s mark of its key at [frame] is drawn in.
  Rect markBox(WidgetTester tester, String laneId, int frame) =>
      tester.getRect(
        find.descendant(
          of: find.byKey(
            ValueKey<String>('timeline-lane-key-layer-a-$laneId-$frame'),
          ),
          matching: find.byType(CustomPaint),
        ),
      );

  /// Where the mark of [laneId]'s key at [frame] stands — its middle.
  Matcher atMark(WidgetTester tester, String laneId, int frame) =>
      offsetMoreOrLessEquals(
        tester.getCenter(
          find.byKey(
            ValueKey<String>('timeline-lane-key-layer-a-$laneId-$frame'),
          ),
        ),
      );

  group('the frames it runs over', () {
    test('from the first key to the last, whatever order they come in', () {
      expect(timelineKeysLineSpan({3, 9}), (first: 3, last: 9));
      expect(timelineKeysLineSpan([14, 3, 9]), (first: 3, last: 14));
    });

    test('no two keys, no line: a row with none, a key alone', () {
      expect(timelineKeysLineSpan(const <int>{}), isNull);
      expect(timelineKeysLineSpan({5}), isNull);
    });
  });

  group('a lane\'s band', () {
    testWidgets('one line, from its first mark to its last — in the row\'s '
        'colour, as heavy as a hold\'s', (tester) async {
      await pumpBand(tester, laneOf({9, 3, 14}));
      expect(line, findsOneWidget);
      final stroke = strokeOf(tester);
      expect(stroke.from, atMark(tester, 'position', 3));
      expect(stroke.to, atMark(tester, 'position', 14));
      // A paint keeps its width in 32 bits and its colour in 8 a channel.
      expect(
        stroke.width,
        moreOrLessEquals(timelineJoiningLineWidth, epsilon: 1e-6),
      );
      expect(stroke.color.toARGB32(), layerMarkColor(layer.mark).toARGB32());
    });

    testWidgets('on the light palette too, over its ground, the label as it '
        'is (I-143: 「색라벨 진하게한거면 너무 진하니까 그냥 기존이랑 똑같이」)', (
      tester,
    ) async {
      AppColors.accentSettings.value = const AppAccentSettings(
        mode: AppColorMode.light,
      );
      addTearDown(
        () => AppColors.accentSettings.value = const AppAccentSettings(),
      );
      await pumpBand(tester, laneOf({3, 14}), ground: AppPalette.light.surface);
      expect(
        strokeOf(tester).color.toARGB32(),
        layerMarkColor(layer.mark).toARGB32(),
      );
    });

    testWidgets('nothing before the first key, nothing after the last', (
      tester,
    ) async {
      await pumpBand(tester, laneOf({3, 14}));
      final box = tester.getRect(line);
      expect(box.left, 3 * cell, reason: 'the first key\'s own cell');
      expect(box.right, 15 * cell, reason: 'the last key\'s own cell');
      final stroke = strokeOf(tester);
      expect(stroke.from.dx, greaterThan(box.left));
      expect(stroke.to.dx, lessThan(box.right));
    });

    testWidgets('a key alone has no line, and a row with no key has none', (
      tester,
    ) async {
      await pumpBand(tester, laneOf({5}));
      expect(line, findsNothing);
      await pumpBand(tester, laneOf(const {}));
      expect(line, findsNothing);
    });

    testWidgets('it lies UNDER the marks', (tester) async {
      await pumpBand(tester, laneOf({3, 14}));
      final stack = tester.widget<Stack>(
        find.ancestor(of: line, matching: find.byType(Stack)).first,
      );
      expect(
        (stack.children.first as Positioned).child,
        isA<TimelineLaneKeysLine>(),
        reason: 'the first child is painted first',
      );
      expect(stack.children.length, greaterThan(1), reason: 'then the marks');
    });

    testWidgets('a group header\'s union is joined as its members are', (
      tester,
    ) async {
      await pumpBand(tester, laneOf({2, 8}, header: true));
      final stroke = strokeOf(tester);
      expect(stroke.from, atMark(tester, 'transform-group', 2));
      expect(stroke.to, atMark(tester, 'transform-group', 8));
    });

    testWidgets('down the sheet it runs down', (tester) async {
      await pumpBand(tester, laneOf({3, 14}), axis: Axis.vertical);
      expect(
        tester
            .widget<TimelineLaneKeyMarker>(
              find.byKey(
                const ValueKey<String>('timeline-lane-key-layer-a-position-3'),
              ),
            )
            .axis,
        Axis.vertical,
        reason: 'the marks stand on the sheet as the line runs down it',
      );
      final stroke = strokeOf(tester);
      expect(stroke.from, atMark(tester, 'position', 3));
      expect(stroke.to, atMark(tester, 'position', 14));
      expect(stroke.from.dx, stroke.to.dx);
      expect(stroke.to.dy, greaterThan(stroke.from.dy));
    });
  });

  group('a band shows the part of the line its window holds', () {
    testWidgets('a window opening past the first key: the line comes in at '
        'its edge and stops at the last mark', (tester) async {
      await pumpBand(
        tester,
        laneOf({3, 9}),
        frameStartIndex: 6,
        frameEndIndexExclusive: 12,
      );
      final stroke = strokeOf(tester);
      expect(stroke.from.dx, 0, reason: 'the band\'s own first edge');
      expect(stroke.to, atMark(tester, 'position', 9));
    });

    testWidgets('a window closing before the last key: the line leaves at '
        'its edge', (tester) async {
      await pumpBand(
        tester,
        laneOf({8, 30}),
        frameStartIndex: 6,
        frameEndIndexExclusive: 12,
      );
      final stroke = strokeOf(tester);
      expect(stroke.from, atMark(tester, 'position', 8));
      expect(stroke.to.dx, 6 * cell, reason: 'the band\'s own last edge');
    });

    testWidgets('a window between two keys far apart: edge to edge', (
      tester,
    ) async {
      await pumpBand(
        tester,
        laneOf({0, 30}),
        frameStartIndex: 6,
        frameEndIndexExclusive: 12,
      );
      final stroke = strokeOf(tester);
      expect((stroke.from.dx, stroke.to.dx), (0, 6 * cell));
    });

    testWidgets('a window keeps the line out of the ring it holds, where the '
        'ring stands — and of none it does not hold', (tester) async {
      await pumpBand(
        tester,
        laneOf(
          {0, 8, 30},
          header: true,
          marks: {0: KeyMark.mixed, 8: KeyMark.mixed, 30: KeyMark.mixed},
        ),
        frameStartIndex: 6,
        frameEndIndexExclusive: 12,
      );
      final box = tester.getRect(line);
      final ring = markBox(tester, 'transform-group', 8);
      expect(strokeOf(tester).clearOf, [
        rectMoreOrLessEquals(
          Rect.fromLTRB(ring.left, box.top, ring.right, box.bottom),
        ),
      ]);
    });

    testWidgets('a window the line does not reach has none of it', (
      tester,
    ) async {
      for (final keys in [
        {0, 3},
        {14, 20},
      ]) {
        await pumpBand(
          tester,
          laneOf(keys),
          frameStartIndex: 6,
          frameEndIndexExclusive: 12,
        );
        expect(line, findsNothing, reason: '$keys');
      }
    });
  });

  group('the camera row\'s summary', () {
    const rowExtent = 28.0;
    final union = laneOf({10, 4, 12}, header: true);

    test('its marks ride a span each — and the line one span under them, '
        'from the first key\'s cell through the last\'s', () {
      final spans = timelineUnionKeyMarkerSpans(
        keyPrefix: 'timeline',
        layer: layer,
        lane: union,
        crossExtent: rowExtent,
        axis: Axis.horizontal,
      ).cast<TimelineFrameSpan>();
      expect(spans, hasLength(4));
      expect(
        spans.first.placement,
        const TimelineFrameSpanPlacement(startIndex: 4, endIndexExclusive: 13),
      );
      final drawn = spans.first.child as TimelineLaneKeysLine;
      expect(drawn.cells, 9);
      expect((drawn.startsAtKey, drawn.endsAtKey), (true, true));
      expect(drawn.layer, same(layer), reason: 'the row\'s look');
    });

    test('a key alone has its mark and no line', () {
      final spans = timelineUnionKeyMarkerSpans(
        keyPrefix: 'timeline',
        layer: layer,
        lane: laneOf({7}, header: true),
        crossExtent: rowExtent,
        axis: Axis.horizontal,
      ).cast<TimelineFrameSpan>();
      expect(spans, hasLength(1));
      expect(spans.single.child, isNot(isA<TimelineLaneKeysLine>()));
    });

    /// [lane]'s summary laid on a row of its own, along [axis].
    Future<void> pumpSummary(
      WidgetTester tester,
      PropertyLaneRow lane, {
      Axis axis = Axis.horizontal,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: sizedAlong(
                axis,
                along: 20 * cell,
                across: rowExtent,
                child: TimelineFixedFrameSpanLayer(
                  geometry: const TimelineFrameGeometry(
                    frameCellExtent: cell,
                    frameStartIndex: 0,
                    frameEndIndexExclusive: 20,
                    leadingFrameSpacerWidth: 0,
                    trailingFrameSpacerWidth: 0,
                  ),
                  crossAxisExtent: rowExtent,
                  axis: axis,
                  children: timelineUnionKeyMarkerSpans(
                    keyPrefix: 'timeline',
                    layer: layer,
                    lane: lane,
                    crossExtent: rowExtent,
                    axis: axis,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final axis in Axis.values) {
      testWidgets('laid on the row it runs from the first mark to the last '
          '($axis)', (tester) async {
        await pumpSummary(tester, union, axis: axis);
        final stroke = strokeOf(tester);
        expect(stroke.from, atMark(tester, 'transform-group', 4));
        expect(stroke.to, atMark(tester, 'transform-group', 12));
      });
    }

    testWidgets('a ring on it keeps the line out of its box', (tester) async {
      await pumpSummary(
        tester,
        laneOf({10, 4, 12}, header: true, marks: {10: KeyMark.mixed}),
      );
      final box = tester.getRect(line);
      final ring = markBox(tester, 'transform-group', 10);
      expect(strokeOf(tester).clearOf, [
        rectMoreOrLessEquals(
          Rect.fromLTRB(ring.left, box.top, ring.right, box.bottom),
        ),
      ]);
    });
  });

  // I-89 ②: a union's ○ where its members disagree is HOLLOW — the drawing
  // the user picked (option 나, 유저 2026-10-10 「2. 추천대로」) has the line
  // stop at its edge.
  group('a hollow mark is not run through', () {
    testWidgets('the line stops at a ring\'s box and goes on past it — one '
        'line still, from the first mark to the last', (tester) async {
      await pumpBand(
        tester,
        laneOf({2, 8, 14}, header: true, marks: {8: KeyMark.mixed}),
      );
      final box = tester.getRect(line);
      final ring = markBox(tester, 'transform-group', 8);
      final stroke = strokeOf(tester);
      expect(stroke.from, atMark(tester, 'transform-group', 2));
      expect(stroke.to, atMark(tester, 'transform-group', 14));
      expect(stroke.clearOf, [
        rectMoreOrLessEquals(
          Rect.fromLTRB(ring.left, box.top, ring.right, box.bottom),
        ),
      ]);
    });

    testWidgets('⛔every other mark stands ON the line, whatever its sides — '
        'it is kept out of none', (tester) async {
      await pumpBand(
        tester,
        laneOf(
          {2, 8, 14},
          marks: const {
            2: SidesKeyMark(
              incoming: KeySideKind.ease,
              outgoing: KeySideKind.ease,
            ),
            8: SidesKeyMark(
              incoming: KeySideKind.linear,
              outgoing: KeySideKind.hold,
            ),
            14: SidesKeyMark(
              incoming: KeySideKind.auto,
              outgoing: KeySideKind.auto,
            ),
          },
        ),
      );
      expect(strokeOf(tester).clearOf, isEmpty);
    });

    testWidgets('down the sheet it is kept out of the ring down the sheet', (
      tester,
    ) async {
      await pumpBand(
        tester,
        laneOf({2, 8, 14}, header: true, marks: {8: KeyMark.mixed}),
        axis: Axis.vertical,
      );
      final box = tester.getRect(line);
      final ring = markBox(tester, 'transform-group', 8);
      expect(strokeOf(tester).clearOf, [
        rectMoreOrLessEquals(
          Rect.fromLTRB(box.left, ring.top, box.right, ring.bottom),
        ),
      ]);
    });

    testWidgets('a line handed another ring is painted again', (tester) async {
      CustomPainter painter() => tester
          .widget<CustomPaint>(
            find.descendant(of: line, matching: find.byType(CustomPaint)),
          )
          .painter!;
      await pumpBand(
        tester,
        laneOf({2, 8, 14}, header: true, marks: {8: KeyMark.mixed}),
      );
      final ringed = painter();
      await pumpBand(tester, laneOf({2, 8, 14}, header: true));
      final plain = painter();
      expect(plain.shouldRepaint(ringed), isTrue);
      await pumpBand(tester, laneOf({2, 8, 14}, header: true));
      expect(painter().shouldRepaint(plain), isFalse, reason: 'the same line');
    });
  });

  // 「그 선」 is one kind of line: what names a camera's move will ride the
  // instruction's, so the three weigh the same.
  testWidgets('an instruction\'s duration line weighs what the line between '
      'keys does', (tester) async {
    final transition = Layer(
      id: const LayerId('transition'),
      name: 'T',
      kind: LayerKind.transition,
      frames: const [],
      instructions: {
        2: const InstructionEvent(instructionId: 'wipe', length: 6),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 20 * cell,
              height: 28,
              child: TimelineFixedFrameSpanLayer(
                geometry: const TimelineFrameGeometry(
                  frameCellExtent: cell,
                  frameStartIndex: 0,
                  frameEndIndexExclusive: 20,
                  leadingFrameSpacerWidth: 0,
                  trailingFrameSpacerWidth: 0,
                ),
                crossAxisExtent: 28,
                axis: Axis.horizontal,
                children: timelineRowInstructionOverlays(
                  layer: transition,
                  frameStartIndex: 0,
                  frameEndIndexExclusive: 20,
                  axis: Axis.horizontal,
                  defById: CameraInstructionSet.standard.defById,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final mark = find.descendant(
      of: find.byKey(
        const ValueKey<String>('timeline-instruction-transition-2'),
      ),
      matching: find.byType(CustomPaint),
    );
    final spy = _StrokeSpy();
    tester.widget<CustomPaint>(mark).painter!.paint(spy, tester.getSize(mark));
    expect(
      theOne(spy.strokes).width,
      moreOrLessEquals(timelineJoiningLineWidth, epsilon: 1e-6),
    );
  });

  // The row as the app mounts it: a cut's camera keyed twice.
  group('on the camera row itself', () {
    Project project() => Project(
      id: const ProjectId('camera-line'),
      name: 'Camera line',
      createdAt: DateTime.utc(2026, 10, 8),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('cut-0'),
              name: 'cut-0',
              duration: 12,
              canvasSize: const CanvasSize(width: 1280, height: 720),
              camera: CutCamera.empty(),
              layers: [
                Layer(
                  id: const LayerId('drawing'),
                  name: 'Drawing',
                  frames: const [],
                ),
                Layer(
                  id: const LayerId('camera'),
                  name: 'Camera',
                  kind: LayerKind.camera,
                  frames: const [],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    for (final sheet in [false, true]) {
      testWidgets('two keys are joined '
          '${sheet ? 'down the x-sheet' : 'along the timeline'}, one key is '
          'not', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(home: HomePage(initialProject: project())),
        );
        await tester.pumpAndSettle();
        if (sheet) {
          await tester.tap(
            find.byKey(
              const ValueKey<String>('timeline-orientation-toggle-button'),
            ),
          );
          await tester.pumpAndSettle();
        }
        final session = tester
            .widget<EditorWorkspace>(find.byType(EditorWorkspace))
            .session;

        Future<void> keyAt(int frame) async {
          session.selectFrameIndex(frame);
          session.camera.setCameraKeyframeAtCurrentFrame(
            CameraPose(center: CanvasPoint(x: 10.0 * frame, y: 10), zoom: 1),
          );
          await tester.pumpAndSettle();
        }

        await keyAt(2);
        expect(line, findsNothing, reason: 'a key alone');
        await keyAt(8);
        expect(line, findsOneWidget);
        expect(
          tester.widget<TimelineLaneKeysLine>(line).axis,
          sheet ? Axis.vertical : Axis.horizontal,
        );
        for (final marker in tester.widgetList<TimelineLaneKeyMarker>(
          find.byType(TimelineLaneKeyMarker),
        )) {
          expect(
            marker.axis,
            sheet ? Axis.vertical : Axis.horizontal,
            reason: 'a mark stands on its row\'s axis',
          );
        }
        final stroke = strokeOf(tester);
        if (sheet) {
          expect(stroke.from.dx, moreOrLessEquals(stroke.to.dx));
          expect(stroke.to.dy, greaterThan(stroke.from.dy));
        } else {
          expect(stroke.from.dy, moreOrLessEquals(stroke.to.dy));
          expect(stroke.to.dx, greaterThan(stroke.from.dx));
        }
      });
    }
  });
}

/// One line a painter strokes, and the boxes it is kept out of then.
typedef _Stroke =
    ({Offset from, Offset to, double width, Color color, List<Rect> clearOf});

/// Records what a painter strokes as lines — and the boxes each is kept
/// out of while it is.
class _StrokeSpy implements Canvas {
  final strokes = <_Stroke>[];

  /// The boxes kept out of, at each depth of save.
  final _clearOf = [<Rect>[]];

  @override
  void save() => _clearOf.add([..._clearOf.last]);

  @override
  void restore() {
    if (_clearOf.length > 1) {
      _clearOf.removeLast();
    }
  }

  @override
  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    if (clipOp == ClipOp.difference) {
      _clearOf.last.add(rect);
    }
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    strokes.add((
      from: p1,
      to: p2,
      width: paint.strokeWidth,
      color: paint.color,
      clearOf: [..._clearOf.last],
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The only one of [found] — a pin that expects one fails by saying how
/// many there were.
T theOne<T>(Iterable<T> found) {
  final all = found.toList();
  expect(all, hasLength(1));
  return all.single;
}
