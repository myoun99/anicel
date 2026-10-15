import 'package:flutter/foundation.dart' show Listenable;

import '../../models/brush_frame_key.dart';
import '../../models/cel_photo.dart';
import '../brush_frame_editing_coordinator.dart';
import '../brush_frame_store.dart';
import '../commands/cel_photo_edit_command.dart';
import '../history_manager.dart';
import 'media_moves.dart' show mediaMovesInPoolSpelling;

/// The photos on the sheets' ink (I-97) as the media pool meets them: which
/// cels name a pool file, and the pool's edits of them — a file taken out
/// of the pool takes its photos along (F-118), a file found somewhere else
/// takes them with it (다시 연결), and a project opened where its files
/// moved finds them there (열 때 경로 옮기기).
///
/// A cel is asked what it names by its store, without a decode
/// ([BrushFrameStore.celPhotoPathsByKey]); only a cel being edited is read,
/// through a coordinator of its own over its store
/// ([BrushFrameEditingCoordinator.overInk]) — the sheet's panel may not be
/// open, and a panel's sessions follow the store, whoever writes it.
///
/// ⚠️What the pool does to the REFERENCES on rows and frames, said of the
/// photos a sheet keeps in its pictures: the project's own walks
/// (`projectWithMediaMoved`, `MediaPool.removeMediaAsset`) never reach a
/// cel.
class SheetPhotoEdits {
  SheetPhotoEdits(this._stores);

  /// The sheets' ink stores — the conte's, the envelope's, the timesheet's.
  final List<BrushFrameStore> Function() _stores;

  /// The pool files each sheet cel's photos name, by cel.
  Map<BrushFrameKey, List<String>> get pathsByCel => {
    for (final store in _stores()) ...store.celPhotoPathsByKey,
  };

  /// Ticks on every write to a sheet's ink — each store's one signal for a
  /// surface write ([BrushFrameStore.celPixelRevision]). A photo put on a
  /// sheet, taken off it or undone there is written without a word to the
  /// session, and [pathsByCel] moves with it.
  late final Listenable writes = Listenable.merge([
    for (final store in _stores()) store.celPixelRevision,
  ]);

  /// Every photo of [path] taken off the cels [keys] — each cel a step of
  /// [history], for the caller to fold into its own.
  void takeOff(
    String path,
    Set<BrushFrameKey> keys,
    HistoryManager history,
  ) => _edit(
    history,
    named: (key, paths) => keys.contains(key) && paths.contains(path),
    photos: (photos) => [
      for (final photo in photos)
        if (photo.reference.assetPath != path) photo,
    ],
  );

  /// Every photo of a file [moved] names standing on the file where it
  /// went — each cel a step of [history], for the caller to fold into its
  /// own.
  void follow(Map<String, String> moved, HistoryManager history) {
    final moves = mediaMovesInPoolSpelling(moved);
    _edit(
      history,
      named: (_, paths) => paths.any(moves.containsKey),
      photos: (photos) => celPhotosMoved(photos, moves),
    );
  }

  /// [follow] for a project being opened, where nothing was done that an
  /// undo could take back: each cel is kept as it now is, and the next save
  /// writes it. Answers whether any photo moved — a session whose load
  /// moved one is unsaved, as one whose load healed a cel is.
  bool followOpened(Map<String, String> moved) {
    final moves = mediaMovesInPoolSpelling(moved);
    var any = false;
    for (final store in _stores()) {
      for (final MapEntry(:key, value: paths)
          in store.celPhotoPathsByKey.entries) {
        final picture = paths.any(moves.containsKey)
            ? store.bakedSurfaceOrNull(key)
            : null;
        if (picture != null) {
          store.storeBakedSurface(
            key,
            picture.withPhotos(celPhotosMoved(picture.photos, moves)),
          );
          any = true;
        }
      }
    }
    return any;
  }

  /// [photos] made of the photos of every cel [named] says, each a step of
  /// [history].
  void _edit(
    HistoryManager history, {
    required bool Function(BrushFrameKey key, List<String> paths) named,
    required List<CelPhoto> Function(List<CelPhoto> photos) photos,
  }) {
    for (final store in _stores()) {
      for (final MapEntry(:key, value: paths)
          in store.celPhotoPathsByKey.entries) {
        final size = named(key, paths)
            ? store.bakedSurfaceOrNull(key)?.canvasSize
            : null;
        if (size == null) {
          continue;
        }
        history.execute(
          CelPhotoEditCommand(
            coordinator: BrushFrameEditingCoordinator.overInk(
              store: store,
              canvasSize: size,
              initialFrameKey: key,
            ),
            frameKey: key,
            description: 'Edit photos',
            photos: photos,
          ),
        );
      }
    }
  }
}
