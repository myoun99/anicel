import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// A cut's SE rows' name tags are rows of its frame's own picture, over
/// every other and outside the V row's fx (card
/// the-flutter-fx-chain-is-a-second-chain, 🗣️-Q1 유저 2026-11-12
/// 「이름표를 엔진 그림 안으로」) — in the tree every screen and run stacks
/// for the frame: the editing canvas's at the playhead, and a run's, the
/// track stack's and the warmer's for any cut, each its OWN cut's speakers
/// (R5b).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Two cuts on the default track, a line on the SE row through each
  /// one's frames — the first cut's [first], the second's [second], none
  /// where it is null.
  (EditorSessionManager, Cut, Cut) twoCutsSpeaking({
    String first = '쿵',
    String? second = '팡',
  }) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.cutVerbs.createCut();
    final track = s.repository.requireProject().tracks.first;
    final seRow = s.layers.firstWhere((layer) => layer.kind == LayerKind.se);
    for (final (cut, line) in [
      (track.cuts[0], first),
      (track.cuts[1], second),
    ]) {
      if (line == null) {
        continue;
      }
      s.selectCut(cut.id);
      s.selectLayer(seRow.id);
      s.selectFrameIndex(0);
      s.seEntries.createSeEntryAtCurrentFrame(name: line);
    }
    final cuts = s.repository.requireProject().tracks.first.cuts;
    s.selectCut(cuts[0].id);
    s.selectFrameIndex(0);
    return (s, cuts[0], cuts[1]);
  }

  ResolvedSeNameTag? topTagOf(List<CompositeNode<CanvasStackRow>> nodes) =>
      switch (nodes.lastOrNull) {
        CompositeLeaf(payload: CanvasNameTagRow(:final tag)) => tag,
        _ => null,
      };

  test('the editing canvas\'s frame ends with its cut\'s names', () {
    final (s, first, _) = twoCutsSpeaking();
    addTearDown(s.dispose);
    final tags = s.seEntries.seNameTagsForCutFrame(first, 0);
    expect(tags, hasLength(1), reason: 'LIVENESS: the first cut speaks');
    expect(topTagOf(s.editingCanvas.stack.nodes), tags.single);
    expect(topTagOf(s.editingCanvas.stackWithItsGhosts.nodes), tags.single);
    expect(topTagOf(s.editingCanvas.playingStack.nodes), tags.single);
  });

  test('a run\'s frame of any cut ends with that cut\'s own names', () {
    final (s, first, second) = twoCutsSpeaking();
    addTearDown(s.dispose);
    expect(s.activeCutId, first.id, reason: '⛔premise: the second is not open');
    for (final cut in [first, second]) {
      final tags = s.seEntries.seNameTagsForCutFrame(cut, 0);
      expect(tags, hasLength(1), reason: 'LIVENESS: ${cut.id} speaks');
      expect(
        topTagOf(s.editingCanvas.playedStackAt(cut, 0)),
        tags.single,
        reason: 'its OWN speakers, not the open cut\'s',
      );
    }
    expect(
      topTagOf(s.editingCanvas.playedStackAt(second, 0))!.line!.text,
      '팡',
    );
  });

  test('a frame no line covers has no name row', () {
    final (s, first, quiet) = twoCutsSpeaking(second: null);
    addTearDown(s.dispose);
    expect(
      s.seEntries.seNameTagsForCutFrame(quiet, 0),
      isEmpty,
      reason: '⛔premise: nobody speaks in the second cut',
    );
    expect(topTagOf(s.editingCanvas.playedStackAt(first, 0)), isNotNull);
    expect(topTagOf(s.editingCanvas.playedStackAt(quiet, 0)), isNull);
  });
}
