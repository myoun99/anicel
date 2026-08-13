import '../models/attached_layer_resolve.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import 'default_layer_helpers.dart';
import '../services/commands/add_layer_command.dart';
import '../services/commands/cut_command_input_planner.dart';
import '../services/history_manager.dart';
import '../services/project_lookup.dart';
import '../services/project_repository.dart';

class LayerController {
  LayerController({
    required ProjectRepository repository,
    required HistoryManager historyManager,
    required CutId? cutId,
    required FrameId frameId,
    LayerId? initialActiveLayerId,
    List<Layer> Function()? trackSeDisplayLayers,
    Layer Function()? trackTransitionDisplayLayer,
  }) : _repository = repository,
       _historyManager = historyManager,
       _cutId = cutId,
       _defaultFrameId = frameId,
       _trackSeDisplayLayers = trackSeDisplayLayers,
       _trackTransitionDisplayLayer = trackTransitionDisplayLayer,
       _activeLayerId = initialActiveLayerId {
    if (_activeLayerId != null && !_hasLayer(_activeLayerId!)) {
      throw StateError('Layer not found: $_activeLayerId');
    }
    _activeLayerId ??= layers.isEmpty ? null : layers.first.id;
  }

  final ProjectRepository _repository;
  final HistoryManager _historyManager;

  /// NULL = no active cut (gap state, UI-R9 #3): [layers] is empty and
  /// layer creation stands down.
  final CutId? _cutId;
  final FrameId _defaultFrameId;

  /// The track's SE rows as cut-local DISPLAY clones (the session windows
  /// them per active cut). They join [layers] so selection, row rendering
  /// and every read path see one composed list; mutations detect SE ids
  /// and edit the track's GLOBAL layers instead (never these clones).
  final List<Layer> Function()? _trackSeDisplayLayers;

  /// The track's ONE transition row, likewise a read-only display clone.
  /// It is a PROJECTION rather than a window: a span crossing this cut's
  /// boundary shows at full length on the side it belongs to, so the clone
  /// deliberately disagrees with the global row about where the span sits.
  final Layer Function()? _trackTransitionDisplayLayer;

  LayerId? _activeLayerId;

  List<Layer> get layers {
    final cut = _findCutOrNull();
    if (cut == null) {
      // Gap state: no rows at all — not even the track SE clones (the
      // timeline shows its empty state).
      return const <Layer>[];
    }
    final cutLayers = cut.layers;
    // SYNCED attach rows join as DISPLAY clones whose timeline mirrors
    // the base through the cell links (W5) — the same read-clone pattern
    // as the track SE rows below; writes address the real layers via
    // commands. FREE attach rows (UI-R21 #3) pass through untouched —
    // they own their timeline like any drawing layer.
    final displayed = [
      for (final layer in cutLayers)
        if (isSyncedAttachedLayer(layer))
          switch (attachedBaseOf(layer, cutLayers)) {
            null => layer,
            final base => attachedDisplayLayer(attached: layer, base: base),
          }
        else
          layer,
    ];
    final trackSe = _trackSeDisplayLayers?.call() ?? const <Layer>[];
    // The TRANSITION row joins on the same terms as the SE rows: track
    // owned, read here through a display clone, written only on the global
    // axis. It sorts into the camera section by kind like any other row.
    final transition = _trackTransitionDisplayLayer?.call();
    if (trackSe.isEmpty && transition == null) {
      return displayed;
    }
    final composed = [...displayed, ...trackSe];
    if (transition != null) {
      // Directly BEFORE the camera row in raw order, which puts the camera row
      // on TOP on screen: the horizontal timeline reverses raw order, so last
      // in the list is highest. The order is direction, transition, camera
      // with the camera highest (user 2026-08-10).
      //
      // Appending it — which is what this did — put the TRANSITION on top for
      // exactly that reason.
      final cameraIndex = composed.cameraIndex;
      composed.insert(
        cameraIndex < 0 ? composed.length : cameraIndex,
        transition,
      );
    }
    return composed;
  }

  LayerId? get activeLayerId {
    _ensureActiveLayerExists();
    return _activeLayerId;
  }

  Layer? get activeLayer {
    final id = activeLayerId;
    if (id == null) {
      return null;
    }

    return layers.firstWhere((layer) => layer.id == id);
  }

  bool get hasActiveLayer => activeLayer != null;

  FrameId get frameId {
    final layer = activeLayer;
    if (layer == null) {
      return _defaultFrameId;
    }
    if (layer.frames.isEmpty) {
      throw StateError('Active layer has no frames: ${layer.id}');
    }
    return layer.frames.first.id;
  }

  Frame? get activeFrame {
    final layer = activeLayer;
    if (layer == null || layer.frames.isEmpty) {
      return null;
    }
    return layer.frames.first;
  }

  void selectLayer(LayerId layerId) {
    if (!_hasLayer(layerId)) {
      throw StateError('Layer not found: $layerId');
    }
    _activeLayerId = layerId;
  }

  void addLayer({required Layer layer, int? insertionIndex}) {
    final cutId = _cutId;
    if (cutId == null) {
      return; // Gap state: nowhere to add (the UI stands down too).
    }
    // Layer EXISTENCE is shared structure: a row created here appears in
    // every 겸용 sibling too, with ids planned up front so redo reuses
    // them.
    final plan = planAddLayerCommandInput(
      project: _repository.requireProject(),
      cutId: cutId,
      layer: layer,
    );
    _historyManager.execute(
      AddLayerCommand(
        repository: _repository,
        cutId: cutId,
        layer: layer,
        insertionIndex: insertionIndex ?? _insertionIndexAboveActiveLayer(),
        mirrors: plan.mirrors,
        linkGroupId: plan.linkGroupId,
      ),
    );
    _activeLayerId = layer.id;
  }

  void addLayerWithDefaults({
    required LayerId layerId,
    String? name,
    LayerKind kind = LayerKind.animation,
  }) {
    final cut = _findCutOrNull();
    if (cut == null) {
      return;
    }
    addLayer(
      layer: createDefaultAnimationLayer(
        layerId: layerId,
        cut: cut,
      ).copyWith(kind: kind),
    );
  }

  /// 🚨T9 (유저 2026-08-13) — THE EYE IS PER-USE. So are static opacity and
  /// blend, and ⛔this REVERSES 「레인만 각자, 나머지는 하나」, which used to be
  /// quoted right here: 「링크레이어 … **비지블/정적불투명도는 독립되게
  /// 하고싶음.** 지금 하나 바꾸면 링크된 레이어들 바꿈. **겸용컷에서도 같은
  /// 로직 쓰지? 똑같이 적용되도록**」.
  ///
  /// ★What a link shares is the DRAWING — that is the whole of what it means
  /// for two rows to be one cel. How loudly a given cut shows that cel is
  /// that cut's own business, and mirroring it made one drawing impossible to
  /// use twice at two strengths, which is an ordinary reason to link.
  ///
  /// The 겸용 cut needed no separate answer because it never had one: both
  /// went through the same registry, so this is ONE deletion rather than two
  /// edits — and the mirror helper died with it, since these three were its
  /// only callers ([[duplication-program]]: the last step is removing the
  /// predecessor).
  void toggleLayerVisibility(LayerId layerId) {
    final project = _repository.requireProject();
    final nextVisible = !requireLayerAnywhere(project, layerId).isVisible;
    _repository.updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(isVisible: nextVisible),
    );
  }

  /// The layer-list twirl: PER-USE view state, persisted like CSP. Folder
  /// rows use it to swallow their members; the eye, static opacity and blend
  /// a folder carries need no method of their own, because a folder IS a
  /// layer and rides [toggleLayerVisibility] / [setLayerOpacity] /
  /// [setLayerBlendMode] — all four per-use since T9.
  void toggleLayerCollapsed(LayerId layerId) {
    _repository.updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(collapsed: !layer.collapsed),
    );
  }

  /// The audio counterpart of [toggleLayerVisibility]: silences the SE
  /// row's sounds without touching them (view state, not undoable).
  void toggleLayerMuted(LayerId layerId) {
    _repository.updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(muted: !layer.muted),
    );
  }

  /// The SE row's track fader + pan (AUDIO-PRO R1) — mix state alongside
  /// [toggleLayerMuted], written the same repo-direct way.
  void setLayerAudio({
    required LayerId layerId,
    double? gain,
    double? pan,
  }) {
    _repository.updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(
        audioGain: gain == null ? null : (gain < 0.0 ? 0.0 : gain),
        audioPan: pan?.clamp(-1.0, 1.0),
      ),
    );
  }

  /// R26 #30: the layer's composite blend — display state written the
  /// repo-direct way, and PER-USE like the eye (T9).
  void setLayerBlendMode({
    required LayerId layerId,
    required LayerBlendMode blendMode,
  }) {
    _repository.updateLayer(
      layerId: layerId,
      update: (layer) =>
          layer.blendMode == blendMode ? layer : layer.copyWith(blendMode: blendMode),
    );
  }

  /// Static opacity is PER-USE (T9), like the eye beside it. Per-use FADES
  /// still belong to the local FX opacity lane — that split is unchanged;
  /// what changed is that this one stopped reaching across the link.
  void setLayerOpacity({required LayerId layerId, required double opacity}) {
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    _repository.updateLayer(
      layerId: layerId,
      update: (layer) =>
          layer.opacity == clamped ? layer : layer.copyWith(opacity: clamped),
    );
  }

  Cut? _findCutOrNull() {
    if (_cutId == null) {
      return null;
    }
    final project = _repository.requireProject();
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id == _cutId) {
          return cut;
        }
      }
    }
    return null;
  }

  bool _hasLayer(LayerId layerId) {
    return layers.any((layer) => layer.id == layerId);
  }

  int _insertionIndexAboveActiveLayer() {
    // Insertion is into the CUT's layer list; a track-SE active layer is
    // not in it and appends like no-selection does.
    final cutLayers = _findCutOrNull()?.layers ?? const <Layer>[];
    final id = _activeLayerId;
    if (id == null) {
      return cutLayers.length;
    }

    final index = cutLayers.indexWhere((layer) => layer.id == id);
    return index < 0 ? cutLayers.length : index + 1;
  }

  void _ensureActiveLayerExists() {
    final id = _activeLayerId;
    if (id == null) {
      _activeLayerId = layers.isEmpty ? null : layers.first.id;
      return;
    }

    if (!_hasLayer(id)) {
      _activeLayerId = layers.isEmpty ? null : layers.first.id;
    }
  }
}
