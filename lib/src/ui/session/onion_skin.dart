import '../../services/commands/toggle_id_in_set_command.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/layer_folder.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../canvas/canvas_layer_stack_view.dart';
import '../../services/command.dart';
import '../../services/onion_skin_plan.dart';
import 'session_roles.dart';

/// The ONION SKIN — which layers ghost, the sweep over the displayed ones,
/// and what the canvas is asked to draw for them — as its own object. The
/// settings and the layer set stay on the session: the UI reads them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: no private field of its own and
/// eight session members touched. It names the roles it needs in its constructor.
class OnionSkin {
  OnionSkin({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _internals = internals;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;

  bool isLayerOnionSkinEnabled(LayerId layerId) =>
      _internals.onionSkinLayerIds.value.contains(layerId);

  void toggleLayerOnionSkin(LayerId layerId) {
    // 🚨UNDOABLE (유저 2026-08-29: 「아무튼 레이어에 있는 버튼 싹다」). ⛔I
    // began to explain that undoing this "only moves session state, not
    // the project", and 유저 stopped me: 「프로젝트 파일이 바뀌란건
    // 무슨소리지? 아무튼 어니언 적용 미적용만 되면 되는건데」. Press the
    // button, press Ctrl+Z, the ghosts come back. Where the bit lives is
    // plumbing.
    _project.historyManager.execute(
      ToggleIdInSetCommand(
        notifier: _internals.onionSkinLayerIds,
        layerId: layerId,
        debugLabel: 'Toggle onion skin',
      ),
    );
    // Row/legend toggle glyphs read through the session listenable.
    _changes.notifyChanged();
  }

  /// The drawing layers the legend's bulk onion sweep addresses: the
  /// active cut's VISIBLE brush-holding rows.
  List<Layer> get _onionSweepLayers {
    final stack = _project.activeCutOrNull?.layers ?? const <Layer>[];
    return [
      for (final layer in stack)
        // `rowVisible`, not `isVisible`: a row inside a hidden folder is not
        // displayed, so the sweep over "every displayed layer" must not
        // count it — otherwise the bulk button reads OFF because of rows
        // nobody can see.
        if (stack.rowVisible(layer) && layerKindAcceptsBrushInput(layer.kind))
          layer,
    ];
  }

  /// Whether the legend's bulk button reads ON (every displayed layer
  /// currently ghosting).
  bool get displayedLayersOnionSkinEnabled {
    final targets = _onionSweepLayers;
    return targets.isNotEmpty &&
        targets.every((layer) => isLayerOnionSkinEnabled(layer.id));
  }

  /// Legend bulk sweep (UI-R17 #5): all displayed layers on — or, when
  /// they all are already, all off.
  void toggleOnionSkinForDisplayedLayers() {
    final targets = _onionSweepLayers;
    if (targets.isEmpty) {
      return;
    }
    final enable = !displayedLayersOnionSkinEnabled;
    // 🚨ONE undo step for one legend press. This used to write the set
    // directly, so the bulk sweep undid NOTHING even after the per-row
    // toggle became undoable — 유저 caught the gap by asking what
    // "restores this id's membership" meant: 「조작끝낸 모든 레이어가
    // 안돌아간단거야 설마?」. It would not have, here.
    //
    // ⛔Only the rows this press actually CHANGES go in the batch: a
    // command for a row already in the target state is a no-op that still
    // costs an entry to walk back through.
    final changing = [
      for (final layer in targets)
        if (isLayerOnionSkinEnabled(layer.id) != enable) layer.id,
    ];
    if (changing.isEmpty) {
      return;
    }
    _project.historyManager.execute(
      CompositeCommand(
        description: 'Toggle onion skin (${changing.length} layers)',
        commands: [
          for (final layerId in changing)
            ToggleIdInSetCommand(
              notifier: _internals.onionSkinLayerIds,
              layerId: layerId,
              debugLabel: 'Toggle onion skin',
            ),
        ],
      ),
    );
    _changes.notifyChanged();
  }

  /// The `O` shortcut: toggles the ACTIVE layer's onion (the per-layer
  /// model's successor of the old master toggle).
  void toggleOnionSkin() {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return;
    }
    toggleLayerOnionSkin(layer.id);
  }

  /// Whose effect chain a ghost of [layer] wears: an ATTACH row wears its
  /// BASE's (W5), everyone else their own.
  ///
  /// The same carrier rule the active-row node applies — named once so the
  /// two cannot answer differently for the same row.
  static Layer _onionFxCarrier(Layer layer, List<Layer> layers) {
    if (!isAttachedLayer(layer)) {
      return layer;
    }
    return attachedBaseOf(layer, layers) ?? layer;
  }

  /// The ghost frames to composite at the playhead: every onion-enabled
  /// VISIBLE drawing layer contributes its plan (unique drawings, peg
  /// opacities, side tints) in layer-stack order.
  List<CanvasLayerImageRequest> onionSkinCanvasRequests() {
    final settings = _internals.onionSkinSettings.value;
    final cut = _project.activeCutOrNull;
    final enabledIds = _internals.onionSkinLayerIds.value;
    if (cut == null || enabledIds.isEmpty) {
      return const [];
    }
    return [
      for (final layer in cut.layers)
        // A ghost is that layer's artwork, so it is shown exactly when the
        // layer is: hiding the FOLDER used to leave its members' onion skins
        // on screen with nothing under them.
        if (enabledIds.contains(layer.id) &&
            cut.layers.rowVisible(layer) &&
            layerKindAcceptsBrushInput(layer.kind))
          for (final plan in planOnionSkin(
            layer: layer,
            frameIndex: _timeline.timelineController.currentFrameIndex,
            settings: settings,
          ))
            CanvasLayerImageRequest(
              frameKey: _internals.brushFrameKeyForCut(
                cut,
                layer.id,
                plan.frameId,
              ),
              opacity: plan.opacity,
              tint: plan.tint,
              // ✅유저 2026-08-27 (I-8-Q5): a ghost shows the pixels the
              // screen shows. It used to carry NO chain, which read as a
              // design ("editing scaffolding") but was really the Colors
              // tint owning the paint's one color-filter slot — the fold in
              // `resolveCompositeEffectPaint` retired that constraint.
              //
              // Sampled at the GHOST's own frame, and read off the attach
              // BASE where there is one — an attach row wears its base's fx
              // (W5), the same carrier rule the active-row node uses.
              effects: resolveLayerEffectsAt(
                effects: _onionFxCarrier(layer, cut.layers).effects,
                frameIndex: plan.frameIndex,
              ),
            ),
    ];
  }
}
