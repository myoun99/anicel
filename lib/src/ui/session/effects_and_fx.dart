import '../../services/project_lookup.dart'
    show cutIdOfLayer, layerAnywhereOrNull;
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../../services/command.dart';
import '../../services/commands/update_layer_transform_enabled_command.dart';
import '../timeline/effect_lane_editing.dart'
    show effectsWithAdded, effectsWithEnabledToggled, effectsWithGroupReset;
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
    required ActiveCutEdits activeCut,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _activeCut = activeCut;

  final ActiveCutEdits _activeCut;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;

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
  /// FX.
  ///
  /// ↩️A track-owned SE row was fenced off here since R6a (2026-07-30: 「its
  /// display clone strips FX」). The clone projects the track's chain now,
  /// and 유저's law for a global row is that every cut can work it (F-102:
  /// 「로컬에서도 조작은 가능」) — so the chain goes where the row lives
  /// ([ProjectAccess.commitLayerById]).
  bool get canAddEffectToActiveLayer {
    final layer = _selection.activeLayer;
    return layer != null &&
        layer.kind.hasLayerEffects &&
        // Attach rows wear their BASE's FX (W5) and have no lanes of their
        // own — the effect belongs on the base.
        layer.attachedToLayerId == null;
  }

  /// Appends a fresh effect of [kind] (every parameter at its default, so
  /// adding one changes nothing until a value moves) to the active row.
  ///
  /// ⚠️Built from the row that HOLDS the chain, not from the active row: an
  /// SE row's active row is its cut's projection, whose keys sit on the
  /// cut's frames — appending to that would write them back onto the
  /// track's row at the wrong frames.
  void addEffectToActiveLayer(EffectKind kind) {
    final active = _selection.activeLayer;
    if (active == null || !canAddEffectToActiveLayer) {
      return;
    }
    final layer = _project.commitLayerById(active.id) ?? active;
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

  int _effectSequence = 0;

  /// An effect parameter's resolved value at [frameIndex] — the lane value
  /// column and the key-freeze source, read through the SAME resolver the
  /// composite uses so the number in the lane is the number on the canvas.
  double layerEffectParameterAtFrame(
    Layer layer,
    EffectId effectId,
    String parameterId,
    int frameIndex,
  ) => effectParameterValueAt(layer.effects, effectId, parameterId, frameIndex);

  /// The row's FX state: its TRANSFORM switch ([Layer.transformEnabled])
  /// plus every effect's own switch, read as one answer for the layer-label
  /// button — AE's fx column, and a MASTER over the per-group switches
  /// (user, 2026-07-30: "통합토글버튼").
  ///
  /// [LayerFxState.mixed] is what makes it a master rather than a second
  /// independent bypass: some groups on, some off, and tapping resolves the
  /// whole row one way.
  LayerFxState layerFxState(LayerId layerId) {
    final layer = _fxRow(layerId);
    if (layer == null) {
      return LayerFxState.on;
    }
    final switches = <bool>[
      if (layer.kind.hasTransformFxSwitch) layer.transformEnabled,
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
      _fxRow(layerId)?.transformEnabled ?? true;

  /// The MASTER toggle: off unless the row is already fully off, in which
  /// case it turns everything back on. ONE undo step for the whole row.
  void toggleLayerFx(LayerId layerId) {
    final layer = _fxRow(layerId);
    if (layer == null) {
      return;
    }
    final turnOn = layerFxState(layerId) == LayerFxState.off;
    _setLayerFxSwitches([layer], enabled: turnOn);
  }

  /// The TRANSFORM group header's own switch (R8).
  void toggleLayerTransformFx(LayerId layerId) {
    final layer = _fxRow(layerId);
    if (layer == null) {
      return;
    }
    setLayerTransformFx(
      layerId,
      enabled: !layer.transformEnabled,
      description: layer.transformEnabled
          ? 'Bypass transform'
          : 'Apply transform',
    );
  }

  /// Sets [layerId]'s TRANSFORM switch — one undo step, and none at all
  /// when it already reads [enabled].
  void setLayerTransformFx(
    LayerId layerId, {
    required bool enabled,
    String description = 'Toggle transform FX',
  }) {
    final layer = _fxRow(layerId);
    final command = layer == null
        ? null
        : _transformSwitch(layer, enabled: enabled, description: description);
    if (command == null) {
      return;
    }
    _project.historyManager.execute(command);
    // Not a structural cut edit — see [_setLayerFxSwitches].
    _changes.notifyChanged();
  }

  // ⛔The row an FX edit addresses is [ProjectAccess.commitLayerById] — the
  // row every layer op commits against, a track-owned SE row's GLOBAL form
  // and not its cut's projection. A private `fxSwitchLayerById` restated it
  // as 「cut layer, else the SE row」 and asked the cut FIRST, which hands
  // back the projection: a chain built from it lands on the track at the
  // cut's frames (se-row-fx-write-path's third pin).
  //
  // 🚨AND WHERE THAT KNOWS NOTHING, THE ROW WHEREVER IT LIVES
  // (other-track-s-row-fx-and-mixer, measured 2026-09-25): the storyboard
  // rail carries every track's S rows, and `commitLayerById` answers a
  // track row from the ACTIVE track alone — another track's fx read
  // 「on」 forever and its press did nothing. The model walk returns the
  // global form too, never a projection. `commitLayerById` itself stays
  // as it is: its timing callers work inside the active cut's window.
  Layer? _fxRow(LayerId layerId) =>
      _project.commitLayerById(layerId) ??
      layerAnywhereOrNull(_project.repository.requireProject(), layerId);

  /// The command that sets [layer]'s transform switch, or null when the
  /// row has none or it already reads [enabled].
  UpdateLayerTransformEnabledCommand? _transformSwitch(
    Layer layer, {
    required bool enabled,
    String description = 'Toggle transform FX',
  }) => layer.kind.hasTransformFxSwitch && layer.transformEnabled != enabled
      ? UpdateLayerTransformEnabledCommand(
          repository: _project.repository,
          layerId: layer.id,
          transformEnabled: enabled,
          description: description,
        )
      : null;

  /// Writes every FX switch of [targets] to [enabled] as ONE undo step.
  void _setLayerFxSwitches(List<Layer> targets, {required bool enabled}) {
    final commands = <Command>[];
    for (final layer in targets) {
      // The camera row is IN: it carries no effects, but its own switch —
      // the one that bypasses the cut camera's work — is this flag.
      final transform = _transformSwitch(layer, enabled: enabled);
      if (transform != null) {
        commands.add(transform);
      }
      if (layer.effects.isEmpty) {
        continue;
      }
      // Through the COORDINATOR, not a hand-built command: it owns the
      // 겸용컷 effect mirror, and a master that built its own would write
      // one cut of a link group and leave its twin permanently `mixed`.
      // A track-owned SE row lives in no cut: its chain is addressed from
      // the cut the user stands in, as every other FX edit of it is
      // ([updateLayerEffects]).
      final cutId =
          cutIdOfLayer(_project.repository.requireProject(), layer.id) ??
          _project.activeCutId;
      if (cutId == null) {
        continue;
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

  /// Runs one `effectsWith*` transform over [trackId]'s chain and banks it
  /// as one undo step; false when there is no such track, or the transform
  /// declines (null = nothing would change). The envelope the track verbs
  /// each wrote out around effect_lane_editing.dart's transforms.
  bool _editTrackEffects(
    TrackId trackId, {
    required String description,
    required List<LayerEffect>? Function(List<LayerEffect> fx) edit,
  }) {
    final track = _project.trackById(trackId);
    final next = track == null ? null : edit(track.effects);
    if (next == null) {
      return false;
    }
    updateTrackEffects(trackId, next, description: description);
    return true;
  }

  /// A V-track effect group's RESET (R5) — the track twin of
  /// [SessionInternals.resetLaneGroup]. Track effects have no lane-range
  /// selection of their own, so the scope is always the playhead.
  bool resetTrackEffectGroup(TrackId trackId, String headerLaneId) =>
      _editTrackEffects(
        trackId,
        description: 'Reset group',
        edit: (fx) => effectsWithGroupReset(
          fx,
          laneId: headerLaneId,
          frameIndexes: [_selection.currentFrameIndex],
        ),
      );

  /// One effect's own bypass on the V row — the switch on its group header,
  /// the twin of a layer effect's.
  void toggleTrackEffectEnabled(TrackId trackId, EffectId effectId) =>
      _editTrackEffects(
        trackId,
        description: 'Toggle effect',
        edit: (effects) => effectsWithEnabledToggled(effects, effectId),
      );

  /// A track effect parameter's resolved value at GLOBAL [frameIndex] — the
  /// lane value column and the key-freeze source, through the same resolver
  /// the composite samples with.
  double trackEffectParameterAtFrame(
    Track track,
    EffectId effectId,
    String parameterId,
    int frameIndex,
  ) => effectParameterValueAt(track.effects, effectId, parameterId, frameIndex);

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
