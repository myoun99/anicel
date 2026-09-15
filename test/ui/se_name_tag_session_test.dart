import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/se_entries.dart';

/// The SE name tag's SESSION path (R5b, §6-z15): the tag is per SE ROW
/// (one speaker), the rows are TRACK-owned, and the write must reach them
/// through the anywhere seam with one undo — the cut-scoped path throws
/// for track rows, which is the trap this pins.
///
/// ↩️The writes here went through `SeEntries.setActiveSeNameTag`, which
/// nothing in the app had called since its session forwarder went
/// (588a8e58), and which wrote the tag raw off the row the timeline SHOWS —
/// for a track-SE row, its cut-local clone. F-102 retired it with the rest of
/// the trip through the cut window; the anywhere write it wrapped is what
/// these tests pin now, the one the lane verbs commit through.
/// The collaborator that resolves the tags every surface draws — named so
/// `tool/mutation_run.dart` has a suite to run for it.
SeEntries seEntriesOf(EditorSessionManager session) => session.seEntries;

void main() {
  test('the tag write reaches a TRACK-owned SE row and undoes in one step; '
      'null resets it to the stacked default', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final seRow = s.activeTrack.seLayers.first;

    // R5 #7: a tag has no position of its own — nothing to seed, and
    // nothing written until a STYLE is set.
    expect(s.activeTrack.seLayers.first.seNameTag, isNull);

    const configured = SeNameTag(
      style: TextCelStyle(fontSize: 48, color: 0xFFFFFFFF),
    );
    s.cutCommandCoordinator.setSeNameTag(
      layerId: seRow.id,
      seNameTag: configured,
    );
    expect(s.activeTrack.seLayers.first.seNameTag, configured);

    s.undo();
    expect(
      s.activeTrack.seLayers.first.seNameTag,
      isNull,
      reason: 'one undo, and the row is back on the default',
    );

    s.redo();
    expect(s.activeTrack.seLayers.first.seNameTag, configured);

    // Reset: the null contract.
    s.cutCommandCoordinator.setSeNameTag(layerId: seRow.id, seNameTag: null);
    expect(s.activeTrack.seLayers.first.seNameTag, isNull);
    s.undo();
    expect(s.activeTrack.seLayers.first.seNameTag, configured);
  });

  test('an unchanged apply costs no history entry, and a non-SE row refuses '
      'the write outright', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final seRow = s.activeTrack.seLayers.first;
    const tag = SeNameTag(style: TextCelStyle(fontSize: 11));
    s.cutCommandCoordinator.setSeNameTag(layerId: seRow.id, seNameTag: tag);
    final undoDepthAfterFirst = s.canUndo;
    s.cutCommandCoordinator.setSeNameTag(layerId: seRow.id, seNameTag: tag);
    s.undo();
    expect(undoDepthAfterFirst, isTrue);
    expect(
      s.activeTrack.seLayers.first.seNameTag,
      isNull,
      reason: 'the second identical apply added no step to undo through',
    );

    // A drawing row has no tag to edit.
    final drawing = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    expect(
      () => s.cutCommandCoordinator.setSeNameTag(
        layerId: drawing.id,
        seNameTag: const SeNameTag(style: TextCelStyle(fontSize: 9)),
      ),
      throwsStateError,
    );
    expect(
      s.requireActiveCut.layers.firstWhere((l) => l.id == drawing.id).seNameTag,
      isNull,
    );
  });

  test('the resolved tags follow the SE block and the row eye through the '
      'session verb every drawing surface calls', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final seRow = s.activeTrack.seLayers.first;
    s.selectLayer(seRow.id);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: '', lengthFrames: 4);
    s.seEntries.updateSelectedSeEntry(dialogue: 'おはよう', seName: 'タモツ');

    final cut = s.requireActiveCut;
    // R5 #7: two runs — the name in the box, the dialogue beside it.
    final tag = s.seEntries.seNameTagsForCutFrame(cut, 0).single;
    expect(tag.content.text, 'タモツ');
    expect(tag.line?.text, 'おはよう');
    expect(
      s.seEntries.seNameTagsForCutFrame(cut, 10),
      isEmpty,
      reason: 'past the block, nothing shows',
    );

    s.layerSwitches.toggleLayerVisibility(seRow.id);
    expect(
      s.seEntries.seNameTagsForCutFrame(cut, 0),
      isEmpty,
      reason: 'the row eye is the display switch (§6-z15 ②)',
    );
  });

  test('the over-end runway is a CLIPPED VIEW of the cut: a frame past the '
      'last one reads the cut\'s own last frame, never the next cut\'s '
      'speaker', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final seRow = s.activeTrack.seLayers.first;
    s.selectLayer(seRow.id);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: '', lengthFrames: 2);
    s.seEntries.updateSelectedSeEntry(dialogue: 'おはよう', seName: 'タモツ');

    final cut = s.requireActiveCut;
    final atEnd = s.seEntries.seNameTagsForCutFrame(cut, cut.duration - 1);
    final pastEnd = s.seEntries.seNameTagsForCutFrame(cut, cut.duration + 50);
    expect(
      pastEnd.map((tag) => tag.content.text),
      atEnd.map((tag) => tag.content.text),
      reason:
          'the runway clamps to the cut, it does not spill into the '
          'neighbour\'s SE window',
    );
  });

  test('the unconfigured default lands INSIDE the shot on the shipped '
      'canvas/camera mismatch, so the framed surfaces show it', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final seRow = s.activeTrack.seLayers.first;
    s.selectLayer(seRow.id);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: '', lengthFrames: 4);
    s.seEntries.updateSelectedSeEntry(dialogue: 'おはよう', seName: 'タモツ');

    final cut = s.requireActiveCut;
    final shot = shotRectIn(
      canvas: cut.canvasSize,
      cameraFrame: s.camera.cameraFrameSize,
    );
    // The fixture must actually exercise the mismatch, or it proves
    // nothing (the first version of this suite used canvas == camera).
    expect(
      shot.width,
      lessThan(cut.canvasSize.width),
      reason: 'the default project frames a smaller camera than its paper',
    );
    final position = s.seEntries.seNameTagsForCutFrame(cut, 0).single.content.position!;
    expect(position.dx, inInclusiveRange(shot.left, shot.left + shot.width));
    expect(position.dy, inInclusiveRange(shot.top, shot.top + shot.height));
  });

  test('a STYLE-ONLY tag keeps the position null, so the default keeps '
      'following each cut\'s own geometry', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final seRow = s.activeTrack.seLayers.first;
    s.cutCommandCoordinator.setSeNameTag(
      layerId: seRow.id,
      seNameTag: const SeNameTag(
        style: TextCelStyle(fontSize: 20, color: 0xFF202020),
      ),
    );
    final stored = s.activeTrack.seLayers.first.seNameTag!;
    expect(stored.style.fontSize, 20);
    // R5 #7: a tag has no position at all — styling never places, because
    // placing is the SE row's Position lane.
    expect(stored.track, isNull, reason: 'a style edit keys nothing');
  });
}
