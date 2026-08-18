import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer_kind.dart';
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
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart'
    show TimelineLayerControlsRow;
import 'package:anicel/src/ui/timeline/timeline_selected_exposure_outline.dart'
    show TimelineSelectedExposureOutline;

/// The TRANSITION row inside a CUT's timeline — visible, and read-only.
///
/// 📐 The shape was settled long before this (the design's "글로벌 ↔ 로컬" law):
/// the global row is edited, a cut's row is READ, and the two deliberately draw
/// the same O.L differently — a cut sees the mark at its FULL length on its own
/// side, because half a bowtie tells an animator nothing.
///
/// 🚨What was missing was not the shape but the PATH. Eight sites in the
/// timeline asked `kind == LayerKind.instruction` where the question they meant
/// was "does this row carry instruction events". The transition row answered no
/// eight times over, so its spans drew nothing and a range selection on it
/// covered nothing (user 2026-08-11: 「타임라인에서 안보이거든?」 ·
/// 「선택범위… 트랜지션레이어만 작동안하니까 공통 규칙 그대로」).
void main() {
  /// A session with two cuts and an O.L span straddling their boundary, reached
  /// through the live tree so the host is notified — a raw repository write
  /// leaves the rows on the old number and the test reads green-looking.
  Future<EditorSessionManager> pumpTwoCutsWithOverlap(
    WidgetTester tester,
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
    session.createCut();
    await tester.pumpAndSettle();
    final first = session.repository.requireProject().tracks.first.cuts.first;
    // Straddling the boundary between cut 1 and cut 2: 8 frames, half on each
    // side. This is the O.L both cuts take a のりしろ for.
    session.updateTransitionInstructions(
      SplayTreeMap<int, InstructionEvent>.from({
        first.duration - 4: const InstructionEvent(
          instructionId: 'ol',
          length: 8,
        ),
      }),
    );
    session.selectCut(first.id);
    await tester.pumpAndSettle();
    return session;
  }

  Finder transitionRow() => find.byWidgetPredicate(
    (widget) =>
        widget is TimelineLayerControlsRow &&
        widget.layer.kind == LayerKind.transition,
  );

  /// Every instruction-span overlay currently mounted, by its widget key.
  List<String> spanOverlayKeys(WidgetTester tester) => [
    for (final element in find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>).value.contains('-instruction-'),
        )
        .evaluate())
      ((element.widget.key) as ValueKey<String>).value,
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
    session.createCut();
    await tester.pumpAndSettle();
    final first = session.repository.requireProject().tracks.first.cuts.first;
    final crossingStart = first.duration - 4;
    // One F.O that CROSSES cut 1's end (refused + marked), one that stays
    // INSIDE it (applies, no marker).
    session.updateTransitionInstructions(
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
              matching: find.byType(Tooltip),
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

  testWidgets('⑦ and it is READ-ONLY: no edge grips, unlike the direction row '
      'right below it', (tester) async {
    final session = await pumpTwoCutsWithOverlap(tester);
    final transitionLayerId = session.activeTrack.transitionLayer.id.value;

    final gripKeys = [
      for (final element in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>).value.contains('edge-grip'),
          )
          .evaluate())
        ((element.widget.key) as ValueKey<String>).value,
    ];
    expect(
      gripKeys.where((key) => key.contains(transitionLayerId)),
      isEmpty,
      reason:
          'a grip here would drag a PROJECTION — authoring lives on the global '
          'axis (layerKindIsReadOnlyInCut)',
    );
  });

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
    final marks = session.trackTransitionDisplayLayer.instructions;
    expect(marks, isNotEmpty, reason: 'the projection produced a mark');
    final markStart = marks.keys.first;
    final span = marks[markStart]!;
    session.selectFrameIndex(markStart);
    await tester.pumpAndSettle();

    expect(
      session.canDeleteCellAtCurrentFrame,
      isFalse,
      reason:
          'read-only: the row is selectable and measurable, and still refuses '
          'every verb that would change it',
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
    // ⚠️MEASURED, not assumed: the block reaches the cut's end and stops there,
    // because the resolver walks inside the frame WINDOW. Cut 1 is the outgoing
    // side, so its mark overhangs into the のりしろ — the part past the cut end
    // is outside the window and does not join the block. The span is 8 and this
    // is 4; asserting 8 would be asserting a number the timeline never makes.
    final covered =
        range.resolvedRange.endFrameIndexExclusive -
        range.resolvedRange.startFrameIndex;
    expect(covered, session.activeCutPlaybackFrameCount - markStart);
    expect(
      covered,
      greaterThan(1),
      reason: 'a range, not the single cell under the cursor',
    );
    expect(span.length, greaterThan(covered), reason: 'the mark overhangs');

    // And the reason the routing was needed at all: the CEL reader knows
    // nothing about spans, so the row measured empty before.
    expect(
      session.exposureStateForLayer(
        session.trackTransitionDisplayLayer,
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
    final foId = session.cameraInstructionSet.defs
        .firstWhere((def) => def.markType == CameraInstructionMarkType.fo)
        .id;
    final olId = session.cameraInstructionSet.defs
        .firstWhere((def) => def.markType == CameraInstructionMarkType.ol)
        .id;

    session.updateTransitionInstructions(
      SplayTreeMap<int, InstructionEvent>.from({
        0: InstructionEvent(instructionId: foId, length: 4),
        8: InstructionEvent(instructionId: olId, length: 4),
      }),
    );

    final spans = session.activeTrackTransitionSpans;
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
    session.createCut();
    final first = session.repository.requireProject().tracks.first.cuts.first;
    final crossingStart = first.duration - 4;
    final foId = session.cameraInstructionSet.defs
        .firstWhere((def) => def.markType == CameraInstructionMarkType.fo)
        .id;
    // One F.O INSIDE cut 1 (applies) and one CROSSING its end (refused —
    // 미적용, inert in playback and export).
    session.updateTransitionInstructions(
      SplayTreeMap<int, InstructionEvent>.from({
        2: InstructionEvent(instructionId: foId, length: 4),
        crossingStart: InstructionEvent(instructionId: foId, length: 8),
      }),
    );
    session.selectCut(first.id);

    // The cut-view ROW keeps both: the red warning needs the block.
    expect(
      session.trackTransitionDisplayLayer.instructions.keys,
      containsAll([2, crossingStart]),
    );
    // The printed SHEET carries only what applies — an animator must not
    // shoot material for a fade the compositor never runs.
    expect(session.trackTransitionSheetLayer.instructions.keys, [2]);
  });

  /// ③ Create / edit / delete are ONE verb — the instance editor.
  ///
  /// The user's ask was that the transition row stop having its own creation
  /// button and answer to Edit Instance like every other row, with only the
  /// wiring done because the button itself arrives later. So the test is about
  /// the ROUTE, and the route's fork is which surface asked: the storyboard
  /// authors, the cut view reads.
  testWidgets('③ the cut view still refuses to open the editor, while the '
      'enablement gate says a span is there to edit', (tester) async {
    final session = await pumpTwoCutsWithOverlap(tester);
    final before = session.activeTrack.transitionLayer.instructions;
    expect(before, isNotEmpty);

    await tester.tap(transitionRow());
    await tester.pumpAndSettle();
    expect(session.activeLayerId, session.activeTrack.transitionLayer.id);

    // The default is the READ-ONLY answer, so a caller that forgets the flag
    // cannot break the law by omission.
    await editActiveInstance(tester.element(transitionRow()), session);
    await tester.pumpAndSettle();

    expect(
      find.byType(InstructionEventDialog),
      findsNothing,
      reason: 'no editor in a cut — its placement here is a projection',
    );
    expect(
      session.activeTrack.transitionLayer.instructions,
      before,
      reason: 'and nothing was created either',
    );
  });

  test('③ an EMPTY frame creates rather than opening a dialog — the same '
      'shape the direction row has, so one verb covers create and edit', () {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    expect(session.activeTrack.transitionLayer.instructions, isEmpty);

    // The create half needs no BuildContext: it is the session verb the
    // editor falls through to when no span covers the playhead. Reached the
    // same way `editTransitionSpanInstance` reaches it.
    expect(session.transitionSpanAt(session.editingGlobalFrame), isNull);
    expect(session.canCreateTransitionSpanAtPlayhead, isTrue);
    session.createTransitionSpanAtPlayhead();

    expect(session.activeTrack.transitionLayer.instructions, hasLength(1));
    expect(
      session.transitionSpanAt(session.editingGlobalFrame),
      isNotNull,
      reason: 'so a second Edit Instance opens the dialog instead',
    );
  });

  test('the predicate names the two kinds that carry instruction events, and '
      'only those', () {
    expect(layerKindCarriesInstructions(LayerKind.instruction), isTrue);
    expect(layerKindCarriesInstructions(LayerKind.transition), isTrue);
    for (final kind in LayerKind.values) {
      if (kind == LayerKind.instruction || kind == LayerKind.transition) {
        continue;
      }
      expect(
        layerKindCarriesInstructions(kind),
        isFalse,
        reason: '$kind holds cels or nothing, never instruction spans',
      );
    }
    // The two answers differ on EDITING, which is why the grips ask both.
    expect(layerKindIsReadOnlyInCut(LayerKind.transition), isTrue);
    expect(layerKindIsReadOnlyInCut(LayerKind.instruction), isFalse);
  });
}
