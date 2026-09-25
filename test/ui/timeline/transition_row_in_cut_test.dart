import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/transition_geometry.dart'
    show TransitionSides, transitionSidesOf;
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/dialogs/instruction_event_dialog.dart'
    show InstructionEventDialog;
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/instance_editor_commands.dart'
    show editActiveInstance;
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart'
    show TimelineBlockEdgeGrip;
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart'
    show TimelineFrameCellsRow;
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart'
    show TimelineLayerControlsRow;
import 'package:anicel/src/ui/timeline/timeline_selected_exposure_outline.dart'
    show TimelineSelectedExposureOutline;
import 'package:anicel/src/ui/session/transitions.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart' show TimelineTabHost;

/// The TRANSITION row inside a CUT's timeline — a projection you can edit.
///
/// 📐 The shape was settled long before this (the design's "글로벌 ↔ 로컬" law):
/// the two rows deliberately draw the same O.L differently — a cut sees the
/// mark at its FULL length on its own side, because half a bowtie tells an
/// animator nothing.
///
/// ↩️The cut's row was READ-ONLY by the same law until 유저 2026-09-25
/// (transition-row-open-in-the-cut): 「편집은 동일하게 타임라인에서 다
/// 할수있고, 원본 데이터는 글로벌에서 가지고있음. 일방적인 투영만 하되 편집은
/// 가능하게」. The projection stays; every edit made on a mark is written to
/// the GLOBAL span it shows — except an O.L's, which the cut draws whole and
/// the storyboard edits (유저 2026-09-26: 「일단 ol블록만 편집불가능이
/// 맞을거같은데」). The editing cases use a fade that began in the cut before:
/// its mark is drawn from local 0, so its frames are not the span's own — the
/// one place a verb that skipped the mapping would reach the wrong frames.
///
/// 🚨What was missing was not the shape but the PATH. Eight sites in the
/// timeline asked `kind == LayerKind.instruction` where the question they meant
/// was "does this row carry instruction events". The transition row answered no
/// eight times over, so its spans drew nothing and a range selection on it
/// covered nothing (user 2026-08-11: 「타임라인에서 안보이거든?」 ·
/// 「선택범위… 트랜지션레이어만 작동안하니까 공통 규칙 그대로」).
/// The collaborator that owns the spans — named so `tool/mutation_run.dart`
/// has a suite to run for it.
Transitions transitionsOf(EditorSessionManager session) =>
    session.transitions;

void main() {
  /// A session with two cuts and one transition span on the track, set by
  /// [spanAt] from cut 1's duration — reached through the live tree so the
  /// host is notified; a raw repository write leaves the rows on the old
  /// number and the test reads green-looking.
  Future<EditorSessionManager> pumpTwoCutsWith(
    WidgetTester tester,
    MapEntry<int, InstructionEvent> Function(int firstDuration) spanAt,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final first = session.repository.requireProject().tracks.first.cuts.first;
    final span = spanAt(first.duration);
    transitionsOf(session).updateTransitionInstructions(
      SplayTreeMap<int, InstructionEvent>.from({span.key: span.value}),
    );
    session.selectCut(first.id);
    await tester.pumpAndSettle();
    return session;
  }

  /// An O.L straddling the boundary between cut 1 and cut 2: 8 frames, half
  /// on each side — the span both cuts take a のりしろ for.
  Future<EditorSessionManager> pumpTwoCutsWithOverlap(WidgetTester tester) =>
      pumpTwoCutsWith(
        tester,
        (firstDuration) => MapEntry(
          firstDuration - 4,
          const InstructionEvent(instructionId: 'ol', length: 8),
        ),
      );

  /// An F.I that begins two frames before cut 2 and ends three frames into
  /// it: it belongs to cut 2 (a fade in lands where it ends) and crosses
  /// cut 2's start, so cut 2 draws it from its frame 0 — at 0–5, while the
  /// span itself covers −2…3 there.
  Future<EditorSessionManager> pumpTwoCutsWithFadeIn(WidgetTester tester) =>
      pumpTwoCutsWith(
        tester,
        (firstDuration) => MapEntry(
          firstDuration - 2,
          const InstructionEvent(instructionId: 'fi', length: 5),
        ),
      );

  Finder transitionRow() => find.byWidgetPredicate(
    (widget) =>
        widget is TimelineLayerControlsRow &&
        widget.layer.kind == LayerKind.transition,
  );

  /// The second cut — the side whose row draws a span that crosses in from
  /// cut 1 from its own frame 0.
  Future<void> openTheSecondCut(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    session.selectCut(
      session.repository.requireProject().tracks.first.cuts[1].id,
    );
    await tester.pumpAndSettle();
  }

  /// Stands on the transition row at [frame] of the open cut.
  Future<void> standOnTheRowAt(
    WidgetTester tester,
    EditorSessionManager session,
    int frame,
  ) async {
    await tester.tap(transitionRow());
    await tester.pumpAndSettle();
    expect(session.activeLayerId, session.activeTrack.transitionLayer.id);
    session.selectFrameIndex(frame);
    await tester.pumpAndSettle();
  }

  /// Stands on the F.I's mark in cut 2 at frame 4: inside the drawn mark
  /// (0–5), past the span's own end (it covers −2…3 here), so only a verb
  /// that maps the mark back to its span reaches it.
  Future<void> standOnTheMarkBeyondTheSpan(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await standOnTheRowAt(tester, session, 4);
    expect(
      session.transitions.transitionSpanAt(session.editingGlobalFrame),
      isNull,
      reason: 'the premise: the span itself does not cover this frame',
    );
  }

  /// The transition row's grips on the cut's grids — none of the
  /// storyboard's.
  Finder cutGrips(EditorSessionManager session, TimelineBlockEdge edge) =>
      find.descendant(
        of: find.byType(TimelineTabHost),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is TimelineBlockEdgeGrip &&
              widget.layerId == session.activeTrack.transitionLayer.id &&
              widget.edge == edge,
        ),
      );

  /// The transition row as the cut's grid draws it right now.
  Layer shownTransitionRow(WidgetTester tester) => tester
      .widgetList<TimelineFrameCellsRow>(
        find.descendant(
          of: find.byType(TimelineTabHost),
          matching: find.byType(TimelineFrameCellsRow),
        ),
      )
      .map((row) => row.layer)
      .singleWhere((layer) => layer.kind == LayerKind.transition);

  /// Every instruction-span overlay currently mounted, by its widget key.
  List<String> spanOverlayKeys(WidgetTester tester) => [
    for (final element in find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.contains('-instruction-'),
        )
        .evaluate())
      (element.widget.key! as ValueKey<String>).value,
  ];

  testWidgets('⑦ the row DRAWS its span in the cut — the mark the design says '
      'a cut reads, not a blank row', (tester) async {
    final session = await pumpTwoCutsWithOverlap(tester);
    final transitionLayerId = session.activeTrack.transitionLayer.id.value;

    expect(transitionRow(), findsOneWidget, reason: 'the row itself is there');
    final keys = spanOverlayKeys(tester);
    expect(
      keys.where((key) => key.contains(transitionLayerId)),
      isNotEmpty,
      reason:
          'the projected O.L mark is mounted on the transition row — this is '
          'the whole of ⑦, and it was empty before the predicate',
    );
  });

  testWidgets('D26: a crossing F.O wears the red corner + tooltip in the cut '
      'view; an inside one stays clean; the refused block still draws', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final first = session.repository.requireProject().tracks.first.cuts.first;
    final crossingStart = first.duration - 4;
    // One F.O that CROSSES cut 1's end (refused + marked), one that stays
    // INSIDE it (applies, no marker).
    final transitions = transitionsOf(session);
    transitions.updateTransitionInstructions(
      SplayTreeMap<int, InstructionEvent>.from({
        2: const InstructionEvent(instructionId: 'fo', length: 4),
        crossingStart: const InstructionEvent(instructionId: 'fo', length: 8),
      }),
    );
    session.selectCut(first.id);
    await tester.pumpAndSettle();

    final transitionLayerId = session.activeTrack.transitionLayer.id.value;
    // The cut view re-keys spans to LOCAL starts; both spans are anchored
    // inside cut 1, so their projected keys equal their global ones here.
    final crossingMarker = find.byKey(
      ValueKey<String>(
        'timeline-instruction-crossing-$transitionLayerId-$crossingStart',
      ),
    );
    expect(
      crossingMarker,
      findsOneWidget,
      reason: 'D26: the crossing fade wears the red corner',
    );
    expect(
      find.byKey(
        ValueKey<String>(
          'timeline-instruction-crossing-$transitionLayerId-2',
        ),
      ),
      findsNothing,
      reason: 'an inside fade applies and carries no warning',
    );
    expect(
      tester
          .widget<Tooltip>(
            find.descendant(
              of: crossingMarker,
              matching: find.byType(AppTooltip),
            ),
          )
          .message,
      session.uiStrings.tlTransitionCrossingWarning,
      reason: 'the hover text is the one warning string',
    );
    // And the refused span's BLOCK is still mounted — display is un-gated,
    // or the marker would have nothing to sit on.
    expect(
      spanOverlayKeys(tester).where(
        (key) =>
            key.contains(transitionLayerId) && key.endsWith('-$crossingStart'),
      ),
      isNotEmpty,
      reason: 'the refused span still draws its mark overlay',
    );
  });

  for (final xsheet in [false, true]) {
    testWidgets('⑦ a grip on a fade\'s mark drags the GLOBAL span it shows — '
        'the mark following the hand, one undo on release; its head, in the '
        'cut before, takes no grip here'
        '${xsheet ? ' (X-sheet)' : ''}', (tester) async {
      final session = await pumpTwoCutsWithFadeIn(tester);
      final spanStart = session.activeTrack.transitionLayer.instructions.keys
          .single;
      await openTheSecondCut(tester, session);
      if (xsheet) {
        await tester.tap(
          find.byKey(
            const ValueKey<String>('timeline-orientation-toggle-button'),
          ),
        );
        // The sheet runs its frames down the screen, and at 900 tall the
        // mark's tail sat below the window — measured: a press there hit
        // nothing but the view.
        await tester.binding.setSurfaceSize(const Size(1400, 1600));
        await tester.pumpAndSettle();
      }
      expect(
        session.transitions.trackTransitionDisplayLayer.instructions.keys,
        [0],
        reason: 'the premise: the cut draws the mark from its frame 0',
      );
      expect(
        cutGrips(session, TimelineBlockEdge.start),
        findsNothing,
        reason: 'UI-R7 #6, the SE rows\' law: the head is in the cut before',
      );
      final depth = session.historyManager.undoCount;

      final grip = cutGrips(session, TimelineBlockEdge.end);
      expect(grip, findsOneWidget, reason: 'the tail is this cut\'s to drag');
      final cell = tester
          .widget<TimelineBlockEdgeGrip>(grip)
          .resolveFrameCellExtent();
      final gesture = await tester.startGesture(tester.getCenter(grip));
      for (var step = 1; step <= 4; step += 1) {
        await gesture.moveBy(xsheet ? Offset(0, cell / 2) : Offset(cell / 2, 0));
        await tester.pump();
      }

      expect(
        shownTransitionRow(tester).instructions[0]!.length,
        7,
        reason: 'two frames longer on screen while the hand is still down',
      );
      expect(
        session.activeTrack.transitionLayer.instructions[spanStart]!.length,
        5,
        reason: 'and nothing is written until the release',
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        session.activeTrack.transitionLayer.instructions.keys,
        [spanStart],
        reason: 'the span on the global row, at its own start, took the drag',
      );
      expect(
        session.activeTrack.transitionLayer.instructions[spanStart]!.length,
        7,
      );
      expect(session.historyManager.undoCount, depth + 1);
      session.undo();
      await tester.pumpAndSettle();
      expect(
        session.activeTrack.transitionLayer.instructions[spanStart]!.length,
        5,
      );
    });
  }

  for (final second in [false, true]) {
    testWidgets('an O.L\'s mark is the storyboard\'s to edit — no grip, no '
        'term window, no delete in the cut, and nothing made under it '
        '(${second ? 'the incoming cut' : 'the outgoing cut'})', (
      tester,
    ) async {
      final session = await pumpTwoCutsWithOverlap(tester);
      final before = session.activeTrack.transitionLayer.instructions;
      if (second) {
        await openTheSecondCut(tester, session);
      }
      final mark = session.transitions.trackTransitionDisplayLayer.instructions
          .keys
          .single;
      expect(
        [
          cutGrips(session, TimelineBlockEdge.start),
          cutGrips(session, TimelineBlockEdge.end),
        ],
        everyElement(findsNothing),
        reason: '유저 2026-09-26: 「일단 ol블록만 편집불가능이 맞을거같은데」',
      );

      await standOnTheRowAt(tester, session, mark + 1);
      expect(session.cells.canDeleteCellAtCurrentFrame, isFalse);
      expect(session.cellInstances.canEditCellInstanceAtCurrentFrame, isFalse);
      expect(
        session.cellInstances.activeCellHoldsAnInstance,
        isTrue,
        reason: 'the mark still stands there — a double tap makes nothing',
      );
      await editActiveInstance(tester.element(transitionRow()), session);
      await tester.pumpAndSettle();
      expect(find.byType(InstructionEventDialog), findsNothing);
      session.cells.deleteCellAtCurrentFrame();
      await tester.pumpAndSettle();
      expect(session.activeTrack.transitionLayer.instructions, before);
    });
  }

  testWidgets('⑧ standing on the row and pressing a span frame selects it — '
      'the range verb reads the same exposure the marks do', (tester) async {
    final session = await pumpTwoCutsWithOverlap(tester);
    final layerId = session.activeTrack.transitionLayer.id;

    // Stand on the transition row through the rail, the user's own path.
    await tester.tap(transitionRow());
    await tester.pumpAndSettle();
    expect(
      session.activeLayerId,
      layerId,
      reason: 'the rail put the standing row on the transition layer',
    );

    // The cut's projected mark starts at local 0 for the incoming side and
    // overhangs the end for the outgoing one; cut 1 is the OUTGOING side, so
    // its mark sits at its tail. Seek onto a frame the span covers.
    final marks = session.transitions.trackTransitionDisplayLayer.instructions;
    expect(marks, isNotEmpty, reason: 'the projection produced a mark');
    final markStart = marks.keys.first;
    final span = marks[markStart]!;
    session.selectFrameIndex(markStart);
    await tester.pumpAndSettle();

    expect(
      session.cells.canDeleteCellAtCurrentFrame,
      isFalse,
      reason:
          'selectable and measurable, but an O.L\'s mark is the storyboard\'s '
          'to delete (유저 2026-09-26)',
    );

    // 🚨The oracle has to be the CURSOR LAYER's own outline, not the reader
    // function: asserting `instructionCellExposureState(...) != uncovered` is
    // true whether or not the cursor layer calls it, and a mutation run proved
    // exactly that — reverting the predicate left that assertion green. What ⑧
    // is about is the ROUTING, so the test reads the widget the routing feeds.
    final outline = tester.widget<TimelineSelectedExposureOutline>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TimelineSelectedExposureOutline &&
            widget.layerId == layerId,
      ),
    );
    final range = outline.displayRange;
    expect(
      range.resolvedRange.isBlock,
      isTrue,
      reason: 'the span reads as a BLOCK, which is what a range can cover',
    );
    // ⚠️HOW FAR it reaches is the WINDOW's, not the span's or the cut's: this
    // is the display's outline («a visual display effect only», the policy
    // file says), resolved inside the built frame window. Measured 2026-09-25
    // on this fixture: 3 · 4 · 5 · 8 frames for surfaces 1400 · 1409 · 1600 ·
    // 2400 — 8 is the whole span, のりしろ included. The earlier claim that
    // it stops at the cut's end was one window's number, and it broke the day
    // the rail widened by 9 (text-scale-rail-opac). ⑧ asks that the span
    // READS as a block from its first frame, which every window answers.
    final covered =
        range.resolvedRange.endFrameIndexExclusive -
        range.resolvedRange.startFrameIndex;
    expect(
      range.resolvedRange.startFrameIndex,
      markStart,
      reason: 'the block begins where the span does',
    );
    expect(
      covered,
      greaterThan(1),
      reason: 'a range, not the single cell under the cursor',
    );
    expect(
      covered,
      lessThanOrEqualTo(span.length),
      reason: 'and never past the span',
    );

    // And the reason the routing was needed at all: the CEL reader knows
    // nothing about spans, so the row measured empty before.
    expect(
      session.exposureStateForLayer(
        session.transitions.trackTransitionDisplayLayer,
        markStart,
      ),
      TimelineCellExposureState.uncovered,
    );
  });

  /// ⑩ The span reader carries the TERM'S MARK.
  ///
  /// 🚨This is where F.O became O.L: the reader mapped each event to
  /// `(start, length)` and dropped its id, so the geometry could only treat
  /// every span as a symmetric cross-dissolve. Asserting the geometry alone
  /// would not have caught it — the bug was in the hand-off.
  test('⑩ the session hands the geometry each span WITH its mark, so an F.O '
      'reaches it as one-sided', () {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    final foId = session.camera.cameraInstructionSet.defs
        .firstWhere((def) => def.markType == CameraInstructionMarkType.fo)
        .id;
    final olId = session.camera.cameraInstructionSet.defs
        .firstWhere((def) => def.markType == CameraInstructionMarkType.ol)
        .id;

    final transitions = transitionsOf(session);
    transitions.updateTransitionInstructions(
      SplayTreeMap<int, InstructionEvent>.from({
        0: InstructionEvent(instructionId: foId, length: 4),
        8: InstructionEvent(instructionId: olId, length: 4),
      }),
    );

    final spans = session.transitions.activeTrackTransitionSpans;
    expect(spans, hasLength(2));
    expect(
      spans.map((span) => span.mark),
      [CameraInstructionMarkType.fo, CameraInstructionMarkType.ol],
      reason: 'the mark survives the hand-off, in span order',
    );
    expect(
      transitionSidesOf(spans.first.mark),
      TransitionSides.fadesOut,
      reason: 'so the geometry can tell this from a cross-dissolve',
    );
  });

  test('D31 × D26: the SHEET\'s transition layer drops the refused crossing '
      'fade that the cut-view row keeps for its warning to sit on', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    final first = session.repository.requireProject().tracks.first.cuts.first;
    final crossingStart = first.duration - 4;
    final foId = session.camera.cameraInstructionSet.defs
        .firstWhere((def) => def.markType == CameraInstructionMarkType.fo)
        .id;
    // One F.O INSIDE cut 1 (applies) and one CROSSING its end (refused —
    // 미적용, inert in playback and export).
    final transitions = transitionsOf(session);
    transitions.updateTransitionInstructions(
      SplayTreeMap<int, InstructionEvent>.from({
        2: InstructionEvent(instructionId: foId, length: 4),
        crossingStart: InstructionEvent(instructionId: foId, length: 8),
      }),
    );
    session.selectCut(first.id);

    // The cut-view ROW keeps both: the red warning needs the block.
    expect(
      session.transitions.trackTransitionDisplayLayer.instructions.keys,
      containsAll([2, crossingStart]),
    );
    // The printed SHEET carries only what applies — an animator must not
    // shoot material for a fade the compositor never runs.
    expect(
      session.transitions
          .trackTransitionSheetLayerFor(cutStart: 0, duration: first.duration)
          .instructions
          .keys,
      [2],
    );
  });

  /// ③ Create / edit / delete are ONE verb — the instance editor.
  ///
  /// The user's ask was that the transition row stop having its own creation
  /// button and answer to Edit Instance like every other row. The cut view
  /// opens it too now, on the span the mark shows.
  testWidgets('③ the cut view opens the editor on the span a fade\'s mark '
      'shows — from a frame the span itself does not cover', (tester) async {
    final session = await pumpTwoCutsWithFadeIn(tester);
    await openTheSecondCut(tester, session);
    await standOnTheMarkBeyondTheSpan(tester, session);
    expect(
      session.cellInstances.canEditCellInstanceAtCurrentFrame,
      isTrue,
      reason: 'the Edit button lights for the mark under the cursor',
    );

    // Not awaited: the verb waits on the window it opens.
    final editing = editActiveInstance(
      tester.element(transitionRow()),
      session,
    );
    await tester.pumpAndSettle();

    final dialog = find.byType(InstructionEventDialog);
    expect(dialog, findsOneWidget, reason: 'the term window of that span');
    expect(tester.widget<InstructionEventDialog>(dialog).editing, isTrue);
    expect(
      tester.widget<InstructionEventDialog>(dialog).initialInstructionId,
      'fi',
    );
    Navigator.of(tester.element(dialog)).pop();
    await tester.pumpAndSettle();
    await editing;
  });

  testWidgets('a delete on the mark removes the GLOBAL span it shows — one '
      'undo puts it back', (tester) async {
    final session = await pumpTwoCutsWithFadeIn(tester);
    final before = session.activeTrack.transitionLayer.instructions;
    await openTheSecondCut(tester, session);
    await standOnTheMarkBeyondTheSpan(tester, session);

    expect(session.cells.canDeleteCellAtCurrentFrame, isTrue);
    session.cells.deleteCellAtCurrentFrame();
    await tester.pumpAndSettle();
    expect(session.activeTrack.transitionLayer.instructions, isEmpty);

    session.undo();
    await tester.pumpAndSettle();
    expect(session.activeTrack.transitionLayer.instructions, before);
  });

  test('③ an EMPTY frame creates rather than opening a dialog — the same '
      'shape the direction row has, so one verb covers create and edit', () {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    expect(session.activeTrack.transitionLayer.instructions, isEmpty);

    // The create half needs no BuildContext: it is the session verb the
    // editor falls through to when no span covers the playhead. Reached the
    // same way `editTransitionSpanInstance` reaches it.
    expect(session.transitions.transitionSpanAt(session.editingGlobalFrame), isNull);
    expect(session.transitions.canCreateTransitionSpanAtPlayhead, isTrue);
    session.transitions.createTransitionSpanAtPlayhead();

    expect(session.activeTrack.transitionLayer.instructions, hasLength(1));
    expect(
      session.transitions.transitionSpanAt(session.editingGlobalFrame),
      isNotNull,
      reason: 'so a second Edit Instance opens the dialog instead',
    );
  });

  test('the predicate names the two kinds that carry instruction events, and '
      'only those', () {
    expect(LayerKind.instruction.carriesInstructions, isTrue);
    expect(LayerKind.transition.carriesInstructions, isTrue);
    for (final kind in LayerKind.values) {
      if (kind == LayerKind.instruction || kind == LayerKind.transition) {
        continue;
      }
      expect(
        kind.carriesInstructions,
        isFalse,
        reason: '$kind holds cels or nothing, never instruction spans',
      );
    }
    // The two differ on the ROW's own verbs: the transition row is its
    // track's fixture, which no surface renames or deletes.
    expect(LayerKind.transition.isTrackFixture, isTrue);
    expect(LayerKind.instruction.isTrackFixture, isFalse);
  });
}
