import '../../models/attached_layer_resolve.dart'
    show attachRowWearsBaseComposite;
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
import '../../services/commands/update_track_effects_command.dart';
import '../timeline/effect_lane_editing.dart'
    show effectsWithAdded, effectsWithEnabledToggled, effectsWithGroupReset;
import '../timeline/effect_lane_policy.dart' show effectGroupLaneId;
import 'active_cut_edits.dart';
import 'row_written_by_id.dart';
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
    required Command? Function(LayerId row, String laneId) laneGroupShown,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _activeCut = activeCut,
       _laneGroupShown = laneGroupShown;

  final ActiveCutEdits _activeCut;

  /// The step that shows a row's lane group — its lanes twirled down and
  /// the group open among them; null where it already shows (F-396).
  final Command? Function(LayerId row, String laneId) _laneGroupShown;

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
  }) => _activeCut.onCutOfRowQuietly(
    layerId,
    (cutId) => _project.cutCommandCoordinator.updateLayerEffects(
      cutId: cutId,
      layerId: layerId,
      effects: effects,
      description: description,
    ),
  );

  /// Whether the ACTIVE row can take an effect of [kind]: a row that carries
  /// its own FX — and, for a kind that draws a cel number
  /// ([EffectKind.drawsItsOwnPicture]), one whose drawings carry one
  /// ([LayerKind.numbersItsDrawings]): the letters print it.
  ///
  /// ↩️A track-owned SE row was fenced off here since R6a (2026-07-30: 「its
  /// display clone strips FX」). The clone projects the track's chain now,
  /// and 유저's law for a global row is that every cut can work it (F-102:
  /// 「로컬에서도 조작은 가능」) — so the chain goes where the row lives
  /// ([ProjectAccess.commitLayerById]).
  bool canAddEffectToActiveLayer(EffectKind kind) {
    final layer = _selection.activeLayer;
    return layer != null &&
        layer.kind.hasLayerEffects &&
        // A row that wears its BASE's fx has no lanes of its own — the
        // effect belongs on the base. ↩️It asked `attachedToLayerId` alone,
        // so a 공정 organizer folder took an effect no lane could reach
        // (I-99).
        !attachRowWearsBaseComposite(
          layer,
          _project.activeCutOrNull?.layers ?? const [],
        ) &&
        (!kind.drawsItsOwnPicture || layer.kind.numbersItsDrawings);
  }

  /// Appends a fresh effect of [kind] (every parameter at its default, so
  /// adding one changes nothing until a value moves) to the active row —
  /// and shows it: the row's lanes twirled down and the effect's header
  /// open, in the same undo step ([_laneGroupShown], F-396).
  ///
  /// ⚠️Built from the row that HOLDS the chain, not from the active row: an
  /// SE row's active row is its cut's projection, whose keys sit on the
  /// cut's frames — appending to that would write them back onto the
  /// track's row at the wrong frames.
  void addEffectToActiveLayer(EffectKind kind) {
    if (canAddEffectToActiveLayer(kind)) {
      _appendToActiveLayer([
        (id) => LayerEffect.defaults(id: id, kind: kind),
      ], description: 'Add ${kind.label}');
    }
  }

  /// Whether [holder]'s chain can take an effect of [kind] — the active
  /// row's gate or the V row's.
  bool canAddEffect(EffectChainHolder holder, EffectKind kind) =>
      switch (holder) {
        ActiveRowChain() => canAddEffectToActiveLayer(kind),
        TrackChain(:final trackId) => canAddEffectToTrack(trackId, kind),
      };

  /// Adds an effect of [kind] to [holder]'s chain.
  void addEffect(EffectChainHolder holder, EffectKind kind) => switch (holder) {
    ActiveRowChain() => addEffectToActiveLayer(kind),
    TrackChain(:final trackId) => addEffectToTrack(trackId, kind),
  };

  /// Whether [holder]'s chain takes any of [effects] — each by the gate an
  /// add of its kind keeps ([canAddEffect]).
  bool canAddEffectCopies(
    EffectChainHolder holder,
    List<LayerEffect> effects,
  ) => effects.any((effect) => canAddEffect(holder, effect.kind));

  /// 🗣️F-476-Q1 (유저 2026-10-27, 「b + 복제도」): a paste of effects is an
  /// ADD of them — each [holder]'s chain takes, a copy under an id of its
  /// own, at the end of its chain, shown as an add shows it. One undo.
  void addEffectCopies(EffectChainHolder holder, List<LayerEffect> effects) {
    final made = [
      for (final effect in effects)
        if (canAddEffect(holder, effect.kind))
          (EffectId id) => effect.copyWith(id: id),
    ];
    const description = 'Paste effects';
    switch (holder) {
      case ActiveRowChain():
        _appendToActiveLayer(made, description: description);
      case TrackChain(:final trackId):
        _appendToTrack(trackId, made, description: description);
    }
  }

  /// Appends what [made] makes, each under an id minted for the row, to the
  /// active row's chain, and shows them ([showEffects]) — one undo.
  void _appendToActiveLayer(
    List<LayerEffect Function(EffectId id)> made, {
    required String description,
  }) {
    final active = _selection.activeLayer;
    if (active == null || made.isEmpty) {
      return;
    }
    final layer = _project.commitLayerById(active.id) ?? active;
    final effects = [
      for (final make in made) make(mintEffectId(layer.id.value)),
    ];
    final history = _project.historyManager;
    _activeCut.onCutOfRowQuietly(
      layer.id,
      (cutId) => history.runAsOneStep(description, () {
        history.executeAsOneStep(
          description,
          _project.cutCommandCoordinator.layerEffectsCommands(
            cutId: cutId,
            layerId: layer.id,
            effects: effects.fold(layer.effects, effectsWithAdded),
            description: description,
          ),
        );
        showEffects(layer.id, effects);
      }),
    );
  }

  /// A fresh id for an effect on [owner]'s chain. Timestamped like the
  /// frame ids: the lane address embeds it, so two effects minted in the
  /// same session must never collide.
  EffectId mintEffectId(String owner) {
    _effectSequence += 1;
    return EffectId(
      'fx-$owner-${DateTime.now().microsecondsSinceEpoch}-$_effectSequence',
    );
  }

  int _effectSequence = 0;

  /// Shows [effects] on [row]: its lanes twirled down and each effect's
  /// header open (F-396) — each a step of the caller's ONE, so it runs
  /// inside it; one show reads what the one before it opened.
  void showEffects(LayerId row, Iterable<LayerEffect> effects) {
    for (final effect in effects) {
      final shown = _laneGroupShown(row, effectGroupLaneId(effect.id));
      if (shown != null) {
        _project.historyManager.execute(shown);
      }
    }
  }

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
    final layer = _project.rowWrittenById(layerId);
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
      _project.rowWrittenById(layerId)?.transformEnabled ?? true;

  /// The MASTER toggle: off unless the row is already fully off, in which
  /// case it turns everything back on. ONE undo step for the whole row.
  void toggleLayerFx(LayerId layerId) {
    final layer = _project.rowWrittenById(layerId);
    if (layer == null) {
      return;
    }
    final turnOn = layerFxState(layerId) == LayerFxState.off;
    _setLayerFxSwitches([layer], enabled: turnOn);
  }

  /// The TRANSFORM group header's own switch (R8).
  void toggleLayerTransformFx(LayerId layerId) {
    final layer = _project.rowWrittenById(layerId);
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
    final layer = _project.rowWrittenById(layerId);
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
      final cutId = _activeCut.cutOfRow(layer.id);
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
    _project.historyManager.executeAsOneStep(
      enabled ? 'Apply layer FX' : 'Bypass layer FX',
      commands,
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

  /// Whether [trackId]'s V row can take an effect of [kind]: a track that
  /// is there, and not a kind that draws a cel number
  /// ([EffectKind.drawsItsOwnPicture]), by the law the row gate keeps
  /// ([canAddEffectToActiveLayer]): the V row has no drawing whose number
  /// the letters would print.
  bool canAddEffectToTrack(TrackId trackId, EffectKind kind) =>
      _project.trackById(trackId) != null && !kind.drawsItsOwnPicture;

  /// Adds an effect to the V row's chain, as [addEffectToActiveLayer] does
  /// to a layer's.
  void addEffectToTrack(TrackId trackId, EffectKind kind) {
    if (canAddEffectToTrack(trackId, kind)) {
      _appendToTrack(trackId, [
        (id) => LayerEffect.defaults(id: id, kind: kind),
      ], description: 'Add ${kind.label}');
    }
  }

  /// Appends what [made] makes to [trackId]'s chain, as
  /// [_appendToActiveLayer] does to the active row's. The ids are minted off
  /// the TRACK id, since that is what carries the chain, and the effects are
  /// shown on the row's lane carrier ([trackTransformLaneCarrierId]).
  void _appendToTrack(
    TrackId trackId,
    List<LayerEffect Function(EffectId id)> made, {
    required String description,
  }) {
    final track = _project.trackById(trackId);
    if (track == null || made.isEmpty) {
      return;
    }
    final effects = [
      for (final make in made) make(mintEffectId(trackId.value)),
    ];
    final history = _project.historyManager;
    history.runAsOneStep(description, () {
      history.execute(
        UpdateTrackEffectsCommand(
          repository: _project.repository,
          trackId: trackId,
          effects: effects.fold(track.effects, effectsWithAdded),
          description: description,
        ),
      );
      showEffects(trackTransformLaneCarrierId(trackId), effects);
    });
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
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
  /// `LaneVerbs.resetLaneGroup`. Track effects have no lane-range
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

  /// The effect chain a lane/fx-header address names: a real layer's — the
  /// row a write of it addresses ([RowWrittenById.rowWrittenById]) — or the
  /// V TRACK's through the carrier id (R4b). Null when neither exists.
  ///
  /// 🗣️I-89 ①ⓓ: the conte rail re-orders an S row's chain on every track
  /// (유저 2026-10-13 「같은 법으로」). ↩️It asked the active cut's rows
  /// alone, so another track's S row found no chain and its drag did
  /// nothing — the fx switch's own trap, measured 09-25.
  List<LayerEffect>? effectChainOf(LayerId layerId) {
    final trackId = trackIdOfTransformLaneCarrier(layerId);
    if (trackId != null) {
      return _project.trackById(trackId)?.effects;
    }
    return _project.rowWrittenById(layerId)?.effects;
  }

  /// Bypasses or restores EVERY layer's fx — the legend's bulk flyout,
  /// through the same persisted switches the per-row master writes, as ONE
  /// undo step (R8).
  void setAllLayersFxBypassed(bool bypassed) {
    _setLayerFxSwitches(_project.layers, enabled: !bypassed);
  }
}

/// The row whose chain an add of effects lands on — the fx menu's, and a
/// paste of effects, which is an add of them (F-476-Q1).
sealed class EffectChainHolder {
  const EffectChainHolder();
}

/// The cut's ACTIVE row ([EffectsAndFx.addEffectToActiveLayer]).
final class ActiveRowChain extends EffectChainHolder {
  const ActiveRowChain();
}

/// [trackId]'s V row ([EffectsAndFx.addEffectToTrack]).
///
/// 🗣️layer-menu-strings-outlive-their-entries-Q1 (유저 2026-10-30, 「공용
/// Fx 가 V행도 받는다」): B7 took the V row's own fx pill away as the same
/// button as the shared Fx (08-17), and the shared one only added to the
/// active row — so nothing reached the V row's chain.
final class TrackChain extends EffectChainHolder {
  const TrackChain(this.trackId);

  final TrackId trackId;
}
