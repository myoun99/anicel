import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineFrameRangeSelection, TimelineLaneSelection;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/lane_graph_box_stretch.dart'
    show LaneGraphBoxPoint, laneGraphBoxMiddle;
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart'
    show LaneGraphLine, LaneGraphReach;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_grid_range_callbacks.dart'
    show timelineGridLaneRangeCallbacks;
import 'package:anicel/src/ui/dashed_path.dart' show antsColour;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// **I-3 ⑤ — a box drawn on a graph's ground picks the keys it holds.**
///
/// 🗣️I-3-Q3 (유저 2026-10-21): 「레인 칸 선택으로 (상자가 걸친 프레임 × 안에
/// 든 키의 레인)」 — the frames the box spans, across the lanes of the keys
/// inside it. 🗣️I-3-Q4 (유저 2026-10-22): 「레인 행을 끌 때와 똑같이」 — the
/// keys of two layers, or of two cuts, picked as a lane drag across them
/// picks. And a key picked on to them with Shift, and a line's every key
/// with Alt (graph-key-pick-rest), the same way.
void main() {
  Layer layerOf(String id, TransformTrack transform) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    transformTrack: transform,
  );
  PropertyTrack<double> linear(Map<int, double> keys) {
    var track = PropertyTrack<double>();
    for (final MapEntry(key: frame, :value) in keys.entries) {
      track = track.withKey(
        frame,
        value,
        incoming: KeySide.linear,
        outgoing: KeySide.linear,
      );
    }
    return track;
  }

  LaneGraphLine lineOf(Layer layer, String laneId, {LaneGraphReach? reach}) {
    final lanes = propertyLanesForRow(
      layer: layer,
      rows: [layer],
      expandedGroupKeys: {
        laneGroupKey(layer.id, transformGroupHeaderLane.laneId),
      },
      valueSourceAt: (frame) => (layer: layer, frame: frame),
      poseCentre: const CanvasSize(width: 400, height: 300),
      hasPlugin: null,
    );
    return (
      layer: layer,
      lane: lanes.firstWhere((lane) => lane.laneId == laneId),
      reach: reach,
    );
  }

  /// Rotation keyed on 0 and 16, opacity on 4 and 12.
  final both = layerOf(
    'c',
    TransformTrack.empty().copyWith(
      rotation: linear({0: 0, 16: 90}),
      opacity: linear({4: 1, 12: 0.25}),
    ),
  );
  final rising = layerOf(
    'b',
    TransformTrack.empty().copyWith(rotation: linear({0: 0, 8: 40})),
  );
  final falling = layerOf(
    'd',
    TransformTrack.empty().copyWith(rotation: linear({0: 30, 8: 0})),
  );

  const cell = 12.0;
  const size = Size(48 * cell, 196);
  late ValueNotifier<TimelineFrameGeometry> geometry;
  late ValueNotifier<int> bucket;
  setUp(() {
    geometry = ValueNotifier(
      const TimelineFrameGeometry(
        viewExtentPx: 48 * cell,
        frameCellExtent: cell,
        frameStartIndex: 0,
        frameEndIndexExclusive: 48,
      ),
    );
    bucket = ValueNotifier(0);
  });
  tearDown(() {
    geometry.dispose();
    bucket.dispose();
  });

  group('the picture', () {
    final selection = ValueNotifier<TimelineLaneSelection?>(null);
    tearDownAll(selection.dispose);

    String rowsOf(List<LaneRowAddress> rows) => [
      for (final row in rows) '${row.layerId.value}:${row.laneId}',
    ].join(',');

    /// The picture drawing [own] and [guests], [wide] — its frames' own
    /// width, unless more — what its lanes' verbs are told heard into
    /// [heard].
    Future<void> pump(
      WidgetTester tester,
      List<String> heard, {
      required List<LaneGraphLine> own,
      List<LaneGraphLine> guests = const [],
      double wide = 48 * cell,
    }) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: wide,
            height: size.height,
            child: LaneGraphPicture(
              own: own,
              guests: guests,
              frameAxis: (
                geometry: geometry,
                windowBucket: bucket,
                axis: Axis.horizontal,
                laneExtent: timelineLayerRowHeight,
                playhead: null,
                frameCount: 0,
              ),
              edits: null,
              mode: LaneGraphMode.value,
              lanes: TimelineLaneRangeCallbacks(
                selection: selection,
                onSelectUpdate: (layer, lane, anchor, head, across) =>
                    heard.add('pick ${layer.value} $lane'),
                onSelectRows: (rows, anchor, head) =>
                    heard.add('rows ${rowsOf(rows)} $anchor-$head'),
                onTapAt: (_, _, _) => heard.add('stand'),
                onTapClear: () => heard.add('clear'),
                onMoveBegin: () => false,
                onMoveUpdate: (_, {stretch, values, landings}) {},
                onMoveEnd: () {},
                onMoveCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );

    TimelineLaneGraphPainter painterOf(WidgetTester tester) =>
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(LaneGraphPicture),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as TimelineLaneGraphPainter;

    /// The picture as it paints.
    RenderObject paintOf(WidgetTester tester) => tester.renderObject(
      find.descendant(
        of: find.byType(LaneGraphPicture),
        matching: find.byType(CustomPaint),
      ),
    );

    /// A path stroked in the ants' black: the box ([antsColour]).
    final ants = paints
      ..something(
        (method, arguments) =>
            method == #drawPath &&
            (arguments.last as Paint).color.toARGB32() ==
                antsColour.toARGB32(),
      );

    /// A point on the graph's ground in frame [frame]'s cell, [across] it.
    Offset ground(WidgetTester tester, int frame, double across) {
      final at = Offset(geometry.value.edgeAt(frame) + cell / 2, across);
      final painter = painterOf(tester);
      expect(
        (painter.keyAt(at, size), painter.handleAt(at, size)),
        (null, null),
        reason: '⛔전제: nothing drawn takes the press there',
      );
      return at;
    }

    testWidgets('a mouse\'s drag on the ground draws a box, and picks as it '
        'grows the frames it spans across the lanes of the keys inside — '
        'let go of, it goes and the pick stays', (tester) async {
      final heard = <String>[];
      final own = [lineOf(both, 'rotation'), lineOf(both, 'opacity')];
      await pump(tester, heard, own: own);
      final keys = painterOf(tester).keysIn(size);
      expect(
        keys.every((key) => key.at.dy > 2 && key.at.dy < size.height - 2),
        isTrue,
        reason: '⛔전제: every key within the box\'s reach across',
      );

      final from = ground(tester, 2, 2);
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final to = Offset(geometry.value.edgeAt(5) + 1, size.height - 2);
      await gesture.moveTo(to);
      await tester.pump();
      expect(heard, ['rows c:opacity 2-5']);
      expect(painterOf(tester).box, Rect.fromPoints(from, to));
      expect(paintOf(tester), ants);

      await gesture.moveTo(
        Offset(geometry.value.edgeAt(13) + 1, size.height - 2),
      );
      await tester.pump();
      await gesture.moveTo(
        Offset(geometry.value.edgeAt(17) + 1, size.height - 2),
      );
      await tester.pump();
      expect(heard, [
        'rows c:opacity 2-5',
        'rows c:opacity 2-13',
        'rows c:rotation,c:opacity 2-17',
      ]);

      await gesture.up();
      await tester.pump();
      expect(painterOf(tester).box, isNull);
      expect(paintOf(tester), isNot(ants));
      expect(heard, hasLength(3), reason: 'the pick stays as it was');
    });

    group('Shift and Alt (graph-key-pick-rest)', () {
      tearDown(() => selection.value = null);

      /// Where [layer]'s [laneId] line is drawn on [frame].
      Offset onTheLine(
        WidgetTester tester,
        Layer layer,
        String laneId,
        int frame,
      ) {
        final painter = painterOf(tester);
        final line = painter.own.singleWhere(
          (line) => line.layer.id == layer.id && line.lane.laneId == laneId,
        );
        final fit = painter.fits[laneGroupKey(layer.id, laneId)]!;
        return Offset(
          laneGraphAlong(frame.toDouble(), geometry.value),
          laneGraphAcross(
            line.lane.curve!.at(frame.toDouble()).single,
            fit.ranges.single,
            size.height,
            Axis.horizontal,
          ),
        );
      }

      Offset keyOn(WidgetTester tester, String laneId, int frame) =>
          painterOf(tester)
              .keysIn(size)
              .singleWhere(
                (key) => key.line.lane.laneId == laneId && key.frame == frame,
              )
              .at;

      Future<void> press(WidgetTester tester, Offset at) async {
        await tester.tapAt(at, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 500));
      }

      // 🗣️graph-key-pick-rest-Q1 (유저 2026-10-22): 「사각형을 그 키까지
      // 넓힌다」.
      testWidgets('with Shift held, a press on a key widens what is picked '
          'to it — its lanes and its frames, as a box picks them — and a '
          'key picked already stays picked', (tester) async {
        final heard = <String>[];
        await pump(
          tester,
          heard,
          own: [lineOf(both, 'rotation'), lineOf(both, 'opacity')],
        );
        selection.value = const TimelineLaneSelection(
          layerId: LayerId('c'),
          laneId: 'rotation',
          startIndex: 0,
          endIndexExclusive: 1,
        );
        await press(tester, keyOn(tester, 'opacity', 12));
        expect(heard, ['pick c opacity'], reason: '⛔전제: no Shift, its own');

        heard.clear();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await press(tester, keyOn(tester, 'opacity', 12));
        expect(heard, ['rows c:rotation,c:opacity 0-12']);

        heard.clear();
        selection.value = const TimelineLaneSelection(
          layerId: LayerId('c'),
          laneId: 'opacity',
          startIndex: 12,
          endIndexExclusive: 13,
        );
        await press(tester, keyOn(tester, 'rotation', 0));
        expect(heard, ['rows c:opacity,c:rotation 0-12'], reason: 'back');

        heard.clear();
        selection.value = const TimelineLaneSelection(
          layerId: LayerId('c'),
          laneId: 'rotation',
          startIndex: 0,
          endIndexExclusive: 13,
          laneIds: ['rotation', 'opacity'],
        );
        await press(tester, keyOn(tester, 'rotation', 0));
        expect(heard, ['rows c:rotation,c:opacity 0-12']);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });

      testWidgets('with Alt held, a press on a line picks every key of its '
          'lane, its first to its last', (tester) async {
        final heard = <String>[];
        await pump(tester, heard, own: [lineOf(both, 'rotation')]);
        await press(tester, onTheLine(tester, both, 'rotation', 8));
        expect(heard, ['clear'], reason: '⛔전제: no Alt, a tap on the ground');

        heard.clear();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await press(tester, onTheLine(tester, both, 'rotation', 8));
        expect(heard, ['rows c:rotation 0-16']);

        // Inside the box round two keys picked, where a press takes the
        // key nearest it: the line, not the key.
        heard.clear();
        selection.value = const TimelineLaneSelection(
          layerId: LayerId('c'),
          laneId: 'rotation',
          startIndex: 0,
          endIndexExclusive: 17,
        );
        await tester.pump();
        expect(painterOf(tester).pickedIn(size).box, isNotNull);
        await press(tester, onTheLine(tester, both, 'rotation', 8));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        expect(heard, ['rows c:rotation 0-16']);
      });

      testWidgets('of the lines a cut, a key widened on to from another cut '
          'is counted in the frames of the cut the pick began in — held to '
          'them, as a box is', (tester) async {
        final heard = <String>[];
        await pump(
          tester,
          heard,
          own: [
            lineOf(rising, 'rotation', reach: (start: 0, end: 10)),
            lineOf(falling, 'rotation', reach: (start: 10, end: 20)),
          ],
        );
        selection.value = const TimelineLaneSelection(
          layerId: LayerId('b'),
          laneId: 'rotation',
          startIndex: 0,
          endIndexExclusive: 1,
        );
        final dsOwnEight = painterOf(tester)
            .keysIn(size)
            .singleWhere(
              (key) => key.line.layer.id == falling.id && key.frame == 8,
            )
            .at;

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await press(tester, dsOwnEight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(heard, ['rows b:rotation,d:rotation 0-9']);
      });
    });

    testWidgets('a box the platform cancels goes, as one let go of does', (
      tester,
    ) async {
      final heard = <String>[];
      await pump(tester, heard, own: [lineOf(rising, 'rotation')]);

      final gesture = await tester.startGesture(
        ground(tester, 6, 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        Offset(geometry.value.edgeAt(10) - 1, size.height - 2),
      );
      await tester.pump();
      expect(painterOf(tester).box, isNotNull, reason: '⛔전제');
      await gesture.cancel();
      await tester.pump();

      expect(painterOf(tester).box, isNull);
      expect(heard, ['rows b:rotation 6-9']);
    });

    testWidgets('a finger\'s box begins the moment it leaves the box it '
        'pressed — its frame\'s cell, or its lane\'s row across — before '
        'the hand\'s slop, as a band\'s select does', (tester) async {
      final heard = <String>[];
      await pump(tester, heard, own: [lineOf(rising, 'rotation')]);
      Future<Rect?> boxAfter(Offset press, Offset by) async {
        final gesture = await tester.startGesture(
          press,
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        await gesture.moveBy(by);
        await tester.pump();
        final box = painterOf(tester).box;
        await gesture.up();
        await tester.pump();
        return box;
      }

      // 8px along, across into frame 7's cell.
      expect(
        await boxAfter(ground(tester, 6, 2), const Offset(8, 0)),
        isNotNull,
      );
      // 8px along, still in frame 6's: the slop not crossed.
      final early = Offset(geometry.value.edgeAt(6) + 1, 2);
      expect(await boxAfter(early, const Offset(8, 0)), isNull);
      // 3px across, over a lane's row's edge.
      const row = timelineLayerRowHeight;
      expect(
        await boxAfter(
          ground(tester, 20, row * 2 - 1),
          const Offset(0, 3),
        ),
        isNotNull,
      );
      expect(
        await boxAfter(ground(tester, 20, row * 2 + 1), const Offset(0, 3)),
        isNull,
      );
    });

    testWidgets('a box pressed past the last frame stands on it, and so does '
        'one drawn past it', (tester) async {
      final heard = <String>[];
      await pump(
        tester,
        heard,
        own: [lineOf(both, 'rotation')],
        wide: 60 * cell,
      );

      var gesture = await tester.startGesture(
        Offset(geometry.value.edgeAt(55), 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(geometry.value.edgeAt(10), size.height - 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(heard, ['rows c:rotation 47-10']);

      heard.clear();
      gesture = await tester.startGesture(
        ground(tester, 10, 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(geometry.value.edgeAt(55), size.height - 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(heard, ['rows c:rotation 10-47']);
    });

    test('a box moved, the transform box shown or hidden, or its anchor '
        'point moved, repaints the picture', () {
      final own = [lineOf(rising, 'rotation')];
      TimelineLaneGraphPainter painter(
        Rect? box, {
        bool transformBox = true,
        LaneGraphBoxPoint pivot = laneGraphBoxMiddle,
      }) => TimelineLaneGraphPainter(
        own: own,
        guests: const [],
        frameAxis: (
          geometry: geometry,
          windowBucket: bucket,
          axis: Axis.horizontal,
          laneExtent: timelineLayerRowHeight,
          playhead: null,
          frameCount: 0,
        ),
        box: box,
        transformBox: transformBox,
        pivot: pivot,
      );

      expect(
        painter(const Rect.fromLTWH(0, 0, 4, 4)).shouldRepaint(painter(null)),
        isTrue,
      );
      expect(
        painter(null, transformBox: false).shouldRepaint(painter(null)),
        isTrue,
      );
      expect(
        painter(
          null,
          pivot: (along: 0, across: 0),
        ).shouldRepaint(painter(null)),
        isTrue,
      );
      expect(painter(null).shouldRepaint(painter(null)), isFalse);
    });

    testWidgets('the box\'s height counts: a key above it is not inside', (
      tester,
    ) async {
      final heard = <String>[];
      await pump(tester, heard, own: [lineOf(rising, 'rotation')]);
      final top = painterOf(
        tester,
      ).keysIn(size).singleWhere((key) => key.frame == 8).at;

      final gesture = await tester.startGesture(
        ground(tester, 9, top.dy + 6),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(geometry.value.edgeAt(7), size.height - 1));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(heard, ['clear']);
    });

    testWidgets('a box over no key lets every key go — and so does a tap on '
        'the ground', (tester) async {
      final heard = <String>[];
      await pump(tester, heard, own: [lineOf(rising, 'rotation')]);

      final gesture = await tester.startGesture(
        ground(tester, 20, 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(geometry.value.edgeAt(30), size.height - 4));
      await tester.pump();
      await gesture.moveTo(Offset(geometry.value.edgeAt(31), size.height - 4));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(heard, ['clear'], reason: 'once, though the box grew');

      heard.clear();
      await tester.tapAt(
        ground(tester, 30, 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(heard, ['clear']);
    });

    testWidgets('a finger draws a box as a lane\'s band selects by it: '
        'where one finger draws, and nowhere else', (tester) async {
      addTearDown(
        () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
      );
      final heard = <String>[];
      await pump(tester, heard, own: [lineOf(rising, 'rotation')]);
      Future<Rect?> drag() async {
        final gesture = await tester.startGesture(
          ground(tester, 6, 2),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        await gesture.moveTo(
          Offset(geometry.value.edgeAt(10) - 1, size.height - 2),
        );
        await tester.pump();
        final box = painterOf(tester).box;
        await gesture.up();
        await tester.pump();
        return box;
      }

      expect(await drag(), isNotNull);
      expect(heard, ['rows b:rotation 6-9']);

      heard.clear();
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
      await tester.pump();
      expect(await drag(), isNull);
      expect(heard, isEmpty);
    });

    testWidgets('the keys of two layers are picked together — the mount told '
        'the lanes of both', (tester) async {
      final heard = <String>[];
      await pump(
        tester,
        heard,
        own: [lineOf(rising, 'rotation')],
        guests: [lineOf(falling, 'rotation')],
      );

      final gesture = await tester.startGesture(
        ground(tester, 6, 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        Offset(geometry.value.edgeAt(10) - 1, size.height - 2),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(heard, ['rows b:rotation,d:rotation 6-9']);
    });

    testWidgets('of the lines a cut, the box picks the keys of the cut it '
        'began in, in that cut\'s own frames — held to them', (tester) async {
      final heard = <String>[];
      await pump(
        tester,
        heard,
        own: [
          lineOf(rising, 'rotation', reach: (start: 0, end: 10)),
          lineOf(falling, 'rotation', reach: (start: 10, end: 20)),
        ],
      );

      // Over b's key on 8 and d's on its own 0 and 8 — begun in b's cut.
      var gesture = await tester.startGesture(
        ground(tester, 6, 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(geometry.value.edgeAt(19) + 1, 194));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(heard, ['rows b:rotation 6-9']);

      // Begun in d's, back over b's key on 8: d's own 0 alone.
      heard.clear();
      gesture = await tester.startGesture(
        ground(tester, 12, 194),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(geometry.value.edgeAt(5) + 1, 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(heard, ['rows d:rotation 2-0']);
    });
  });

  group('the grid\'s answer', () {
    final laneSelection = ValueNotifier<TimelineLaneSelection?>(null);
    final cellSelection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    tearDownAll(() {
      laneSelection.dispose();
      cellSelection.dispose();
    });

    /// The grid's lane verbs over hooks that tell [heard] what they are
    /// told — the cells' none where [cells] is false.
    TimelineLaneRangeCallbacks gridOf(
      List<String> heard, {
      bool cells = true,
    }) => timelineGridLaneRangeCallbacks(
      hostLaneRange: TimelineLaneRangeHooks(
        selection: laneSelection,
        onSelectUpdate: (layer, lane, anchor, head, lanes) => heard.add(
          'lanes ${layer.value} $lane $anchor-$head ${lanes.join(',')}',
        ),
        onTapAt: (_, _, _) {},
        onTapClear: () {},
        onMoveBegin: () => false,
        onMoveUpdate: (_, {stretch, values, landings}) {},
        onMoveEnd: () {},
        onMoveCancel: () {},
      ),
      rangeHooks: cells
          ? TimelineFrameRangeHooks(
              selection: cellSelection,
              onSelectUpdate:
                  (
                    layer,
                    anchor,
                    head, {
                    headLayerId,
                    spanRows = const [],
                  }) => heard.add(
                    'cells ${layer.value} $anchor-$head '
                    '${headLayerId?.value} $spanRows',
                  ),
              onClear: () {},
              move: TimelineRangeMoveCallbacks(
                holds: (_) => false,
                onBegin: (_) => false,
                onUpdate: ({required frameDelta, targetLayerId}) {},
                onEnd: () {},
                onCancel: () {},
              ),
            )
          : null,
      dragRows: () => throw StateError('a box asks no rows of the grid'),
      dragEdges: () => throw StateError('nor where they are'),
    );

    const cRotation = LaneRowAddress(LayerId('c'), 'rotation');
    const cOpacity = LaneRowAddress(LayerId('c'), 'opacity');
    const dRotation = LaneRowAddress(LayerId('d'), 'rotation');

    test('one layer\'s lanes are a lane selection of exactly those', () {
      final heard = <String>[];
      gridOf(heard).onSelectRows!([cRotation, cOpacity], 2, 17);
      expect(heard, ['lanes c rotation 2-17 rotation,opacity']);
    });

    test('lanes of two layers join the cells law, the rows the box held as '
        'its span — as a lane drag leaving its group does', () {
      final heard = <String>[];
      gridOf(heard).onSelectRows!([cOpacity, dRotation], 6, 9);
      expect(heard, ['cells c 6-9 d ${[cOpacity, dRotation]}']);
    });

    test('where the grid keeps no cells selection, the first layer\'s lanes '
        'alone — as a lane drag stays in its group there', () {
      final heard = <String>[];
      gridOf(
        heard,
        cells: false,
      ).onSelectRows!([cRotation, dRotation, cOpacity], 6, 9);
      expect(heard, ['lanes c rotation 6-9 rotation,opacity']);
    });
  });
}
