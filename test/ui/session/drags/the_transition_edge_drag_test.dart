import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/ui/session/drags/transition_edge_drag.dart';

/// The transition row's edge drag — the FIRST drag session, and the one
/// that had no test naming it (the audit's untested-file pass,
/// 2026-09-05).
void main() {
  Layer transitionRow(Map<int, InstructionEvent> instructions) => Layer(
    id: const LayerId('tr'),
    name: 'transition',
    frames: const [],
    timeline: const {},
    kind: LayerKind.transition,
    instructions: instructions,
  );

  InstructionEvent span(int length) =>
      InstructionEvent(instructionId: 'fade', length: length);

  ({
    TransitionEdgeDrag? drag,
    ValueNotifier<Layer?> preview,
    List<({Map<int, InstructionEvent> instructions, String description})>
    commits,
  })
  open({
    Layer? layer,
    int spanStartIndex = 4,
    TimelineBlockEdge edge = TimelineBlockEdge.end,
    LayerId? layerId,
  }) {
    final preview = ValueNotifier<Layer?>(null);
    addTearDown(preview.dispose);
    final commits =
        <({Map<int, InstructionEvent> instructions, String description})>[];
    return (
      drag: TransitionEdgeDrag.begin(
        layer: layer ?? transitionRow({4: span(6)}),
        spanStartIndex: spanStartIndex,
        edge: edge,
        layerId: layerId,
        preview: preview,
        commitInstructions: (instructions, {required description}) =>
            commits.add((instructions: instructions, description: description)),
      ),
      preview: preview,
      commits: commits,
    );
  }

  test('⛔no span starts there — no object, no drag', () {
    expect(open(spanStartIndex: 99).drag, isNull);
  });

  test('🚨a grip belonging to ANOTHER track\'s row is refused rather than '
      'silently retiming this track\'s span — every verb here is '
      'active-track scoped', () {
    expect(open(layerId: const LayerId('somebody-else')).drag, isNull);
  });

  test('the row\'s own id is accepted', () {
    expect(open(layerId: const LayerId('tr')).drag, isNotNull);
  });

  test('dragging the END edge out lengthens the span, live', () {
    final session = open();

    session.drag!.update(3);

    expect(session.preview.value?.instructions[4]?.length, 9);
    expect(session.commits, isEmpty, reason: 'nothing lands mid-drag');
  });

  test('dragging the START edge moves where the span begins', () {
    final session = open(edge: TimelineBlockEdge.start);

    session.drag!.update(2);

    final instructions = session.preview.value!.instructions;
    expect(instructions.containsKey(4), isFalse);
    expect(instructions[6]?.length, 4);
  });

  test('commit lands ONE step with its own description, from the drag\'s '
      'stored after-state', () {
    final session = open();

    session.drag!.update(3);
    session.drag!.commit();

    expect(session.commits.single.instructions[4]?.length, 9);
    expect(session.commits.single.description, 'Resize transition');
    expect(session.preview.value, isNull, reason: 'the closer clears it');
  });

  test('🚨a delta that lands on NO CHANGE commits nothing', () {
    final session = open();

    session.drag!.update(3);
    session.drag!.update(0);
    session.drag!.commit();

    expect(session.commits, isEmpty);
    expect(session.preview.value, isNull);
  });

  test('dragging the end edge all the way IN floors the span at one frame '
      '— a transition with no frames is not a transition', () {
    final session = open();

    session.drag!.update(-999);
    session.drag!.commit();

    expect(session.commits.single.instructions[4]?.length, 1);
  });

  test('a drag whose clamp lands back on the same span commits nothing', () {
    // ⚠️It is the SHIFT that answers here: it returns null rather than an
    // equal map (`instruction_span_editing`, pinned by its own test), so
    // the commit's `after == _before` clause never fires. The clause stays
    // as the drag's own guard against that contract moving — measured
    // unreachable 2026-09-05, and the drag says so at its site.
    final session = open(layer: transitionRow({4: span(1)}));

    session.drag!.update(-5);
    session.drag!.commit();

    expect(session.commits, isEmpty);
    expect(session.preview.value, isNull);
  });

  test('cancel drops the preview and touches no history', () {
    final session = open();

    session.drag!.update(3);
    session.drag!.cancel();

    expect(session.commits, isEmpty);
    expect(session.preview.value, isNull);
  });
}
