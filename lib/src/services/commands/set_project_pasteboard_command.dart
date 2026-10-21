import '../../models/brush_frame_key.dart';
import '../../models/pasteboard_bounds.dart';
import '../brush_frame_store.dart';
import '../cels_ahead.dart';
import '../command.dart';
import '../import/raster_cel_import.dart' show bakeCelSurface;
import '../project_repository.dart';
import '../undo_surface_snapshot.dart';

/// The project's pasteboard — its size, and whether it is there at all
/// (I-109) — as one undo step, with every picture the move of its wall
/// cuts. Null leaves that field as it is.
///
/// 🗣️I-109-Q2 (유저 2026-10-20): 「잘라낸다 … 다만 언두하면 제대로 돌아온다거나
/// 이런 안전장치만 제대로 철저하게」. So each move of the wall keeps what it cut,
/// as it was, and the move back lays it back — an undo and a redo alike: a
/// wall grown back cuts nothing, and what the shrink took comes back whole,
/// in the place it was.
class SetProjectPasteboardCommand
    implements
        Command,
        RetainedBytesCommand,
        ParkableCommand,
        PictureRestoringCommand {
  SetProjectPasteboardCommand({
    required this.repository,
    this.brushFrameStore,
    this.size,
    this.inUse,
  });

  final ProjectRepository repository;

  /// The canvas's cels — the pictures that stand behind the wall. Null in a
  /// host that holds none: the project's fields move alone.
  final BrushFrameStore? brushFrameStore;
  final PasteboardSize? size;
  final bool? inUse;

  ({PasteboardSize size, bool inUse})? _before;

  /// What the last move of the wall cut, as it was — laid back by the move
  /// the other way. Only one move's is ever held: the stack steps LIFO.
  Map<BrushFrameKey, UndoSurfaceSnapshot> _cut = const {};

  @override
  String get description => 'Change pasteboard';

  @override
  void execute() {
    final project = repository.requireProject();
    final before = _before ??= (
      size: project.pasteboardSize,
      inUse: project.pasteboardInUse,
    );
    _move(size: size ?? before.size, inUse: inUse ?? before.inUse);
  }

  @override
  void undo() {
    final before = _before;
    if (before == null) {
      throw StateError('Command has not been executed.');
    }
    _move(size: before.size, inUse: before.inUse);
  }

  /// The project's pasteboard set to [size] and [inUse], the store's wall
  /// moved with it, and what the move before this one cut laid back.
  void _move({required PasteboardSize size, required bool inUse}) {
    repository.updateProject(
      (project) =>
          project.copyWith(pasteboardSize: size, pasteboardInUse: inUse),
    );
    final store = brushFrameStore;
    if (store == null) {
      return;
    }
    final layBack = _cut;
    final cut = store.adoptPasteboardReach(
      repository.requireProject().pasteboardReach,
    );
    for (final MapEntry(:key, value: snapshot) in layBack.entries) {
      // ⛔A cel whose parked picture will not read back keeps what it has
      // rather than taking a picture with holes in it (the resize's rule).
      final picture = snapshot.surfaceOver(store.bakedSurfaceOrNull(key));
      if (picture != null) {
        bakeCelSurface(store, key, picture);
      }
    }
    UndoSurfaceSnapshot.dropAll(layBack.values);
    _cut = {
      for (final MapEntry(:key, value: picture) in cut.entries)
        key: UndoSurfaceSnapshot(
          key: key,
          snapshot: picture,
          sharedWith: store.hotBakedSurfaceOrNull(key),
        ),
    };
  }

  /// ⛔[undone] changes nothing here: the entry holds what the last move
  /// cut and nothing else, whichever way it went.
  @override
  int estimatedRetainedBytes({required bool undone}) => _cut.values.fold(
    0,
    (total, snapshot) => total + snapshot.residentBytes,
  );

  @override
  Future<bool> parkPayload() => UndoSurfaceSnapshot.parkAll(_cut.values);

  @override
  void dropPayload() => UndoSurfaceSnapshot.dropAll(_cut.values);

  /// The next step lays back what the last move cut, whichever way it is
  /// taken — read through the very reader [_move] uses.
  @override
  void readAhead(CelsAhead cels, {required bool undo}) {
    final store = brushFrameStore;
    if (store == null) {
      return;
    }
    for (final MapEntry(:key, value: snapshot) in _cut.entries) {
      cels.readSnapshot(key, snapshot, () => store.bakedSurfaceOrNull(key));
    }
  }

  @override
  void dropReadAhead() {
    for (final snapshot in _cut.values) {
      snapshot.dropReadAhead();
    }
  }

  @override
  void visitHeldTiles(HeldTileVisitor visit, {required bool undone}) {
    for (final snapshot in _cut.values) {
      snapshot.visitResidentOwnedTiles(visit);
    }
  }
}
