import 'package:flutter/foundation.dart';

import '../../../models/attached_mode.dart';
import '../../../models/cut.dart';
import '../../../models/cut_id.dart';
import '../../../models/layer.dart';
import '../../../models/layer_effect.dart';
import '../../../models/layer_id.dart';
import '../../../models/track.dart';
import '../../../models/track_id.dart';
import '../../text/app_strings.dart';
import '../../timeline/layer_drop_policy.dart'
    show
        LayerDropPlan,
        layerDragRun,
        layerDropRefusedForNestedFolder,
        modelInsertionForSlot,
        resolveEffectDrop,
        resolveLayerDrop,
        resolveLayerDropOnRow,
        resolveTrackSeDrop;
import '../../timeline/layer_row_drag.dart'
    show
        EffectRowSubject,
        LayerRowDragState,
        LayerRowDragSubject,
        LayerRowSubject,
        TrackRowSubject;

/// The row-order drag (layer / track / effect rows) as its own object.
///
/// It follows [EditorDragSession]'s lifecycle — begun by constructing it,
/// closed by exactly one of [commit] or [cancel], then discarded — without
/// implementing the interface: its update surface is FOUR caret verbs with
/// different shapes, not one scalar, and pretending otherwise would lie
/// about the family.
///
/// Its channel ([_channel], the session's `layerRowDrag`) carries the drawn
/// state — subject, caret, legality, the label the caret SAYS — but the
/// COMMIT reads only this object's fields: the plan held beside the drawn
/// state so the release does not resolve the landing a second time, and so
/// the drawn `legal` and the committed plan cannot disagree.
class RowOrderDrag {
  RowOrderDrag({
    required LayerRowDragSubject subject,
    required ValueNotifier<LayerRowDragState?> channel,
    required List<Track> Function() tracksNow,
    required List<LayerEffect>? Function(LayerId) effectChainOf,
    required ({Track track, Layer layer})? Function(LayerId) trackSeAnywhere,
    required Cut? Function() activeCutOrNull,
    required bool Function(LayerId) isTrackSeLayerId,
    required Set<LayerId> Function(LayerId) rowSelectionCarriedBy,
    required TrackId? Function(LayerId) trackIdOfTransformLaneCarrier,
    required AttachedMode Function({
      required CutId cutId,
      required LayerId layerId,
      required LayerId baseId,
    })
    mountModeFor,
    required AppStrings Function() uiStrings,
    required void Function({
      required int fromIndex,
      required int toIndex,
      required String trackName,
    })
    commitTrackReorder,
    required void Function(TrackId trackId, List<LayerEffect> effects)
    commitTrackEffects,
    required void Function({
      required CutId cutId,
      required LayerId layerId,
      required List<LayerEffect> effects,
    })
    commitLayerEffects,
    required void Function({
      required TrackId trackId,
      required List<LayerId> order,
    })
    commitSeOrder,
    required void Function({
      required CutId cutId,
      required LayerDropPlan plan,
      required LayerId subjectLayerId,
      required Set<LayerId> movedIds,
    })
    commitPlacement,
  }) : _subject = subject,
       _channel = channel,
       _tracksNow = tracksNow,
       _effectChainOf = effectChainOf,
       _trackSeAnywhere = trackSeAnywhere,
       _activeCutOrNull = activeCutOrNull,
       _isTrackSeLayerId = isTrackSeLayerId,
       _rowSelectionCarriedBy = rowSelectionCarriedBy,
       _trackIdOfTransformLaneCarrier = trackIdOfTransformLaneCarrier,
       _mountModeFor = mountModeFor,
       _uiStrings = uiStrings,
       _commitTrackReorder = commitTrackReorder,
       _commitTrackEffects = commitTrackEffects,
       _commitLayerEffects = commitLayerEffects,
       _commitSeOrder = commitSeOrder,
       _commitPlacement = commitPlacement {
    _channel.value = LayerRowDragState(
      subject: subject,
      caretSlot: -1,
      legal: false,
    );
  }

  final LayerRowDragSubject _subject;
  final ValueNotifier<LayerRowDragState?> _channel;

  /// What releasing would commit — held beside the drawn state.
  LayerDropPlan? _plan;
  List<LayerId>? _seOrder;
  List<EffectId>? _effectOrder;
  int? _trackSlot;

  final List<Track> Function() _tracksNow;
  final List<LayerEffect>? Function(LayerId) _effectChainOf;
  final ({Track track, Layer layer})? Function(LayerId) _trackSeAnywhere;
  final Cut? Function() _activeCutOrNull;
  final bool Function(LayerId) _isTrackSeLayerId;
  final Set<LayerId> Function(LayerId) _rowSelectionCarriedBy;
  final TrackId? Function(LayerId) _trackIdOfTransformLaneCarrier;
  final AttachedMode Function({
    required CutId cutId,
    required LayerId layerId,
    required LayerId baseId,
  })
  _mountModeFor;
  final AppStrings Function() _uiStrings;

  /// The four commit paths, one per subject kind, each ONE undo step with
  /// its own epilogue behind it on the session.
  final void Function({
    required int fromIndex,
    required int toIndex,
    required String trackName,
  })
  _commitTrackReorder;
  final void Function(TrackId trackId, List<LayerEffect> effects)
  _commitTrackEffects;
  final void Function({
    required CutId cutId,
    required LayerId layerId,
    required List<LayerEffect> effects,
  })
  _commitLayerEffects;
  final void Function({required TrackId trackId, required List<LayerId> order})
  _commitSeOrder;
  final void Function({
    required CutId cutId,
    required LayerDropPlan plan,
    required LayerId subjectLayerId,
    required Set<LayerId> movedIds,
  })
  _commitPlacement;

  /// R5 #9: the caret moved within the project's TRACK list.
  ///
  /// It is legal wherever it lands — tracks are a flat list with no
  /// folders, no attach and no 겸용 mirror, so there is nothing a slot can
  /// be refused for. That is why this holds a slot and not a plan.
  void updateTrackRow(int slot) {
    if (_subject is! TrackRowSubject) {
      return;
    }
    final clamped = slot.clamp(0, _tracksNow().length);
    _trackSlot = clamped;
    final state = _channel.value;
    if (state != null && state.caretSlot == clamped && state.legal) {
      return;
    }
    _channel.value = LayerRowDragState(
      subject: _subject,
      caretSlot: clamped,
      legal: true,
    );
  }

  /// The caret moved within one layer's effect CHAIN.
  ///
  /// The chain's order is shared STRUCTURE, so the commit goes through the
  /// coordinator's `updateLayerEffects` — which mirrors the shape across
  /// the 겸용 link group. Building an `UpdateLayerEffectsCommand` here
  /// would drop that mirror silently, which is the trap that command's own
  /// doc names.
  void updateEffectRow(LayerId layerId, List<EffectId> displayEffects, int slot) {
    final subject = _subject;
    // The V row's chain rides the same drag through the carrier id (R4b) —
    // the gesture, the caret and the arithmetic are the layer rail's; only
    // the list being re-ordered differs.
    final chain = _effectChainOf(layerId);
    if (subject is! EffectRowSubject || chain == null) {
      return;
    }
    final order = resolveEffectDrop(
      modelEffects: [for (final effect in chain) effect.id],
      displayEffects: displayEffects,
      movingId: subject.effectId,
      slot: slot,
    );
    _effectOrder = order;
    _channel.value = LayerRowDragState(
      subject: subject,
      caretSlot: slot,
      legal: order != null,
    );
  }

  /// The caret moved to [slot] of [displayLayers] — the list the SURFACE
  /// renders, which is what lets the model insertion be resolved without
  /// this verb knowing which way that rail runs.
  ///
  /// [noticeLabel] overrides what the caret SAYS (⑦): the landing is an
  /// ordinary move, but something the pointer just passed over refused for a
  /// reason worth naming.
  void updateLayerRow(
    List<Layer> displayLayers,
    int slot, {
    String? noticeLabel,
  }) {
    final subject = _subject;
    if (subject is! LayerRowSubject) {
      return;
    }
    // The row's OWN track, not the selected one: an S row is a track
    // fixture and re-orders its own track's list wherever the open cut is.
    if (_trackSeAnywhere(subject.layerId)?.track case final seTrack?) {
      final landing = _nearestLanding(
        displayLayers,
        subject.layerId,
        slot,
        (probe) => resolveTrackSeDrop(
          seLayers: seTrack.seLayers,
          displayRows: displayLayers,
          movingId: subject.layerId,
          slot: probe,
        ),
      );
      _seOrder = landing?.value;
      _channel.value = LayerRowDragState(
        subject: subject,
        caretSlot: landing?.slot ?? slot,
        legal: landing != null,
      );
      return;
    }
    final cut = _activeCutOrNull();
    if (cut == null) {
      return;
    }
    final landing = _nearestLanding(displayLayers, subject.layerId, slot, (
      probe,
    ) {
      final insertAt = modelInsertionForSlot(
        stack: cut.layers,
        displayRows: displayLayers,
        slot: probe,
      );
      return insertAt == null
          ? null
          : resolveLayerDrop(
              stack: cut.layers,
              movingId: subject.layerId,
              insertAt: insertAt,
              alsoMoving: _rowSelectionCarriedBy(subject.layerId),
            );
    });
    final plan = landing?.value;
    _plan = plan;
    _channel.value = LayerRowDragState(
      subject: subject,
      caretSlot: landing?.slot ?? slot,
      legal: plan != null,
      joinLabel:
          noticeLabel ?? _rowDropLabel(cut.id, cut.layers, subject.layerId, plan),
    );
  }

  /// 결정 6 (유저 확정 2026-08-22) — **THE CARET STANDS AT THE NEAREST SLOT
  /// THAT WOULD ACTUALLY LAND**, searching back toward the row's own place.
  ///
  /// > 「놓을 수 없는 곳엔 선을 안 그리고, 커서가 넘어가면 **갈 수 있는 마지막
  /// > 자리에 붙여둔다** — 전 섹션 공통」
  ///
  /// 🎯**One law, not two.** The rail already refused to draw a caret it had
  /// called illegal (the painter gates on `legal`), so the visible half of the
  /// complaint was the OTHER half: past the last legal slot the line did not
  /// stay put, it VANISHED — the drag looked dead while it was merely being
  /// asked for something it could not do. Pinning to the nearest landing makes
  /// the first clause moot rather than implementing it twice: there is no
  /// "illegal caret" state left to hide.
  ///
  /// ⛔The search stops AT the row's own place rather than passing through it.
  /// A run owns the gaps at both its ends and putting it back there is not a
  /// landing (④, 2026-08-12) — walking past would let a drag that has gone
  /// nowhere draw a caret on the far side, which is the announcement ④
  /// removed. So "nothing legal between here and home" still draws nothing.
  ///
  /// ⚠️It walks one slot at a time because legality is not an interval: a
  /// section boundary, a group that cannot be split and a folder run all
  /// refuse for different reasons and can sit in any arrangement. The walk
  /// only runs when the slot under the pointer is already refused, and it is
  /// bounded by the distance home, so an ordinary in-section drag pays one
  /// resolve exactly as before.
  ({int slot, T value})? _nearestLanding<T>(
    List<Layer> displayLayers,
    LayerId movingId,
    int slot,
    T? Function(int probe) resolveAt,
  ) {
    final home = displayLayers.indexWhere((layer) => layer.id == movingId);
    // The two gaps the row itself occupies; a caret in neither direction has
    // anywhere to walk to when the row is not on this surface at all.
    final lower = home < 0 ? slot : home;
    final upper = home < 0 ? slot : home + 1;
    var probe = slot.clamp(0, displayLayers.length);
    while (true) {
      final value = resolveAt(probe);
      if (value != null) {
        return (slot: probe, value: value);
      }
      if (probe >= lower && probe <= upper) {
        return null;
      }
      probe += probe > upper ? -1 : 1;
    }
  }

  /// R5 #15: the pointer is ON [targetId] rather than between rows.
  ///
  /// The intent a caret cannot carry: a folder with no members has no gap
  /// that means "inside it", and a base with no riders has none either.
  /// Everything past the intent is [resolveLayerDropOnRow]'s, which hands
  /// the ordinary resolver the same stack — so an on-row landing and a gap
  /// landing cannot disagree about what is legal.
  void updateLayerRowDropOnRow(
    List<Layer> displayLayers,
    int slot,
    LayerId targetId,
  ) {
    final subject = _subject;
    final cut = _activeCutOrNull();
    // Track-owned SE rows re-order a flat list of their own and hold
    // nothing, so they have no inside to drop into.
    if (subject is! LayerRowSubject ||
        cut == null ||
        _isTrackSeLayerId(subject.layerId)) {
      updateLayerRow(displayLayers, slot);
      return;
    }
    // THE RULE (user, 2026-08-09): ON a row is a STRUCTURAL drop — into the
    // folder, or onto the base as its rider. BETWEEN rows is a move. That a
    // full row of travel therefore stops being "nudge it past its
    // neighbour" is not a collision, it is the point: the gap is where
    // repositioning lives, and the gap is half a row away.
    //
    // The two read cleanly against the arithmetic already here — travelling
    // a whole number of rows preserves where in a row you grabbed, so a
    // FULL row lands dead centre of the next one (structural) and a HALF
    // row lands on the boundary (the caret, one step). The "half a row is
    // one step" rule this drag has always used is the same sentence read
    // from the other end.
    final plan = resolveLayerDropOnRow(
      stack: cut.layers,
      movingId: subject.layerId,
      targetId: targetId,
      alsoMoving: _rowSelectionCarriedBy(subject.layerId),
    );
    if (plan == null) {
      // Nothing there can swallow it — an SE row, a camera row, a base that
      // already carries riders. The gap under the pointer is still a
      // perfectly good landing, so the caret comes back rather than the drag
      // going dead.
      //
      // ⑦: with ONE exception the user asked to be told about — a folder
      // that carries a folder. The drag stays useful (the caret is still
      // the fallback), but it says why the attach did not happen, because
      // that landing is the only one that looks like it should have worked.
      updateLayerRow(
        displayLayers,
        slot,
        noticeLabel: layerDropRefusedForNestedFolder(
              stack: cut.layers,
              movingId: subject.layerId,
              targetId: targetId,
            )
            ? _uiStrings().tlDropFolderInAttachFolder
            : null,
      );
      return;
    }
    _plan = plan;
    _seOrder = null;
    _channel.value = LayerRowDragState(
      subject: subject,
      caretSlot: -1,
      legal: true,
      onRowTarget: targetId,
      joinLabel: _rowDropLabel(cut.id, cut.layers, subject.layerId, plan),
    );
  }

  /// What the drop would DO beyond re-ordering, named — or null when it only
  /// re-orders. The parts of a drop that outlive the gesture are the parts
  /// the caret spells out, and it says them in order of how much they change:
  /// becoming an attach row, ceasing to be one, then folder membership.
  String? _rowDropLabel(
    CutId cutId,
    List<Layer> stack,
    LayerId movingId,
    LayerDropPlan? plan,
  ) {
    if (plan == null) {
      return null;
    }
    // ⑦: a folder drop carries several mounts, but they share a base and a
    // side — the caret names the base, so the first one speaks for all.
    final mount = plan.attach.mounts.firstOrNull;
    if (mount != null) {
      final base = stack.byId(mount.baseId);
      final mode = _mountModeFor(
        cutId: cutId,
        layerId: mount.layerId,
        baseId: mount.baseId,
      );
      // SYNCED and FREE are different promises about the row's timing, so
      // the caret names which one rather than just "attach".
      final template = mode == AttachedMode.synced
          ? AppText.strings.tlDropAttachSyncedTemplate
          : AppText.strings.tlDropAttachFreeTemplate;
      return base == null ? null : template.replaceAll('{name}', base.name);
    }
    // A folder carried out of a group detaches its MEMBERS, not the row the
    // pointer holds, so the question is whether anything detaches at all.
    if (plan.attach.detachIds.isNotEmpty) {
      return AppText.strings.tlDropDetachAttach;
    }
    if (!plan.folderIds.containsKey(movingId)) {
      return null;
    }
    final joined = plan.joinedFolderId;
    if (joined == null) {
      return AppText.strings.tlDropOutOfFolder;
    }
    final folder = stack.byId(joined);
    return folder == null
        ? null
        : AppText.strings.tlDropIntoFolderTemplate.replaceAll(
            '{name}',
            folder.name,
          );
  }

  void commit() {
    final plan = _plan;
    final seOrder = _seOrder;
    final effectOrder = _effectOrder;
    final trackSlot = _trackSlot;
    final subject = _subject;
    cancel();
    if (subject is TrackRowSubject) {
      // R5 #9. The caret is a SLOT (between rows) and the model wants an
      // INDEX: landing after yourself means one fewer position once you
      // are lifted out, which is the off-by-one every reorder has.
      final tracks = _tracksNow();
      final from = tracks.indexWhere((track) => track.id == subject.trackId);
      if (trackSlot == null || from < 0) {
        return;
      }
      final to = trackSlot > from ? trackSlot - 1 : trackSlot;
      if (to == from) {
        return;
      }
      _commitTrackReorder(
        fromIndex: from,
        toIndex: to,
        trackName: tracks[from].name,
      );
      return;
    }
    final cut = _activeCutOrNull();
    if (subject is EffectRowSubject) {
      final chain = _effectChainOf(subject.layerId);
      if (effectOrder == null || chain == null) {
        return;
      }
      final byId = {for (final effect in chain) effect.id: effect};
      final reordered = [for (final id in effectOrder) byId[id]!];
      final carrierTrackId = _trackIdOfTransformLaneCarrier(subject.layerId);
      if (carrierTrackId != null) {
        // The V row's chain lives on the TRACK, so there is no cut and no
        // 겸용 mirror in this commit.
        _commitTrackEffects(carrierTrackId, reordered);
        return;
      }
      if (cut == null) {
        return;
      }
      _commitLayerEffects(
        cutId: cut.id,
        layerId: subject.layerId,
        effects: reordered,
      );
      return;
    }
    if (subject is! LayerRowSubject) {
      return;
    }
    if (seOrder != null) {
      // The track the dragged row BELONGS to. This used to commit to the
      // selected track, which is why the rail only offered the drag while
      // that track held the open cut — the gate was a guard against this
      // line, not a rule anyone wanted.
      final seTrack = _trackSeAnywhere(subject.layerId)?.track;
      if (seTrack != null) {
        _commitSeOrder(trackId: seTrack.id, order: seOrder);
      }
      return;
    }
    if (plan == null || cut == null) {
      return;
    }
    final run = layerDragRun(cut.layers, subject.layerId);
    if (run == null) {
      return;
    }
    _commitPlacement(
      cutId: cut.id,
      plan: plan,
      subjectLayerId: subject.layerId,
      movedIds: {
        for (final layer in cut.layers.sublist(run.start, run.endExclusive))
          layer.id,
      },
    );
  }

  void cancel() {
    _plan = null;
    _seOrder = null;
    _effectOrder = null;
    _trackSlot = null;
    _channel.value = null;
  }
}
