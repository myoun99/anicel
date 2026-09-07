import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

import '../../core/path_names.dart';
import 'media_blob_codec.dart';
import 'session_scratch.dart';

/// 🚨★★★**WHAT「품기」MEANS BETWEEN THE IMPORT AND THE FIRST SAVE.**
///
/// Carrying a file used to be a promise the project kept only at save
/// time: the flag said「this travels with the project」and the bytes were
/// still the ones on disk, so editing or deleting the original before the
/// first save changed or emptied what got saved. 유저 2026-08-30 named the
/// behaviour they wanted instead — 「품은 순간 데이터를 가지고있고
/// **불변**이었으면좋겠어서」 — and chose where it lives: 「앱컨테이너에
/// 먼저 넣는거… **저장할때 옮겨가는걸로**」.
///
/// So an import COPIES, compressed, into the app container, and the save
/// moves those bytes into the .anicel and retires the staged copy.
///
/// ⛔**This is not a second copy of the asset.** It is the only copy the
/// project controls until the first save, and it stops being anything the
/// moment the save absorbs it. 유저 08-27: 「사본 남으면 진짜 용서안할게」 —
/// which is what [retire] and the room's own lifetime are for.
///
/// ⚠️**It is also not a new category in the container.** `Recovery/` held
/// project snapshots and `Conformed/` held audio derived from project
/// media when this was written — both are gone now, absorbed into the room
/// this store lives in; see [appSupportFilePath]. What a new tenant
/// owes is a LIFETIME, and this one's is now written in its PATH: it lives
/// in [SessionScratch]'s room for this run, retired by the save that
/// absorbs it, and gone with the room when the run ends. A room still
/// standing at the next launch is a crash, and what it holds is offered
/// back rather than swept.
///
/// 🚨**The name is DERIVED, never recorded** — the same rule the conform
/// store follows ("under a name derived by rule from the source path —
/// nothing recorded, nothing to fall out of sync"). A staged file that
/// nothing remembers cannot be remembered wrongly.
class MediaStagingStore {
  MediaStagingStore({String? directoryPath})
    : directoryPath = (directoryPath ?? defaultDirectory()).replaceAll(
        r'\',
        '/',
      );

  /// `<container>/Sessions/<this run>/Staged`.
  ///
  /// 🚨It moved out of the flat `<container>/Staged` and into THIS RUN'S
  /// room ([SessionScratch]) so that a file's lifetime is written in its
  /// path: the room goes when the run ends normally, and a room still
  /// standing at the next launch is a crash whose staged media recovery
  /// can offer back. ⛔The container gained no new KIND of tenant by this —
  /// staged media is what it always was; it gained a place where 「until
  /// this run is over」 is expressible.
  static String defaultDirectory() => SessionScratch.stagedFolder();

  /// Test seam: do the staging work HERE instead of in an isolate.
  ///
  /// 🚨★★★**A `testWidgets` CLOCK NEVER LETS A REAL ISOLATE FINISH.** The
  /// widget binding runs the body in a fake-async zone, so awaiting
  /// [Isolate.run] is a hang, not a wait — every voice-take and import
  /// widget test stopped at「did not complete」the moment this moved off
  /// the UI isolate. `tester.runAsync` is the other answer and it does not
  /// fit: these tests pump between the await and the assertion.
  ///
  /// ⛔**Inline is not a second implementation.** The same [_stageBytes]
  /// runs either way, and [stageCarriedBytes] stays `async` either way — so the
  /// ORDER a caller sees is identical, which is what the entrances'
  /// invariant actually rests on.
  ///
  /// ⚠️`flutter_test_config.dart` turns this ON for the whole suite, so the
  /// isolate road needs one test that turns it back OFF — see
  /// `media_staging_store_test`. Without that, nothing would ever run the
  /// road production takes.
  @visibleForTesting
  static bool debugStageInline = false;

  /// 🚨Separators normalised HERE, once.
  ///
  /// Every method compares a path it BUILT ([pathFor]) against a path the
  /// filesystem LISTED, and on Windows those disagree the moment a caller
  /// hands in a `\`-flavoured directory — `Directory.systemTemp` does. An
  /// earlier keep-set sweep failed to match a single live file that way
  /// and deleted the lot; that sweep is gone — the room's lifetime replaced
  /// it — but [find] and [list] still stand on the same comparison, so the
  /// normalisation stays where it cannot be forgotten.
  final String directoryPath;

  /// Where [poolPath]'s staged bytes live, framed or not.
  ///
  /// The suffix carries the same meaning it does inside the archive — see
  /// [mediaFramedEntrySuffix] — so a staged file can be streamed into the
  /// .anicel without being decoded and re-encoded on the way.
  String pathFor(String poolPath, {required bool framed}) =>
      mediaPathFramed(_basePathFor(poolPath), framed: framed);

  String _basePathFor(String poolPath) =>
      '$directoryPath/${stagedNameFor(poolPath)}';

  /// The staged copy of [poolPath], or null when there is none.
  ///
  /// Framed-first, through [mediaFramedOrPlainPaths] — the one place that
  /// knows a file this app wrote may wear either name.
  StagedMedia? find(String poolPath) {
    for (final candidate in mediaFramedOrPlainPaths(_basePathFor(poolPath))) {
      final file = File(candidate);
      if (file.existsSync()) {
        return StagedMedia(
          poolPath: poolPath,
          path: file.path.replaceAll(r'\', '/'),
          framed: mediaEntryIsFramed(candidate),
          storedLength: file.lengthSync(),
        );
      }
    }
    return null;
  }

  /// Copies [poolPath] into the staging area, compressed when that is
  /// worth it, and answers what landed.
  ///
  /// Idempotent: an asset already staged is left alone, because the bytes
  /// it holds are the ones the user asked to keep and the file on disk may
  /// have moved on since.
  ///
  /// 🚨★★★**THE WORK RUNS IN AN ISOLATE AND THE CALLER WAITS FOR IT.**
  ///
  /// Memory stopped being the problem when the write started streaming, but
  /// TIME did not: zstd is a blocking native call, so compressing a carried
  /// movie held the UI thread from the moment 품기 was pressed until the
  /// last block — minutes on a big file, with the app frozen.
  ///
  /// ⛔**Awaited, never fired and forgotten.** 유저 2026-08-30 asked for
  /// exactly one property — 「품은 순간 데이터를 가지고있고 **불변**
  /// 이었으면좋겠어서」 — and the pool must not record an asset whose bytes
  /// are still being secured. Every entrance therefore awaits this before
  /// the command that registers the asset runs, which is what turned four
  /// call sites async. The same shape the .tvpp import already uses:
  /// `Isolate.run` per unit, awaited, nothing registered early.
  Future<StagedMedia?> stage(String poolPath) async =>
      (await stageCarriedBytes([poolPath])).firstOrNull;

  /// 🚨★★★**EVERY WAY AN ASSET BECOMES CARRIED COMES THROUGH HERE.**
  ///
  /// Carrying means the project holds the bytes from the moment the choice
  /// is made — 유저 2026-08-30: 「품은 순간 데이터를 가지고있고 **불변**
  /// 이었으면좋겠어서」 — and there are FOUR ways to make that choice: the
  /// import window, a folder import, promoting a reference afterwards, and
  /// recording a voice take. Each one used to be free to forget, and three
  /// of them did.
  ///
  /// ⛔Called BEFORE the pool records the asset. A staged copy with no
  /// asset is an orphan the run's room takes when the run ends; an asset
  /// the pool holds whose bytes were never staged is the old behaviour
  /// back, silently — and silently is how it survived two rounds of this
  /// work.
  /// 🚨★★★**AWAIT IT. A DROPPED FUTURE HERE IS THE OLD BUG, SILENTLY.**
  ///
  /// The compression moved into an isolate so a carried movie stops
  /// freezing the app, and that turned this into a `Future`. Nothing in the
  /// analyzer stops a caller from ignoring it — `stageCarriedBytes(paths);`
  /// still compiles inside a `void` method — and a caller that does has put
  /// the registration back in front of the bytes, which is exactly the
  /// state the ⛔ above forbids. That is why the entrances are async now.
  ///
  /// Every path in [poolPaths], in ONE isolate.
  ///
  /// ⚡One, not one each. A folder import can hand this hundreds of files,
  /// and an isolate costs milliseconds to start — spawning per file would
  /// have made the many-small-files case SLOWER than the synchronous
  /// version it replaces, while fixing only the one-big-file case.
  ///
  /// Answers only what actually landed: a path that was already staged
  /// comes back as it sits, and one whose file is gone is absent rather
  /// than null-in-place, because no caller asks "which index failed".
  ///
  /// ⚠️The name is the law's ([[every_carry_stages_its_bytes_test]] scans
  /// the source for it). It used to be `stageAll`, with the law's name on
  /// a one-line forwarder in the session — so the file that decided an
  /// asset carried and the file that held the bytes were two hops apart,
  /// and the scan could only see the hop.
  Future<List<StagedMedia>> stageCarriedBytes(
    Iterable<String> poolPaths,
  ) async {
    final todo = <String>[];
    final done = <StagedMedia>[];
    for (final path in poolPaths) {
      final already = find(path);
      if (already != null) {
        done.add(already);
      } else if (File(path).existsSync()) {
        todo.add(path);
      }
    }
    if (todo.isEmpty) {
      return done;
    }
    Directory(directoryPath).createSync(recursive: true);
    // Scalars only. The closure crosses an isolate boundary, so it opens
    // its own handles over there rather than capturing any from here.
    final directory = directoryPath;
    final written = debugStageInline
        ? _stageBytes(todo, directory)
        : await Isolate.run(() => _stageBytes(todo, directory));
    for (final one in written) {
      done.add(
        StagedMedia(
          poolPath: one.poolPath,
          path: one.path,
          framed: one.framed,
          storedLength: one.storedLength,
        ),
      );
    }
    return done;
  }

  /// [stageCarriedBytes] for bytes that have no file yet — a voice take,
  /// which this app MADE rather than copied from somewhere.
  ///
  /// 🚨★★★**IT IS THE SAME DOOR, AND THAT IS THE POINT.** A take used to be
  /// written to a shelf folder outside the container and then read straight
  /// back to be staged, so one recording was **two files on disk** — the
  /// exact shape 유저 2026-08-27 refuses (「사본 남으면 진짜 용서안할게」).
  /// Handing the bytes to the store instead writes them ONCE, at the
  /// address the store already derives, through the same [writeMediaBlob]
  /// every other carried asset goes through — so the framing rule stays
  /// one rule and a take is stored exactly like an import.
  ///
  /// ⛔The name starts with `stageCarriedBytes` on purpose:
  /// `every_carry_stages_its_bytes_test` scans for that, and a variant of
  /// the funnel must read as one to the scanner as well as to a person.
  ///
  /// Idempotent for the same reason the funnel is: an asset already staged
  /// keeps the bytes it has.
  ///
  /// ⚠️No isolate. A take is what a person just performed — seconds of PCM
  /// the caller is already holding — where the funnel's isolate exists for
  /// the multi-gigabyte file it must not read into this one.
  Future<StagedMedia> stageCarriedBytesInMemory(
    String poolPath,
    Uint8List bytes,
  ) async {
    final already = find(poolPath);
    if (already != null) {
      return already;
    }
    Directory(directoryPath).createSync(recursive: true);
    final written = writeMediaBlob(
      basePath: _basePathFor(poolPath),
      length: bytes.length,
      readInto: (buffer, position, size) {
        buffer.setRange(0, size, bytes, position);
        return size;
      },
    );
    return StagedMedia(
      poolPath: poolPath,
      path: written.path,
      framed: written.framed,
      storedLength: File(written.path).lengthSync(),
    );
  }

  /// Follows an asset whose pool path changed — a relink.
  ///
  /// 🚨★★★**THE NAME IS DERIVED, SO IT HAS TO MOVE WHEN THE PATH DOES.**
  /// Deriving the name is what makes a staged file impossible to remember
  /// wrongly, and the price is exactly this: nothing points at it, so a
  /// path change orphans it silently. The asset would then look unstaged —
  /// back to the promise being kept at save time — while the bytes it was
  /// promised sat under the old name waiting for the sweep.
  ///
  /// ⚠️The fingerprints already move this way (`_moveMediaFingerprints`),
  /// and for the same reason. Derived state follows its key or it is not
  /// derived, it is stale.
  void rename(String fromPoolPath, String toPoolPath) {
    final staged = find(fromPoolPath);
    if (staged == null) {
      return;
    }
    final destination = pathFor(toPoolPath, framed: staged.framed);
    if (destination == staged.path) {
      return;
    }
    Directory(directoryPath).createSync(recursive: true);
    // ⛔The destination is emptied first: a rename onto an existing file
    // fails on Windows, and the bytes already there belong to whatever
    // used to hold that pool path — which the caller has just replaced.
    final existing = File(destination);
    if (existing.existsSync()) {
      existing.deleteSync();
    }
    File(staged.path).renameSync(destination);
  }

  /// Drops the staged copy of [poolPath] — the save absorbed it.
  ///
  /// BOTH spellings, because which one is on disk depends on whether the
  /// bytes shrank, and a save must not leave half of an absorbed import
  /// behind (유저 08-27: 「사본 남으면 진짜 용서안할게」).
  void retire(String poolPath) {
    for (final candidate in mediaFramedOrPlainPaths(_basePathFor(poolPath))) {
      final file = File(candidate);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  // 🪦**THE AGE SWEEP MOVED ONTO THE ROOM** — see
  // [SessionScratch.deleteFoldersOfEndedRunsOlderThan]. It used to live
  // here as `sweepAbandoned`, and its own doc said why it had to use age:
  // 「the obvious sweep — delete anything no open project claims — cannot
  // be written safely: at launch nothing is open yet, so the live set is
  // empty and the sweep would take everything」, and 「being handed a
  // PARTIAL live set is the one mistake this class cannot make, so it is
  // not asked for one」.
  //
  // ⛔**Both halves of that still hold and neither is being taken back.**
  // What changed is that a staged file now sits in the room of the RUN
  // that staged it, and a room can be asked whether its owner is still
  // here without anybody handing over a list. So the sweep still refuses
  // a live set, and it no longer has to wait a month to tell a crash from
  // an abandonment: a crashed run's staged media is offered back, and only
  // a room nobody came back to for 30 days (유저 2026-08-26: 「30일좋고」)
  // goes.

  /// Every staged file, for the settings list that shows what the app
  /// container holds.
  List<StagedMedia> list() {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      return const [];
    }
    return [
      for (final entity in directory.listSync())
        if (entity is File && !entity.path.endsWith('.part'))
          StagedMedia(
            poolPath: null,
            path: entity.path.replaceAll(r'\', '/'),
            framed: mediaEntryIsFramed(entity.path),
            storedLength: entity.lengthSync(),
          ),
    ];
  }

  /// A stable, filesystem-safe name for [poolPath].
  ///
  /// The basename rides ahead of the hash for the same reason the archive
  /// entry's does: a person looking in the folder should be able to tell
  /// what they are looking at.
  /// The staged file's name for [poolPath] — derived, never recorded.
  ///
  /// Public because [_stageBytes] runs in an isolate and has to derive the
  /// same name over there; a second spelling of this rule is exactly the
  /// drift the derived-name design exists to make impossible.
  static String stagedNameFor(String poolPath) {
    final normalized = poolPath.replaceAll(r'\', '/');
    final base = fileNameOfPath(normalized);
    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    final safe = base.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    return '${hash.toRadixString(16).padLeft(8, '0')}-$safe';
  }
}

/// One staged file.
@immutable
class StagedMedia {
  const StagedMedia({
    required this.poolPath,
    required this.path,
    required this.framed,
    required this.storedLength,
  });

  /// The pool path these bytes were staged for, or null when the file was
  /// enumerated rather than looked up.
  final String? poolPath;

  /// Where the staged bytes are.
  final String path;

  /// Whether [path] holds a framed blob rather than the file's own bytes.
  final bool framed;

  /// Bytes on disk — the framed length when [framed], the file's own
  /// otherwise.
  final int storedLength;

  /// The bytes to write into the .anicel, verbatim.
  ///
  /// 🚨Framed or not, they go in AS THEY ARE: decoding a staged blob only
  /// to re-encode it would burn the whole point of having compressed it at
  /// import.
  Uint8List readStoredSync() => File(path).readAsBytesSync();
}

/// [MediaStagingStore.stageCarriedBytes]'s work, as a top-level function so the
/// isolate closure captures a list of strings and nothing else.
///
/// ONE handle per file: `MediaFileBytes.readIntoSync` opens and closes per
/// call, which a 4GB asset at 512KB blocks would pay eight thousand times.
///
/// ⚠️A file that cannot be opened is SKIPPED, not thrown for. The batch may
/// be a whole folder, and one unreadable asset must not cost the rest their
/// bytes — the pool then simply has no staged copy for it, which is the
/// same state as never having asked.
List<({String poolPath, String path, bool framed, int storedLength})>
_stageBytes(List<String> poolPaths, String directoryPath) {
  final out =
      <({String poolPath, String path, bool framed, int storedLength})>[];
  for (final poolPath in poolPaths) {
    final RandomAccessFile handle;
    try {
      handle = File(poolPath).openSync();
    } on FileSystemException {
      continue;
    }
    try {
      final written = writeMediaBlob(
        basePath: '$directoryPath/${MediaStagingStore.stagedNameFor(poolPath)}',
        length: handle.lengthSync(),
        readInto: (buffer, position, size) {
          handle.setPositionSync(position);
          return handle.readIntoSync(buffer, 0, size);
        },
      );
      out.add((
        poolPath: poolPath,
        path: written.path,
        framed: written.framed,
        storedLength: File(written.path).lengthSync(),
      ));
    } finally {
      handle.closeSync();
    }
  }
  return out;
}
