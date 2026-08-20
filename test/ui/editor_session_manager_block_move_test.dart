import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// R10-④b: the whole-block move drag session — channel-only previews, one
/// undo per drag, and the brush store re-keyed when the cel changes layer.
void main() {
  /// A session with drawings on TWO animation layers: layer A's block at
  /// frame 0, layer B's at frame 6 (room to land between).
  (EditorSessionManager, Layer a, Layer b) twoLayerSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final layerA = s.activeLayer!;
    s.addLayer();
    final layerB = s.activeLayer!;
    expect(layerB.id, isNot(layerA.id));
    s.selectFrameIndex(6);
    s.createDrawingAtCurrentFrame();
    s.selectLayer(layerA.id);
    s.selectFrameIndex(0);
    return (
      s,
      s.layers.firstWhere((l) => l.id == layerA.id),
      s.layers.firstWhere((l) => l.id == layerB.id),
    );
  }

  test('slide: channel-only preview, one commit notify, one undo', () {
    final (s, a, _) = twoLayerSession();
    var notifies = 0;
    s.addListener(() => notifies += 1);

    expect(
      s.beginDrawingBlockMoveDrag(layerId: a.id, blockStartIndex: 0),
      isTrue,
    );
    s.updateDrawingBlockMoveDrag(frameDelta: 2);

    final preview = s.dragPreview.value;
    expect(preview, isA<BlockMoveDragPreview>());
    final previewLayer = (preview as BlockMoveDragPreview).previewLayers[a.id]!;
    expect(previewLayer.timeline[0], isNull);
    expect(previewLayer.timeline[2], isNotNull);
    // Repository untouched, no session notify per step.
    expect(s.layers.firstWhere((l) => l.id == a.id).timeline[0], isNotNull);
    expect(notifies, 0);

    s.endDrawingBlockMoveDrag();
    expect(s.dragPreview.value, isNull);
    expect(notifies, 1);
    expect(s.layers.firstWhere((l) => l.id == a.id).timeline[0], isNull);
    expect(s.layers.firstWhere((l) => l.id == a.id).timeline[2], isNotNull);

    s.undo();
    expect(s.layers.firstWhere((l) => l.id == a.id).timeline[0], isNotNull);
    expect(s.layers.firstWhere((l) => l.id == a.id).timeline[2], isNull);
  });

  test('cross-layer: cel travels, brush drawings re-key, one undo restores '
      'everything', () {
    final (s, a, b) = twoLayerSession();
    final frameId = a.timeline[0]!.frameId!;
    final cut = s.requireActiveCut;
    final fromKey = s.brushFrameKeyForCut(cut, a.id, frameId);
    final toKey = s.brushFrameKeyForCut(cut, b.id, frameId);
    // Seed a stored drawing under the source key.
    s.brushFrameStore.getOrCreateFrame(fromKey);

    expect(
      s.beginDrawingBlockMoveDrag(layerId: a.id, blockStartIndex: 0),
      isTrue,
    );
    s.updateDrawingBlockMoveDrag(frameDelta: 1, targetLayerId: b.id);

    final preview = s.dragPreview.value! as BlockMoveDragPreview;
    expect(preview.previewLayers.keys, containsAll([a.id, b.id]));
    expect(preview.previewLayers[b.id]!.timeline[1]!.frameId, frameId);

    s.endDrawingBlockMoveDrag();
    // The selection follows the block onto its new layer (R12-④).
    expect(s.activeLayer!.id, b.id);
    final movedA = s.layers.firstWhere((l) => l.id == a.id);
    final movedB = s.layers.firstWhere((l) => l.id == b.id);
    expect(movedA.timeline[0], isNull);
    expect(movedA.frames.any((f) => f.id == frameId), isFalse);
    expect(movedB.timeline[1]!.frameId, frameId);
    expect(movedB.frames.any((f) => f.id == frameId), isTrue);
    expect(s.brushFrameStore.frameOrNull(fromKey), isNull);
    expect(s.brushFrameStore.frameOrNull(toKey), isNotNull);
    expect(s.brushFrameStore.frameOrNull(toKey)!.key, toKey);
    // The canvas targets the moved drawing where it landed (R12-⑪): the
    // brush editor selection resolves the cel on the NEW layer.
    s.selectFrameIndex(1);
    final selection = s.activeBrushEditorSelection;
    expect(selection, isNotNull);
    expect(selection!.layerId, b.id);
    expect(selection.frameId, frameId);

    // ONE undo restores both layers AND the store keys.
    s.undo();
    final backA = s.layers.firstWhere((l) => l.id == a.id);
    final backB = s.layers.firstWhere((l) => l.id == b.id);
    expect(backA.timeline[0]!.frameId, frameId);
    expect(backA.frames.any((f) => f.id == frameId), isTrue);
    expect(backB.timeline[1], isNull);
    expect(backB.frames.any((f) => f.id == frameId), isFalse);
    expect(s.brushFrameStore.frameOrNull(fromKey), isNotNull);
    expect(s.brushFrameStore.frameOrNull(toKey), isNull);
  });

  test('an occupied landing PUSHES the block in the way (R12-②)', () {
    final (s, a, b) = twoLayerSession();

    s.beginDrawingBlockMoveDrag(layerId: a.id, blockStartIndex: 0);
    // Layer B's block sits at frame 6 — landing on it pushes it behind.
    s.updateDrawingBlockMoveDrag(frameDelta: 6, targetLayerId: b.id);
    final preview = s.dragPreview.value! as BlockMoveDragPreview;
    final previewB = preview.previewLayers[b.id]!;
    expect(previewB.timeline[6], isNotNull, reason: 'moved block lands at 6');
    expect(
      previewB.timeline[7],
      isNotNull,
      reason: 'the resident block pushed from 6 to 7',
    );

    s.endDrawingBlockMoveDrag();
    final movedB = s.layers.firstWhere((l) => l.id == b.id);
    expect(movedB.timeline[6], isNotNull);
    expect(movedB.timeline[7], isNotNull);

    // ONE undo restores both blocks and the source layer.
    s.undo();
    expect(s.layers.firstWhere((l) => l.id == a.id).timeline[0], isNotNull);
    expect(s.layers.firstWhere((l) => l.id == b.id).timeline[6], isNotNull);
    expect(s.layers.firstWhere((l) => l.id == b.id).timeline[7], isNull);
  });

  test('dot toggle on an empty cell is a session no-op: dots are '
      'block-owned, nothing recorded, no notify', () {
    final (s, a, _) = twoLayerSession();
    s.selectFrameIndex(4); // Empty space on layer A.
    final undoProbe = s.canUndo;
    var notifies = 0;
    s.addListener(() => notifies += 1);

    expect(s.canToggleMarkAtCurrentFrame, isFalse);
    s.toggleMarkAtCurrentFrame();

    expect(
      s.layers.firstWhere((l) => l.id == a.id).timeline.containsKey(4),
      isFalse,
    );
    expect(s.canUndo, undoProbe);
    expect(notifies, 0);
  });

  test('cancel drops the preview without repo or history traces', () {
    final (s, a, _) = twoLayerSession();
    final undoProbe = s.canUndo;
    var notifies = 0;
    s.addListener(() => notifies += 1);

    s.beginDrawingBlockMoveDrag(layerId: a.id, blockStartIndex: 0);
    s.updateDrawingBlockMoveDrag(frameDelta: 3);
    expect(s.dragPreview.value, isNotNull);
    s.cancelDrawingBlockMoveDrag();

    expect(s.dragPreview.value, isNull);
    expect(s.layers.firstWhere((l) => l.id == a.id).timeline[0], isNotNull);
    expect(s.canUndo, undoProbe);
    expect(notifies, 0);
  });

  test('SE and empty rows reject the drag', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final seLayer = s.layers.firstWhere((l) => l.name.startsWith('S'));
    expect(
      s.beginDrawingBlockMoveDrag(layerId: seLayer.id, blockStartIndex: 0),
      isFalse,
    );
    // No block at frame 9.
    expect(
      s.beginDrawingBlockMoveDrag(
        layerId: s.activeLayer!.id,
        blockStartIndex: 9,
      ),
      isFalse,
    );
  });

  test('a REFUSED begin leaves the drag in flight alone', () {
    // 🚨The hazard the drag-session split names by hand: the first wiring of
    // that type assigned the slot from the factory unconditionally, so a
    // refusal wrote null over a LIVE drag and its preview stayed stuck in
    // the channel with nothing left to clear it. A second grip landing on
    // an SE row is exactly how a user reaches that.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final seLayer = s.layers.firstWhere((l) => l.name.startsWith('S'));

    expect(
      s.beginDrawingBlockMoveDrag(
        layerId: s.activeLayer!.id,
        blockStartIndex: 0,
      ),
      isTrue,
    );
    s.updateDrawingBlockMoveDrag(frameDelta: 2);
    expect(s.dragPreview.value, isNotNull, reason: 'a move is in flight');

    expect(
      s.beginDrawingBlockMoveDrag(layerId: seLayer.id, blockStartIndex: 0),
      isFalse,
    );
    expect(
      s.isBlockMoveDragActive,
      isTrue,
      reason: 'the refusal is not a cancel',
    );
    expect(s.dragPreview.value, isNotNull, reason: 'and it kept its preview');

    // And the original drag can still be closed the normal way.
    s.cancelDrawingBlockMoveDrag();
    expect(s.isBlockMoveDragActive, isFalse);
    expect(s.dragPreview.value, isNull);
  });

  group('BrushFrameStore.rekeyFrames', () {
    BrushFrameKey key(String layer) => BrushFrameKey(
      projectId: const ProjectId('p'),
      trackId: const TrackId('t'),
      cutId: const CutId('c'),
      layerId: LayerId(layer),
      frameId: const FrameId('f'),
    );

    test('moves the state under the new key and inverts cleanly', () {
      final store = BrushFrameStore();
      final from = key('a');
      final to = key('b');
      store.getOrCreateFrame(from);

      store.rekeyFrames([(from, to)]);
      expect(store.frameOrNull(from), isNull);
      expect(store.frameOrNull(to)!.key, to);

      store.rekeyFrames([(to, from)]);
      expect(store.frameOrNull(from)!.key, from);
      expect(store.frameOrNull(to), isNull);
    });

    test('a missing source is skipped (empty cel moved)', () {
      final store = BrushFrameStore();
      store.rekeyFrames([(key('a'), key('b'))]);
      expect(store.frameOrNull(key('a')), isNull);
      expect(store.frameOrNull(key('b')), isNull);
    });
  });
}
