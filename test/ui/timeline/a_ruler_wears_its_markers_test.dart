import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/ruler_marker.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/ruler_marker_palette.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/ruler_marker_layer.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_playhead_writing.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/number_pad_keyboard.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';
import 'timeline_ruler_probe.dart';

/// 🗣️I-169 (유저 2026-11-12): 「새 기능. 타임라인 룰러에 북마크? 메모
/// 넣는기능」 — and of what was drawn for it (2026-11-13):
///
///  * Q1 「룰러 칸 자체 더블클릭하면 편집페이지 열리고 … 룰러 한 칸에서
///    위쪽절반은 마크위젯, 아래는 기존처럼 룰러위젯으로 대응하도록 … 룰러위젯
///    드래그해서 바로바로 움직일수있게. 마커로 명명할건데, 마커끼리 겹치는건
///    불가능하고 어떻게 움직일지는 프레임블록 규칙이랑 동일하게. 마커가 생기고
///    나서라도 더블클릭은 룰러 칸 자체 더블클릭해서 대응하도록」
///  * Q2 「컷(로컬)이랑 콘티(글로벌)이랑 마커 독립적으로 하고싶음 … 뭐
///    움직인다고 동기화되서 같이움직이지도않음」
///  * Q4 「구간 정하는건 마커 편집창에서만 … 깃발이랑 동일한 모양으로 옆으로
///    늘린모양으로. 즉 모양 통일 … 그냥 마커에 애초에 텍스트 보이게 …
///    심플하게 se블록 텍스트에서 쓰는 법 그대로 쓰자」
///
/// Driven through the tabs as the workspace hosts them, by real presses:
/// the ruler across, the X-sheet's rail down, and the conte panel's ruler.
void main() {
  const window = ValueKey<String>('instance-edit-dialog');
  const textField = ValueKey<String>('ruler-marker-text-field');

  Project project() => Project(
    id: const ProjectId('markers'),
    name: 'Markers',
    createdAt: DateTime.utc(2026, 11, 14),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          for (final name in ['a', 'b'])
            Cut(
              id: CutId('cut-$name'),
              name: name,
              duration: 48,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(id: LayerId('$name-cel'), name: 'A', frames: const []),
              ],
            ),
        ],
      ),
    ],
  );

  const movie = RulerMarkerHolder.timeline();
  RulerMarkerHolder cutOf(EditorSessionManager session) =>
      RulerMarkerHolder.cut(session.activeCutId!);

  final two = RulerMarkers.settled(const [
    RulerMarker(start: 4, length: 2, text: 'ab'),
    RulerMarker(start: 10, text: 'c', color: RulerMarkerColor.sky),
  ]);

  /// The ribbon at [index] of the ruler whose marker layer is [layer].
  Finder ribbon(int index, {String layer = 'timeline-ruler-markers'}) =>
      find.descendant(
        of: find.byKey(ValueKey<String>(layer)),
        matching: find.byKey(ValueKey<String>('ruler-marker-$index')),
      );

  /// The ruler's cell of [frame], and a point in the half of it the numbers
  /// stand in, and in the half the markers stand in.
  Offset numbersHalf(Rect cell) => Offset(cell.center.dx, cell.bottom - 4);
  Offset markersHalf(Rect cell) => Offset(cell.center.dx, cell.top + 4);

  Future<void> doubleClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
  }

  Future<void> typeAndPressEnter(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(textField), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  /// Lets a double click's window go by, so the next press begins another
  /// — and a test that ends on a press of the ruler leaves no window open
  /// behind it: every press there is one a double click may begin (the
  /// frame block's recognizer, its timers with it).
  Future<void> rest(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 500));

  group('the ruler across', () {
    testWidgets('🚨a double click on a cell — the numbers\' half of it — '
        'opens the window, and Enter stands a marker on that frame of the '
        'cut: in the upper half, a ribbon, its text on it; ONE undo step', (
      tester,
    ) async {
      final session = await pumpTimelineHost(tester, project());
      final cut = cutOf(session);
      final cell = timelineHeaderGlobalRect(tester, 5);
      expect(ribbon(0), findsNothing, reason: 'premise');

      await doubleClick(tester, numbersHalf(cell));
      expect(find.byKey(window), findsOneWidget);
      expect(find.text(AppText.strings.rulerMarkerNewTitle), findsOneWidget);
      await typeAndPressEnter(tester, 'メモ');

      expect(find.byKey(window), findsNothing);
      expect(session.rulerMarkers.markersOn(cut).inOrder, const [
        RulerMarker(start: 5, text: 'メモ'),
      ]);
      expect(
        tester.getRect(ribbon(0)),
        rectMoreOrLessEquals(
          Rect.fromLTRB(cell.left, cell.top, cell.right, cell.center.dy),
        ),
        reason: 'over its frame, in the half the seconds are written in',
      );
      final letters = tester.widget<DialogueFitText>(
        find.descendant(of: ribbon(0), matching: find.byType(DialogueFitText)),
      );
      expect(
        (
          letters.text,
          letters.frames,
          letters.spacing.komaPerGlyph,
          letters.spacing.offset,
          letters.axis,
          letters.color,
        ),
        ('メモ', 1, 1, 0, Axis.horizontal, rulerMarkerInk),
        reason: 'the SE block\'s letters, a glyph to a frame',
      );
      expect(
        tester
            .widget<AppTooltip>(
              find.descendant(
                of: ribbon(0),
                matching: find.byType(AppTooltip),
              ),
            )
            .message,
        'メモ',
        reason: 'the whole text on a hover',
      );
      expect(
        session.rulerMarkers.markersOn(movie).isEmpty,
        isTrue,
        reason: 'the cut\'s, not the conte\'s (I-169-Q2)',
      );

      session.undo();
      await tester.pump();
      expect(session.rulerMarkers.markersOn(cut).isEmpty, isTrue);
      expect(ribbon(0), findsNothing);
    });

    testWidgets('a frame and a span wear ONE shape, each in its colour, on '
        'a layer of their own', (tester) async {
      final session = await pumpTimelineHost(tester, project());
      session.rulerMarkers.setMarkers(cutOf(session), two);
      await tester.pump();

      RulerMarkerRibbonPainter painterOf(int index) =>
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: ribbon(index),
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is CustomPaint &&
                            widget.painter is RulerMarkerRibbonPainter,
                      ),
                    ),
                  )
                  .painter!
              as RulerMarkerRibbonPainter;
      expect(painterOf(0).color, rulerMarkerRibbon(RulerMarkerColor.yellow));
      expect(painterOf(1).color, rulerMarkerRibbon(RulerMarkerColor.sky));
      expect(
        [
          for (final index in [0, 1])
            tester
                .widget<DialogueFitText>(
                  find.descendant(
                    of: ribbon(index),
                    matching: find.byType(DialogueFitText),
                  ),
                )
                .frames,
        ],
        [2, 1],
        reason: 'the letters are set over the frames their marker runs',
      );

      for (final index in [0, 1]) {
        final size = tester.getSize(ribbon(index));
        final outline = rulerMarkerOutline(Axis.horizontal, Offset.zero & size);
        expect(
          outline.contains(Offset(size.width / 2, size.height * 0.5)),
          isTrue,
          reason: 'marker $index: the ribbon\'s body',
        );
        expect(
          outline.contains(Offset(size.width / 2, size.height - 1)),
          isFalse,
          reason: 'marker $index: the notch, cut into the far edge',
        );
        expect(
          outline.contains(Offset(1.5, size.height - 1)),
          isTrue,
          reason: 'marker $index: its tails run the whole breadth',
        );
      }

      // Their own layer: a drag's step paints the ribbons, and the strip
      // under them stays as it was recorded.
      final layer = find.ancestor(
        of: ribbon(0),
        matching: find.byType(TickLayer),
      );
      expect(layer, findsWidgets);
      expect(
        find.descendant(of: layer.first, matching: timelineRulerPaintFinder()),
        findsNothing,
      );
    });

    testWidgets('🚨a press on a marker is the marker\'s: it drags by whole '
        'frames as a frame block moves, shows every step, lands ONE undo '
        'step on release — and the ruler under it never scrubs', (
      tester,
    ) async {
      final session = await pumpTimelineHost(tester, project());
      final cut = cutOf(session);
      session.rulerMarkers.setMarkers(cut, two);
      await tester.pump();
      final cell = timelineHeaderGlobalRect(tester, 0).width;
      final stoodOn = session.currentFrameIndex;

      final gesture = await tester.startGesture(
        tester.getCenter(ribbon(0)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(Offset(cell * 2 + 2, 0));
      await tester.pump();
      expect(
        session.dragPreview.value,
        RulerMarkerDragPreview(holder: cut, markers: two.moved(0, 2)),
      );
      expect(
        tester.getRect(ribbon(0)).left,
        moreOrLessEquals(timelineHeaderGlobalRect(tester, 6).left),
        reason: 'the ribbon follows the step',
      );
      expect(
        session.rulerMarkers.markersOn(cut),
        two,
        reason: 'nothing lands mid-drag',
      );

      // Pulled across its axis too: still the marker's, and on past its
      // neighbour — the blocks' plan says where both stand.
      await gesture.moveBy(Offset(cell * 5, 40));
      await tester.pump();
      expect(
        session.dragPreview.value,
        RulerMarkerDragPreview(holder: cut, markers: two.moved(0, 7)),
      );
      await gesture.up();
      await tester.pump();

      expect(session.dragPreview.value, isNull);
      expect(session.rulerMarkers.markersOn(cut), two.moved(0, 7));
      expect(two.moved(0, 7), isNot(two), reason: 'LIVENESS');
      expect(
        session.currentFrameIndex,
        stoodOn,
        reason: 'the playhead stood where it was through all of it',
      );

      session.undo();
      await tester.pump();
      expect(session.rulerMarkers.markersOn(cut), two);
      await rest(tester);

      // The marker pressed is the one that moves.
      final second = await tester.startGesture(
        tester.getCenter(ribbon(1)),
        kind: PointerDeviceKind.mouse,
      );
      await second.moveBy(Offset(-(cell + 2), 0));
      await tester.pump();
      await second.up();
      await tester.pump();
      expect(session.rulerMarkers.markersOn(cut), two.moved(1, -1));
      expect(two.moved(1, -1), isNot(two.moved(0, -1)), reason: 'LIVENESS');
      await rest(tester);
    });

    testWidgets('the numbers\' half of a marker\'s cell scrubs as it always '
        'did, and so does the markers\' half where none stands', (
      tester,
    ) async {
      final session = await pumpTimelineHost(tester, project());
      session.rulerMarkers.setMarkers(cutOf(session), two);
      await tester.pump();

      await tester.tapAt(numbersHalf(timelineHeaderGlobalRect(tester, 4)));
      await tester.pump();
      expect(session.currentFrameIndex, 4);
      await rest(tester);

      await tester.tapAt(markersHalf(timelineHeaderGlobalRect(tester, 20)));
      await tester.pump();
      expect(session.currentFrameIndex, 20);
      await rest(tester);

      // …and the same half over a marker does not.
      await tester.tapAt(markersHalf(timelineHeaderGlobalRect(tester, 10)));
      await tester.pump();
      expect(session.currentFrameIndex, 20);
      await rest(tester);
    });

    testWidgets('🚨a double click on a marker — or on its cell\'s other '
        'half — opens THAT marker; a length given there pushes what '
        'follows, and 삭제 takes it off', (tester) async {
      final session = await pumpTimelineHost(tester, project());
      final cut = cutOf(session);
      session.rulerMarkers.setMarkers(cut, two);
      await tester.pump();

      // 확인 on a marker left as it stands is no step.
      final steps = session.historyManager.undoCount;
      await doubleClick(tester, tester.getCenter(ribbon(0)));
      expect(find.text(AppText.strings.rulerMarkerEditTitle), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
      );
      await tester.pumpAndSettle();
      expect(session.rulerMarkers.markersOn(cut), two);
      expect(session.historyManager.undoCount, steps);
      await rest(tester);

      // The second frame of the span, by the numbers' half.
      await doubleClick(
        tester,
        numbersHalf(timelineHeaderGlobalRect(tester, 5)),
      );
      expect(find.text(AppText.strings.rulerMarkerEditTitle), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(textField)).controller!.text,
        'ab',
      );
      await typeOnThePad(tester, 'ruler-marker-length-field', '8');
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
      );
      await tester.pumpAndSettle();
      expect(session.rulerMarkers.markersOn(cut).inOrder, const [
        RulerMarker(start: 4, length: 8, text: 'ab'),
        RulerMarker(start: 12, text: 'c', color: RulerMarkerColor.sky),
      ]);
      await rest(tester);

      // The ribbon itself.
      await doubleClick(tester, tester.getCenter(ribbon(1)));
      expect(find.text(AppText.strings.rulerMarkerEditTitle), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(textField)).controller!.text,
        'c',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-delete-button')),
      );
      await tester.pumpAndSettle();
      expect(session.rulerMarkers.markersOn(cut).inOrder, const [
        RulerMarker(start: 4, length: 8, text: 'ab'),
      ]);

      session.undo();
      session.undo();
      await tester.pump();
      expect(
        session.rulerMarkers.markersOn(cut),
        two,
        reason: 'each window\'s answer was one step',
      );
    });

    testWidgets('two presses on two cells are two seeks, never a window', (
      tester,
    ) async {
      final session = await pumpTimelineHost(tester, project());
      await tester.tapAt(numbersHalf(timelineHeaderGlobalRect(tester, 5)));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(numbersHalf(timelineHeaderGlobalRect(tester, 6)));
      await tester.pumpAndSettle();
      expect(find.byKey(window), findsNothing);
      expect(session.currentFrameIndex, 6);
    });

    testWidgets('the ruler\'s own writing shows over a ribbon: the second '
        'its ribbon hides is written again on it, and the layer hears the '
        'drag', (tester) async {
      final session = await pumpTimelineHost(tester, project());
      final cut = cutOf(session);
      TimelineRulerPlayheadWritingPainter writing() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(
                      const ValueKey<String>(
                        'timeline-ruler-playhead-writing',
                      ),
                    ),
                  )
                  .painter!
              as TimelineRulerPlayheadWritingPainter;
      expect(writing().writtenOverMarkers(), isEmpty, reason: 'premise');

      // Frame 25 is where the first second is written. The marker far off
      // the window is none of the writing's: it shows the ones that stand
      // in what is painted.
      session.rulerMarkers.setMarkers(
        cut,
        RulerMarkers.settled(const [
          RulerMarker(start: 23, length: 3),
          RulerMarker(start: 90000, text: 'far'),
        ]),
      );
      session.selectFrameIndex(2);
      await tester.pump();
      expect(writing().markersShown(), const [
        RulerMarker(start: 23, length: 3),
      ]);
      final over = writing().writtenOverMarkers();
      expect([for (final glyph in over) glyph.painter.plainText], ['1']);
      expect(over.single.painter.text!.style!.color, rulerMarkerInk);

      final gesture = await tester.startGesture(
        tester.getCenter(ribbon(0)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(
        Offset(timelineHeaderGlobalRect(tester, 0).width * 6 + 2, 0),
      );
      await tester.pump();
      expect(
        writing().markersShown(),
        const [RulerMarker(start: 29, length: 3)],
        reason: 'the writing follows the step, as the ribbon does',
      );
      expect(writing().writtenOverMarkers(), isEmpty);
      await gesture.up();
      await rest(tester);
    });

    // 🔬2026-11-14: it heard the session's drag channel whole, so a frame's
    // drag on the sheet painted it at every step — and a dock's image cut
    // at it (`a_drag_keeps_the_docks_image_the_docks_size_test`).
    testWidgets('🚨the writing hears a marker\'s drag alone — a drag of '
        'anything else leaves it as it was painted', (tester) async {
      final session = await pumpTimelineHost(tester, project());
      final cut = cutOf(session);
      session.rulerMarkers.setMarkers(cut, two);
      await tester.pump();
      RenderObject writing() => tester.renderObject(
        find.byKey(const ValueKey<String>('timeline-ruler-playhead-writing')),
      );
      expect(writing().debugNeedsPaint, isFalse, reason: 'premise');

      session.dragPreview.value = const MovieEndDragPreview(trailingFrames: 3);
      expect(writing().debugNeedsPaint, isFalse, reason: 'not a marker\'s');
      session.dragPreview.value = null;
      expect(writing().debugNeedsPaint, isFalse);

      session.dragPreview.value = RulerMarkerDragPreview(
        holder: cut,
        markers: two,
      );
      expect(writing().debugNeedsPaint, isTrue);
      session.dragPreview.value = null;
      await rest(tester);
    });
  });

  group('the X-sheet\'s rail', () {
    testWidgets('🚨shows the cut\'s markers down its leading half, drags '
        'them along its own axis, and opens one by the same double click', (
      tester,
    ) async {
      final session = await pumpTimelineHost(
        tester,
        project(),
        orientation: TimelineOrientation.vertical,
      );
      final cut = cutOf(session);
      session.rulerMarkers.setMarkers(cut, two);
      await tester.pump();
      Finder onRail(int index) => ribbon(index, layer: 'xsheet-rail-markers');

      final first = xsheetFrameRowGlobalRect(tester, 4);
      final last = xsheetFrameRowGlobalRect(tester, 5);
      expect(
        tester.getRect(onRail(0)),
        rectMoreOrLessEquals(
          Rect.fromLTRB(first.left, first.top, first.center.dx, last.bottom),
        ),
      );
      expect(
        tester
            .widget<DialogueFitText>(
              find.descendant(
                of: onRail(0),
                matching: find.byType(DialogueFitText),
              ),
            )
            .axis,
        Axis.vertical,
      );

      final stoodOn = session.currentFrameIndex;
      final gesture = await tester.startGesture(
        tester.getCenter(onRail(0)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(0, first.height * 2 + 2));
      await tester.pump();
      expect(
        session.dragPreview.value,
        RulerMarkerDragPreview(holder: cut, markers: two.moved(0, 2)),
      );
      await gesture.up();
      await tester.pump();
      expect(session.rulerMarkers.markersOn(cut), two.moved(0, 2));
      expect(session.currentFrameIndex, stoodOn, reason: 'no scrub');

      // The numbers' side of a row scrubs; a double click there opens. A
      // row near the rail's head: the sheet's header block leaves the rail
      // nine rows of this surface.
      final row = xsheetFrameRowGlobalRect(tester, 2);
      final numbers = Offset(row.left + row.width * 0.75, row.center.dy);
      expect(stoodOn, isNot(2), reason: 'premise');
      await tester.tapAt(numbers);
      await tester.pump();
      expect(session.currentFrameIndex, 2);
      await rest(tester);
      await doubleClick(tester, numbers);
      expect(find.text(AppText.strings.rulerMarkerNewTitle), findsOneWidget);
      await typeAndPressEnter(tester, 'x');
      expect(
        session.rulerMarkers.markersOn(cut).inOrder.first,
        const RulerMarker(start: 2, text: 'x'),
      );
    });
  });

  group('the conte panel\'s ruler', () {
    testWidgets('🚨holds the open timeline\'s own markers, in the movie\'s '
        'frames — a cut\'s never show there, and neither moves the other', (
      tester,
    ) async {
      final session = await pumpStoryboardHost(tester, project());
      final cut = cutOf(session);
      session.rulerMarkers.setMarkers(cut, two);
      await tester.pump();
      expect(
        ribbon(0),
        findsNothing,
        reason: 'the cut\'s markers are the cut ruler\'s (I-169-Q2)',
      );

      // Frame 60 of the movie is the second cut's thirteenth.
      final cell = timelineHeaderGlobalRect(tester, 60);
      await doubleClick(tester, numbersHalf(cell));
      expect(find.text(AppText.strings.rulerMarkerNewTitle), findsOneWidget);
      await typeAndPressEnter(tester, 'B');
      expect(session.rulerMarkers.markersOn(movie).inOrder, const [
        RulerMarker(start: 60, text: 'B'),
      ]);
      expect(session.rulerMarkers.markersOn(cut), two);
      expect(
        tester.getRect(ribbon(0)),
        rectMoreOrLessEquals(
          Rect.fromLTRB(cell.left, cell.top, cell.right, cell.center.dy),
        ),
      );

      final stoodOn = session.playheadCursors.trackFrameNow();
      final gesture = await tester.startGesture(
        tester.getCenter(ribbon(0)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(-(cell.width * 3 + 1), 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(session.rulerMarkers.markersOn(movie).inOrder, const [
        RulerMarker(start: 57, text: 'B'),
      ]);
      expect(session.rulerMarkers.markersOn(cut), two);
      expect(
        session.playheadCursors.trackFrameNow(),
        stoodOn,
        reason: 'a press on a marker scrubs the conte no more than a cut',
      );
      await rest(tester);
    });
  });
}
