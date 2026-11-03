import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../brush_frame_store.dart';
import 'link_registry_snapshot_command.dart';
import '../project_lookup.dart';

/// 독립시키기 (L2, layer scale): removes a layer's WHOLE attach group
/// from its link groups and FORKS the pixels — each member gets its own
/// physical copy of the shared cels, so edits stop propagating both
/// ways. The escape hatch of the "완전 링크" model: local exceptions are
/// made by unlinking, never by weakening the link.
///
/// Symmetric with 링크 복제: the unit is the attach group (one member
/// leaving alone would break the mirrored structure).
class UnlinkLayerCommand extends LinkRegistrySnapshotCommand {
  UnlinkLayerCommand({
    required super.repository,
    required this.brushFrameStore,
    required this.cutId,
    required this.sourceLayerId,
  });

  final BrushFrameStore brushFrameStore;
  final CutId cutId;

  /// Any member of the group to unlink (resolves to its base).
  final LayerId sourceLayerId;

  /// The cels forked at execute — undo removes exactly these.
  ///
  /// 🚨★★★**KEYS AND SIZES, NEVER THE SURFACES.** This used to hold the
  /// forked [BitmapSurface]s and it read them for one field: undo puts an
  /// EMPTY surface of the same canvas size back. So an entry sitting on
  /// the undo stack for the rest of the session pinned a whole layer's
  /// pixels — invisibly, because this command reports no weight at all
  /// (the byte budget only sees a [RetainedBytesCommand]). It looked
  /// harmless while the store still held the same objects, and stopped
  /// being harmless the moment the user drew on the forked layer.
  ///
  /// ⛔It cannot become a [RetainedBytesCommand] instead: the answer is
  /// not「report these bytes」, it is「do not hold them」. A redo re-reads
  /// the pixels from the store on its way through [execute] anyway.
  final List<(BrushFrameKey, CanvasSize)> _forkedCels = [];

  @override
  String get description => 'Unlink layer $sourceLayerId';

  @override
  void execute() {
    final project = repository.requireProject();
    final registry = project.linkRegistry;
    // A 동기컷's rows leave TOGETHER and stay one group: the sync is one
    // cut, and its row is unlinked wherever the cut stands (I-150-Q3).
    final leaving = {
      for (final member in requireAttachedGroup(
        project,
        cutId: cutId,
        layerId: sourceLayerId,
      ).members)
        ...registry.rowAcrossItsSync(cutId: cutId, layerId: member.id),
    };
    bool leaves(LayerLinkMember member) =>
        leaving.contains((member.cutId, member.layerId));

    // 1. Each group parted in two — the rows leaving and the rows staying,
    //    a part of one dissolving — and the part the group's cels are NOT
    //    kept under (its first member's) starts from its own copy of them.
    //    ↩️Only the leaving rows were copied: unlinked in the cut the cels
    //    were kept under, the rows staying lost every picture, and the
    //    undo's emptying of the copies emptied the kept cels.
    final groups = <LayerLinkGroup>[];
    final copiers = <LayerLinkMember>[];
    for (final group in registry.groups) {
      final staying = [
        for (final member in group.members)
          if (!leaves(member)) member,
      ];
      final going = [
        for (final member in group.members)
          if (leaves(member)) member,
      ];
      if (staying.length >= 2) {
        groups.add(group.copyWith(members: staying));
      }
      if (going.length >= 2) {
        groups.add(
          staying.length >= 2
              ? LayerLinkGroup(id: '${group.id}:sync', members: going)
              : group.copyWith(members: going),
        );
      }
      if (staying.isNotEmpty && going.isNotEmpty) {
        copiers.add((leaves(group.members.first) ? staying : going).first);
      }
    }

    // 2. The cels captured THROUGH the copier's still-linked keys (they
    //    resolve to the kept cels). LOCAL, so the pixels are gone the
    //    moment this call returns — see [_forkedCels].
    final forked = <(BrushFrameKey, BitmapSurface)>[];
    _forkedCels.clear();
    for (final copier in copiers) {
      final row = requireLayer(
        project,
        cutId: copier.cutId,
        layerId: copier.layerId,
      );
      for (final frame in row.frames) {
        final key = BrushFrameKey(
          projectId: project.id,
          trackId: copier.trackId,
          cutId: copier.cutId,
          layerId: copier.layerId,
          frameId: frame.id,
        );
        final surface = brushFrameStore.bakedSurfaceOrNull(key);
        if (surface != null) {
          forked.add((key, surface));
          _forkedCels.add((key, surface.canvasSize));
        }
      }
    }

    snapshotRegistry(project);
    repository.updateProject(
      (current) => current.copyWith(
        linkRegistry: current.linkRegistry.copyWith(groups: groups),
      ),
    );

    // 3. A copier's keys now resolve to THEMSELVES — the first of its part
    //    — so the captured pixels are that part's own cels (surfaces are
    //    immutable, sharing the object is a true copy-on-write fork).
    for (final (key, surface) in forked) {
      brushFrameStore.storeBakedSurface(key, surface);
    }
    markExecuted();
  }

  /// Remove the forked cels FIRST (keys still self-resolving), then
  /// restore the registry — reads flow back to the canonical cels. The
  /// template fixes that order (see [LinkRegistrySnapshotCommand.undo]).
  @override
  void undoBeforeRegistry() {
    for (final (key, canvasSize) in _forkedCels) {
      brushFrameStore.storeBakedSurface(
        key,
        BitmapSurface(canvasSize: canvasSize),
      );
    }
  }
}
