// 🗣️shortcut-presets-anicel-and-clip-studio-Q1 (유저 2026-10-09): 「버튼이
// 있는 자리로」 — the shortcut window's shelves are the screen's places, the
// bars and pills in them, and on the timeline the pills one level in.
//
// What each shelf holds is what stands on that bar, pill or menu; a key
// with no button stands where it moves. These pins name the readings the
// answer did not spell out (ShortcutShelf's ⚠️) and one row of every shelf
// besides, so a row filed on the wrong shelf is a red line here.
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/layer_effect.dart' show EffectKind;
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart' show CanvasTool;
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_shelf.dart';

ShortcutShelf shelfOf(String id) =>
    editorActionDefinitions.singleWhere((row) => row.id == id).shelf;

void main() {
  test('the places are the answer\'s but the tool library (F-560) — and '
      'under 도구, each tool\'s own shelf names it (F-580)', () {
    expect(ShortcutShelf.places, [
      ShortcutShelf.canvas,
      ShortcutShelf.timeline,
      ShortcutShelf.topStrip,
    ]);
    expect(ShortcutShelf.canvas.shelves, [
      ShortcutShelf.tools,
      ShortcutShelf.blendModes,
      ShortcutShelf.selection,
      ShortcutShelf.edit,
      ShortcutShelf.view,
    ]);
    expect(ShortcutShelf.timeline.shelves, [
      ShortcutShelf.moves,
      ShortcutShelf.playback,
      ShortcutShelf.pills,
      ShortcutShelf.layerHeader,
      ShortcutShelf.timelineBar,
    ]);
    // 🗣️F-580: 「브러시 도구 밑에 브러시 도구의 브러시 항목 … 그 다음 아래에
    // 지우개 도구, 그 밑에 지우개 도구의 브러시 항목」 — a shelf under 도구 is
    // a tool's own, and stands under that tool's row.
    expect(
      [for (final shelf in ShortcutShelf.tools.shelves) (shelf, shelf.tool)],
      [
        (ShortcutShelf.brushToolBrushes, CanvasTool.brush),
        (ShortcutShelf.eraserToolBrushes, CanvasTool.eraser),
        (ShortcutShelf.texts, CanvasTool.text),
        (ShortcutShelf.guides, CanvasTool.guide),
      ],
    );
    expect(ShortcutShelf.topStrip.shelves, [
      ShortcutShelf.file,
      ShortcutShelf.settings,
      ShortcutShelf.panels,
      ShortcutShelf.debug,
    ]);
    expect(ShortcutShelf.pills.path, [
      ShortcutShelf.timeline,
      ShortcutShelf.pills,
    ]);
    expect(ShortcutShelf.pills.shelves, [
      ShortcutShelf.cutPill,
      ShortcutShelf.layerPill,
      ShortcutShelf.framePill,
      ShortcutShelf.fxPill,
      ShortcutShelf.sharedPill,
      ShortcutShelf.colourEdit,
    ]);
  });

  test('the readings: the clipboard and the colour edit are the shared '
      'pill\'s, the canvas keeps the rail\'s undo, the onion and the solo '
      'stand by the view, a tool panel\'s buttons by their tool, and the '
      'whole picture cut\'s 실행 by the stamp\'s buttons (F-580)', () {
    for (final (id, shelf) in [
      (EditorActionIds.editCut, ShortcutShelf.sharedPill),
      (EditorActionIds.editPasteIndependent, ShortcutShelf.sharedPill),
      (EditorActionIds.editDelete, ShortcutShelf.sharedPill),
      (EditorActionIds.editDuplicate, ShortcutShelf.sharedPill),
      (EditorActionIds.editClearPixels, ShortcutShelf.colourEdit),
      (EditorActionIds.editCopyPixels, ShortcutShelf.colourEdit),
      (EditorActionIds.undo, ShortcutShelf.edit),
      (EditorActionIds.redo, ShortcutShelf.edit),
      (EditorActionIds.confirm, ShortcutShelf.selection),
      (EditorActionIds.onionSkinToggle, ShortcutShelf.view),
      (EditorActionIds.layerVisibilitySolo, ShortcutShelf.view),
      (EditorActionIds.guideAddSymmetry, ShortcutShelf.guides),
      (EditorActionIds.textDeleteText, ShortcutShelf.texts),
      (EditorActionIds.cutStampRegisterTip, ShortcutShelf.edit),
      (EditorActionIds.toolCutWholeRun, ShortcutShelf.edit),
    ]) {
      expect(shelfOf(id), shelf, reason: id);
    }
  });

  test('a key with no button stands where it moves', () {
    for (final id in [
      EditorActionIds.framePrevious,
      EditorActionIds.drawingNext,
      EditorActionIds.layerUp,
    ]) {
      expect(shelfOf(id), ShortcutShelf.moves, reason: id);
    }
    expect(shelfOf(EditorActionIds.canvasPanHold), ShortcutShelf.view);
  });

  test('a row of every other shelf stands on it', () {
    for (final (id, shelf) in [
      (EditorActionIds.toolBrush, ShortcutShelf.tools),
      (EditorActionIds.toolCut, ShortcutShelf.tools),
      (EditorActionIds.toolFillBucket, ShortcutShelf.tools),
      (EditorActionIds.toolTransformFree, ShortcutShelf.tools),
      (EditorActionIds.toolCutStamp, ShortcutShelf.tools),
      (
        shapeTileActionId(CanvasTool.select, CanvasShapeKind.lasso),
        ShortcutShelf.tools,
      ),
      (blendModeActionId(BrushBlendMode.erase), ShortcutShelf.blendModes),
      (EditorActionIds.selectionDeselect, ShortcutShelf.selection),
      (EditorActionIds.canvasRotateCw, ShortcutShelf.view),
      (EditorActionIds.playbackToggle, ShortcutShelf.playback),
      (EditorActionIds.cutNew, ShortcutShelf.cutPill),
      (EditorActionIds.layerAdd, ShortcutShelf.layerPill),
      (addLayerKindActionId(LayerKind.folder), ShortcutShelf.layerPill),
      (EditorActionIds.layerDetach, ShortcutShelf.layerPill),
      (EditorActionIds.frameNewDrawing, ShortcutShelf.framePill),
      (EditorActionIds.timelineComma2, ShortcutShelf.framePill),
      (EditorActionIds.frameSelectRowSpan, ShortcutShelf.framePill),
      (addEffectActionId(EffectKind.blur), ShortcutShelf.fxPill),
      (EditorActionIds.timelineZoomIn, ShortcutShelf.timelineBar),
      (EditorActionIds.cameraViewToggle, ShortcutShelf.timelineBar),
      (EditorActionIds.fileSave, ShortcutShelf.file),
      (EditorActionIds.preferences, ShortcutShelf.settings),
      (EditorActionIds.regionOnTop, ShortcutShelf.panels),
      (EditorActionIds.inputInspector, ShortcutShelf.debug),
    ]) {
      expect(shelfOf(id), shelf, reason: id);
    }
  });
}
