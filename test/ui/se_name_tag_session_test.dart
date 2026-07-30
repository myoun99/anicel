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

    // Unconfigured: the editor still opens on what the row DRAWS today.
    final seeded = s.activeSeNameTagOrDefault;
    expect(seeded, isNotNull);
    expect(seeded!.style, SeNameTag.defaultStyle);
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
    expect(s.activeSeNameTagOrDefault, isNull);
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
    expect(s.seNameTagsForCutFrame(cut, 0).single.content.text, '[タモツ] おはよう');
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
}
