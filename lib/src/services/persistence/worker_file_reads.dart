import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/on_a_worker.dart';
import 'same_file.dart';

/// Stretches of files read on workers — off the thread that asks — each
/// through a handle of the worker's own, opened for that read and closed
/// with it.
///
/// 🗣️Card a-thawed-cel-is-adopted-on-the-ui-thread. A kept cel's bytes
/// were read on the UI thread and only then handed to a worker — the saved
/// file's through the session's one handle (`OpenProjectFile.readAt`).
/// 🔬FNK_02 v35's 1,328 cels (318 KiB the median), a read each, on the
/// Surface (2026-11-15, a Dart probe reading as that handle does): where
/// the user keeps the file, a Google Drive folder, **4.3 ms the median,
/// 9.0 the p90, 112 the longest** on a first pass and 1.0 / 1.9 / 38 once
/// cached; a local SSD 0.9 / 2.1 / 80 with its cache dropped and
/// 0.3 / 0.8 / 13 cached. A frame thaws a cel a row, at once.
///
/// 🚨★★★A WORKER'S HANDLE IS THIS PROCESS'S, AND WINDOWS REFUSES A RENAME
/// ONTO A FILE ANYTHING IN THE PROCESS HOLDS OPEN (`OpenProjectFile`, its
/// fourth measurement). So whoever puts another file in the place of one
/// these may be reading does it through [replacing]: the reads in flight
/// end first, and one asked meanwhile waits until the file is replaced.
///
/// 🚨★★★BYTES READ BY A REF THAT HAS MOVED MAY BE ANOTHER'S. A read is of
/// the file as it is when the worker gets to it, and a save may have moved
/// what was there: the in-place push-down writes over a stretch once the
/// refs are moved off it (`BrushFrameStore.relocateFileRefs`), and a whole
/// write lays the file out anew. Every move re-issues the ref
/// (`AnicelCelFileRef.movedTo`), so the asker keeps what it read only
/// while it still keeps that very ref
/// (`BrushFrameStore._keptBlobOffThisThread`). ⛔Not a wait in the save:
/// the ref's identity already says it, for every mover there is.
abstract final class WorkerFileReads {
  /// The reads in flight, by the file each reads.
  static final List<({String path, Future<void> ended})> _inFlight = [];

  /// The files being replaced right now, each with when it has been.
  static final List<({String path, Future<void> replaced})> _replacing = [];

  /// How many reads are in flight (tests).
  static int get inFlight => _inFlight.length;

  /// [length] bytes of [path] from [offset], read on a worker
  /// ([onAWorker]) — or what the read threw: no file there, no leave to
  /// open it.
  static Future<Uint8List> read(String path, int offset, int length) async {
    // Asked again after each wait: another replace may have begun.
    var replaced = _replacingOf(path);
    while (replaced != null) {
      await replaced;
      replaced = _replacingOf(path);
    }
    // In flight until it is out of the list: who waits for [ended] finds
    // the list without it ([replacing]).
    final ended = Completer<void>();
    final flight = (path: path, ended: ended.future);
    _inFlight.add(flight);
    try {
      return await onAWorker(_reading(path, offset, length));
    } finally {
      _inFlight.remove(flight);
      ended.complete();
    }
  }

  /// [replace] — what puts another file in [path]'s place — run once no
  /// worker reads [path], with nothing between the last of them ending and
  /// it: a read asked from now on waits until it has run.
  ///
  /// ⚠️Answers as [replace] returns, nothing waited for after it: a save's
  /// swap and the adoption of its refs stay a microtask apart
  /// (`AnicelFileService`, the whole write).
  ///
  /// ⚠️No bound, where the media readers' letting go has one
  /// (`ProjectFile.readersLetGoOf`, for a reader that never follows): a
  /// worker's read ends by itself.
  static Future<T> replacing<T>(String path, T Function() replace) async {
    final replaced = Completer<void>();
    final entry = (path: path, replaced: replaced.future);
    _replacing.add(entry);
    try {
      await Future.wait([
        for (final flight in _inFlight)
          if (namesTheSameFile(flight.path, path)) flight.ended,
      ]);
      return replace();
    } finally {
      _replacing.remove(entry);
      replaced.complete();
    }
  }

  static Future<void>? _replacingOf(String path) {
    for (final entry in _replacing) {
      if (namesTheSameFile(entry.path, path)) {
        return entry.replaced;
      }
    }
    return null;
  }

  /// The read that crosses to the worker — made here, of these three
  /// alone: a closure made in [read] would carry what [read] holds
  /// (`onAWorker`'s own note on what a closure carries).
  static Uint8List Function() _reading(String path, int offset, int length) =>
      () => _readHere(path, offset, length);

  /// [length] bytes of [path] from [offset], through a handle opened here
  /// and closed here.
  static Uint8List _readHere(String path, int offset, int length) {
    final file = File(path).openSync();
    try {
      file.setPositionSync(offset);
      return file.readSync(length);
    } finally {
      file.closeSync();
    }
  }
}
