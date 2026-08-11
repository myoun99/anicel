import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
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
