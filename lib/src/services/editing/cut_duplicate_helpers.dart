import '../../models/attached_layer_resolve.dart' show attachedMirrorCelId;
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart' show effectsWithRowsRenamed;
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project_timeline.dart';
import '../../models/stroke.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_id.dart';
import '../../models/track_id.dart';

Cut duplicateCutAsIndependentCopy({
  required Cut source,
  required CutId newCutId,
  required String newName,
  required Map<LayerId, LayerId> layerIdMap,
  required Map<FrameId, FrameId> frameIdMap,
}) {
  return Cut(
    id: newCutId,
    name: newName,
    layers: source.layers
        .map(
          (layer) => duplicateLayerAsIndependentCopy(
            source: layer,
            newLayerId: _requireMapped(
              layerIdMap,
              layer.id,
              argument: 'layerIdMap',
              what: 'LayerId for source layer',
            ),
            newName: layer.name,
            frameIdMap: frameIdMap,
            // The whole cut duplicates together: attach linkage remaps
            // onto the copied base (both the layer pointer and the
            // per-cel links).
            layerIdMap: layerIdMap,
          ),
        )
        .toList(),
    duration: source.duration,
    canvasSize: source.canvasSize,
    metadata: source.metadata,
    // Share the immutable track directly: a pose-view round-trip would
    // resynchronize (and thus lose) independently keyed properties.
    camera: CutCamera.fromTrack(source.camera.track),
  );
}

/// The ids a timeline's copy takes (`planDuplicateTimelineCommandInput`),
/// each by the one it copies.
class TimelineCopyIds {
  TimelineCopyIds({
    required this.timelineId,
    required Map<TrackId, TrackId> tracks,
    required Map<CutId, CutId> cuts,
    required Map<LayerId, LayerId> rows,
    required Map<FrameId, FrameId> cels,
    required Map<String, String> links,
  }) : tracks = Map.unmodifiable(tracks),
       cuts = Map.unmodifiable(cuts),
       rows = Map.unmodifiable(rows),
       cels = Map.unmodifiable(cels),
       links = Map.unmodifiable(links);

  final TimelineId timelineId;
  final Map<TrackId, TrackId> tracks;
  final Map<CutId, CutId> cuts;

  /// Every row: a cut's, and a track's SE and transition rows.
  final Map<LayerId, LayerId> rows;

  /// Every cel — ONE map across the whole timeline: rows linked to each
  /// other share their cels (a link IS the shared ids), so their copies
  /// share the copies.
  final Map<FrameId, FrameId> cels;

  /// The link groups two or more of whose members the timeline holds, by
  /// the id of the group their copies make.
  final Map<String, String> links;
}

/// A TIMELINE'S COPY (I-150 「복제」): every track, cut and row of [source]
/// under the ids [ids] took — a cut as a duplicated cut is
/// ([duplicateCutAsIndependentCopy]) but under its own name, a track's SE
/// and transition rows as a row is — numbered [number], named [name].
ProjectTimeline duplicateTimelineAsIndependentCopy({
  required ProjectTimeline source,
  required TimelineCopyIds ids,
  required int number,
  required String? name,
}) {
  Layer copied(Layer row) => duplicateLayerAsIndependentCopy(
    source: row,
    newLayerId: _requireMapped(
      ids.rows,
      row.id,
      argument: 'rows',
      what: 'LayerId for track row',
    ),
    newName: row.name,
    frameIdMap: ids.cels,
    layerIdMap: ids.rows,
  );

  return ProjectTimeline(
    id: ids.timelineId,
    number: number,
    name: name,
    trailingFrames: source.trailingFrames,
    tracks: [
      for (final track in source.tracks)
        track.copyWith(
          id: _requireMapped(
            ids.tracks,
            track.id,
            argument: 'tracks',
            what: 'TrackId for track',
          ),
          cuts: [
            for (final cut in track.cuts)
              duplicateCutAsIndependentCopy(
                source: cut,
                newCutId: _requireMapped(
                  ids.cuts,
                  cut.id,
                  argument: 'cuts',
                  what: 'CutId for cut',
                ),
                newName: cut.name,
                layerIdMap: ids.rows,
                frameIdMap: ids.cels,
              ),
          ],
          seLayers: [for (final row in track.seLayers) copied(row)],
          transitionLayer: copied(track.transitionLayer),
          effects: effectsWithRowsRenamed(
            track.effects,
            (row) => ids.rows[row] ?? row,
          ),
        ),
    ],
  );
}

/// The link groups of [registry] that a timeline's copy took two or more
/// members of ([TimelineCopyIds.links]), made again of the copies — in the
/// order the source's were, so the first copied is the canonical.
List<LayerLinkGroup> linkGroupsOfACopy(
  LayerLinkRegistry registry,
  TimelineCopyIds ids,
) => [
  for (final group in registry.groups)
    if (ids.links[group.id] case final id?)
      LayerLinkGroup(
        id: id,
        members: [
          for (final member in group.members)
            if (ids.cuts[member.cutId] case final cutId?)
              LayerLinkMember(
                trackId: ids.tracks[member.trackId]!,
                cutId: cutId,
                layerId: ids.rows[member.layerId]!,
              ),
        ],
      ),
];

Layer duplicateLayerAsIndependentCopy({
  required Layer source,
  required LayerId newLayerId,
  required String newName,
  required Map<FrameId, FrameId> frameIdMap,
  LayerKind? kind,
  Map<LayerId, LayerId> layerIdMap = const {},
}) {
  final attachedTo = source.attachedToLayerId;
  final folderId = source.folderId;
  // Field-by-field reconstruction is this helper's trap, the same one
  // [duplicateFrameContent] documents: every field NOT listed here is
  // silently reset to its default. The R6 audit found nine already lost —
  // blendMode, folderId (so a duplicated cut FLATTENED every folder),
  // seNameTag, clipsToBelow, runBehaviors, collapsed, the mixer's gain
  // and pan (the row's sound since I-140) and attachedMode. Anything
  // added to [Layer] belongs here.
  return Layer(
    id: newLayerId,
    name: newName,
    frames: source.frames
        .map(
          (frame) => duplicateFrameContent(
            frame: frame,
            newFrameId: _requireMapped(
              frameIdMap,
              frame.id,
              argument: 'frameIdMap',
              what: 'FrameId for source frame',
            ),
          ),
        )
        .toList(),
    timeline: source.timeline.map(
      (index, exposure) => MapEntry(
        index,
        remapTimelineExposure(exposure: exposure, frameIdMap: frameIdMap),
      ),
    ),
    isVisible: source.isVisible,
    collapsed: source.collapsed,
    lanesExpanded: source.lanesExpanded,
    expandedLaneGroups: source.expandedLaneGroups,
    muted: source.muted,
    seSound: source.seSound,
    opacity: source.opacity,
    blendMode: source.blendMode,
    kind: kind ?? source.kind,
    onTimesheet: source.onTimesheet,
    mark: source.mark,
    clipsToBelow: source.clipsToBelow,
    // The duplicated layer shows the same library asset (§6-z23).
    mediaReference: source.mediaReference,
    seNameTag: source.seNameTag,
    transformTrack: source.transformTrack,
    // The transform's switch (R8) and what it reads its keys by (I-120-Q10)
    // go with its keys — the switch had been left out, so a copy showed a
    // bypassed transform switched on.
    transformEnabled: source.transformEnabled,
    transformBasis: source.transformBasis,
    // The effect chain is layer state like the transform track (R6): a
    // duplicated cut keeps its 촬영 work. The rows it names remap as the
    // attach pointer does, below.
    effects: effectsWithRowsRenamed(
      source.effects,
      (row) => layerIdMap[row] ?? row,
    ),
    instructions: source.instructions,
    audioClips: [
      for (final clip in source.audioClips)
        clip.copyWith(frameId: frameIdMap[clip.frameId] ?? clip.frameId),
    ],
    // Attach linkage: the base pointer remaps when its copy is known (a
    // whole-cut duplicate); a lone-layer copy keeps pointing at the
    // original base in the same cut. Cel links remap on BOTH sides where
    // mapped.
    attachedToLayerId: attachedTo == null
        ? null
        : (layerIdMap[attachedTo] ?? attachedTo),
    attachedPlacement: source.attachedPlacement,
    attachedMode: source.attachedMode,
    // Folder membership remaps exactly like the attach pointer: the copied
    // folder row when the whole cut duplicates, the ORIGINAL folder when a
    // lone layer is copied inside the same cut.
    folderId: folderId == null ? null : (layerIdMap[folderId] ?? folderId),
    baseFrameLinks: {
      for (final entry in source.baseFrameLinks.entries)
        (frameIdMap[entry.key] ?? entry.key):
            frameIdMap[entry.value] ?? entry.value,
    },
  );
}

/// One frame's CONTENT under a new id — strokes deep-copied, so the copy
/// owes the source nothing afterwards.
///
/// Public because ㉕'s independent paste wants exactly this and nothing
/// else: a cel that came from another cel and is not linked to it. The cut
/// duplication below is the same question asked about a whole cut, so it
/// asks it here rather than growing a second answer.
///
/// ↩️Field-by-field reconstruction was this helper's trap: it silently
/// dropped `seName` until the text round walked past, and I-20's delivery
/// type would have been the next. A copy that names only what CHANGES —
/// the id and the strokes — carries every other field by construction.
Frame duplicateFrameContent({
  required Frame frame,
  required FrameId newFrameId,
}) => frame.copyWith(
  id: newFrameId,
  strokes: frame.strokes.map(_duplicateStroke).toList(),
);

/// What one synced attach row gains when its base's cels are re-cut as cels
/// of their own: the mirror cels [born], the [baseLinks] that name them, and
/// which mirror each came from ([minted]) — for the pictures, which the
/// session copies (`copyBakedPictures`).
typedef MirrorCopies = ({
  LayerId layerId,
  List<Frame> born,
  Map<FrameId, FrameId> baseLinks,
  Map<FrameId, FrameId> minted,
});

/// 🚨F-275 (유저 2026-10-04): 「기준레이어 링크된상태에서 독립시킬때, 어태치
/// 싱크레이어의 그림은 사라지고 기준레이어 그림만 남아있는데, 어태치 싱크
/// 레이어 그림도 남아있도록」 — the SYNCED attach rows riding a base whose
/// cels [baseMinted] (source → copy) were re-cut take their MIRRORS of those
/// cels along. And so do the rows synced on a conte whose panel a RASTERIZE
/// parts (🗣️I-120-Q17 「칸을 나눈다」: 싱크 행의 셀도 같은 그림으로 같이
/// 나뉜다).
///
/// A mirror cel is the attach row's picture OF a base cel, found by the base
/// cel's id ([Layer.baseFrameLinks]). A base cel given a new id had no mirror
/// under it, so the settle minted an EMPTY one
/// (`cutWithReconciledAttachedMirrors`): the base kept its picture and the
/// attach row lost the one drawn there. Each copy's mirror is born here
/// instead — a copy of its source's mirror, under the very id the settle
/// gives it ([attachedMirrorCelId] with [mintedUnder]'s answer), so the
/// settle finds the link already made.
///
/// ⚠️A base cel a row never mirrored has nothing to keep there: the settle
/// mints its empty mirror as before. A FREE attach row authors its own cels
/// and is not one of [attachedRows].
List<MirrorCopies> mirrorCopiesFor({
  required Iterable<Layer> attachedRows,
  required Map<FrameId, FrameId> baseMinted,
  required LayerId Function(Layer attached) mintedUnder,
}) {
  final copies = <MirrorCopies>[];
  for (final attached in attachedRows) {
    final born = <Frame>[];
    final baseLinks = <FrameId, FrameId>{};
    final minted = <FrameId, FrameId>{};
    for (final MapEntry(key: source, value: copy) in baseMinted.entries) {
      final linked = attached.baseFrameLinks[source];
      final mirror = linked == null ? null : attached.frameById(linked);
      if (mirror == null) {
        continue;
      }
      final id = attachedMirrorCelId(mintedUnder(attached), copy);
      born.add(duplicateFrameContent(frame: mirror, newFrameId: id));
      baseLinks[copy] = id;
      minted[mirror.id] = id;
    }
    if (born.isNotEmpty) {
      copies.add((
        layerId: attached.id,
        born: born,
        baseLinks: baseLinks,
        minted: minted,
      ));
    }
  }
  return copies;
}

/// One timeline cell pointed at the copied cel: the exposure's frame id
/// resolved through [frameIdMap], which must cover it.
///
/// Public because the paste planner rebuilds a layer's whole timeline with
/// exactly this rule and used to spell it out inline.
TimelineExposure remapTimelineExposure({
  required TimelineExposure exposure,
  required Map<FrameId, FrameId> frameIdMap,
}) {
  final sourceFrameId = exposure.frameId;
  if (sourceFrameId == null) {
    throw ArgumentError.value(
      frameIdMap,
      'frameIdMap',
      'Missing mapped FrameId for timeline exposure ${exposure.frameId}.',
    );
  }
  return exposure.copyWith(
    frameId: _requireMapped(
      frameIdMap,
      sourceFrameId,
      argument: 'frameIdMap',
      what: 'FrameId for timeline exposure',
    ),
  );
}

/// The id [key] was minted as, or an [ArgumentError] naming the map that
/// should have carried it. Three walks of this file look a minted id up
/// and refuse the same way when it is missing.
V _requireMapped<K, V>(
  Map<K, V> map,
  K key, {
  required String argument,
  required String what,
}) {
  final mapped = map[key];
  if (mapped == null) {
    throw ArgumentError.value(map, argument, 'Missing mapped $what $key.');
  }
  return mapped;
}

Stroke _duplicateStroke(Stroke stroke) {
  return stroke.copyWith(
    points: stroke.points.map((point) => point.copyWith()).toList(),
    brushSettings: stroke.brushSettings.copyWith(),
  );
}
