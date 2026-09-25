import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

import '../../core/path_names.dart';
import '../../models/media_asset.dart'
    show MediaCarry, mediaCarryName, mediaNameParts;
import 'media_blob_codec.dart';
import 'scratch_file.dart';
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
/// moment the save absorbs it — or, when a reader still has it open, the
/// moment that reader lets go ([hold]). 유저 08-27: 「사본 남으면 진짜
/// 용서안할게」 — which is what [retire] and the room's own lifetime are for.
///
/// ⚠️**It is also not a new category in the container.** `Recovery/` held
/// project snapshots and `Conformed/` held audio derived from project
/// media when this was written — both are gone now, absorbed into the room
/// this store lives in; see [appSupportFilePath]. What a new tenant
/// owes is a LIFETIME, and this one's is now written in its PATH: it lives
/// in [SessionScratch]'s room for this run, retired by the save that
/// absorbs it, and gone with the room when the run ends. A room still
/// standing at the next launch belonged to a run that crashed, and goes
/// then (유저 확정 2026-09-10 — see the 🪦 note above [list]).
///
/// 🚨**A staged file is named by its carry, and nothing here records it**
/// ([mediaCarryName]) — the name is minted with the carry and kept by the
/// asset it belongs to ([MediaAsset.carriedAs]), the way the conform store
/// names a file by rule from its source path ("nothing recorded, nothing
/// to fall out of sync"). A staged file that no list remembers cannot be
/// remembered wrongly.
class MediaStagingStore {
  MediaStagingStore({String? directoryPath})
    : _injected = directoryPath?.replaceAll(r'\', '/');

  /// `<container>/Sessions/<this run>/Staged`.
  ///
  /// 🚨It moved out of the flat `<container>/Staged` and into THIS RUN'S
  /// room ([SessionScratch]) so that a file's lifetime is written in its
  /// path: the room goes when the run ends normally, and a room still
  /// standing at the next launch belonged to a run that crashed — which
  /// takes it then. ⛔The container gained no new KIND of tenant by this —
  /// staged media is what it always was; it gained a place where 「until
  /// this run is over」 is expressible.
  ///
  /// ⚠️**CALLING THIS BUILDS AND LOCKS THE ROOM**, which is why
  /// [directoryPath] resolves it on use rather than in the constructor.
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

  /// 🚨Separators normalised HERE, once — every path built from it
  /// ([_basePathFor]) is in the one spelling, and a path the file system
  /// LISTS is put in it where it is listed ([list]; [holdsAnyCopyOf] reads
  /// only its name, through [fileNameOfPath]).
  ///
  /// On Windows the two disagree the moment a caller hands in a
  /// `\`-flavoured directory — `Directory.systemTemp` does. An earlier
  /// keep-set sweep failed to match a single live file that way and deleted
  /// the lot; that sweep is gone — the room's lifetime replaced it — but
  /// [find] and [list] still stand on the one spelling, so the
  /// normalisation stays where it cannot be forgotten.
  /// 🚨★★★**RESOLVED ON USE, NOT IN THE CONSTRUCTOR** — because resolving
  /// it BUILDS AND LOCKS the run's room ([SessionScratch.stagedFolder]),
  /// and this store is constructed while the editor comes up. A `final`
  /// field computed in the initialiser therefore made every launch leave a
  /// locked, empty room behind, whether or not the user ever carried a
  /// single file. 유저 확정 2026-09-10: 「애초에 안생기도록」.
  ///
  /// ⚠️An injected path is kept as given — a test's folder is not the
  /// run's room and must not summon one.
  String get directoryPath =>
      _injected ?? defaultDirectory().replaceAll(r'\', '/');

  final String? _injected;

  /// Where [carry]'s staged bytes live, before the framed suffix — which
  /// carries the same meaning it does inside the archive
  /// ([mediaFramedEntrySuffix]), so a staged file can be streamed into the
  /// .anicel without being decoded and re-encoded on the way.
  String _basePathFor(MediaCarry carry) =>
      '$directoryPath/${mediaCarryName(carry)}';

  /// The staged copy of [carry], or null when there is none.
  ///
  /// Framed-first, through [mediaFramedOrPlainPaths] — the one place that
  /// knows a file this app wrote may wear either name.
  ///
  /// ⛔A copy whose retirement is only waiting on a reader ([hold]) is not
  /// the staged copy any more: a save absorbed it, and what still reads it
  /// is finishing. 🪦Found as current, it was re-used as the copy of a file
  /// carried AGAIN under the same path — old bytes for the new carry — and
  /// then deleted when the reader let go, taking the only copy with it
  /// (audit 2026-09-24). A carry again under the same path is a different
  /// carry now, under a different name ([MediaAsset.carriedAs]).
  StagedMedia? find(MediaCarry carry) {
    if (_retiring(carry)) {
      return null;
    }
    for (final candidate in mediaFramedOrPlainPaths(_basePathFor(carry))) {
      final file = File(candidate);
      if (file.existsSync()) {
        return StagedMedia(
          path: candidate,
          framed: mediaEntryIsFramed(candidate),
          storedLength: file.lengthSync(),
        );
      }
    }
    return null;
  }

  /// Whether ANY carry of [poolPath] has a copy here — live, or waiting on
  /// its reader to retire.
  ///
  /// For a walk that makes pool paths of its own — a voice take's `T02`, a
  /// trimmed piece's `_2`: a path this run already gave out is not given
  /// out again while the pool has forgotten it, because an undo can bring
  /// that asset back.
  ///
  /// ⚠️Read off the names on disk, which is where the path is: every carry
  /// made at one path shares the name's front (the path's hash) and its
  /// back (the file's name) — see [mediaNameParts]. One relinked away since
  /// still counts, which is the safe side: an undo of the relink brings it
  /// back here.
  bool holdsAnyCopyOf(String poolPath) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      return false;
    }
    final (:hash, :safe) = mediaNameParts(poolPath);
    for (final entity in directory.listSync()) {
      final name = fileNameOfPath(entity.path);
      if (name.startsWith('$hash-') &&
          mediaFramedOrPlainPaths('-$safe').any(name.endsWith)) {
        return true;
      }
    }
    return false;
  }

  /// Copies [carry]'s file into the staging area, compressed when that is
  /// worth it, and answers what landed.
  ///
  /// Idempotent: a carry already staged is left alone, because the bytes
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
  Future<StagedMedia?> stage(MediaCarry carry) async =>
      (await stageCarriedBytes([carry])).firstOrNull;

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
  /// Every carry in [carries], in ONE isolate.
  ///
  /// ⚡One, not one each. A folder import can hand this hundreds of files,
  /// and an isolate costs milliseconds to start — spawning per file would
  /// have made the many-small-files case SLOWER than the synchronous
  /// version it replaces, while fixing only the one-big-file case.
  ///
  /// Answers only what actually landed: a carry that was already staged
  /// comes back as it sits, and one whose file is gone is absent rather
  /// than null-in-place, because no caller asks "which index failed".
  ///
  /// ⛔**A CARRY'S BYTES ARE TAKEN ONCE, WHEN IT IS MADE.** One whose copy
  /// waits on a reader to retire ([hold]) is not written again either:
  /// re-reading the file would put an edited original's bytes under a name
  /// that already means the old ones — the save absorbed those, and a
  /// carry made again is a new carry with a name of its own
  /// ([MediaAsset.carriedAs]). 🪦The copy in retirement used to be deleted
  /// and rewritten here, back when carrying the same path again reused its
  /// name.
  ///
  /// ⚠️The name is the law's ([[every_carry_stages_its_bytes_test]] scans
  /// the source for it). It used to be `stageAll`, with the law's name on
  /// a one-line forwarder in the session — so the file that decided an
  /// asset carried and the file that held the bytes were two hops apart,
  /// and the scan could only see the hop.
  Future<List<StagedMedia>> stageCarriedBytes(
    Iterable<MediaCarry> carries,
  ) async {
    final todo = <MediaCarry>[];
    final done = <StagedMedia>[];
    for (final carry in carries) {
      final already = find(carry);
      if (already != null) {
        done.add(already);
      } else if (!_retiring(carry) && File(carry.poolPath).existsSync()) {
        todo.add(carry);
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
          path: one.path,
          framed: one.framed,
          storedLength: one.storedLength,
        ),
      );
    }
    return done;
  }

  /// Whether [carry]'s copy is only waiting on its reader to retire.
  bool _retiring(MediaCarry carry) =>
      _retireWhenLetGo.contains(mediaCarryName(carry));

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
  /// Idempotent for the same reason the funnel is: a carry already staged
  /// keeps the bytes it has — and one in retirement is not written again
  /// ([stageCarriedBytes]), which answers null.
  ///
  /// ⚠️No isolate. A take is what a person just performed — seconds of PCM
  /// the caller is already holding — where the funnel's isolate exists for
  /// the multi-gigabyte file it must not read into this one.
  Future<StagedMedia?> stageCarriedBytesInMemory(
    MediaCarry carry,
    Uint8List bytes,
  ) async {
    final already = find(carry);
    if (already != null || _retiring(carry)) {
      return already;
    }
    Directory(directoryPath).createSync(recursive: true);
    final written = writeMediaBlob(
      basePath: _basePathFor(carry),
      length: bytes.length,
      readInto: (buffer, position, size) {
        buffer.setRange(0, size, bytes, position);
        return size;
      },
    );
    return StagedMedia(
      path: written.path,
      framed: written.framed,
      storedLength: File(written.path).lengthSync(),
    );
  }

  /// 🚨★★★**WHAT A SAVE LEAVES BEHIND, THE ROOM KEEPS** (유저 2026-09-25,
  /// board `undo-after-save-reads-the-original`: 「이번 실행의 앱 룸으로
  /// 옮겨 둔다」).
  ///
  /// A save takes out of the file every carry the pool no longer names —
  /// 09-13's 「삭제하고 저장해도 파일 크기 안 줄어든다」 — and an undo can
  /// bring that carry back. Its bytes were then nowhere but its original:
  /// edited since, or gone. So before the save writes, each entry of [left]
  /// is copied out of the file at [archivePath] into this run's room under
  /// the name it wears there, which is the name and framing its staged copy
  /// would have ([find]) — and the file still shrinks. It lives as long as
  /// the room: until this run ends, as a failed copy does.
  ///
  /// ⛔Not copied again: a copy that is here already. One a save absorbed
  /// while a reader held it is still here, retiring ([hold]) — it IS these
  /// bytes, so it stays instead.
  ///
  /// ⚠️An entry that will not copy is skipped ([ScratchFile.writeStreamed]
  /// answers null), as [stageCarriedBytes] skips a file that will not open:
  /// the save goes on, and that carry's undo reads its original, as before
  /// this. Streamed through the IO threads a block at a time — a carried
  /// movie is gigabytes, and this runs while the save window is up;
  /// [onProgress] hears each block as a fraction of everything to copy.
  Future<void> keepLeftBehind(
    String archivePath,
    List<MediaLeftBehind> left, {
    void Function(double)? onProgress,
  }) async {
    final todo = [
      for (final entry in left)
        if (!_keepIfHere(_keyOf(entry.name))) entry,
    ];
    final total = todo.fold(0, (sum, entry) => sum + entry.length);
    var copied = 0;
    for (final entry in todo) {
      await ScratchFile.writeStreamed(
        '$directoryPath/${entry.name}',
        File(archivePath)
            .openRead(entry.offset, entry.offset + entry.length)
            .map((block) {
              copied += block.length;
              onProgress?.call(copied / total);
              return block;
            }),
        length: entry.length,
      );
    }
  }

  /// Keeps the copy named [key] if it is in the room already — cancelling
  /// its retirement when it was only waiting on a reader, since the bytes a
  /// save is about to leave behind are the ones it holds — and answers
  /// whether it was.
  bool _keepIfHere(String key) =>
      _retireWhenLetGo.remove(key) ||
      mediaFramedOrPlainPaths(
        '$directoryPath/$key',
      ).any((path) => File(path).existsSync());

  /// The carry name a room file called [name] is kept under — its name less
  /// the framed suffix.
  String _keyOf(String name) => mediaEntryIsFramed(name)
      ? name.substring(0, name.length - mediaFramedEntrySuffix.length)
      : name;

  // 🪦**A RELINK USED TO RENAME THE STAGED COPY HERE** (`rename`), because
  // the name was derived from the path and had to follow it — and an undo
  // of the relink then looked for the old name and found nothing: the only
  // copy of a carry whose original was gone (audit 09-25). The name is
  // minted with the carry now ([mintMediaCarry]) and a relink keeps it, so
  // nothing here moves when a path does.

  /// Staged copies a reader holds OPEN right now ([hold]), by
  /// [mediaCarryName], and how many hold each.
  final Map<String, int> _held = {};

  /// Held copies whose retirement came while a reader had them — each goes
  /// when its last hold does.
  final Set<String> _retireWhenLetGo = {};

  /// Keeps [carry]'s staged copy where it is until the answer is called —
  /// once, after the reader has CLOSED.
  ///
  /// 🚨★★★**A READER HOLDS THE FILE OPEN, AND WINDOWS WILL NOT DELETE AN
  /// OPEN FILE.** PDFium and the OS movie decoders read a page or a frame at
  /// a time from the path for as long as the viewer shows it, and the save
  /// that absorbs a copy retires it the moment the archive has the bytes —
  /// exactly while the viewer is still showing it. A delete that threw
  /// there would fail a save whose file is already written, so the
  /// retirement waits for the reader instead ([retire]): the rule
  /// `ProjectFile.holdMediaBytes` keeps for an archive entry the in-place
  /// push-down would move, kept for the step that would take this one.
  void Function() hold(MediaCarry carry) {
    final key = mediaCarryName(carry);
    _held.update(key, (count) => count + 1, ifAbsent: () => 1);
    return () {
      final left = _held[key]! - 1;
      if (left > 0) {
        _held[key] = left;
        return;
      }
      _held.remove(key);
      if (_retireWhenLetGo.remove(key)) {
        _retireLetGo(key);
      }
    };
  }

  /// Drops the staged copy of [carry] — the save absorbed it. A copy a
  /// reader holds goes when the reader lets go ([hold]).
  ///
  /// BOTH spellings, because which one is on disk depends on whether the
  /// bytes shrank, and a save must not leave half of an absorbed import
  /// behind (유저 08-27: 「사본 남으면 진짜 용서안할게」).
  void retire(MediaCarry carry) {
    final key = mediaCarryName(carry);
    if (_held.containsKey(key)) {
      _retireWhenLetGo.add(key);
      return;
    }
    _deleteCopies(key);
  }

  /// Both spellings of the copy named [key] ([mediaCarryName]), gone —
  /// whichever is on disk depends on whether the bytes shrank.
  void _deleteCopies(String key) {
    for (final candidate in mediaFramedOrPlainPaths('$directoryPath/$key')) {
      final file = File(candidate);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  /// [retire], for a copy its last reader just let go of — inside that
  /// reader's CLOSE, which has nothing to do with a file that will not go.
  /// One the OS is still holding (an antivirus, an indexer) stays in the
  /// run's room, which takes it when the run ends ([SessionScratch]) — and
  /// no reader's close throws over it (audit 2026-09-24).
  void _retireLetGo(String key) {
    try {
      _deleteCopies(key);
    } on FileSystemException {
      // Left to the room — see above.
    }
  }

  // 🪦**THE AGE SWEEP MOVED ONTO THE ROOM, AND THEN THE AGE ITSELF WENT** —
  // see [SessionScratch.deleteFoldersOfRunsThatEnded]. It used to live here
  // as `sweepAbandoned`, and its own doc said why it had to use age: 「the
  // obvious sweep — delete anything no open project claims — cannot be
  // written safely: at launch nothing is open yet, so the live set is empty
  // and the sweep would take everything」, and 「being handed a PARTIAL live
  // set is the one mistake this class cannot make, so it is not asked for
  // one」.
  //
  // ⛔**Both halves of that still hold and neither is being taken back.**
  // What changed is that a staged file now sits in the room of the RUN that
  // staged it, and a room can be asked whether its owner is still here
  // without anybody handing over a list. The month is gone with it (유저
  // 확정 2026-09-10, reversing 「30일좋고」 of 08-26): it bought the chance
  // to tell a crash from an abandonment, and that only mattered while a
  // crashed run's staged media was going to be offered back. It is not.
  // A room whose run ended goes at the next launch, staged media and all.

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
            path: entity.path.replaceAll(r'\', '/'),
            framed: mediaEntryIsFramed(entity.path),
            storedLength: entity.lengthSync(),
          ),
    ];
  }

  // 🪦`stagedNameFor` spelled the carry's name out a second time — the same
  // hash, sanitising and token rule as the archive entry's (audit 09-25,
  // connascence). The name is [mediaCarryName] now, one function the
  // isolate in [_stageBytes] can call as well as this side.
}

/// One staged file.
@immutable
class StagedMedia {
  const StagedMedia({
    required this.path,
    required this.framed,
    required this.storedLength,
  });

  /// Where the staged bytes are.
  final String path;

  /// Whether [path] holds a framed blob rather than the file's own bytes.
  final bool framed;

  /// Bytes on disk — the framed length when [framed], the file's own
  /// otherwise.
  final int storedLength;
}

/// A media entry a save is about to leave behind, where it lies in the
/// project file — [length] bytes from [offset] — and [name], the name it
/// wears there without the folder: its carry's name, framed suffix and all
/// ([MediaStagingStore.keepLeftBehind]).
typedef MediaLeftBehind = ({String name, int offset, int length});

/// [MediaStagingStore.stageCarriedBytes]'s work, as a top-level function so
/// the isolate closure captures the carries — records of two strings — and
/// the folder, and nothing else.
///
/// ONE handle per file: `MediaFileBytes.readIntoSync` opens and closes per
/// call, which a 4GB asset at 512KB blocks would pay eight thousand times.
///
/// ⚠️A file that cannot be opened is SKIPPED, not thrown for. The batch may
/// be a whole folder, and one unreadable asset must not cost the rest their
/// bytes — the pool then simply has no staged copy for it, which is the
/// same state as never having asked.
List<({String path, bool framed, int storedLength})> _stageBytes(
  List<MediaCarry> carries,
  String directoryPath,
) {
  final out = <({String path, bool framed, int storedLength})>[];
  for (final carry in carries) {
    final RandomAccessFile handle;
    try {
      handle = File(carry.poolPath).openSync();
    } on FileSystemException {
      continue;
    }
    try {
      final written = writeMediaBlob(
        basePath: '$directoryPath/${mediaCarryName(carry)}',
        length: handle.lengthSync(),
        readInto: (buffer, position, size) {
          handle.setPositionSync(position);
          return handle.readIntoSync(buffer, 0, size);
        },
      );
      out.add((
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
