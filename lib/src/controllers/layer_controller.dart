import '../models/attached_layer_resolve.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/project.dart';
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

  void toggleLayerVisibility(LayerId layerId) {
    // The eye MIRRORS across the layer's link group ("레인만 각자,
    // 나머지는 하나"): every member SETS the toggled value — per-member
    // toggling could freeze a divergent state forever.
    final project = _repository.requireProject();
    final target = requireLayerAnywhere(project, layerId);
    final nextVisible = !target.isVisible;
    for (final member in _mirrorTargetsOf(project, layerId)) {
      _repository.updateLayer(
        layerId: member,
        update: (layer) => layer.isVisible == nextVisible
            ? layer
            : layer.copyWith(isVisible: nextVisible),
      );
    }
  }

  /// The layer-list twirl: PER-USE view state — never mirrored ("레인만
  /// 각자" applies to display state too), persisted like CSP. Folder rows
  /// use it to swallow their members; the eye, static opacity and blend a
  /// folder carries need no method of their own, because a folder IS a
  /// layer and rides [toggleLayerVisibility] / [setLayerOpacity] /
  /// [setLayerBlendMode] — mirroring included.
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
  /// repo-direct way (like the eye and static opacity), mirrored across
  /// the link group.
  void setLayerBlendMode({
    required LayerId layerId,
    required LayerBlendMode blendMode,
  }) {
    final project = _repository.requireProject();
    for (final member in _mirrorTargetsOf(project, layerId)) {
      _repository.updateLayer(
        layerId: member,
        update: (layer) => layer.blendMode == blendMode
            ? layer
            : layer.copyWith(blendMode: blendMode),
      );
    }
  }

  void setLayerOpacity({required LayerId layerId, required double opacity}) {
    // Static opacity mirrors like the eye; per-use fades belong to the
    // local FX opacity lane instead.
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    final project = _repository.requireProject();
    for (final member in _mirrorTargetsOf(project, layerId)) {
      _repository.updateLayer(
        layerId: member,
        update: (layer) =>
            layer.opacity == clamped ? layer : layer.copyWith(opacity: clamped),
      );
    }
  }

  /// The link-group member ids a mirrored display edit applies to —
  /// [layerId] alone when unlinked (track SE rows always are).
  List<LayerId> _mirrorTargetsOf(Project project, LayerId layerId) {
    final cutId = cutIdOfLayer(project, layerId);
    if (cutId == null) {
      return [layerId];
    }
    final group = project.linkRegistry.groupOf(
      cutId: cutId,
      layerId: layerId,
    );
    if (group == null) {
      return [layerId];
    }
    return [for (final member in group.members) member.layerId];
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
