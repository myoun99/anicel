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

/// One cel a copier starts from ([LinkPartCopies.take]): the key its
/// picture is kept under, the copier's own key, and the copier's canvas.
typedef LinkPartCopy = ({
  BrushFrameKey from,
  BrushFrameKey to,
  CanvasSize canvasSize,
});

/// The cels a parted group's copiers start from ([partLinkGroup]) — named
/// through each copier's keys while the table still links them to the kept
/// cels, copied under those keys once it no longer does, and emptied again
/// by an undo.
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
  /// not「report these bytes」, it is「do not hold them」. A redo copies
  /// again from the store on its way through execute anyway.
  final List<(BrushFrameKey, CanvasSize)> _kept = [];

  /// [copiers]' cels, each the key its picture is kept under now and the
  /// copier's own key it goes to — named BEFORE the table changes, while a
  /// copier's keys still resolve to the kept cels. Nothing is read: [keep]
  /// hands each pair to the store, which copies in the tier the cel is kept
  /// in ([BrushFrameStore.copyCel]). 🗣️Card `timeline-copy-thaws-every-cel`
  /// (유저 2026-11-04): read as a use, every cel kept in the saved file
  /// thawed hot to be copied.
  List<LinkPartCopy> take(Project project, Iterable<LayerLinkMember> copiers) {
    final store = _store;
    final taken = <LinkPartCopy>[];
    if (store == null) {
      return taken;
    }
    for (final copier in copiers) {
      final canvasSize = requireCut(project, copier.cutId).canvasSize;
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
        taken.add((
          from: store.canonicalKeyOf(key),
          to: key,
          canvasSize: canvasSize,
        ));
      }
    }
    return taken;
  }

  /// [taken] copied — AFTER the table changed, when a copier's keys resolve
  /// to itself, the first of its part. The copies an undo empties are the
  /// ones the store says it made: a cel whose source kept none was copied
  /// nothing.
  void keep(List<LinkPartCopy> taken) {
    _kept.clear();
    for (final (:from, :to, :canvasSize) in taken) {
      if (_store!.copyCel(from, to, canvasSize: canvasSize) case final kept?) {
        _kept.add((to, kept));
      }
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
