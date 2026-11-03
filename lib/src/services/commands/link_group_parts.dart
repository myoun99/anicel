import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../brush_frame_store.dart';
import '../project_lookup.dart';

/// A link group parted ([partLinkGroup]): what the table keeps of it, and
/// the members that start from their own copy of its cels.
typedef PartedLinkGroup = ({
  List<LayerLinkGroup> groups,
  List<LayerLinkMember> copiers,
});

/// [group] parted into [parts] — every member in one of them, each part in
/// the group's order: a part of two rows or more is a group, the first such
/// keeping [group]'s id and each later one taking [idOf] its index; a part
/// of one is a row of its own.
///
/// The group's cels are kept under its first member, so the part holding it
/// keeps them, and each OTHER part starts from its own copy, kept under its
/// first member — the COPIER ([LinkPartCopies]). A part of one too: it would
/// otherwise lose every picture. ↩️Only the leaving rows were copied once:
/// unlinked in the cut the cels were kept under, the rows staying lost every
/// picture, and the undo's emptying of the copies emptied the kept cels.
PartedLinkGroup partLinkGroup(
  LayerLinkGroup group,
  List<List<LayerLinkMember>> parts, {
  required String Function(int part) idOf,
}) {
  final holder = group.members.first;
  final held = [
    for (final part in parts)
      if (part.isNotEmpty) part,
  ];
  final groups = <LayerLinkGroup>[];
  for (final (index, part) in parts.indexed) {
    if (part.length < 2) {
      continue;
    }
    groups.add(
      groups.isEmpty
          ? group.copyWith(members: part)
          : LayerLinkGroup(id: idOf(index), members: part),
    );
  }
  return (
    groups: groups,
    copiers: held.length < 2
        ? const []
        : [
            for (final part in held)
              if (!part.contains(holder)) part.first,
          ],
  );
}

/// The cels a parted group's copiers start from ([partLinkGroup]) — taken
/// through each copier's keys while the table still links them to the kept
/// cels, kept under those keys once it no longer does, and emptied again by
/// an undo.
final class LinkPartCopies {
  LinkPartCopies(this._store);

  /// Null where the session keeps no pictures: there is nothing to copy.
  final BrushFrameStore? _store;

  /// The copies [keep] made — an undo empties exactly these.
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
  /// the pixels from the store on its way through execute anyway.
  final List<(BrushFrameKey, CanvasSize)> _kept = [];

  /// [copiers]' cels as they read now — BEFORE the table changes, so their
  /// keys still resolve to the kept cels. The caller holds them LOCALLY and
  /// hands them to [keep] in the same call ([_kept]'s reason).
  List<(BrushFrameKey, BitmapSurface)> take(
    Project project,
    Iterable<LayerLinkMember> copiers,
  ) {
    final store = _store;
    final taken = <(BrushFrameKey, BitmapSurface)>[];
    if (store == null) {
      return taken;
    }
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
        if (store.bakedSurfaceOrNull(key) case final surface?) {
          taken.add((key, surface));
        }
      }
    }
    return taken;
  }

  /// [taken] kept under its keys — AFTER the table changed, when a copier's
  /// keys resolve to itself, the first of its part. Surfaces are immutable:
  /// sharing the object is a true copy-on-write fork.
  void keep(List<(BrushFrameKey, BitmapSurface)> taken) {
    _kept.clear();
    for (final (key, surface) in taken) {
      _store!.storeBakedSurface(key, surface);
      _kept.add((key, surface.canvasSize));
    }
  }

  /// The copies emptied — FIRST, while their keys still resolve to
  /// themselves; the table goes back after.
  void takeBack() {
    for (final (key, canvasSize) in _kept) {
      _store!.storeBakedSurface(key, BitmapSurface(canvasSize: canvasSize));
    }
  }
}
