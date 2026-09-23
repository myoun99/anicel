import 'dart:io';
import 'dart:isolate';

import '../../core/path_names.dart';
import 'anicel_file_service.dart';
import 'session_scratch.dart';

/// One FAILED COPY (실패본): the work saves could not put in
/// [projectPath], kept in this run's room at [copyPath] — as of [savedAt].
typedef FailedSaveCopy = ({
  String copyPath,
  String projectPath,
  DateTime savedAt,
});

/// Every failed copy this run holds — what 「실패본 백업…」 offers.
///
/// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file, after Q2):
/// 「실패하면 앱컨테이너에 같은파일로 계속 증분저장? 아무튼 쌓이고, 유저가
/// 그 파일 따로 … 해당파일 지정해서 백업할수있게」. A session whose file
/// refuses a save keeps ONE failed copy and goes on saving into it; the
/// copies of the sessions before it in this run stay until the run ends,
/// so a person can still pick one and keep it somewhere of their own.
///
/// ⚠️Knows nothing of sessions or saving: it names the copies and says
/// whether each is still there. Who writes one and when it goes is
/// `ProjectFileDoor`'s.
final class FailedSaveCopies {
  final Map<String, FailedSaveCopy> _byCopy = {};

  /// A new address for a failed copy of [projectPath]: a folder of its own
  /// in this run's room, holding a file under the project's own name —
  /// the name a backup suggests.
  static String addressFor(String projectPath) =>
      '${SessionScratch.unsavedFolder()}/'
      '${DateTime.now().microsecondsSinceEpoch}/${fileNameOfPath(projectPath)}';

  /// [copyPath] copied whole to [destination] — the backup a person asks
  /// for. Through a neighbour of [destination] and the save's own rename,
  /// so a copy cut short never stands under the name they chose and a
  /// scanner that grabs the new file for a beat is waited out as a save
  /// waits it out; the copy in a worker, because a project is big and the
  /// window waiting on it has to keep drawing.
  static Future<void> copyWhole(String copyPath, String destination) async {
    final neighbour =
        '$destination.tmp-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await Isolate.run(() {
        File(copyPath).copySync(neighbour);
      });
      AnicelFileService.renameWithRetry(File(neighbour), destination);
    } on Object {
      try {
        File(neighbour).deleteSync();
      } on FileSystemException {
        // Never written, or already renamed.
      }
      rethrow;
    }
  }

  /// [copyPath] now holds the work saves could not put in [projectPath].
  void record(String copyPath, String projectPath) {
    _byCopy[copyPath] = (
      copyPath: copyPath,
      projectPath: projectPath,
      savedAt: DateTime.now(),
    );
  }

  /// The project [copyPath] holds the work of, or null when it is not a
  /// failed copy this run knows.
  String? projectOf(String copyPath) => _byCopy[copyPath]?.projectPath;

  /// [copyPath] is no longer a failed copy — its project took a save.
  void forget(String copyPath) => _byCopy.remove(copyPath);

  /// The failed copies still standing, the newest first.
  List<FailedSaveCopy> get entries {
    final standing = [
      for (final copy in _byCopy.values)
        if (File(copy.copyPath).existsSync()) copy,
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return standing;
  }
}
