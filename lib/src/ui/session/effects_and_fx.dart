import '../../services/project_lookup.dart' show cutIdOfLayer;
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/property_track.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../../services/command.dart';
import '../../services/commands/update_layer_transform_enabled_command.dart';
import '../timeline/effect_lane_editing.dart'
    show
        effectsWithAdded,
        effectsWithEnabledToggled,
        effectsWithGroupReset,
        effectsWithRemoved;
import 'active_cut_edits.dart';
import 'session_roles.dart';

/// The EFFECTS AND THE FX SWITCHES — the effect chains a layer or a track
/// carries, their key names, and the switches that bypass a layer's, a
/// track's or every layer's effects — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and sixteen
/// session members touched. It names the roles it needs in its constructor.
class EffectsAndFx {
  EffectsAndFx({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required ActiveCutEdits activeCut,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _internals = internals,
       _activeCut = activeCut;

  final ActiveCutEdits _activeCut;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;

  /// [cutId]'s owning track's EFFECT chain — the V row's fx, which every
  /// route that draws this cut filters its finished picture through. Empty
  /// for an orphan, and empty is the zero-cost path.
  List<LayerEffect> trackEffectsForCut(CutId cutId) =>
      _project.trackOwningCut(cutId)?.effects ?? const [];

  /// Replaces [layerId]'s EFFECT CHAIN (R6 — the color/blur lanes); one
  /// undo step, no-op when unchanged.
  void updateLayerEffects(
    LayerId layerId,
    List<LayerEffect> effects, {
    String description = 'Edit layer effects',
  }) => _activeCut.onActiveCutQuietly(
    (cutId) => _project.cutCommandCoordinator.updateLayerEffects(
      cutId: cutId,
      layerId: layerId,
      effects: effects,
      description: description,
    ),
  );

  /// Whether the ACTIVE row can take an effect: a row that carries its own
  /// FX, and not a track-owned SE row (its display clone strips FX, so a
  /// chain committed through it would land nowhere the lanes could edit).
  bool get canAddEffectToActiveLayer {
    final layer = _selection.activeLayer;
    return layer != null &&
        layerKindHasLayerEffects(layer.kind) &&
        !_project.isTrackSeLayerId(layer.id) &&
        // Attach rows wear their BASE's FX (W5) and have no lanes of their
        // own — the effect belongs on the base.
        layer.attachedToLayerId == null;
  }

  /// Appends a fresh effect of [kind] (every parameter at its default, so
  /// adding one changes nothing until a value moves) to the active row.
  void addEffectToActiveLayer(EffectKind kind) {
    final layer = _selection.activeLayer;
    if (layer == null || !canAddEffectToActiveLayer) {
      return;
    }
    _effectSequence += 1;
    final effect = LayerEffect.defaults(
      // Timestamped like the frame ids: the lane address embeds this, so
      // two effects added in the same session must never collide.
      id: EffectId(
        'fx-${layer.id.value}-'
        '${DateTime.now().microsecondsSinceEpoch}-$_effectSequence',
      ),
      kind: kind,
    );
    updateLayerEffects(
      layer.id,
      effectsWithAdded(layer.effects, effect),
      description: 'Add ${kind.label}',
    );
  }

  /// Names (or un-names, with null) one effect-parameter KEY.
  ///
  /// A name is a link: every key called this, in this same parameter, holds
  /// one value — the frame-name rule said of keyframes (user 2026-07-30).
  /// Because linked rows share effect ids, that naming space reaches the
  /// 겸용 siblings whose chains otherwise only share their shape.
  ///
  /// Returns true when [name] is ALREADY taken in that space and NOTHING
  /// was written, so the caller can offer to join instead (see
  /// [linkEffectKeyName]) — the same report [FrameVerbs.renameSelectedFrame] makes
  /// about a colliding frame name. False means the rename applied, or could
  /// not.
  ///
  /// The collision is reported as a FACT rather than as the value behind
  /// it: a transform lane's value is a point, not a number, and a link
  /// whose two halves disagree about what they carry would be two links.
  bool setEffectKeyName({
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
    required String? name,
  }) {
    final cutId = _timeline.editingSession.activeCutId;
    if (cutId == null) {
      return false;
    }
    final site = _effectKeySite(
      cutId: cutId,
      layerId: layerId,
      effectId: effectId,
      parameterId: parameterId,
      frameIndex: frameIndex,
    );
    if (site == null || site.key.name == name) {
      return false;
    }
    if (name != null &&
        _project.cutCommandCoordinator.namedEffectKeyValueInSpace(
              cutId: cutId,
              layerId: layerId,
              effectId: effectId,
              parameterId: parameterId,
              name: name,
            ) !=
            null) {
      return true;
    }
    _writeEffectKeyName(
      cutId: cutId,
      layerId: layerId,
      effectId: effectId,
      parameterId: parameterId,
      frameIndex: frameIndex,
      name: name,
    );
    return false;
  }

  /// Joins [name], ADOPTING the value that name already holds — the answer
  /// to the "합칠까요?" [setEffectKeyName] raises.
  ///
  /// The key takes the number rather than imposing its own, exactly as
  /// [FrameVerbs.linkSelectedFrame] takes the drawing that is already there (user
  /// 2026-08-10). A name that turns out to be free just applies, so a stale
  /// confirmation cannot blank the value.
  void linkEffectKeyName({
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
    required String name,
  }) {
    final cutId = _timeline.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _writeEffectKeyName(
      cutId: cutId,
      layerId: layerId,
      effectId: effectId,
      parameterId: parameterId,
      frameIndex: frameIndex,
      name: name,
      adopted: _project.cutCommandCoordinator.namedEffectKeyValueInSpace(
        cutId: cutId,
        layerId: layerId,
        effectId: effectId,
        parameterId: parameterId,
        name: name,
      ),
    );
  }

  /// The one effect-parameter key a naming verb addresses, with what its
  /// write needs — null when any link of that chain is missing.
  ({
    Layer layer,
    LayerEffect effect,
    int effectIndex,
    EffectParameter parameter,
    PropertyKey<double> key,
  })?
  _effectKeySite({
    required CutId cutId,
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
  }) {
    final layers = _project.cutById(cutId)?.layers ?? const <Layer>[];
    final layerIndex = layers.indexWhere((row) => row.id == layerId);
    if (layerIndex == -1) {
      return null;
    }
    final layer = layers[layerIndex];
    final effectIndex = layer.effects.indexWhere(
      (effect) => effect.id == effectId,
    );
    if (effectIndex == -1) {
      return null;
    }
    final effect = layer.effects[effectIndex];
    final parameter = effect.parameters[parameterId];
    final key = parameter?.track.keyAt(frameIndex);
    if (parameter == null || key == null) {
      return null;
    }
    return (
      layer: layer,
      effect: effect,
      effectIndex: effectIndex,
      parameter: parameter,
      key: key,
    );
  }

  /// Writes one key's [name] — and, when [adopted] is given, the value that
  /// name brings with it — as ONE undo step. The key's interpolation is
  /// carried across explicitly: adopting a value must not silently restyle
  /// the segment leaving the key.
  void _writeEffectKeyName({
    required CutId cutId,
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
    required String? name,
    double? adopted,
  }) {
    final site = _effectKeySite(
      cutId: cutId,
      layerId: layerId,
      effectId: effectId,
      parameterId: parameterId,
      frameIndex: frameIndex,
    );
    if (site == null) {
      return;
    }
    var track = site.parameter.track;
    if (adopted != null && adopted != site.key.value) {
      track = track.withKey(
        frameIndex,
        adopted,
        interpolation: site.key.interpolation,
      );
    }
    track = track.withKeyName(frameIndex, name);
    final next = [...site.layer.effects]
      ..[site.effectIndex] = site.effect.withParameter(
        parameterId,
        EffectParameter(value: site.parameter.value, track: track),
      );
    updateLayerEffects(
      layerId,
      next,
      description: name == null ? 'Unname key' : 'Name key',
    );
  }

  /// Removes one effect from the active row (its keys go with it; one undo
  /// brings both back).
  void removeEffectFromActiveLayer(EffectId effectId) {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return;
    }
    final next = effectsWithRemoved(layer.effects, effectId);
    if (next == null) {
      return;
    }
    updateLayerEffects(layer.id, next, description: 'Remove effect');
  }

  int _effectSequence = 0;

  /// An effect parameter's resolved value at [frameIndex] — the lane value
  /// column and the key-freeze source, read through the SAME resolver the
  /// composite uses so the number in the lane is the number on the canvas.
  double layerEffectParameterAtFrame(
    Layer layer,
    EffectId effectId,
    String parameterId,
    int frameIndex,
  ) {
    for (final effect in layer.effects) {
      if (effect.id == effectId) {
        return effect.parameterOf(parameterId).resolveAt(frameIndex);
      }
    }
    return 0;
  }

  /// The row's FX state: its TRANSFORM switch ([Layer.transformEnabled])
  /// plus every effect's own switch, read as one answer for the layer-label
  /// button — AE's fx column, and a MASTER over the per-group switches
  /// (user, 2026-07-30: "통합토글버튼").
  ///
  /// [LayerFxState.mixed] is what makes it a master rather than a second
  /// independent bypass: some groups on, some off, and tapping resolves the
  /// whole row one way.
  LayerFxState layerFxState(LayerId layerId) {
    final layer = fxSwitchLayerById(layerId);
    if (layer == null) {
      return LayerFxState.on;
    }
    final switches = <bool>[
      if (layerKindHasTransformFxSwitch(layer.kind)) layer.transformEnabled,
      for (final effect in layer.effects) effect.enabled,
    ];
    if (switches.isEmpty) {
      return LayerFxState.on; // An adjustment row with no effects yet.
    }
    if (switches.every((enabled) => enabled)) {
      return LayerFxState.on;
    }
    if (switches.every((enabled) => !enabled)) {
      return LayerFxState.off;
    }
    return LayerFxState.mixed;
  }

  /// Whether ANY of the row's FX apply — the row-level facet question the
  /// timeline filter asks ("show me the rows that are doing something").
  bool isLayerFxEnabled(LayerId layerId) =>
      fxEnabledFromState(layerFxState(layerId));

  /// Whether the row's TRANSFORM applies. Every reader of a transform
  /// PROPERTY (pose, animated opacity, the position gizmo) asks this and
  /// not [isLayerFxEnabled]: since R8 split the switches per group, a row
  /// can have its transform bypassed while a colour effect still runs —
  /// the master's [LayerFxState.mixed] answer cannot decide the pose.
  bool isLayerTransformFxEnabled(LayerId layerId) =>
      fxSwitchLayerById(layerId)?.transformEnabled ?? true;

  /// The MASTER toggle: off unless the row is already fully off, in which
  /// case it turns everything back on. ONE undo step for the whole row.
  void toggleLayerFx(LayerId layerId) {
    final layer = fxSwitchLayerById(layerId);
    if (layer == null) {
      return;
    }
    final turnOn = layerFxState(layerId) == LayerFxState.off;
    _setLayerFxSwitches([layer], enabled: turnOn);
  }

  /// The TRANSFORM group header's own switch (R8).
  void toggleLayerTransformFx(LayerId layerId) {
    final layer = fxSwitchLayerById(layerId);
    if (layer == null) {
      return;
    }
    _internals.updateLayerTransformEnabled(
      layerId,
      enabled: !layer.transformEnabled,
      description: layer.transformEnabled
          ? 'Bypass transform'
          : 'Apply transform',
    );
  }

  /// The row a switch edit addresses: a cut layer, or a track-owned SE row
  /// (whose display clone is not the thing to write).
  Layer? fxSwitchLayerById(LayerId layerId) =>
      _project.layerById(layerId) ?? _project.trackSeGlobalLayerById(layerId);

  /// Writes every FX switch of [targets] to [enabled] as ONE undo step.
  void _setLayerFxSwitches(List<Layer> targets, {required bool enabled}) {
    final commands = <Command>[];
    for (final layer in targets) {
      // The camera row is IN: it carries no effects, but its own switch —
      // the one that bypasses the cut camera's work — is this flag.
      if (layerKindHasTransformFxSwitch(layer.kind) &&
          layer.transformEnabled != enabled) {
        commands.add(
          UpdateLayerTransformEnabledCommand(
            repository: _project.repository,
            layerId: layer.id,
            transformEnabled: enabled,
          ),
        );
      }
      if (layer.effects.isEmpty) {
        continue;
      }
      // Through the COORDINATOR, not a hand-built command: it owns the
      // 겸용컷 effect mirror, and a master that built its own would write
      // one cut of a link group and leave its twin permanently `mixed`.
      final cutId = cutIdOfLayer(
        _project.repository.requireProject(),
        layer.id,
      );
      if (cutId == null) {
        continue; // A row no cut holds (a track-SE clone) has no chain here.
      }
      commands.addAll(
        _project.cutCommandCoordinator.layerEffectsCommands(
          cutId: cutId,
          layerId: layer.id,
          effects: [
            for (final effect in layer.effects)
              effect.copyWith(enabled: enabled),
          ],
          description: enabled ? 'Apply layer FX' : 'Bypass layer FX',
        ),
      );
    }
    if (commands.isEmpty) {
      return;
    }
    _project.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: enabled ? 'Apply layer FX' : 'Bypass layer FX',
              commands: commands,
            ),
    );
    // A bare notify, like every sibling row write (opacity, blend, the
    // transform track, the effect chain): a switch flip is not a structural
    // cut edit, and refreshing as one threw away the frame-range selection
    // the user keeps while A/B-ing the switch.
    _changes.notifyChanged();
  }

  /// Whether the cut's fx (the V track's Transform group — the pose AND
  /// the fade, "opacity joins the transform system") apply at DISPLAY
  /// time. R9 #21: the owning TRACK's persisted master is folded in HERE
  /// rather than at each reader — the playback canvas, the multitrack
  /// stack and the editing preview all ask this one question, so the
  /// track switch reaches all three by arriving at the choke point
  /// instead of being threaded to them.
  ///
  /// R10 R3: the per-CUT bypass that used to sit in front of this line is
  /// gone. It was reachable only through a context menu, it never left the
  /// session, and while editing shows one cut at a time it said exactly
  /// what the track switch already says.
  bool isCutFxEnabled(CutId cutId) =>
      _project.trackOwningCut(cutId)?.fxEnabled ?? true;

  /// The V row's fx switch: OFF while the track's flag is down, ON
  /// otherwise. It stays a [LayerFxState] because the button it drives is
  /// the shared one.
  ///
  /// Still never MIXED, now that the row carries an effect chain as well:
  /// unlike a layer's, this master is STORED state rather than a reading of
  /// the switches beneath it, so it reports what it is. A bypassed effect
  /// says so on its own lane header, where the eye already looks.
  LayerFxState trackFxState(TrackId trackId) {
    final track = _project.trackById(trackId);
    if (track == null) {
      return LayerFxState.on;
    }
    return track.fxEnabled ? LayerFxState.on : LayerFxState.off;
  }

  /// Replaces [trackId]'s effect chain; one undo step.
  void updateTrackEffects(
    TrackId trackId,
    List<LayerEffect> effects, {
    String description = 'Edit track effects',
  }) {
    _project.cutCommandCoordinator.updateTrackEffects(
      trackId: trackId,
      effects: effects,
      description: description,
    );
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  /// Adds an effect to the V row's chain. Ids are minted the way a layer's
  /// are (the lane address embeds them, so two adds in one session must not
  /// collide) — off the TRACK id, since that is what carries the chain.
  void addEffectToTrack(TrackId trackId, EffectKind kind) {
    final track = _project.trackById(trackId);
    if (track == null) {
      return;
    }
    _effectSequence += 1;
    final effect = LayerEffect.defaults(
      id: EffectId(
        'fx-${trackId.value}-'
        '${DateTime.now().microsecondsSinceEpoch}-$_effectSequence',
      ),
      kind: kind,
    );
    updateTrackEffects(
      trackId,
      effectsWithAdded(track.effects, effect),
      description: 'Add ${kind.label}',
    );
  }

  void removeEffectFromTrack(TrackId trackId, EffectId effectId) {
    final track = _project.trackById(trackId);
    if (track == null) {
      return;
    }
    final next = effectsWithRemoved(track.effects, effectId);
    if (next == null) {
      return;
    }
    updateTrackEffects(trackId, next, description: 'Remove effect');
  }

  /// A V-track effect group's RESET (R5) — the track twin of
  /// [_internals.resetLaneGroup]. Track effects have no lane-range selection of their
  /// own, so the scope is always the playhead.
  bool resetTrackEffectGroup(TrackId trackId, String headerLaneId) {
    final track = _project.trackById(trackId);
    if (track == null) {
      return false;
    }
    final next = effectsWithGroupReset(
      track.effects,
      laneId: headerLaneId,
      frameIndexes: [_timeline.timelineController.currentFrameIndex],
    );
    if (next == null) {
      return false;
    }
    updateTrackEffects(trackId, next, description: 'Reset group');
    return true;
  }

  /// One effect's own bypass on the V row — the switch on its group header,
  /// the twin of a layer effect's.
  void toggleTrackEffectEnabled(TrackId trackId, EffectId effectId) {
    final track = _project.trackById(trackId);
    if (track == null) {
      return;
    }
    final next = effectsWithEnabledToggled(track.effects, effectId);
    if (next == null) {
      return;
    }
    updateTrackEffects(trackId, next, description: 'Toggle effect');
  }

  /// A track effect parameter's resolved value at GLOBAL [frameIndex] — the
  /// lane value column and the key-freeze source, through the same resolver
  /// the composite samples with.
  double trackEffectParameterAtFrame(
    Track track,
    EffectId effectId,
    String parameterId,
    int frameIndex,
  ) {
    for (final effect in track.effects) {
      if (effect.id == effectId) {
        return effect.parameterOf(parameterId).resolveAt(frameIndex);
      }
    }
    return 0;
  }

  /// The V row's fx toggle, one undoable write.
  void toggleTrackFx(TrackId trackId) {
    final track = _project.trackById(trackId);
    if (track == null) {
      return;
    }
    final turnOn = !track.fxEnabled;
    _project.cutCommandCoordinator.updateTrackDisplay(
      trackId: trackId,
      fxEnabled: turnOn,
      description: turnOn ? 'Apply track FX' : 'Bypass track FX',
    );
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  /// The effect chain a lane/fx-header address names: a real layer's, or the
  /// V TRACK's through the carrier id (R4b). Null when neither exists.
  List<LayerEffect>? effectChainOf(LayerId layerId) {
    final trackId = trackIdOfTransformLaneCarrier(layerId);
    if (trackId != null) {
      return _project.trackById(trackId)?.effects;
    }
    return _project.layerById(layerId)?.effects;
  }

  /// Bypasses or restores EVERY layer's fx — the legend's bulk flyout,
  /// through the same persisted switches the per-row master writes, as ONE
  /// undo step (R8).
  void setAllLayersFxBypassed(bool bypassed) {
    _setLayerFxSwitches(_project.layers, enabled: !bypassed);
  }
}
