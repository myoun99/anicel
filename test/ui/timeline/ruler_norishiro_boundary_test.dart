import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_body_norishiro_boundary.dart';
import 'package:anicel/src/ui/timeline/timeline_cut_end_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_norishiro_boundary.dart';

/// The ruler's のりしろ mark: a second end-line saying how much is DRAWN, past
/// the red line saying how much PLAYS.
///
/// 📐 The two are different questions and stay two answers — the red line and
/// its outside-cut wash are untouched. The word is spelled ACROSS the handle's
/// own width, so a longer handle spaces its letters further apart, and a
/// handle too short to hold the word drops it and keeps the line.
void main() {
  group('the boundary widget', () {
    Future<void> pumpBoundary(
      WidgetTester tester, {
      required double cutEnd,
      required double drawnEnd,
      String label = '노리시로',
      Axis axis = Axis.horizontal,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 24,
              child: Stack(
                children: [
                  TimelineRulerNoriShiroBoundary(
                    cutEnd: cutEnd,
                    drawnEnd: drawnEnd,
                    label: label,
                    axis: axis,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('draws nothing at all when the cut is drawn no further than '
        'it plays — which is every cut no transition crosses', (tester) async {
      await pumpBoundary(tester, cutEnd: 120, drawnEnd: 120);
      expect(
        find.byKey(const ValueKey<String>('timeline-norishiro-label')),
        findsNothing,
      );
      expect(find.byType(DecoratedBox), findsNothing);
    });

    testWidgets('spells the word across the handle, one glyph per box, and the '
        'boxes spread as the handle grows', (tester) async {
      await pumpBoundary(tester, cutEnd: 100, drawnEnd: 200);
      final narrow = [
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          text.data!,
      ];
      expect(narrow, ['노', '리', '시', '로']);
      final narrowFirst = tester.getCenter(find.text('노')).dx;
      final narrowLast = tester.getCenter(find.text('로')).dx;

      await pumpBoundary(tester, cutEnd: 100, drawnEnd: 340);
      final wideFirst = tester.getCenter(find.text('노')).dx;
      final wideLast = tester.getCenter(find.text('로')).dx;

      expect(
        wideLast - wideFirst,
        greaterThan(narrowLast - narrowFirst),
        reason: 'a wider handle spaces its letters further apart',
      );
    });

    testWidgets('a handle too short for the word keeps the LINE and drops the '
        'letters — four glyphs in 0+2 would collide', (tester) async {
      await pumpBoundary(tester, cutEnd: 100, drawnEnd: 118);
      expect(find.byType(Text), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('timeline-norishiro-label')),
        findsNothing,
      );
      // The line is still there, at the drawn end.
      expect(find.byType(DecoratedBox), findsOneWidget);
      expect(tester.getTopLeft(find.byType(DecoratedBox)).dx, 100 + 18);
    });

    testWidgets('the threshold scales with the LABEL, not a fixed width: a '
        'handle that holds the bare word can be too short once a term is '
        'prefixed to it', (tester) async {
      // 60px holds 여백 (2 glyphs) comfortably…
      await pumpBoundary(tester, cutEnd: 100, drawnEnd: 160, label: '여백');
      expect(find.byType(Text), findsNWidgets(2));

      // …and not O.L 여백 (7 glyphs incl. the space), which is why the room a
      // label needs is counted per glyph.
      await pumpBoundary(tester, cutEnd: 100, drawnEnd: 160, label: 'O.L 여백');
      expect(find.byType(Text), findsNothing);
      expect(find.byType(DecoratedBox), findsOneWidget);
    });

    testWidgets('an empty label keeps the line alone (a language with no short '
        'word for it)', (tester) async {
      await pumpBoundary(tester, cutEnd: 100, drawnEnd: 300, label: '');
      expect(find.byType(Text), findsNothing);
      expect(find.byType(DecoratedBox), findsOneWidget);
    });

    testWidgets('transposes for the X-sheet: the line lies across the frame '
        'rail below the cut end', (tester) async {
      await pumpBoundary(
        tester,
        cutEnd: 40,
        drawnEnd: 140,
        axis: Axis.vertical,
      );
      final line = find.byType(DecoratedBox);
      expect(tester.getTopLeft(line).dy, 140);
      expect(tester.getSize(line).height, 2);
    });

    testWidgets('the letters sit at the TOP of the ruler, not centred in it '
        '(user 2026-08-11: centred was hard to read over the numbers)', (
      tester,
    ) async {
      await pumpBoundary(tester, cutEnd: 100, drawnEnd: 300);
      final region = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-norishiro-label')),
      );
      final glyph = tester.getRect(find.text('노'));
      expect(
        glyph.top,
        moreOrLessEquals(region.top),
        reason: 'flush with the top edge of the handle region',
      );
      expect(
        glyph.bottom,
        lessThan(region.center.dy),
        reason: 'and entirely in the upper half — centred would straddle it',
      );
    });

    testWidgets('line and letters wear the app ACCENT, and follow it when the '
        'user changes it', (tester) async {
      final before = AppColors.accentSettings.value;
      addTearDown(() => AppColors.accentSettings.value = before);

      await pumpBoundary(tester, cutEnd: 100, drawnEnd: 300);
      BoxDecoration lineDecoration() =>
          tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
              as BoxDecoration;
      expect(lineDecoration().color, AppColors.accent);
      expect(
        tester.widget<Text>(find.text('노')).style!.color,
        AppColors.accent,
        reason: 'one colour for the line and the word it names',
      );
      expect(
        lineDecoration().color,
        isNot(const Color(0xFF5C8AC9)),
        reason: 'the fixed muted blue I had chosen is gone',
      );

      // The accent is a LIVE setting, so a const colour here would strand the
      // mark on the default while everything else moved.
      const picked = Color(0xFFCC7722);
      AppColors.accentSettings.value = before.copyWith(accent: picked);
      await pumpBoundary(tester, cutEnd: 100, drawnEnd: 300);
      expect(lineDecoration().color, picked);
      expect(tester.widget<Text>(find.text('노')).style!.color, picked);
    });
  });

  group('the body boundary', () {
    Future<void> pumpBody(
      WidgetTester tester, {
      required double cutEnd,
      required double drawnEnd,
      Axis axis = Axis.horizontal,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: Stack(
                children: [
                  TimelineBodyNoriShiroBoundary(
                    left: drawnEnd,
                    cutEnd: cutEnd,
                    axis: axis,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('runs the FULL cross axis, so the mark is one continuous line '
        'with the ruler\'s instead of a stub that stops at the header', (
      tester,
    ) async {
      await pumpBody(tester, cutEnd: 100, drawnEnd: 180);
      final line = tester.getRect(find.byType(DecoratedBox));
      expect(line.left, 180);
      expect(line.width, 2);
      expect(
        line.height,
        200,
        reason: 'top to bottom of the body, exactly like the red line',
      );
    });

    testWidgets('draws nothing when nothing is drawn past the cut', (
      tester,
    ) async {
      await pumpBody(tester, cutEnd: 120, drawnEnd: 120);
      expect(find.byType(DecoratedBox), findsNothing);
    });

    testWidgets('transposes for the X-sheet', (tester) async {
      await pumpBody(tester, cutEnd: 40, drawnEnd: 90, axis: Axis.vertical);
      final line = tester.getRect(find.byType(DecoratedBox));
      expect(line.top, 90);
      expect(line.height, 2);
      expect(line.width, 400);
    });
  });

  group('the drawn end a live trim shows', () {
    const cut = CutId('cut-1');

    test('is the cut end when no span crosses — the number every cut had '
        'before any of this existed', () {
      expect(
        timelineDrawnEndPreviewFrameCount(
          preview: null,
          cutId: cut,
          playbackFrameCount: 24,
          drawnFrameCount: null,
        ),
        24,
      );
      expect(
        timelineDrawnEndPreviewFrameCount(
          preview: null,
          cutId: cut,
          playbackFrameCount: 24,
          drawnFrameCount: 24,
        ),
        24,
      );
    });

    test('🚨RIDES the trim: the handle is a LENGTH past the boundary, so a '
        'shorter cut keeps the same margin instead of stranding the blue line '
        'where the red one used to be', () {
      final preview = CutTrimDragPreview(previewDurations: {cut: 18});
      expect(
        timelineCutEndPreviewFrameCount(
          preview: preview,
          cutId: cut,
          playbackFrameCount: 24,
        ),
        18,
      );
      expect(
        timelineDrawnEndPreviewFrameCount(
          preview: preview,
          cutId: cut,
          playbackFrameCount: 24,
          drawnFrameCount: 30,
        ),
        24,
        reason: '18 previewed + the 6-frame handle it still owes',
      );
    });

    test('a drag on a DIFFERENT cut moves neither', () {
      final preview = CutTrimDragPreview(
        previewDurations: {const CutId('other'): 4},
      );
      expect(
        timelineDrawnEndPreviewFrameCount(
          preview: preview,
          cutId: cut,
          playbackFrameCount: 24,
          drawnFrameCount: 30,
        ),
        30,
      );
    });
  });

  group('the drawn count the ruler reads', () {
    test('is the cut 尺 until a span crosses one of its boundaries, and then '
        'the SAME number the sheet pages by', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final duration = session.activeCutPlaybackFrameCount;
      expect(session.activeCutDrawnFrameCount, duration);

      // Straddling the cut's END: the cut owes a 6-frame TAIL handle.
      session.updateTransitionInstructions({
        duration - 6: const InstructionEvent(instructionId: 'ol', length: 12),
      });
      expect(session.activeCutDrawnFrameCount, duration + 6);
      expect(
        session.activeTrack.transitionLayer.kind,
        LayerKind.transition,
        reason: 'read off the transition row, not a cut layer',
      );
      expect(
        session.activeTrack.transitionLayer.id,
        transitionLayerIdForTrack(session.activeTrack.id),
      );
    });

    test('a span INSIDE the cut asks for nothing — the geometry only fires '
        'across a boundary', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final duration = session.activeCutPlaybackFrameCount;

      session.updateTransitionInstructions({
        2: const InstructionEvent(instructionId: 'ol', length: 4),
      });
      expect(session.activeCutDrawnFrameCount, duration);
    });
  });

  group('the real timeline ruler', () {
    testWidgets('mounts the boundary, flat until a span crosses the cut end '
        'and grown after', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: createDefaultProject())),
      );
      await tester.pumpAndSettle();

      final boundary = find.byType(TimelineRulerNoriShiroBoundary);
      expect(boundary, findsOneWidget);
      var mark = tester.widget<TimelineRulerNoriShiroBoundary>(boundary);
      expect(mark.drawnEnd, mark.cutEnd, reason: 'nothing drawn past the end');
      expect(
        mark.label,
        isEmpty,
        reason: 'no term asked for a margin, so there is nothing to name',
      );

      // The live session, reached through the canvas that holds it. The write
      // goes through the SESSION rather than the repository so the host is
      // notified — a raw repository write leaves the ruler on the old number,
      // which is exactly how this test first read green-looking-but-flat.
      final session = tester
          .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
          .session;
      final duration = session.activeCutPlaybackFrameCount;
      session.updateTransitionInstructions(
        SplayTreeMap<int, InstructionEvent>.from({
          duration - 4: const InstructionEvent(instructionId: 'ol', length: 8),
        }),
      );
      await tester.pumpAndSettle();

      mark = tester.widget<TimelineRulerNoriShiroBoundary>(boundary);
      expect(
        mark.drawnEnd,
        greaterThan(mark.cutEnd),
        reason: 'the handle reached the ruler',
      );
      // The TERM that asked for the margin leads the word, so the length says
      // what caused it (user 2026-08-10).
      expect(
        mark.label,
        startsWith('O.L'),
        reason: 'the O.L span is why there is a margin at all',
      );
      expect(mark.label, endsWith(session.uiStrings.tlNoriShiro));
    });

    // A plain test: it drives the session and pumps nothing, so the prerender
    // scheduler's debounce timer would trip testWidgets' pending-timer assert.
    test('names EVERY term that fires on the cut — head and tail handles add '
        'up, so one term would be a half-truth', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.createCut();
      final track = session.repository.requireProject().tracks.first;
      final first = track.cuts[0].duration;
      // The middle cut of three, crossed at BOTH boundaries: an F.I arriving
      // into it and an O.L leaving it.
      session.createCut();
      session.selectCut(
        session.repository.requireProject().tracks.first.cuts[1].id,
      );
      final second = session.repository
          .requireProject()
          .tracks
          .first
          .cuts[1]
          .duration;
      session.updateTransitionInstructions(
        SplayTreeMap<int, InstructionEvent>.from({
          first - 2: const InstructionEvent(instructionId: 'fi', length: 4),
          first + second - 2: const InstructionEvent(
            instructionId: 'ol',
            length: 4,
          ),
        }),
      );

      // The terms are whatever the VOCABULARY calls them — 'FI' and 'O.L' as
      // the standard set spells them, not a form invented here.
      final label = session.activeCutNoriShiroLabel;
      expect(label, contains('FI'));
      expect(label, contains('O.L'));
      expect(label, endsWith(session.uiStrings.tlNoriShiro));
      // Both handles counted, not one of them.
      expect(session.activeCutDrawnFrameCount, second + 4);
    });

    testWidgets('🚨the wash begins BEHIND the blue line, not at the red one: '
        'のりしろ frames are drawn material, so shading them as outside-the-cut '
        'was the wash claiming territory it does not own', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: createDefaultProject())),
      );
      await tester.pumpAndSettle();

      double washStart() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<TimelineOutsideCutWashPainter>()
          .single
          .outsideStart;

      final session = tester
          .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
          .session;
      final duration = session.activeCutPlaybackFrameCount;

      // Before: no handle, so the wash sits exactly where it always did.
      final cutEndX = tester
          .widget<TimelineRulerNoriShiroBoundary>(
            find.byType(TimelineRulerNoriShiroBoundary),
          )
          .cutEnd;
      expect(washStart(), moreOrLessEquals(cutEndX));
      expect(find.byType(TimelineBodyNoriShiroBoundary), findsOneWidget);

      session.updateTransitionInstructions(
        SplayTreeMap<int, InstructionEvent>.from({
          duration - 4: const InstructionEvent(instructionId: 'ol', length: 8),
        }),
      );
      await tester.pumpAndSettle();

      final bodyLine = tester.widget<TimelineBodyNoriShiroBoundary>(
        find.byType(TimelineBodyNoriShiroBoundary),
      );
      expect(
        bodyLine.left,
        greaterThan(cutEndX),
        reason: 'the body line moved out to the drawn end',
      );
      expect(
        washStart(),
        moreOrLessEquals(bodyLine.left),
        reason: 'ONE edge: the wash starts where the blue line stands',
      );
      // And the ruler agrees with the body — one mark, not two that drift.
      expect(
        tester
            .widget<TimelineRulerNoriShiroBoundary>(
              find.byType(TimelineRulerNoriShiroBoundary),
            )
            .drawnEnd,
        moreOrLessEquals(bodyLine.left),
      );
    });
  });
}
