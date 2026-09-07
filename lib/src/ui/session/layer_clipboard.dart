import '../../models/attached_layer_resolve.dart';
import '../../models/layer_kind.dart';
import '../../services/clipboard/layer_copy_payload.dart';
import 'layer_stack.dart';
import 'session_roles.dart';

/// The LAYER CLIPBOARD — the layer the user copied, and pasting it into a
/// cut — as its own object.
///
/// 🚨Split out of `FrameClipboard` (G0-2, 2026-09-06). A frame board and a
/// layer board are two boards: they hold different payloads, answer to
/// different verbs, and the only thing they shared was the object that
/// happened to hold both. What kept them together was that one class held
/// them, which is not a reason.
class LayerClipboard {
  LayerClipboard({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required LayerStack layerStack,
  }) : _project = project,
       _selection = selection,
       _changes = changes,

       _layerStack = layerStack;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final LayerStack _layerStack;

  LayerCopyPayload? _layerClipboard;

  String? get layerClipboardName => _layerClipboard?.name;

  bool get hasLayerClipboard => _layerClipboard != null;

  /// The board goes when the project itself is replaced.
  void clear() {
    _layerClipboard = null;
  }

  void copyActiveLayer() {
    final activeLayer = _selection.activeLayer;
    // SE rows are track-owned (global frame axis) — copying a cut-local
    // window onto the cut-layer clipboard would recreate the retired
    // cut-owned SE shape; stands down for now. Attach rows stand down too
    // (their cel links point into THIS cut's base).
    if (activeLayer == null ||
        !layerKindIsClipboardCopyable(activeLayer.kind) ||
        isAttachedLayer(activeLayer)) {
      return;
    }

    _layerClipboard = copyLayerToPayload(activeLayer);
    _changes.notifyChanged();
  }

  void pasteLayerFromClipboard() {
    final payload = _layerClipboard;
    if (payload == null) {
      return;
    }

    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return;
    }
    if (!_layerStack.canAddLayerOfKind(payload.kind)) {
      // R9 #7: this cut already holds its one row of that kind.
      // ⚠️NEVER APPLIED by any test (mutation, 2026-09-06): nothing copies a
      // single-instance row and pastes it into a cut that already has one.
      return;
    }
    final activeLayer = _selection.activeLayer;
    final targetLayers = cut.layers;
    final activeLayerIndex = activeLayer == null
        ? -1
        : targetLayers.indexWhere((layer) => layer.id == activeLayer.id);
    final insertionIndex = activeLayerIndex == -1
        ? targetLayers.length
        : activeLayerIndex + 1;

    final pastedLayerId = _project.cutCommandCoordinator.pasteLayer(
      cutId: cut.id,
      payload: payload,
      insertionIndex: insertionIndex,
    );
    _changes.refreshAfterCutCommand(preferredActiveLayerId: pastedLayerId);
    _changes.notifyChanged();
  }
}
