import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaFitMode;
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The TEXT layer end to end (R5, §6-s): a cel's truth is its parameters,
/// the raster is a store projection the bake sweep re-renders after every
/// history change — so undo/redo, rasterize and 겸용 links all read
/// correctly from the ordinary content signals. Engine text + toImage run
/// inside the runAsync interleave (the import tests' loop).
void main() {
  /// Pump/real-async interleave until [ready] — sweep bakes complete in
  /// real turns, their fake-zone continuations drain on pump.
  Future<void> settle(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 80 && !ready(); i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  testWidgets('a text layer is added under T-names, its cel bakes a '
      'projection on content set, and ONE undo restores both the params '
      'and the blank projection', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    s.addLayerOfKind(LayerKind.text);
    final layer = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.text,
    );
    expect(layer.name, 'T1');
    expect(s.activeLayerId, layer.id, reason: 'the new row selects itself');

    // Blank cel first (UI-R25 #2: creation opens no dialog).
    expect(s.canCreateDrawingAtCurrentFrame, isTrue);
    s.createDrawingAtCurrentFrame();
    final refreshed = s.requireActiveCut.layers.firstWhere(
      (l) => l.id == layer.id,
    );
    expect(refreshed.frames, hasLength(1));
    expect(s.celHasContentForLayer(refreshed, 0), isFalse);

    // Typing bakes the projection.
    s.setTextCelContentForSelectedFrame(
      const TextCelContent(
        text: 'カット 12',
        style: TextCelStyle(fontSize: 64, bold: true),
        position: Offset(200, 100),
      ),
    );
    await settle(tester, () {
      final l = s.requireActiveCut.layers.firstWhere((l) => l.id == layer.id);
      return s.celHasContentForLayer(l, 0);
    });
    expect(s.selectedTextCelContent?.text, 'カット 12');

    // Undo: parameters revert AND the projection reads blank again.
    s.undo();
    await settle(tester, () {
      final l = s.requireActiveCut.layers.firstWhere((l) => l.id == layer.id);
      return !s.celHasContentForLayer(l, 0);
    });
    expect(s.selectedTextCelContent, isNull);

    // Redo: both come back.
    s.redo();
    await settle(tester, () {
      final l = s.requireActiveCut.layers.firstWhere((l) => l.id == layer.id);
      return s.celHasContentForLayer(l, 0);
    });
    expect(s.selectedTextCelContent?.text, 'カット 12');
    await tester.pumpAndSettle();
  });

  testWidgets('rasterize (§6-s): the text row BECOMES an animation layer — '
      'parameters gone, pixels kept, brush unlocked; one undo restores the '
      'kind and the parameters', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    s.addLayerOfKind(LayerKind.text);
    final layerId = s.activeLayerId!;
    s.createDrawingAtCurrentFrame();
    s.setTextCelContentForSelectedFrame(
      const TextCelContent(text: 'BANK', style: TextCelStyle(fontSize: 80)),
    );
    await settle(tester, () {
      final l = s.requireActiveCut.layers.firstWhere((l) => l.id == layerId);
      return s.celHasContentForLayer(l, 0);
    });

    expect(s.canRasterizeActiveLayer, isTrue);
    s.rasterizeActiveLayer();
    var after = s.requireActiveCut.layers.firstWhere((l) => l.id == layerId);
    expect(after.kind, LayerKind.animation);
    expect(after.frames.single.textContent, isNull);
    // The projection SURVIVES — rasterize keeps the picture. The sweep
    // must not clear it (the layer left the text walk; its hash entry is
    // pruned, never clear-baked).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    expect(s.celHasContentForLayer(after, 0), isTrue);

    s.undo();
    after = s.requireActiveCut.layers.firstWhere((l) => l.id == layerId);
    expect(after.kind, LayerKind.text);
    expect(after.frames.single.textContent?.text, 'BANK');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    expect(
      s.celHasContentForLayer(after, 0),
      isTrue,
      reason: 'params match the stored projection — no wasteful re-bake',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('rasterizing a 겸용-LINKED text row converts EVERY member and '
      'keeps the shared pixels (the kind travels the kind-mirror command, '
      'and the sweep never clear-bakes what it did not bake)', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final originCutId = s.requireActiveCut.id;
    s.addLayerOfKind(LayerKind.text);
    final layerId = s.activeLayerId!;
    s.createDrawingAtCurrentFrame();
    s.setTextCelContentForSelectedFrame(
      const TextCelContent(text: 'C-12', style: TextCelStyle(fontSize: 48)),
    );
    await settle(tester, () {
      final l = s.requireActiveCut.layers.firstWhere((l) => l.id == layerId);
      return s.celHasContentForLayer(l, 0);
    });
    s.createLinkedCutFromActiveCut();
    s.selectCut(originCutId);
    s.selectLayer(layerId);

    s.rasterizeActiveLayer();
    // Give the sweep every chance to (wrongly) clear the shared bank.
    for (var i = 0; i < 5; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }

    final project = s.repository.requireProject();
    final track = project.tracks.first;
    for (final cut in track.cuts) {
      final member = cut.layers.firstWhere(
        (layer) => layer.name == 'T1',
        orElse: () => cut.layers.first,
      );
      if (member.name != 'T1') {
        continue;
      }
      expect(
        member.kind,
        LayerKind.animation,
        reason: 'the kind mirrors group-wide (${cut.id})',
      );
      expect(member.frames.single.textContent, isNull);
      expect(
        s.celHasContentForLayer(member, 0),
        isTrue,
        reason: 'parameters go, PIXELS STAY — in every linked cut',
      );
    }

    s.undo();
    final restored = s.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .firstWhere((cut) => cut.id == originCutId)
        .layers
        .firstWhere((l) => l.id == layerId);
    expect(restored.kind, LayerKind.text, reason: 'one undo restores both');
    expect(restored.frames.single.textContent?.text, 'C-12');
    await tester.pumpAndSettle();
  });

  testWidgets('the sweep never blank-bakes pixels it did not bake: a drawn '
      'cel arriving on a text row (the cross-row move shape) survives every '
      'later sweep', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    s.addLayerOfKind(LayerKind.text);
    final layerId = s.activeLayerId!;
    s.createDrawingAtCurrentFrame();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();

    // Simulate a rekeyed drawn cel landing on the text row: pixels enter
    // the bank OUTSIDE the sweep, textContent stays null.
    await tester.runAsync(() async {
      final cut = s.requireActiveCut;
      final layer = cut.layers.firstWhere((l) => l.id == layerId);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 64, 64),
        ui.Paint()..color = const ui.Color(0xFF112233),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(64, 64);
      picture.dispose();
      final surface = await rasterizeImageToSurface(
        image: image,
        canvas: cut.canvasSize,
        fit: MediaFitMode.none,
      );
      image.dispose();
      bakeCelSurface(
        s.brushFrameStore,
        s.brushFrameKeyForCut(cut, layer.id, layer.frames.single.id),
        surface,
      );
    });
    final layer = s.requireActiveCut.layers.firstWhere((l) => l.id == layerId);
    expect(s.celHasContentForLayer(layer, 0), isTrue);

    // Any history change triggers the sweep — the pixels must survive it.
    s.addLayerOfKind(LayerKind.animation);
    for (var i = 0; i < 5; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(
      s.celHasContentForLayer(layer, 0),
      isTrue,
      reason: 'the clear-bake only touches cels the sweep itself recorded',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('an attach row on a text base is born DRAWABLE: the brush '
      'refusal lives in the base kind and must not pass down', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    s.addLayerOfKind(LayerKind.text);
    expect(s.canAddAttachedLayerToActive, isTrue);
    s.addAttachedLayer(AttachedPlacement.above, mode: AttachedMode.free);
    final cut = s.requireActiveCut;
    final attach = cut.layers.firstWhere(
      (layer) => layer.attachedToLayerId != null,
    );
    expect(attach.kind, LayerKind.animation);
    await tester.pumpAndSettle();
  });

  testWidgets('겸용 (§6-z5): the text row links into the linked cut — the '
      'projection is one physical bank, and an edit through either cut '
      'reaches both', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final originCutId = s.requireActiveCut.id;
    s.addLayerOfKind(LayerKind.text);
    final originLayerId = s.activeLayerId!;
    s.createDrawingAtCurrentFrame();
    s.setTextCelContentForSelectedFrame(
      const TextCelContent(text: 'C-12', style: TextCelStyle(fontSize: 48)),
    );
    await settle(tester, () {
      final l = s.requireActiveCut.layers.firstWhere(
        (l) => l.id == originLayerId,
      );
      return s.celHasContentForLayer(l, 0);
    });

    s.createLinkedCutFromActiveCut();
    final project = s.repository.requireProject();
    final track = project.tracks.first;
    final linkedCut = track.cuts.firstWhere((cut) => cut.id != originCutId);
    final linkedText = linkedCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.text,
    );
    expect(
      project.linkRegistry.groupOf(cutId: linkedCut.id, layerId: linkedText.id),
      isNotNull,
      reason: '§6-z5: text rows share across 겸용컷',
    );
    // The linked copy reads the SAME projection (canonical bank).
    s.selectCut(linkedCut.id);
    expect(s.celHasContentForLayer(linkedText, 0), isTrue);
    expect(linkedText.frames.single.textContent?.text, 'C-12');
    await tester.pumpAndSettle();
  });
}
