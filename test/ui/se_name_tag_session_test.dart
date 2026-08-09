import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The SE name tag's SESSION path (R5b, §6-z15): the tag is per SE ROW
/// (one speaker), the rows are TRACK-owned, and the write must reach them
/// through the anywhere seam with one undo — the cut-scoped path throws
/// for track rows, which is the trap this pins.
void main() {
  test('the tag write reaches a TRACK-owned SE row and undoes in one step; '
      'null resets it to the stacked default', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final seRow = s.activeTrack.seLayers.first;
    s.selectLayer(seRow.id);
    expect(s.canEditActiveSeNameTag, isTrue);

    // Unconfigured: the editor seeds from the default the row DRAWS with
    // today — inside the shot, and without writing anything.
    final seeded = s.activeSeNameTagDefaultPosition;
    expect(seeded, isNotNull);
    final cut = s.requireActiveCut;
    final shot = shotRectIn(
      canvas: cut.canvasSize,
      cameraFrame: s.cameraFrameSize,
    );
    expect(seeded!.dy, inInclusiveRange(shot.top, shot.top + shot.height));
    expect(
      s.activeTrack.seLayers.first.seNameTag,
      isNull,
      reason: 'seeding never writes',
    );

    const configured = SeNameTag(
      position: Offset(200, 800),
      style: TextCelStyle(fontSize: 48, color: 0xFFFFFFFF),
    );
    s.setActiveSeNameTag(configured);
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
    s.setActiveSeNameTag(null);
    expect(s.activeTrack.seLayers.first.seNameTag, isNull);
    s.undo();
    expect(s.activeTrack.seLayers.first.seNameTag, configured);
  });

  test('an unchanged apply costs no history entry, and non-SE rows refuse '
      'the verb outright', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final seRow = s.activeTrack.seLayers.first;
    s.selectLayer(seRow.id);
    const tag = SeNameTag(position: Offset(10, 20));
    s.setActiveSeNameTag(tag);
    final undoDepthAfterFirst = s.canUndo;
    s.setActiveSeNameTag(tag);
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
    s.selectLayer(drawing.id);
    expect(s.canEditActiveSeNameTag, isFalse);
    expect(s.activeSeNameTagDefaultPosition, isNull);
    s.setActiveSeNameTag(const SeNameTag(position: Offset(1, 2)));
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
    s.createSeEntryAtCurrentFrame(name: '', lengthFrames: 4);
    s.updateSelectedSeEntry(dialogue: 'おはよう', seName: 'タモツ');

    final cut = s.requireActiveCut;
    // R5 #7: two runs — the name in the box, the dialogue beside it.
    final tag = s.seNameTagsForCutFrame(cut, 0).single;
    expect(tag.content.text, 'タモツ');
    expect(tag.line?.text, 'おはよう');
    expect(
      s.seNameTagsForCutFrame(cut, 10),
      isEmpty,
      reason: 'past the block, nothing shows',
    );

    s.toggleLayerVisibility(seRow.id);
    expect(
      s.seNameTagsForCutFrame(cut, 0),
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
    s.createSeEntryAtCurrentFrame(name: '', lengthFrames: 2);
    s.updateSelectedSeEntry(dialogue: 'おはよう', seName: 'タモツ');

    final cut = s.requireActiveCut;
    final atEnd = s.seNameTagsForCutFrame(cut, cut.duration - 1);
    final pastEnd = s.seNameTagsForCutFrame(cut, cut.duration + 50);
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
    s.createSeEntryAtCurrentFrame(name: '', lengthFrames: 4);
    s.updateSelectedSeEntry(dialogue: 'おはよう', seName: 'タモツ');

    final cut = s.requireActiveCut;
    final shot = shotRectIn(
      canvas: cut.canvasSize,
      cameraFrame: s.cameraFrameSize,
    );
    // The fixture must actually exercise the mismatch, or it proves
    // nothing (the first version of this suite used canvas == camera).
    expect(
      shot.width,
      lessThan(cut.canvasSize.width),
      reason: 'the default project frames a smaller camera than its paper',
    );
    final position = s.seNameTagsForCutFrame(cut, 0).single.content.position!;
    expect(position.dx, inInclusiveRange(shot.left, shot.left + shot.width));
    expect(position.dy, inInclusiveRange(shot.top, shot.top + shot.height));
  });

  test('a STYLE-ONLY tag keeps the position null, so the default keeps '
      'following each cut\'s own geometry', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final seRow = s.activeTrack.seLayers.first;
    s.selectLayer(seRow.id);
    s.setActiveSeNameTag(
      const SeNameTag(style: TextCelStyle(fontSize: 20, color: 0xFF202020)),
    );
    final stored = s.activeTrack.seLayers.first.seNameTag!;
    expect(stored.style.fontSize, 20);
    expect(
      stored.position,
      isNull,
      reason: 'a colour edit must not pin this cut\'s default in pixels',
    );
  });
}
