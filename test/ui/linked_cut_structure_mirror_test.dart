import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 겸용컷 STRUCTURE mirroring: layer existence is shared structure, so a
/// row created in one use site appears in every sibling ("존재는 공유,
/// 내용은 각자"). Before this round only FOLDER creation mirrored —
/// `AddLayerCommand` never looked at the link registry, so adding an A cel
/// row to a 겸용 cut left its siblings without one and the structure
/// silently diverged.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  Cut cutById(CutId cutId) =>
      session.activeTrack.cuts.firstWhere((cut) => cut.id == cutId);

  /// Makes the active cut 겸용 with a fresh sibling and returns both ids
  /// (the new linked cut becomes active).
  ({CutId source, CutId linked}) makeLinkedPair() {
    final source = session.requireActiveCut.id;
    session.createLinkedCutFromActiveCut();
    return (source: source, linked: session.requireActiveCut.id);
  }

  test('a drawing row added to a 겸용 cut appears in its sibling too, '
      'linked and identically named', () {
    final pair = makeLinkedPair();
    final sourceIdsBefore = {
      for (final layer in cutById(pair.source).layers) layer.id,
    };
    final linkedBefore = cutById(pair.linked).layers.length;

    session.addLayerOfKind(LayerKind.animation);

    expect(cutById(pair.linked).layers, hasLength(linkedBefore + 1));

    final added = session.activeLayer!;
    expect(session.isLayerLinked(added.id), isTrue);

    // The sibling's NEW row, found by id rather than by name: isLayerLinked
    // answers about the ACTIVE cut only, so a counterpart's id cannot be
    // asked about from here.
    final appeared = [
      for (final layer in cutById(pair.source).layers)
        if (!sourceIdsBefore.contains(layer.id)) layer,
    ];
    expect(
      appeared,
      hasLength(1),
      reason: 'the sibling gains the row too — existence is shared',
    );
    expect(appeared.single.id, isNot(added.id), reason: 'ids stay per-cut');
    expect(appeared.single.name, added.name);
    expect(appeared.single.kind, added.kind);
  });

  test('undo removes the mirrored row from every sibling', () {
    final pair = makeLinkedPair();
    final sourceBefore = cutById(pair.source).layers.length;
    final linkedBefore = cutById(pair.linked).layers.length;

    session.addLayerOfKind(LayerKind.animation);
    session.undo();

    expect(cutById(pair.linked).layers, hasLength(linkedBefore));
    expect(
      cutById(pair.source).layers,
      hasLength(sourceBefore),
      reason: 'one undo takes the whole mirrored creation',
    );
  });

  test('redo re-uses the SAME planned ids (ids are planned, not minted '
      'inside the command)', () {
    final pair = makeLinkedPair();

    session.addLayerOfKind(LayerKind.animation);
    final idsAfterFirst = [
      for (final layer in cutById(pair.source).layers) layer.id,
    ];

    session.undo();
    session.redo();

    expect(
      [for (final layer in cutById(pair.source).layers) layer.id],
      idsAfterFirst,
    );
  });

  test('a PER-USE fixture kind does not mirror (instruction rows belong to '
      'their own cut)', () {
    final pair = makeLinkedPair();
    final sourceBefore = cutById(pair.source).layers.length;

    session.addLayerOfKind(LayerKind.instruction);

    expect(
      cutById(pair.source).layers,
      hasLength(sourceBefore),
      reason:
          'layerKindLinksIntoLinkedCut is the one predicate for this — CAM '
          'rows are per-use fixtures every cut already has',
    );
    expect(session.isLayerLinked(session.activeLayer!.id), isFalse);
  });

  test('an UNLINKED cut is untouched by the mirror path', () {
    final soloCutId = session.requireActiveCut.id;
    final before = cutById(soloCutId).layers.length;

    session.addLayerOfKind(LayerKind.animation);

    expect(cutById(soloCutId).layers, hasLength(before + 1));
    expect(session.isLayerLinked(session.activeLayer!.id), isFalse);
  });

  /// The sibling's row with the same identity (linked rows are created by
  /// copying, so they share name and kind).
  Layer counterpartIn(CutId cutId, Layer of) => cutById(cutId).layers
      .firstWhere((layer) => layer.name == of.name && layer.kind == of.kind);

  test('a row created inside a folder lands in the SIBLING\'s own folder, '
      'not the origin cut\'s', () {
    final pair = makeLinkedPair();
    session.groupActiveLayerIntoFolder();
    final sourceIdsBefore = {
      for (final layer in cutById(pair.source).layers) layer.id,
    };

    session.addLayerOfKind(LayerKind.animation);

    final added = session.activeLayer!;
    expect(
      added.folderId,
      isNotNull,
      reason: 'a new row inherits the active row\'s folder',
    );

    final appeared = [
      for (final layer in cutById(pair.source).layers)
        if (!sourceIdsBefore.contains(layer.id)) layer,
    ];
    expect(appeared, hasLength(1));
    final siblingFolderId = appeared.single.folderId;
    expect(siblingFolderId, isNotNull);
    expect(
      siblingFolderId,
      isNot(added.folderId),
      reason: 'copying the anchor verbatim would point at a stranger\'s row',
    );
    expect(
      cutById(pair.source).layers.map((layer) => layer.id),
      contains(siblingFolderId),
      reason: 'the anchor resolves to a folder that lives in THIS cut',
    );
  });

  test('an effect added to a 겸용 row appears in the sibling, same id', () {
    final pair = makeLinkedPair();

    session.addEffectToActiveLayer(EffectKind.blur);

    final added = session.activeLayer!;
    expect(added.effects, hasLength(1));
    final counterpart = counterpartIn(pair.source, added);
    expect(
      counterpart.effects.map((effect) => effect.id),
      [added.effects.single.id],
      reason: 'which effects a row carries is shared structure',
    );
  });

  test("a sibling's OWN parameter values survive a later shape change", () {
    final radiusId = effectParametersOf(EffectKind.blur).first.id;
    final pair = makeLinkedPair();
    session.addEffectToActiveLayer(EffectKind.blur);
    final linkedRow = session.activeLayer!;

    // Give the SIBLING its own blur radius (a per-use lane value).
    session.selectCut(pair.source);
    final sourceRow = counterpartIn(pair.source, linkedRow);
    session.updateLayerEffects(sourceRow.id, [
      sourceRow.effects.single.withParameter(
        radiusId,
        EffectParameter(value: 7),
      ),
    ]);
    expect(
      counterpartIn(pair.source, linkedRow).effects.single
          .parameterOf(radiusId)
          .value,
      7,
    );

    // Change the SHAPE from the other cut.
    session.selectCut(pair.linked);
    session.addEffectToActiveLayer(EffectKind.brightnessContrast);

    final after = counterpartIn(pair.source, linkedRow);
    expect(after.effects, hasLength(2), reason: 'the new effect mirrored');
    expect(
      after.effects.first.parameterOf(radiusId).value,
      7,
      reason: 'a verbatim copy would have wiped this back to the default',
    );
  });

  test('the TRANSFORM switch mirrors — a bypass says whether the row has '
      'that FX at all', () {
    final pair = makeLinkedPair();
    final row = session.activeLayer!;
    expect(row.transformEnabled, isTrue);

    session.updateLayerTransformEnabled(row.id, enabled: false);

    expect(counterpartIn(pair.source, row).transformEnabled, isFalse);

    session.undo();
    expect(counterpartIn(pair.source, row).transformEnabled, isTrue);
  });

  test('a NAMED key carries its value across 겸용 cuts — the way a shape-only '
      'mirror leaves open', () {
    final radiusId = effectParametersOf(EffectKind.blur).first.id;
    final pair = makeLinkedPair();
    session.addEffectToActiveLayer(EffectKind.blur);
    final row = session.activeLayer!;
    final effectId = row.effects.single.id;

    // Each cut authors its OWN key on the shared blur (values are lane
    // content, so the shape mirror never carried them).
    void putKey(CutId cutId, double value) {
      session.selectCut(cutId);
      final layer = counterpartIn(cutId, row);
      final effect = layer.effects.single;
      final parameter = effect.parameters[radiusId]!;
      session.updateLayerEffects(layer.id, [
        effect.withParameter(
          radiusId,
          EffectParameter(
            value: parameter.value,
            track: parameter.track.withKey(0, value),
          ),
        ),
      ]);
    }

    void nameKey(CutId cutId) {
      session.selectCut(cutId);
      session.setEffectKeyName(
        layerId: counterpartIn(cutId, row).id,
        effectId: effectId,
        parameterId: radiusId,
        frameIndex: 0,
        name: 'A',
      );
    }

    putKey(pair.linked, 3);
    putKey(pair.source, 5);
    expect(
      counterpartIn(
        pair.source,
        row,
      ).effects.single.parameters[radiusId]!.track.keyAt(0)!.value,
      5,
      reason: 'values start out independent',
    );

    nameKey(pair.source);
    nameKey(pair.linked);

    expect(
      counterpartIn(
        pair.source,
        row,
      ).effects.single.parameters[radiusId]!.track.keyAt(0)!.value,
      3,
      reason: 'joining the name adopts the joining key\'s number',
    );
  });

  test('removing an effect removes it from the sibling too', () {
    final pair = makeLinkedPair();
    session.addEffectToActiveLayer(EffectKind.blur);
    final added = session.activeLayer!;

    session.removeEffectFromActiveLayer(added.effects.single.id);

    expect(counterpartIn(pair.source, added).effects, isEmpty);
  });

  test('the mirrored row lands in the same relative position, not appended '
      'blindly', () {
    final pair = makeLinkedPair();

    // Two rows in a row: the second must sit above the first in BOTH cuts.
    session.addLayerOfKind(LayerKind.animation);
    final first = session.activeLayer!;
    session.addLayerOfKind(LayerKind.animation);
    final second = session.activeLayer!;

    int indexIn(CutId cutId, String name) => cutById(
      cutId,
    ).layers.indexWhere((layer) => layer.name == name);

    expect(
      indexIn(pair.linked, second.name),
      greaterThan(indexIn(pair.linked, first.name)),
    );
    expect(
      indexIn(pair.source, second.name),
      greaterThan(indexIn(pair.source, first.name)),
      reason: 'the sibling keeps the same stacking order',
    );
  });
}
