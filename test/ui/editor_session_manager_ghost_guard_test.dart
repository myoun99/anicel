import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// UI-R19 → R19b (user decision): ghost frames (derived repeat/hold
/// instances) resolve to their ANCHOR cel for rename and drawing — a
/// deliberate light-table workflow, not a leak. Only DELETE stays
/// refused on ghosts (there is no block of their own to remove).
void main() {
  (EditorSessionManager, LayerId) sessionWithGhostTail() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final layerId = s.activeLayer!.id;
    // End REPEAT: frames 1.. become derived ghost instances of frame 0.
    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    return (s, layerId);
  }

  test('the ghost tail exists (fixture sanity)', () {
    final (s, layerId) = sessionWithGhostTail();
    final layer = s.layers.firstWhere((layer) => layer.id == layerId);
    expect(layer.timeline[1]!.ghost, isTrue);
  });

  test('delete stands down on a ghost frame (pin)', () {
    final (s, _) = sessionWithGhostTail();
    s.selectFrameIndex(0);
    expect(s.canDeleteCellAtCurrentFrame, isTrue);

    s.selectFrameIndex(2);
    expect(s.canDeleteCellAtCurrentFrame, isFalse);
  });

  test('rename on a ghost frame renames the ANCHOR cel (UI-R19b: the '
      'deliberate resolve-through)', () {
    final (s, _) = sessionWithGhostTail();
    s.selectFrameIndex(2);
    expect(s.canRenameFrameAtCurrentFrame, isTrue);
    expect(s.renameSelectedFrame('7'), isNull, reason: 'applies cleanly');
    final layer = s.activeLayer!;
    expect(
      layer.frames.single.name,
      '7',
      reason: 'the ghost resolved to (and renamed) the source cel',
    );
  });

  test('the brush target on a ghost frame is the ANCHOR cel (UI-R19b: '
      'drawing through the repeat edits the source)', () {
    final (s, _) = sessionWithGhostTail();
    s.selectFrameIndex(0);
    final anchorSelection = s.activeBrushEditorSelection;
    expect(anchorSelection, isNotNull);

    s.selectFrameIndex(2);
    final ghostSelection = s.activeBrushEditorSelection;
    expect(ghostSelection, isNotNull);
    expect(
      ghostSelection!.frameId,
      anchorSelection!.frameId,
      reason: 'same cel through the ghost',
    );
  });
}
