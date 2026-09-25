import 'dart:io';

import '../../models/brush_frame_key.dart';
import '../brush_frame_store.dart';
import 'anicel_file_service.dart';
import 'folder_grant.dart' show FolderPicker;
import 'open_project_file.dart';
import 'same_file.dart';
import 'save_failure.dart' show SaveNotSwappedIn;

/// Swaps [from] — a complete archive the stores' refs already point into —
/// onto [to] through the platform's file coordinator, then repoints the
/// refs: the copy is byte-identical, so the same offsets hold.
///
/// The one swap every coordinated save ends in, whether the archive was
/// written beside the file (the ordinary whole write) or in this run's
/// staging room (a location that refused the temp beside it). A
/// persistence concern, not a door's: the door decides WHEN to save, this
/// is HOW a finished archive becomes the project file where a provider
/// has to be told.
///
/// 🚨THE HELD HANDLE GOES FIRST. The session holds the project file open
/// ([OpenProjectFile]); a replace under a held descriptor leaves it on the
/// OLD inode, and every cel read after the repoint would read the old
/// bytes at the new offsets. Released before, held again after — the shape
/// the direct road's rename uses for the same reason.
///
/// ⚠️Keys dirty AGAIN (drawn on while the save ran) keep their refs into
/// [from] and their dirt: repointing them through `adoptSavedFile` would
/// CLEAR that dirt, and the next save would quietly skip the stroke — the
/// exact loss shape the editTick round closed. Which is also why [from] is
/// not deleted here: it holds those cels until the next save writes them
/// again, and a temp beside the file is swept by the next whole write like
/// any stray.
Future<void> replaceProjectFileCoordinated({
  required String from,
  required String to,
  required List<BrushFrameStore> stores,
}) async {
  OpenProjectFile.instance.releaseFor(to);
  final replaced = await FolderPicker.replaceFileCoordinated(
    sourcePath: from,
    destinationPath: to,
  );
  if (!replaced) {
    // Where the archive is, so the session can keep the work in its
    // failed copy before [from] goes (whole-write-temp-beside-the-file).
    throw SaveNotSwappedIn(
      archive: from,
      error: FileSystemException(
        'the coordinated replace onto this location failed — it cannot be '
        'saved to in place',
        to,
      ),
      refusedByProvider: true,
    );
  }
  for (final store in stores) {
    final snapshot = store.bakedSnapshotForSave();
    final dirtyAgain = store.dirtyCelKeysSinceSave;
    final moved = <BrushFrameKey, AnicelCelFileRef>{
      for (final entry in snapshot.fileRefs.entries)
        if (!dirtyAgain.contains(entry.key) &&
            namesTheSameFile(entry.value.filePath, from))
          entry.key: AnicelCelFileRef(
            filePath: to,
            dataOffset: entry.value.dataOffset,
            length: entry.value.length,
            canvasSize: entry.value.canvasSize,
            tileSize: entry.value.tileSize,
          ),
    };
    if (moved.isNotEmpty) {
      store.adoptSavedFile(moved, dirtyTicksAtSnapshot: snapshot.dirtyTicks);
    }
  }
  // The refs read from [to] now — held, as after every adopting save
  // ([OpenProjectFile.hold]).
  OpenProjectFile.instance.hold(to);
  // The direct road sweeps its strays after every whole write; this road
  // does the same, sparing only [from] — gone if the platform moved it, and
  // still the home of any key dirty again if it copied.
  AnicelFileService.sweepStaleSaveTemps(to, except: from);
}
