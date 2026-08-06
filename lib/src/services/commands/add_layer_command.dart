import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import '../project_tree_editor.dart';
import 'link_mirror.dart';

/// One 겸용 sibling's copy of a layer being created: the cut it lands in,
/// the id it takes there, and its ANCHORS resolved to that cut's own rows.
///
/// Ids are PLANNED by the caller (the repo's rule for every mirroring
/// command) so undo/redo replay the same addresses. The anchors matter
/// because a new row inherits the active row's folder and may ride an
/// attach base — ids from the ORIGIN cut, which would point at a stranger's
/// rows if copied verbatim.
class AddLayerMirror {
  const AddLayerMirror({
    required this.cutId,
    required this.layerId,
    this.folderId,
    this.attachedToLayerId,
  });

  final CutId cutId;
  final LayerId layerId;

  /// The sibling's own folder row, when the source sits in one.
  final LayerId? folderId;

  /// The sibling's own attach base, when the source rides one.
  final LayerId? attachedToLayerId;
}

/// Adds a layer, and the same layer to every 겸용 (linked) sibling cut in
/// [mirrors] — layer EXISTENCE is shared structure, so a row created in
/// one use site appears in all of them ("존재는 공유, 내용은 각자").
///
/// The copies share the source's cels by construction (same FrameIds, the
/// bank the registry group makes canonical) and start with the source's
/// timeline: a row created empty has no lane worth protecting yet, and
/// leaving the siblings blank would give them a row they cannot use.
/// Everything after creation follows the ordinary rules — lane edits stay
/// per-use, mirrored properties fan out through [linkMirrorTargets].
class AddLayerCommand implements Command {
  AddLayerCommand({
    required this.repository,
    required this.cutId,
    required this.layer,
    this.insertionIndex,
    this.mirrors = const [],
    this.linkGroupId,
  }) : assert(
         mirrors.isEmpty || linkGroupId != null,
         'Mirrored creation needs a planned link-group id.',
       );

  final ProjectRepository repository;
  final CutId cutId;
  final Layer layer;
  final int? insertionIndex;

  /// The sibling cuts this layer also appears in, with their planned ids.
  final List<AddLayerMirror> mirrors;

  /// The planned id of the link group the source and its mirrors join.
  final String? linkGroupId;

  Project? _previousProject;

  @override
  String get description => 'Add layer ${layer.name}';

  @override
  void execute() {
    _previousProject = repository.requireProject();
    if (mirrors.isEmpty) {
      repository.insertLayer(cutId: cutId, layer: layer, index: insertionIndex);
      return;
    }

    repository.updateProject((project) {
      final source = requireCut(project, cutId);
      final sourceIndex = insertionIndex ?? source.layers.length;

      var next = _withLayerInserted(
        project,
        cutId: cutId,
        layer: layer,
        index: sourceIndex,
      );
      for (final mirror in mirrors) {
        final sibling = requireCut(next, mirror.cutId);
        next = _withLayerInserted(
          next,
          cutId: mirror.cutId,
          layer: layer.copyWith(
            id: mirror.layerId,
            // Anchors point at the SIBLING's rows; `folderId` takes null
            // through its sentinel, so a source outside any folder puts
            // its copies outside too.
            folderId: mirror.folderId,
            attachedToLayerId: mirror.attachedToLayerId,
          ),
          index: mirroredInsertionIndex(
            project,
            source: source,
            sourceIndex: sourceIndex,
            sibling: sibling,
          ),
        );
      }

      return next.copyWith(
        linkRegistry: LayerLinkRegistry(
          groups: [
            ...next.linkRegistry.groups,
            LayerLinkGroup(
              id: linkGroupId!,
              members: [
                LayerLinkMember(
                  // Each member's OWN track: a link group may span tracks,
                  // and stamping the source's id on all of them would file
                  // the copy under a track it does not live in.
                  trackId: requireTrackOfCut(next, cutId).id,
                  cutId: cutId,
                  layerId: layer.id,
                ),
                for (final mirror in mirrors)
                  LayerLinkMember(
                    trackId: requireTrackOfCut(next, mirror.cutId).id,
                    cutId: mirror.cutId,
                    layerId: mirror.layerId,
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }

  static Project _withLayerInserted(
    Project project, {
    required CutId cutId,
    required Layer layer,
    required int index,
  }) {
    final next = updateCutAnywhere(project, cutId, (cut) {
      final layers = [...cut.layers];
      layers.insert(index.clamp(0, layers.length).toInt(), layer);
      return cut.copyWith(layers: layers);
    });
    if (next == null) {
      throw StateError('Cut not found: $cutId');
    }
    return next;
  }

  @override
  void undo() {
    final previousProject = _previousProject;
    if (previousProject == null) {
      throw StateError('Command has not been executed.');
    }

    repository.replaceProject(previousProject);
  }
}
