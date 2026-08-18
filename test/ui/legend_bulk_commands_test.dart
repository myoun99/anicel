import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_display_adapter.dart';

/// The rail legend's bulk commands (R-toolbar round): project-state sweeps
/// (sheet/mark/fill-ref) land as ONE undo entry; the view-ish sweeps
/// (eye/mute/fx/opacity) mirror their per-row toggles.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  test('setAllLayersOnTimesheet flips every cut-owned layer in ONE undo', () {
    final s = session();
    final before = [for (final layer in s.requireActiveCut.layers) layer.onTimesheet];
    expect(before, contains(true), reason: 'fixture has sheet-on layers');

    s.setAllLayersOnTimesheet(false);
    expect(s.requireActiveCut.layers.every((layer) => !layer.onTimesheet), isTrue);

    s.undo();
    expect([for (final layer in s.requireActiveCut.layers) layer.onTimesheet], before);
  });

  test('D31: the sheet sweep reaches the track TRANSITION row — its flag '
      'gates a printed column now, so "remove all" must silence it too', () {
    final s = session();
    expect(
      s.activeTrack.transitionLayer.onTimesheet,
      isTrue,
      reason: 'fixture default: the flag starts on',
    );

    s.setAllLayersOnTimesheet(false);
    expect(s.activeTrack.transitionLayer.onTimesheet, isFalse);

    s.setAllLayersOnTimesheet(true);
    expect(s.activeTrack.transitionLayer.onTimesheet, isTrue);

    // Still ONE undo per sweep.
    s.undo();
    expect(s.activeTrack.transitionLayer.onTimesheet, isFalse);
  });

  test('flag commands reach track-owned SE rows (R3 #11: mark/sheet used '
      'to dead-end in the cut-scoped lookup)', () {
    final s = session();
    final seLayer = s.activeTrack.seLayers.first;
    expect(seLayer.mark, LayerMark.none);

    s.setLayerMark(seLayer.id, LayerMark.red);
    expect(
      s.layers.firstWhere((layer) => layer.id == seLayer.id).mark,
      LayerMark.red,
    );
    s.undo();
    expect(
      s.layers.firstWhere((layer) => layer.id == seLayer.id).mark,
      LayerMark.none,
    );

    final sheetBefore = seLayer.onTimesheet;
    s.toggleLayerTimesheet(seLayer.id);
    expect(
      s.layers.firstWhere((layer) => layer.id == seLayer.id).onTimesheet,
      !sheetBefore,
    );

    // The bulk sweeps include the track SE rows now too.
    s.setLayerMark(seLayer.id, LayerMark.blue);
    s.clearAllLayerMarks();
    expect(s.layers.every((layer) => layer.mark == LayerMark.none), isTrue);
  });

  test('clearAllLayerMarks clears in one undo and no-ops when markless', () {
    final s = session();
    final markedId = s.requireActiveCut.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    s.setLayerMark(markedId, LayerMark.red);
    final undosAfterMark = s.canUndo;
    expect(undosAfterMark, isTrue);

    s.clearAllLayerMarks();
    expect(s.layers.every((layer) => layer.mark == LayerMark.none), isTrue);
    s.undo();
    expect(
      s.layers.firstWhere((layer) => layer.id == markedId).mark,
      LayerMark.red,
    );

    // A markless sweep adds no history: clearing twice then undoing ONCE
    // returns to the marked state (the second clear was a no-op).
    s.clearAllLayerMarks();
    s.clearAllLayerMarks();
    s.undo();
    expect(
      s.layers.firstWhere((layer) => layer.id == markedId).mark,
      LayerMark.red,
    );
  });

  test('visibility sweeps: hide all, show all', () {
    final s = session();
    s.setAllLayersVisibility(false);
    expect(s.layers.every((layer) => !layer.isVisible), isTrue);

    s.setAllLayersVisibility(true);
    expect(s.layers.every((layer) => layer.isVisible), isTrue);
  });

  test('visibility solo MODE flips REAL eyes, follows the active layer and '
      'restores each eye from the snapshot on exit (R4 #7)', () {
    final s = session();
    final firstActive = s.activeLayerId!;
    // Hide one non-active row up front: exiting the solo must bring it
    // back HIDDEN (per-row snapshot restore, not a blanket show-all).
    final other = s.layers
        .firstWhere(
          (layer) => layer.id != firstActive && layer.kind != LayerKind.camera,
        )
        .id;
    s.toggleLayerVisibility(other);
    expect(
      s.layers.firstWhere((layer) => layer.id == other).isVisible,
      isFalse,
    );

    s.toggleLayerVisibilitySolo();
    expect(s.layerVisibilitySoloEnabled, isTrue);
    for (final layer in s.layers) {
      expect(layer.isVisible, layer.id == firstActive);
    }

    // Switching the active layer re-solos automatically.
    s.selectLayer(other);
    for (final layer in s.layers) {
      expect(layer.isVisible, layer.id == other);
    }

    // Exit: every eye returns to its snapshot state ('other' was hidden).
    s.toggleLayerVisibilitySolo();
    expect(s.layerVisibilitySoloEnabled, isFalse);
    for (final layer in s.layers) {
      expect(layer.isVisible, layer.id != other);
    }
  });

  test('switching cuts exits the visibility solo and restores eyes', () {
    final s = session();
    final firstCutId = s.requireActiveCut.id;
    s.createCut();
    s.selectCut(firstCutId);
    final activeId = s.activeLayerId!;

    s.toggleLayerVisibilitySolo();
    for (final layer in s.layers) {
      expect(layer.isVisible, layer.id == activeId);
    }

    final otherCutId = s.activeTrack.cuts
        .firstWhere((cut) => cut.id != firstCutId)
        .id;
    s.selectCut(otherCutId);
    expect(s.layerVisibilitySoloEnabled, isFalse);
    // The first cut's eyes are restored.
    s.selectCut(firstCutId);
    expect(s.layers.every((layer) => layer.isVisible), isTrue);
  });

  test('a hidden active layer takes no strokes (R4 #1)', () {
    final s = session();
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    expect(s.activeBrushEditorSelection, isNotNull);
    s.toggleLayerVisibility(s.activeLayerId!);
    expect(s.activeBrushEditorSelection, isNull);
    s.toggleLayerVisibility(s.activeLayerId!);
    expect(s.activeBrushEditorSelection, isNotNull);
  });

  test('opacity drag previews WITHOUT a session notify; the release commits '
      'one write (R4 #4)', () {
    final s = session();
    var notifies = 0;
    s.addListener(() => notifies += 1);
    final id = s.activeLayerId!;

    s.previewLayerOpacity(id, 0.5);
    expect(notifies, 0);
    // The repo stays untouched during the drag…
    expect(s.layers.firstWhere((layer) => layer.id == id).opacity, 1.0);
    // …while the editing canvas follows the preview.
    expect(s.editingCanvasStack.activeLayerOpacity, closeTo(0.5, 1e-9));

    s.commitLayerOpacity(id, 0.5);
    expect(notifies, 1);
    expect(s.layers.firstWhere((layer) => layer.id == id).opacity, 0.5);
    expect(s.opacityDragPreview.value, isNull);
  });

  test('the master bar commit writes every targeted row, camera excluded '
      '(R4 #6)', () {
    final s = session();
    final targets = {
      for (final layer in s.layers)
        if (layerKindHasPictureOpacity(layer.kind)) layer.id,
    };
    s.commitLayersOpacity(targets, 0.3);
    for (final layer in s.layers) {
      if (layerKindHasPictureOpacity(layer.kind)) {
        expect(layer.opacity, closeTo(0.3, 1e-9));
      } else {
        // The camera's slider is the view dim, and the TRANSITION row is
        // read-only notation — neither has a picture opacity to write.
        expect(layer.opacity, 1.0, reason: '${layer.kind}');
      }
    }
  });

  test('the master bar RESTS on the last committed value — previews leave '
      'it alone (UI-R6 #2)', () {
    final s = session();
    expect(s.lastMasterOpacity, 1.0);
    final targets = {
      for (final layer in s.layers)
        if (layerKindHasPictureOpacity(layer.kind)) layer.id,
    };

    s.previewLayersOpacity(targets, 0.42);
    expect(s.lastMasterOpacity, 1.0);

    s.commitLayersOpacity(targets, 0.42);
    expect(s.lastMasterOpacity, closeTo(0.42, 1e-9));
  });

  test('filter engagement moves a FAILING active selection to the nearest '
      'passing layer above, else the first passing (UI-R6 #3)', () {
    final s = session();
    final display = horizontalLayerDisplayOrder(s.layers);
    expect(
      display.length,
      greaterThanOrEqualTo(4),
      reason: 'fixture: cel + instruction + camera + 2 SE rows',
    );
    final activeIndex = display.indexWhere(
      (layer) => layer.id == s.activeLayerId,
    );
    expect(
      activeIndex,
      display.length - 1,
      reason: 'fixture: the drawing cel is the bottom row',
    );

    // Two passing rows above: the NEAREST above wins.
    final near = display[activeIndex - 1];
    final far = display[0];
    s.moveSelectionToFilteredLayer(
      (layer) => layer.id == near.id || layer.id == far.id,
    );
    expect(s.activeLayerId, near.id);

    // Nothing above the top row: falls back to the first passing anywhere.
    s.selectLayer(far.id);
    final below = display[2];
    s.moveSelectionToFilteredLayer((layer) => layer.id == below.id);
    expect(s.activeLayerId, below.id);

    // A passing active stays put.
    s.moveSelectionToFilteredLayer((layer) => layer.id == below.id);
    expect(s.activeLayerId, below.id);
  });

  test('fx bulk bypass/restore writes every row switch', () {
    final s = session();
    expect(s.layers.every((layer) => s.isLayerFxEnabled(layer.id)), isTrue);

    s.setAllLayersFxBypassed(true);
    // The TRANSITION row has neither a transform nor a chain, so it owns no
    // fx switch to flip — its flag stays where it was rather than reading
    // as an un-bypassed row the sweep missed.
    expect(
      s.layers
          .where((layer) => layerKindHasTransformFxSwitch(layer.kind))
          .every((layer) => !s.isLayerFxEnabled(layer.id)),
      isTrue,
    );

    s.setAllLayersFxBypassed(false);
    expect(s.layers.every((layer) => s.isLayerFxEnabled(layer.id)), isTrue);
  });

  test('SE mute sweep touches only SE layers', () {
    final s = session();
    s.setAllSeLayersMuted(true);
    for (final layer in s.layers) {
      if (layer.kind == LayerKind.se) {
        expect(layer.muted, isTrue);
      } else {
        expect(layer.muted, isFalse);
      }
    }
    s.setAllSeLayersMuted(false);
    expect(s.layers.every((layer) => !layer.muted), isTrue);
  });

  test('resetAllLayersOpacity restores 1.0 for non-camera layers', () {
    final s = session();
    final target = s.layers
        .firstWhere((layer) => layer.kind != LayerKind.camera)
        .id;
    s.setLayerOpacity(layerId: target, opacity: 0.4);
    s.resetAllLayersOpacity();
    for (final layer in s.layers) {
      if (layer.kind != LayerKind.camera) {
        expect(layer.opacity, 1.0);
      }
    }
  });
}
