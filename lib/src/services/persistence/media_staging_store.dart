import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

import '../../core/path_names.dart';
import '../../models/media_asset.dart' show MediaCarry, normalizedMediaPath;
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
/// standing at the next launch is a crash, and what it holds is offered
/// back rather than swept.
///
/// 🚨**The name is DERIVED, never recorded** — the same rule the conform
/// store follows ("under a name derived by rule from the source path —
/// nothing recorded, nothing to fall out of sync"). A staged file that
/// nothing remembers cannot be remembered wrongly.
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

  /// 🚨Separators normalised HERE, once.
  ///
  /// Every method compares a path it BUILT ([pathFor]) against a path the
  /// filesystem LISTED, and on Windows those disagree the moment a caller
  /// hands in a `\`-flavoured directory — `Directory.systemTemp` does. An
  /// earlier keep-set sweep failed to match a single live file that way
  /// and deleted the lot; that sweep is gone — the room's lifetime replaced
  /// it — but [find] and [list] still stand on the same comparison, so the
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

  /// Where [carry]'s staged bytes live, framed or not.
  ///
  /// The suffix carries the same meaning it does inside the archive — see
  /// [mediaFramedEntrySuffix] — so a staged file can be streamed into the
  /// .anicel without being decoded and re-encoded on the way.
  String pathFor(MediaCarry carry, {required bool framed}) =>
      mediaPathFramed(_basePathFor(carry), framed: framed);

  String _basePathFor(MediaCarry carry) =>
      '$directoryPath/${stagedNameFor(carry)}';

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
          path: file.path.replaceAll(r'\', '/'),
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
  /// of one path shares the name's front (the path's hash) and its back
  /// (the file's name) — see [stagedNameFor].
  bool holdsAnyCopyOf(String poolPath) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      return false;
    }
    final (:front, :back) = _stagedNameEnds(poolPath);
    for (final entity in directory.listSync()) {
      final name = fileNameOfPath(entity.path.replaceAll(r'\', '/'));
      if (name.startsWith(front) &&
          mediaFramedOrPlainPaths(back).any(name.endsWith)) {
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
      _retireWhenLetGo.contains(stagedNameFor(carry));

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
  ///
  /// The carry keeps its token: a relink moves the asset, and
  /// `copyWith(path:)` keeps [MediaAsset.carriedAs] with it.
  void rename(MediaCarry from, String toPoolPath) {
    final staged = find(from);
    if (staged == null) {
      return;
    }
    final destination = pathFor(
      (poolPath: toPoolPath, token: from.token),
      framed: staged.framed,
    );
    if (destination == staged.path) {
      return;
    }
    Directory(directoryPath).createSync(recursive: true);
    // ⛔The destination is emptied first: a rename onto an existing file
    // fails on Windows, and the bytes already there belong to whatever
    // used to hold that name — which the caller has just replaced.
    final existing = File(destination);
    if (existing.existsSync()) {
      existing.deleteSync();
    }
    File(staged.path).renameSync(destination);
  }

  /// Staged copies a reader holds OPEN right now ([hold]), by
  /// [stagedNameFor], and how many hold each.
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
    final key = stagedNameFor(carry);
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
    final key = stagedNameFor(carry);
    if (_held.containsKey(key)) {
      _retireWhenLetGo.add(key);
      return;
    }
    _deleteCopies(key);
  }

  /// Both spellings of the copy named [key] ([stagedNameFor]), gone —
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

  /// The staged file's name for [carry] — derived, never recorded, and
  /// safe on every filesystem: `<path hash>-<token>-<file name>`, the token
  /// left out for the carry that has none (`''`).
  ///
  /// The file name rides behind the hash for the same reason the archive
  /// entry's does: a person looking in the folder should be able to tell
  /// what they are looking at.
  ///
  /// Public because [_stageBytes] runs in an isolate and has to derive the
  /// same name over there; a second spelling of this rule is exactly the
  /// drift the derived-name design exists to make impossible.
  static String stagedNameFor(MediaCarry carry) {
    final (:front, :back) = _stagedNameEnds(carry.poolPath);
    return carry.token.isEmpty
        ? '$front${back.substring(1)}'
        : '$front${carry.token}$back';
  }

  /// What the staged name of every carry of [poolPath] starts and ends
  /// with: the path's hash, and its file name ([holdsAnyCopyOf]).
  static ({String front, String back}) _stagedNameEnds(String poolPath) {
    final normalized = normalizedMediaPath(poolPath);
    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    final safe = fileNameOfPath(
      normalized,
    ).replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    return (
      front: '${hash.toRadixString(16).padLeft(8, '0')}-',
      back: '-$safe',
    );
  }
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
        basePath: '$directoryPath/${MediaStagingStore.stagedNameFor(carry)}',
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
