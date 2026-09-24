import '../editing/cut_insertion_room.dart';
import '../editing/default_cut_helpers.dart';
import '../editing/default_layer_helpers.dart';
import '../editing/editing_session_state.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_join.dart';
import '../../models/layer_link_registry.dart';
import '../../models/layer_section_defaults.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_tree_editor.dart';
import '../project_repository.dart';

/// 겸용컷 생성 (L2): a NEW cut whose drawing layers are linked copies of
/// the source's — same FrameIds and names (the pictures are one), with
/// **EMPTY timelines**: the bank re-exposes to a new rhythm. "겸용 설정은
/// 그림만 잇는다, 타임라인 불간섭" — full-timing reuse is the plain
/// duplicate → 겸용 변경 composition instead.
///
/// Per the confirmed design:
/// - Every row whose kind links (`LayerKind.linksIntoLinkedCut`) is
///   copied linked: the drawing rows and the FOLDER rows holding them, and
///   — F-84, 유저 2026-09-11 — the conte row and the CAMERA row, which is
///   how the linked cut has a camera at all. SE/instruction rows are fresh
///   per-use fixtures. The camera's LANES arrive copied, not shared
///   ("카메라·SE·타임시트는 각자" still holds for what they say): only a
///   NAMED key carries a value across afterwards — the transform law.
/// - Attach structure and folder membership mirror onto planned ids.
/// - The registry gains one pair per linked row (extending existing
///   groups, so a second 겸용 joins the same bank) — folder rows included,
///   which is what makes a folder's eye/opacity/blend/name mirror through
///   the ordinary layer path with no folder mirror table.
///
/// ↩️F-97 · F-99 (유저 2026-09-12) — the new cut is a NEW CUT first:
/// - It is as long as a new cut, not as its source: 「겸용컷 만든다고 해서
///   현재 컷이랑 컷길이 똑같이 하지않음. 새 컷만드는거랑 똑같은 컷길이로.
///   하드코딩하지말고」.
/// - It takes its room the way every cut landing in front of others does
///   ([followerGapsAfterInsert]) — it used to push every cut behind it.
/// - A row that cannot stand empty — the conte row — is born covering the
///   cut with a fresh panel, the way a new conte row is: 「콘티레이어
///   생성시 기본적으로 프레임 생성되는데 그 법 그대로 재사용/통일」. The panel
///   joins the shared bank on every member of the row's group.
class CreateLinkedCutCommand implements Command {
  CreateLinkedCutCommand({
    required this.repository,
    required this.editingSession,
    required this.sourceCutId,
    required this.newCutId,
    required this.newName,
    required this.layerIdMap,
    required this.newGroupIdBySource,
    required this.coveringFrameIdBySource,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final CutId sourceCutId;
  final CutId newCutId;
  final String newName;

  /// Source row id → linked copy's id (drawing layers AND folder rows).
  final Map<LayerId, LayerId> layerIdMap;

  /// Planned registry group ids for sources not linked yet.
  final Map<LayerId, String> newGroupIdBySource;

  /// The planned fresh panel of each source row whose copy is born covering
  /// the new cut (F-99).
  final Map<LayerId, FrameId> coveringFrameIdBySource;

  CutId? _previousActiveCutId;
  LayerLinkRegistry? _registryBefore;

  /// The followers' leading gaps and the members' banks as they were before
  /// this cut took room and added panels — what undo hands back.
  Map<CutId, int> _gapsBefore = const {};
  Map<LayerId, List<Frame>> _banksBefore = const {};
  bool _hasExecuted = false;

  @override
  String get description => 'Create linked cut $newName';

  @override
  void execute() {
    _previousActiveCutId = editingSession.activeCutId;
    repository.updateProject((project) {
      final position = requireCutPosition(project, sourceCutId);
      final track = position.track;
      final source = position.cut;
      // F-97: a new cut's length, read where a new cut reads it.
      const duration = defaultCutDuration;

      final linkedLayers = <Layer>[
        for (final layer in source.layers)
          if (layerIdMap.containsKey(layer.id))
            _linkedCopyOf(layer, cutDuration: duration),
      ];
      final newCut = Cut(
        id: newCutId,
        name: newName,
        // A fresh direction row — the per-use fixture — around the linked
        // rows.
        layers: withEnsuredSectionLayers(newCutId, linkedLayers),
        duration: duration,
        canvasSize: source.canvasSize,
        // The camera row came across linked; its lanes come across COPIED.
        // The immutable track is shared as the plain duplicate shares it: a
        // pose-view round-trip would resynchronize independently keyed
        // properties.
        camera: CutCamera.fromTrack(source.camera.track),
      );

      _registryBefore = project.linkRegistry;
      var groups = [...project.linkRegistry.groups];
      for (final layer in source.layers) {
        if (!layerIdMap.containsKey(layer.id)) {
          continue;
        }
        groups = linkGroupsJoined(
          groups,
          origin: LayerLinkMember(
            trackId: track.id,
            cutId: sourceCutId,
            layerId: layer.id,
          ),
          joiner: LayerLinkMember(
            trackId: track.id,
            cutId: newCutId,
            layerId: _requireCopyId(layer.id),
          ),
          plannedGroupId: newGroupIdBySource[layer.id],
        );
      }
      final registry = LayerLinkRegistry(groups: groups);

      final sourceIndex = track.cuts.indexWhere(
        (cut) => cut.id == sourceCutId,
      );
      final gaps = followerGapsAfterInsert(
        track.cuts,
        index: sourceIndex + 1,
        leadingGap: newCut.leadingGapFrames,
        duration: newCut.duration,
      );
      _gapsBefore = {
        for (final cut in track.cuts)
          if (gaps.containsKey(cut.id)) cut.id: cut.leadingGapFrames,
      };
      var next = project
          .copyWith(
            tracks: [
              for (final projectTrack in project.tracks)
                if (projectTrack.id == track.id)
                  projectTrack.copyWith(
                    cuts: [
                      for (final cut in projectTrack.cuts)
                        if (gaps.containsKey(cut.id))
                          cut.copyWith(leadingGapFrames: gaps[cut.id])
                        else
                          cut,
                    ]..insert(sourceIndex + 1, newCut),
                  )
                else
                  projectTrack,
            ],
          )
          .copyWith(linkRegistry: registry);

      // F-99: a fresh panel joins the SHARED bank — every member of a linked
      // row holds the same frame list, the invariant
      // `UpdateLayerTimelineCommand` mirrors bank edits by.
      final banksBefore = <LayerId, List<Frame>>{};
      for (final row in source.layers) {
        if (!coveringFrameIdBySource.containsKey(row.id)) {
          continue;
        }
        final copyId = _requireCopyId(row.id);
        final bank = linkedLayers.firstWhere((copy) => copy.id == copyId).frames;
        final members =
            registry.groupOf(cutId: newCutId, layerId: copyId)?.members ??
            const <LayerLinkMember>[];
        for (final member in members) {
          if (member.layerId == copyId) {
            continue;
          }
          next =
              updateLayerAnywhere(next, member.layerId, (layer) {
                banksBefore[layer.id] = layer.frames;
                return layer.copyWith(frames: bank);
              }) ??
              next;
        }
      }
      _banksBefore = banksBefore;
      return next;
    });
    editingSession.setActiveCutId(newCutId);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previousActiveCutId = _previousActiveCutId;
    final registryBefore = _registryBefore;
    if (!_hasExecuted || previousActiveCutId == null || registryBefore == null) {
      throw StateError('Command has not been executed.');
    }
    repository.updateProject((project) {
      var next = removeCutAnywhere(
        project,
        newCutId,
      ).project.copyWith(linkRegistry: registryBefore);
      for (final MapEntry(key: cutId, value: gap) in _gapsBefore.entries) {
        next =
            updateCutAnywhere(
              next,
              cutId,
              (cut) => cut.copyWith(leadingGapFrames: gap),
            ) ??
            next;
      }
      for (final MapEntry(key: layerId, value: frames)
          in _banksBefore.entries) {
        next =
            updateLayerAnywhere(
              next,
              layerId,
              (layer) => layer.copyWith(frames: frames),
            ) ??
            next;
      }
      return next;
    });
    editingSession.setActiveCutId(previousActiveCutId);
  }

  /// [layer]'s linked copy in the new cut: the same bank and an EMPTY
  /// timeline the 겸용 cut exposes anew — or, for a row that cannot stand
  /// empty, its fresh panel over the whole cut (F-99).
  Layer _linkedCopyOf(Layer layer, {required int cutDuration}) {
    final copy = layer.copyWith(
      id: _requireCopyId(layer.id),
      // EMPTY timeline: the 겸용 re-exposes the shared bank.
      timeline: const {},
      attachedToLayerId: layer.attachedToLayerId == null
          ? null
          : _requireCopyId(layer.attachedToLayerId!),
      folderId: layer.folderId == null ? null : layerIdMap[layer.folderId!],
      // Sounds are per-use; drawing layers should carry none,
      // but strip defensively.
      audioClips: const [],
    );
    final panel = coveringFrameIdBySource[layer.id];
    if (panel == null) {
      return copy;
    }
    final cel = coveringCelFor(frameId: panel, cutDuration: cutDuration);
    return copy.copyWith(
      frames: [...layer.frames, cel.frame],
      timeline: cel.timeline,
    );
  }

  LayerId _requireCopyId(LayerId sourceId) {
    final copyId = layerIdMap[sourceId];
    if (copyId == null) {
      throw StateError('No planned copy id for $sourceId');
    }
    return copyId;
  }
}
