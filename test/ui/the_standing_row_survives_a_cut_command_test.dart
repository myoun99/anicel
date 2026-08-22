import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨H17 (유저 2026-08-22) — **A CUT COMMAND DOES NOT MOVE THE ACTIVE ROW.**
///
/// > 「**트랜지션 레이어에 서있을때 엔드라인 드래그로 조작하면 액티브레이어가
/// > 액션레이어로 바뀜.** 또 통일안하고 멋대로 이상한규칙 만들어낸흔적」
///
/// The rule was already written (UI-R20 #1, `_refreshAfterCutCommand`:
/// 「the ACTIVE layer survives cut commands by default」) — it just could not
/// see this row. `_activeCutHasLayer` re-derived membership BY KIND and knew
/// two of the three sources the rail composes from: the cut's own layers, and
/// track-SE rows. The track TRANSITION row joined later and nobody told the
/// predicate, so the guard answered "gone", the rebuilt controller took no
/// preference, and `_activeLayerId ??= layers.first.id` dropped the active
/// row onto the bottom of the raw list — the action layer.
///
/// 🧪The row is in `layers` the entire time and `currentRow` never moves.
/// Only the ACTIVE layer does, and only for this one kind — which is why the
/// test sweeps EVERY row kind rather than pinning the one that was reported.
void main() {
  EditorSessionManager session() =>
      EditorSessionManager(initialProject: createDefaultProject());

  /// The end-line drag, as the timeline's cut-end handle runs it.
  void dragCutEnd(EditorSessionManager s, {int frames = 3}) {
    expect(
      s.beginCutEdgeDrag(cutId: s.activeCutId!, edge: TimelineBlockEdge.end),
      isTrue,
      reason: 'fixture premise: the end line is draggable on this cut',
    );
    s.updateCutEdgeDrag(frames);
    s.endCutEdgeDrag();
  }

  test('EVERY row kind keeps the active row through an end-line drag', () {
    final probe = session();
    // The rail's own composition, so a row kind added later is swept here
    // by existing rather than by being remembered.
    final kinds = <String, Layer>{
      for (final layer in probe.activeCutRowLayers) layer.name: layer,
    };
    expect(
      kinds.length,
      greaterThanOrEqualTo(4),
      reason: 'fixture premise: the default project shows several row kinds',
    );

    for (final entry in kinds.entries) {
      final s = session();
      s.selectLayer(entry.value.id);
      expect(s.activeLayerId, entry.value.id);

      dragCutEnd(s);

      expect(
        s.activeLayerId,
        entry.value.id,
        reason:
            '⛔"${entry.key}" (${entry.value.kind}) lost the active row to a '
            'cut command — H17 was exactly this, for the transition row',
      );
    }
  });

  test('the row is never actually missing — the guard was the thing that '
      'said so', () {
    final s = session();
    final transition = s.trackTransitionDisplayLayer;
    s.selectLayer(transition.id);
    dragCutEnd(s);

    expect(
      s.layers.any((layer) => layer.id == transition.id),
      isTrue,
      reason: 'it was in the composed list the whole time',
    );
    expect(
      s.currentRow.toString(),
      contains(transition.id.value),
      reason: 'and the verb row never moved either — only the ACTIVE layer '
          'did, which is what made this look like a rule rather than a gap',
    );
  });

  test('the membership question asks the SAME three sources the rail '
      'composes from', () {
    final s = session();
    final rows = s.activeCutRowLayers.map((layer) => layer.id).toSet();

    for (final layer in s.layers) {
      expect(
        rows.contains(layer.id),
        isTrue,
        reason:
            '⛔"${layer.name}" is DRAWN but the cut-command guard does not '
            'know it exists — that gap is H17, and a new row kind reopens it',
      );
    }
  });
}
