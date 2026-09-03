import '../editing/editing_session_state.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_join.dart';
import '../../models/layer_link_registry.dart';
import '../../models/layer_section_defaults.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// 겸용컷 생성 (L2): a NEW cut whose drawing layers are linked copies of
/// the source's — same FrameIds and names (the pictures are one), with
/// **EMPTY timelines**: the bank re-exposes to a new rhythm. "겸용 설정은
/// 그림만 잇는다, 타임라인 불간섭" — full-timing reuse is the plain
/// duplicate → 겸용 변경 composition instead.
///
/// Per the confirmed design:
/// - Only drawing (animation) layers and the FOLDER rows holding them
///   link; SE/instruction/camera rows are fresh per-use fixtures
///   ("카메라·SE·타임시트는 각자").
/// - Attach structure and folder membership mirror onto planned ids.
/// - The registry gains one pair per linked row (extending existing
///   groups, so a second 겸용 joins the same bank) — folder rows included,
///   which is what makes a folder's eye/opacity/blend/name mirror through
///   the ordinary layer path with no folder mirror table.
class CreateLinkedCutCommand implements Command {
  CreateLinkedCutCommand({
    required this.repository,
    required this.editingSession,
    required this.sourceCutId,
    required this.newCutId,
    required this.newName,
    required this.layerIdMap,
    required this.newGroupIdBySource,
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

  CutId? _previousActiveCutId;
  LayerLinkRegistry? _registryBefore;
  bool _hasExecuted = false;

  @override
  String get description => 'Create linked cut $newName';

  @override
  void execute() {
    _previousActiveCutId = editingSession.activeCutId;
    repository.updateProject((project) {
      final track = requireTrackOfCut(project, sourceCutId);
      final source = requireCut(project, sourceCutId);

      final linkedLayers = <Layer>[
        for (final layer in source.layers)
          if (layerIdMap.containsKey(layer.id))
            layer.copyWith(
              id: _requireCopyId(layer.id),
              // EMPTY timeline: the 겸용 re-exposes the shared bank.
              timeline: const {},
              attachedToLayerId: layer.attachedToLayerId == null
                  ? null
                  : _requireCopyId(layer.attachedToLayerId!),
              folderId: layer.folderId == null
                  ? null
                  : layerIdMap[layer.folderId!],
              // Sounds are per-use; drawing layers should carry none,
              // but strip defensively.
              audioClips: const [],
            ),
      ];
      final newCut = Cut(
        id: newCutId,
        name: newName,
        // Fresh SE/instruction/camera fixture rows around the linked
        // drawing layers and their folders.
        layers: withEnsuredSectionLayers(newCutId, linkedLayers),
        duration: source.duration,
        canvasSize: source.canvasSize,
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

      final sourceIndex = track.cuts.indexWhere(
        (cut) => cut.id == sourceCutId,
      );
      return project
          .copyWith(
            tracks: [
              for (final projectTrack in project.tracks)
                projectTrack.id == track.id
                    ? projectTrack.copyWith(
                        cuts: [...projectTrack.cuts]
                          ..insert(sourceIndex + 1, newCut),
                      )
                    : projectTrack,
            ],
          )
          .copyWith(linkRegistry: LayerLinkRegistry(groups: groups));
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
      return project
          .copyWith(
            tracks: [
              for (final track in project.tracks)
                track.copyWith(
                  cuts: [
                    for (final cut in track.cuts)
                      if (cut.id != newCutId) cut,
                  ],
                ),
            ],
          )
          .copyWith(linkRegistry: registryBefore);
    });
    editingSession.setActiveCutId(previousActiveCutId);
  }

  LayerId _requireCopyId(LayerId sourceId) {
    final copyId = layerIdMap[sourceId];
    if (copyId == null) {
      throw StateError('No planned copy id for $sourceId');
    }
    return copyId;
  }
}
