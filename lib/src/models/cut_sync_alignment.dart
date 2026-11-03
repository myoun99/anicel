import 'dart:math' as math;

import '../core/mapped_or_same.dart';
import 'brush_frame_key.dart';
import 'conte/conte_ink_keys.dart';
import 'cut.dart';
import 'cut_id.dart';
import 'cut_sync.dart';
import 'envelope/cut_envelope_ink_keys.dart' show envelopeInkKeyOfCut;
import 'layer.dart';
import 'layer_effect.dart' show effectsWithRowsRenamed;
import 'layer_id.dart';
import 'layer_kind.dart';
import 'layer_link_registry.dart';
import 'project.dart';
import 'timesheet_ink_keys.dart';

/// [source]'s content laid onto [onto]'s ids — 🚨THE ONE LAW of what a
/// 동기컷 ([CutSync]) shares: a sync is made with it
/// (`CreateSyncedCutCommand`) and kept with it
/// ([projectWithItsSyncsAligned]).
///
/// Each row of [source] that [rowOf] names comes across WHOLE under that
/// id — its lanes, its eye, its bank — with what it points at (its folder,
/// the row it attaches to, the rows its effects read) pointed at the rows
/// those came across as. The cut's length, canvas, papers, camera and
/// guides come with them. [onto] keeps its own id, its NAME and its GAP:
/// the place it stands is its timeline's (I-150-Q5: a linked paste is named
/// by where it lands).
///
/// What stays [onto]'s own: a row of a kind that links which no row of
/// [source] comes across as — the empty rows its own track's conte gave it
/// (`conteFillId`) — where it stands; and the key a row it already held
/// rides its own track's conte by ([Layer.conteKey]), which is that track's
/// structure, not the cut's.
Cut syncedCopy(
  Cut source, {
  required Cut onto,
  required Map<LayerId, LayerId> rowOf,
}) {
  final held = {for (final layer in onto.layers) layer.id: layer};
  LayerId? across(LayerId? id) => id == null ? null : rowOf[id];
  final rows = <Layer>[
    for (final row in source.layers)
      if (rowOf[row.id] case final id?)
        row.copyWith(
          id: id,
          folderId: across(row.folderId),
          attachedToLayerId: across(row.attachedToLayerId),
          effects: effectsWithRowsRenamed(row.effects, across),
          conteKey: switch (held[id]) {
            null => row.conteKey,
            final own => own.conteKey,
          },
        ),
  ];
  final cameAcross = rowOf.values.toSet();
  for (final (index, layer) in onto.layers.indexed) {
    if (layer.kind.linksIntoLinkedCut && !cameAcross.contains(layer.id)) {
      rows.insert(math.min(index, rows.length), layer);
    }
  }
  return onto.copyWith(
    layers: rows,
    duration: source.duration,
    canvasSize: source.canvasSize,
    metadata: source.metadata,
    camera: source.camera,
    guides: source.guides,
  );
}

/// Which row of [onto] each row of [source] is, for [syncedCopy]: a linked
/// row's counterpart ([LayerLinkRegistry.counterpartIn]) — and, of a kind
/// that never links (the direction rows), the n-th of that kind is the
/// n-th, a row [onto] lacks taken under [syncedRowId]. A row that links and
/// has no counterpart in [onto] is no row of it: it is left out.
Map<LayerId, LayerId> syncedRowsOf(
  Cut source, {
  required Cut onto,
  required LayerLinkRegistry registry,
}) {
  final held = {for (final layer in onto.layers) layer.id};
  final rowOf = <LayerId, LayerId>{};
  for (final row in source.layers) {
    final counterpart = registry.counterpartIn(
      cutId: source.id,
      layerId: row.id,
      targetCutId: onto.id,
    );
    if (counterpart != null && held.contains(counterpart)) {
      rowOf[row.id] = counterpart;
    }
  }
  final claimed = rowOf.values.toSet();
  final spare = <LayerKind, List<LayerId>>{};
  for (final layer in onto.layers) {
    if (!layer.kind.linksIntoLinkedCut && !claimed.contains(layer.id)) {
      spare.putIfAbsent(layer.kind, () => []).add(layer.id);
    }
  }
  final seen = <LayerKind, int>{};
  for (final row in source.layers) {
    if (row.kind.linksIntoLinkedCut || rowOf.containsKey(row.id)) {
      continue;
    }
    final nth = seen[row.kind] ?? 0;
    seen[row.kind] = nth + 1;
    final pool = spare[row.kind] ?? const <LayerId>[];
    rowOf[row.id] = nth < pool.length ? pool[nth] : syncedRowId(row, onto.id);
  }
  return rowOf;
}

/// The id a row of a kind that never links takes in the synced cut [cutId]
/// when that cut lacks it — the same every time, so a step and its redo
/// make the same row.
LayerId syncedRowId(Layer row, CutId cutId) =>
    LayerId('synced:${row.id.value}@${cutId.value}');

/// [after] — what a write made of [before], or a whole step's writes
/// (`ProjectRepository.asOneConteWrite`) — with every 동기컷 one again:
/// the cut of a sync the write changed lays its content onto the others
/// ([syncedCopy]). Of two it changed, the one in the timeline open; of a
/// sync it only ADDED a cut to, the cuts already there — one that just
/// arrived adopts, never gives.
///
/// Changed means changed: a cut the write rebuilt equal is not one (a walk
/// over every row list rebuilds every cut).
///
/// ⛔Not the write-time invariants' pass: what a timeline's own track does
/// to a cut — the のりしろ its transitions ask, the conte its track lays —
/// is laid by that pass when the timeline is the open one, so this runs
/// BEFORE it and carries what the step wrote, never what the laying made.
Project projectWithItsSyncsAligned(Project before, Project after) {
  final registry = after.linkRegistry;
  if (registry.syncs.isEmpty || identical(before.timelines, after.timelines)) {
    return after;
  }
  final named = {for (final sync in registry.syncs) ...sync.cuts};
  final was = _cutsNamed(before, named);
  final now = _cutsNamed(after, named);
  final open = {
    for (final track in after.tracks)
      for (final cut in track.cuts)
        if (named.contains(cut.id)) cut.id,
  };
  final laid = <CutId, Cut>{};
  for (final sync in registry.syncs) {
    final present = [for (final id in sync.cuts) ?now[id]];
    final source = _sourceOf(present, was: was, open: open);
    if (source == null) {
      continue;
    }
    for (final cut in present) {
      if (identical(cut, source)) {
        continue;
      }
      final next = syncedCopy(
        source,
        onto: cut,
        rowOf: syncedRowsOf(source, onto: cut, registry: registry),
      );
      if (next != cut) {
        laid[cut.id] = next;
      }
    }
  }
  if (laid.isEmpty) {
    return after;
  }
  return after.withTracksOfEveryTimeline(
    (tracks) => mappedOrSame(tracks, (track) {
      final cuts = mappedOrSame(track.cuts, (cut) => laid[cut.id] ?? cut);
      return identical(cuts, track.cuts) ? track : track.copyWith(cuts: cuts);
    }),
  );
}

/// The cut of [present] whose content the others take — null when the
/// write changed none of them, or there is no sync of two yet.
Cut? _sourceOf(
  List<Cut> present, {
  required Map<CutId, Cut> was,
  required Set<CutId> open,
}) {
  if (present.length < 2) {
    return null;
  }
  bool edited(Cut cut) => switch (was[cut.id]) {
    null => false,
    final old => !identical(old, cut) && old != cut,
  };
  final changed = present.where(edited).toList();
  if (changed.isNotEmpty) {
    return changed.where((cut) => open.contains(cut.id)).firstOrNull ??
        changed.first;
  }
  final arrived = present.any((cut) => was[cut.id] == null);
  return arrived
      ? present.where((cut) => was[cut.id] != null).firstOrNull
      : null;
}

/// The cuts of [project] [ids] names, in whichever timeline they stand.
Map<CutId, Cut> _cutsNamed(Project project, Set<CutId> ids) => {
  for (final track in project.tracksOfEveryTimeline)
    for (final cut in track.cuts)
      if (ids.contains(cut.id)) cut.id: cut,
};

/// [key] as its store keeps it: a synced cut's sheets are ONE paper — the
/// conte's block handwriting, the timesheet's pages and the envelope's boxes
/// are kept under the sync's canonical cut
/// ([LayerLinkRegistry.syncCanonicalOf]), the same block, the same page, the
/// same box. [key] itself for any other.
///
/// 🗣️I-150-Q3 「실질 같은컷」: what is written on one cut's sheet is on the
/// other's. 🗣️I-150-Q4 (유저 2026-11-03): 「동기컷으로서 답하자면 실질
/// 같은컷이기에 타임라인을 넘어 한 묶음」 — the envelope too. ↩️It was left to
/// its owner (`cutEnvelopeInkOwner`), which is found in the open timeline
/// only: a 동기컷's envelope was one per timeline.
BrushFrameKey syncedSheetInkKey(LayerLinkRegistry registry, BrushFrameKey key) {
  final canonical = registry.syncCanonicalOf(key.cutId);
  if (canonical == key.cutId) {
    return key;
  }
  return sheetInkKeyOfCut(key, canonical) ?? key;
}

/// [key]'s sheet ink — the same block of the conte, the same page of the
/// timesheet, the same box of the envelope — on the cut [cutId] instead;
/// null for a key that is none of them.
BrushFrameKey? sheetInkKeyOfCut(BrushFrameKey key, CutId cutId) {
  if (conteInkRowIdOf(key) case final inkId?) {
    return conteInkRowKey(cutId, inkId);
  }
  return timesheetInkKeyOfCut(key, cutId) ?? envelopeInkKeyOfCut(key, cutId);
}
