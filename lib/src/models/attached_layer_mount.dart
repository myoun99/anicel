/// MAKING and UNMAKING an attach relationship (P3 「붙이고 뗀다」) — the
/// model half.
///
/// [attached_layer_resolve.dart] answers what an attach row LOOKS like while
/// it rides a base. This file answers the two structural questions either
/// side of that:
///
/// * **May this row ride that base's timing?** A SYNCED row has no timeline
///   of its own — the base's exposures are the row's — so mounting one over
///   an existing row can only be lossless when the two already agree. That
///   agreement is [attachExposureShape], and it decides SYNCED vs FREE.
/// * **What is the row once it stops riding?** A SYNCED row's timing lives
///   on the base, so detaching has to BAKE it: the derived timeline becomes
///   the row's own. Its pose and FX do NOT bake (user 2026-08-07: "일단은
///   그렇게") — the row visibly jumps, and that is the intended price.
library;

import 'attached_layer_resolve.dart';
import 'attached_mode.dart';
import 'attached_placement.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'layer_kind.dart';
import 'timeline_exposure.dart';
import 'timeline_repeat.dart';

/// One row's exposure SHAPE — what a SYNCED mount has to agree on.
///
/// Per AUTHORED drawing block, in frame order: where it starts, how long it
/// holds, and which earlier block shares its cel ([celOrdinal] = the index
/// of that cel's first appearance in this list).
///
/// What it deliberately ignores: the cels' identities (the two rows draw
/// different pictures — that is the point), the inbetween dots, the memos,
/// and the GHOSTS a repeat/hold edge derives (a ghost is not authored
/// timing; the mirror row wears the base's tail anyway).
///
/// Why the reuse pattern belongs in the shape: the links are keyed by BASE
/// CEL, so a base exposing one cel twice makes the attach row expose ONE
/// cel twice as well — that is exactly what cell-level links mean. If the
/// row's two blocks held different pictures, one of them would have no link
/// to live in and would go dark. Counting the pattern as part of the shape
/// turns that silent loss into a FREE mount instead.
List<({int start, int length, int celOrdinal})> attachExposureShape(
  Layer layer,
) {
  final shape = <({int start, int length, int celOrdinal})>[];
  final firstSeen = <FrameId, int>{};
  for (final entry in layer.timeline.entries) {
    final exposure = entry.value;
    final frameId = exposure.frameId;
    final length = exposure.length;
    if (!exposure.isDrawing || exposure.ghost || frameId == null ||
        length == null) {
      continue;
    }
    final ordinal = firstSeen.putIfAbsent(frameId, () => shape.length);
    shape.add((start: entry.key, length: length, celOrdinal: ordinal));
  }
  return shape;
}

/// The cell links a SYNCED mount of [row] onto [base] would store — or null
/// when the two shapes disagree, which is the whole SYNCED/FREE decision.
///
/// COMPLETENESS is the contract: every non-ghost base cel gets a link.
/// A link the mount forgets does not stay forgotten — the repository's
/// always-mirror normalization mints a fresh EMPTY cel for it on the next
/// write, and an empty mirror cel published in silence is the hazard this
/// pairing exists to avoid.
Map<FrameId, FrameId>? attachedLinksForMount({
  required Layer row,
  required Layer base,
}) {
  final rowShape = attachExposureShape(row);
  final baseShape = attachExposureShape(base);
  if (rowShape.length != baseShape.length) {
    return null;
  }
  final rowCels = _blockCelIds(row);
  final baseCels = _blockCelIds(base);
  final links = <FrameId, FrameId>{};
  for (var index = 0; index < baseShape.length; index += 1) {
    if (rowShape[index].start != baseShape[index].start ||
        rowShape[index].length != baseShape[index].length ||
        rowShape[index].celOrdinal != baseShape[index].celOrdinal) {
      return null;
    }
    links[baseCels[index]] = rowCels[index];
  }
  return links;
}

/// The cel each authored block of [layer] exposes, in frame order (parallel
/// to [attachExposureShape]).
List<FrameId> _blockCelIds(Layer layer) {
  return [
    for (final entry in layer.timeline.entries)
      if (entry.value.isDrawing &&
          !entry.value.ghost &&
          entry.value.frameId != null &&
          entry.value.length != null)
        entry.value.frameId!,
  ];
}

/// Whether [row] could become an attach row of [base] at all — the kind
/// gate, asked before any timing question.
///
/// Bases are drawing rows and attaches never nest ([canCarryAttachedLayers]).
/// On the riding side the same drawing-kind rule applies, minus the
/// SINGLETON kinds: a cut holds exactly one storyboard row and one camera
/// row, so neither can be somebody's attach row without making that
/// "exactly one" ambiguous.
bool canMountLayerOnBase({required Layer row, required Layer base}) {
  return row.id != base.id &&
      canCarryAttachedLayers(base) &&
      layerKindIsDrawingCel(row.kind) &&
      !layerKindGroupsLayers(row.kind) &&
      !layerKindIsSingletonPerCut(row.kind);
}

/// The fields an attach/detach edit writes, and nothing else.
///
/// Stated as a value so the command can capture the BEFORE and write the
/// AFTER with the same shape — an undo that restores exactly what was
/// overwritten, rather than a whole-layer snapshot that would also undo
/// edits this command never made.
class LayerAttachment {
  const LayerAttachment({
    required this.attachedToLayerId,
    required this.placement,
    required this.mode,
    required this.timeline,
    required this.baseFrameLinks,
    required this.runBehaviors,
  });

  /// The base this row rides; null = an ordinary row.
  final LayerId? attachedToLayerId;
  final AttachedPlacement placement;
  final AttachedMode mode;

  /// The row's OWN stored timeline: empty while SYNCED (the base's
  /// exposures are the row's), the baked timing once it detaches.
  final Map<int, TimelineExposure> timeline;
  final Map<FrameId, FrameId> baseFrameLinks;
  final List<TimelineRunBehavior> runBehaviors;

  static LayerAttachment of(Layer layer) => LayerAttachment(
    attachedToLayerId: layer.attachedToLayerId,
    placement: layer.attachedPlacement,
    mode: layer.attachedMode,
    timeline: layer.timeline,
    baseFrameLinks: layer.baseFrameLinks,
    runBehaviors: layer.runBehaviors,
  );

  Layer applyTo(Layer layer) => layer.copyWith(
    attachedToLayerId: attachedToLayerId,
    attachedPlacement: placement,
    attachedMode: mode,
    timeline: timeline,
    baseFrameLinks: baseFrameLinks,
    runBehaviors: runBehaviors,
  );
}

/// [attached] as an ORDINARY row again.
///
/// FREE: the pointer is the only thing that goes — the timeline was always
/// its own.
///
/// SYNCED: the derived timeline is BAKED into the row (the mirror cels are
/// real cels, so the pictures were never derived — only the timing was).
/// The base's run-edge behaviours come along, restated through the cell
/// links so they name the row's OWN cels: without that the repeat/hold tail
/// the user was looking at would vanish on the next edit, which is timing
/// loss nobody asked for. A behaviour whose anchor has no link drops, and a
/// pattern anchor without one falls back to the whole run — both are the
/// model's own self-healing rules, applied here rather than invented.
///
/// ⚠️Re-mounting SYNCED later cannot restore the timing this row had BEFORE
/// it was first mounted: that timing was replaced by the base's when the
/// mount happened. Undo is the only way back.
Layer detachedLayer({
  required Layer attached,
  required Layer? base,
  required int cutFrameCount,
}) {
  if (attached.attachedToLayerId == null) {
    return attached;
  }
  if (base == null || !isSyncedAttachedLayer(attached)) {
    // FREE, or a dangling link (the base was deleted out from under it —
    // display already showed nothing, so there is nothing to bake).
    return attached.copyWith(
      attachedToLayerId: null,
      baseFrameLinks: const {},
    );
  }
  final links = attached.baseFrameLinks;
  final baked = <int, TimelineExposure>{};
  attachedDisplayTimeline(attached: attached, base: base).forEach((
    index,
    exposure,
  ) {
    if (!exposure.ghost) {
      baked[index] = exposure;
    }
  });
  final behaviors = <TimelineRunBehavior>[
    for (final behavior in base.runBehaviors)
      if (links[behavior.anchorFrameId] != null)
        TimelineRunBehavior(
          anchorFrameId: links[behavior.anchorFrameId]!,
          side: behavior.side,
          mode: behavior.mode,
          patternAnchorFrameId: behavior.patternAnchorFrameId == null
              ? null
              : links[behavior.patternAnchorFrameId!],
        ),
  ];
  return rederiveRunBehaviors(
    attached.copyWith(
      attachedToLayerId: null,
      baseFrameLinks: const {},
      timeline: baked,
      runBehaviors: behaviors,
    ),
    cutFrameCount: cutFrameCount,
  );
}

/// [standaloneRow] as an attach row of [base], in [mode].
///
/// ⚠️[standaloneRow] must be the row's STANDALONE form — [detachedLayer]'s
/// answer — not a row that still rides some other base. A synced row's own
/// timeline is empty, so measuring it as-is would call every re-mount empty
/// and match it against an empty base.
///
/// SYNCED clears the stored timeline (the base's exposures are the row's
/// now) and stores the complete cell links; FREE keeps the row's timeline
/// and behaviours exactly as they were and stores no links.
LayerAttachment attachmentForMount({
  required Layer standaloneRow,
  required Layer base,
  required AttachedPlacement placement,
  required AttachedMode mode,
}) {
  final links = mode == AttachedMode.synced
      ? attachedLinksForMount(row: standaloneRow, base: base)
      : null;
  // A synced mount with no computable links contradicts the mode decision
  // (same predicate, same inputs), so this cannot fire — but standing down
  // to FREE keeps it impossible for a caller's mistake to publish empty
  // mirror cels.
  if (links != null) {
    return LayerAttachment(
      attachedToLayerId: base.id,
      placement: placement,
      mode: AttachedMode.synced,
      timeline: const {},
      baseFrameLinks: links,
      runBehaviors: const [],
    );
  }
  return LayerAttachment(
    attachedToLayerId: base.id,
    placement: placement,
    mode: AttachedMode.free,
    timeline: standaloneRow.timeline,
    baseFrameLinks: const {},
    runBehaviors: standaloneRow.runBehaviors,
  );
}

/// The attach relationships ONE drop makes and breaks.
///
/// It rides with the placement plan rather than being its own edit because
/// it was the same gesture: one drag, one undo step. Empty is the ordinary
/// case (a move that only re-orders).
class LayerAttachDrop {
  const LayerAttachDrop({
    this.mount,
    this.sideChange,
    this.detachIds = const {},
  });

  /// The row that becomes an attach row, and what it lands on. The MODE is
  /// not here: it is decided across the whole 겸용 link group, which only
  /// the command layer can see.
  final ({LayerId layerId, LayerId baseId, AttachedPlacement placement})?
  mount;

  /// A row that KEEPS its base but crossed its picture — above became below.
  /// Only the side changes: the timing contract, the links and the cels are
  /// untouched, which is what makes re-ordering inside a group an ordinary
  /// move that happens to have a direction.
  final ({LayerId layerId, AttachedPlacement placement})? sideChange;

  /// The attach rows this drop turns back into ordinary rows — the row the
  /// pointer held, and any attach row carried along inside a folder.
  final Set<LayerId> detachIds;

  bool get isEmpty =>
      mount == null && sideChange == null && detachIds.isEmpty;
}
