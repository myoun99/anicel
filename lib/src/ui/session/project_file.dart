// The .anicel this session is BOUND to: which file it is, what that file
// carries, whether memory has drifted from it, and where a pool path's
// bytes actually are right now.
//
// Its own object since round 8 (G1, 2026-09-06). It owns the state the
// save and the open both move — the path, the media entries it holds, the
// dirty flag and the file generation — so the two doors push
// facts DOWN into it and nothing has to reach sideways for them.
// [ProjectFileDoor] is the writer; this is the record.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/media_asset.dart' show MediaCarry;
import '../../models/project.dart';
import '../../services/audio/audio_conform_pipeline.dart'
    show ConformCacheLayout;
import '../../services/media/media_byte_source.dart';
import '../../services/media/project_media_sources.dart'
    show
        MediaBytesAt,
        ProjectConforms,
        mediaEntryHeld,
        mediaEntryNameIn,
        projectConformSources,
        readableAnicelLayout,
        storedMediaBytesFor;
import '../../services/persistence/anicel_file_service.dart'
    show AnicelFileService;
import '../../services/persistence/anicel_incremental_writer.dart'
    show AnicelZipLayout;
import '../../services/persistence/anicel_project_archive.dart'
    show
        anicelConformEntryNames,
        anicelMediaEntryName,
        anicelMediaEntryPrefix;
import '../../services/persistence/media_blob_codec.dart';
import '../../services/persistence/media_staging_store.dart';
import '../../services/persistence/same_file.dart'
    show namesTheSameFile;
import 'session_roles.dart';

/// The project file this session is bound to, and everything derived from
/// that binding: what the archive carries, how big those bytes are, and
/// whether the autosave tick may run.
class ProjectFile {
  ProjectFile({
    required ProjectAccess project,
    required MediaStagingStore staging,
  }) : _project = project,
       _staging = staging;

  final ProjectAccess _project;
  final MediaStagingStore _staging;

  Project _requireProject() => _project.repository.requireProject();

  String? _projectFilePath;

  /// The media entries the bound file holds, as of the last save or open.
  ///
  /// NAMES, not offsets. A compaction moves every byte in the file, so a
  /// remembered offset would read a window of whatever landed in its
  /// place — a project that opens fine and plays the wrong sound. The
  /// offset is looked up from the layout at the moment it is wanted, and
  /// the layout is already being parsed then.
  ///
  /// 🚨★★★**NAMES ONLY — NOT KEYED BY PATH.** This was pool path → entry,
  /// and so it answered「the file holds SOME carry of this path」: a file
  /// removed from the pool and carried again before a save found the old
  /// carry's entry here, and every reader and the save took the old bytes
  /// (card `recarry-after-remove-reads-the-old`). A carry is asked for by
  /// its own name ([mediaEntryHeld]).
  Set<String> _mediaInFile = const {};

  /// The carry the pool's [poolPath] asset is right now, or null when the
  /// pool points at the file or names nothing there — the first half of
  /// 「where are these bytes」, and what a reader that KEEPS an answer keys
  /// it by (the conform store, the canvas's movie rows).
  ///
  /// 🚨★★★**THE POOL AS IT IS NOW, NOT THE PATH.** One path can have been
  /// carried twice — removed, then carried again, with an undo able to bring
  /// the first back — and which carry's bytes a reader gets is the one the
  /// pool names at this moment (card `recarry-after-remove-reads-the-old`).
  /// 🪦`projectMediaCarryOf` asked the same thing with a loop of its own
  /// beside [Project.mediaAssetByPath] (audit 09-25).
  MediaCarry? mediaCarryFor(String poolPath) =>
      _requireProject().mediaAssetByPath(poolPath)?.carry;

  /// What [poolPath]'s bytes ACTUALLY occupy right now, or null when only
  /// the file on disk knows.
  ///
  /// 🚨★★★**THE SIZE SHOWN IS THE SIZE TAKEN** (유저 2026-08-30: 「파일이
  /// 보여주는 크기는 압축된 크기를 보여주는게 맞겟지? … 아무튼 실제크기」).
  /// The media pool used to read `identity.lengthBytes` — the length
  /// the file had when it was REGISTERED — which after compression is a
  /// number matching nothing: not the disk, not the project file, not the
  /// staged copy.
  ///
  /// ⛔[MediaAsset.identity] is left alone. That field answers「is this the
  /// same file?」for relink, and a compressed length would make every
  /// carried asset fail to match itself.
  ///
  /// ⚠️Cheap by construction — a stat on the staged file, or a length the
  /// archive layout already handed over. The browser draws a row per asset
  /// and must not parse a ZIP to do it, which is why the archive half is
  /// remembered at save/open rather than asked for here.
  ///
  /// ⚠️In the order every reader looks ([storedMediaBytesFor]) — the project
  /// file first — and through the same gate ([_storedFor]: the file's own
  /// record, [mediaInFile]), so the size shown is the size of the bytes that
  /// are READ. 🪦The staged copy answered first here alone; then the layout
  /// answered here while the readers asked the record (audit 09-25).
  int? mediaStoredBytesFor(String poolPath) {
    final carry = mediaCarryFor(poolPath);
    if (carry == null) {
      return null;
    }
    if (mediaEntryNameIn(_mediaInFile, carry) case final name?) {
      if (_archivedMediaBytes()[name] case final length?) {
        return length;
      }
    }
    return _staging.find(carry)?.storedLength;
  }

  /// Stored lengths of the media entries inside the project file, BY ENTRY
  /// NAME, parsed ONCE per [_fileGeneration] and kept until the next one.
  ///
  /// ⚠️Keyed on the generation rather than time: a compaction moves every
  /// byte, so a length from before one describes nothing. The generation
  /// is the thing that already changes exactly when that happens.
  Map<String, int> _archivedMediaBytes() => _archivedBytes().media;

  /// The archived lengths of the media AND of the conforms, from ONE walk
  /// of the central directory.
  ///
  /// 🚨★★★**ONE PARSE, BECAUSE THE SECOND ONE WAS FREE-LOOKING AND WAS
  /// NOT.** The conform column asks the same question about the same file,
  /// and answering it separately meant a tail parse PER ASSET — and then
  /// again every time the conform store answered, which is once per sound
  /// while a project is warming up. The media half was already careful
  /// about this; the fix was to join them rather than to be careful twice.
  ({Map<String, int> media, Map<String, int> conform}) _archivedBytes() {
    final path = _projectFilePath;
    if (path == null) {
      return (media: const {}, conform: const {});
    }
    if (_archivedBytesGeneration == _fileGeneration) {
      return (media: _mediaStoredBytes, conform: _conformArchivedBytes);
    }
    var media = const <String, int>{};
    var conform = const <String, int>{};
    // The layout a reader sees ([readableAnicelLayout]) — a torn tail's last
    // committed directory included, as the bytes that are read are. None to
    // read answers nothing rather than a wrong number; the row falls back to
    // what it always showed.
    final layout = readableAnicelLayout(path);
    if (layout != null) {
      media = {
        for (final entry in layout.entries)
          if (entry.name.startsWith(anicelMediaEntryPrefix))
            entry.name: entry.length,
      };
      final project = _requireProject();
      conform = {
        for (final asset in project.mediaAssets)
          for (final name in anicelConformEntryNames(
            asset.path,
            sampleRate: project.audioSampleRate,
            speedNumerator: project.audioSpeedNumerator,
            speedDenominator: project.audioSpeedDenominator,
          ))
            if (layout.entryNamed(name) case final found?)
              asset.path: found.length,
      };
    }
    _mediaStoredBytes = media;
    _conformArchivedBytes = conform;
    _archivedBytesGeneration = _fileGeneration;
    return (media: media, conform: conform);
  }

  Map<String, int> _mediaStoredBytes = const {};
  Map<String, int> _conformArchivedBytes = const {};
  int _archivedBytesGeneration = -1;

  /// What [poolPath]'s CONFORM occupies, or null when it has none.
  ///
  /// 🚨★★★**ASKED FOR BY NAME** (유저 2026-08-30, answering
  /// `conform-in-project`): 「가시화정책에 따라 미디어풀 패널에서 해당파일의
  /// 컨폼파일 크기 표시할것」. A conform is the biggest thing an audio asset
  /// costs — several times the sound itself — and until now it was a
  /// number only the settings dialog knew, as one lump for the whole
  /// container.
  ///
  /// The CACHE file first, the carried entry second, and they are the same
  /// bytes: whichever is present answers. A pruned cache still has a size
  /// to report, because the project is still carrying one.
  ///
  /// ⚠️Compressed size, not decoded — the same「실제크기」policy
  /// [mediaStoredBytesFor] follows, because it is the number that says
  /// what the disk lost.
  int? conformStoredBytesFor(String poolPath) {
    final base = conformPathFor(poolPath);
    if (base != null) {
      for (final candidate in mediaFramedOrPlainPaths(base)) {
        final stat = FileStat.statSync(candidate);
        if (stat.type == FileSystemEntityType.file) {
          return stat.size;
        }
      }
    }
    // ⛔Through the shared per-generation walk, NOT [carriedConformFor]:
    // that one parses the archive on the spot, which is right for a single
    // playback request and wrong for a column drawn per asset.
    return _archivedBytes().conform[poolPath];
  }

  /// [conformStoredBytesFor] for every asset that has one — the map the
  /// pool panel draws from.
  ///
  /// 🚨★★★**MEMOISED, BECAUSE A ROW MUST NOT STAT THE DISK TO DRAW
  /// ITSELF.** The panel reads this in `build`, and a panel is rebuilt for
  /// reasons that have nothing to do with the file system — which is the
  /// same reason `missingPaths` and `modifiedTimes` are handed in as maps
  /// instead of probed per row. Without this, every repaint cost two stats
  /// per asset.
  ///
  /// ⚠️Invalidated by [invalidateConformStoredBytes] on two events and
  /// they are BOTH needed: a completed save (the carried entry's length
  /// moved) and the conform store answering (a conform was just built, or
  /// dropped by [AudioConformStore.releaseDiskBacked]). Keying on the file
  /// generation alone ([_fileGeneration], what the media map does) would
  /// leave a freshly conformed sound showing nothing until the next save.
  Map<String, int> get conformStoredBytes {
    final known = _conformStoredBytes;
    if (known != null) {
      return known;
    }
    final sizes = <String, int>{};
    for (final asset in _requireProject().mediaAssets) {
      final bytes = conformStoredBytesFor(asset.path);
      if (bytes != null && bytes > 0) {
        sizes[asset.path] = bytes;
      }
    }
    return _conformStoredBytes = Map<String, int>.unmodifiable(sizes);
  }

  Map<String, int>? _conformStoredBytes;

  void invalidateConformStoredBytes() => _conformStoredBytes = null;

  /// Every carried asset's actual size, for a list that shows sizes.
  Map<String, int> get mediaStoredBytes {
    final sizes = <String, int>{};
    for (final asset in _requireProject().mediaAssets) {
      final bytes = mediaStoredBytesFor(asset.path);
      if (bytes != null) {
        sizes[asset.path] = bytes;
      }
    }
    return sizes;
  }

  /// The media entries the bound file holds ([_mediaInFile]) — what the
  /// save's walk tells a loss from an asset that was never saved.
  Set<String> get mediaInFile => Set<String>.unmodifiable(_mediaInFile);

  /// Whether the PROJECT has [poolPath]'s bytes, wherever the file on disk
  /// has got to.
  ///
  /// 🚨★★★**THIS IS WHAT「MISSING」HAS TO MEAN.** An asset whose original
  /// is gone but whose bytes the project holds is not missing — that is
  /// carrying working. Asking only about the ARCHIVE was right until 품기
  /// started staging at import: between the import and the first save the
  /// bytes are in the container and nowhere else, so a carried asset whose
  /// original the user deleted wore a "File missing — relink it" banner
  /// over a file the project had already secured.
  ///
  /// ⛔And the banner is not cosmetic. It feeds the relink hunt, whose
  /// "success" re-keys the asset to a different path — which, for bytes
  /// held under the OLD key, is how you lose them.
  ///
  /// ⚠️Cheap on purpose: a set lookup and a stat. The pool draws a row per
  /// asset and must not open the archive to do it.
  ///
  /// ⛔The bytes of the carry the pool names NOW ([mediaCarryFor]) — an
  /// earlier carry of the same path is not this asset's, and a reference
  /// has none.
  bool projectHoldsMediaBytes(String poolPath) {
    final carry = mediaCarryFor(poolPath);
    return carry != null &&
        (mediaEntryHeld(_mediaInFile, carry) || _staging.find(carry) != null);
  }

  /// Where [poolPath]'s bytes actually are RIGHT NOW — the read side of
  /// carrying. The save always knew how to stream an embedded asset
  /// forward; playback, the waveform and the existence probe kept asking
  /// the filesystem, so deleting the import original (the very act
  /// carrying exists to survive) silenced the clip and hung a "missing"
  /// banner on an asset the project owns.
  ///
  /// Resolved fresh per call, never held: offsets belong to one layout
  /// and a compaction moves every byte. The archive range carries the
  /// entry's CRC, and the conform pipeline treats a mismatch as transient
  /// — a read that raced a compaction retries against fresh offsets
  /// rather than decoding whatever moved into the window. A reader that
  /// keeps reading takes [holdMediaBytes] instead.
  MediaByteSource mediaByteSourceFor(String poolPath) =>
      _whereTheBytesAre(poolPath).source;

  /// Where [poolPath]'s bytes are ([storedMediaBytesFor] — the one order
  /// the save looks in too: the archive, then the staged copy, then the
  /// file it came from) — and how to keep the answer where it is while a
  /// reader reads it ([holdMediaBytes]), which returns the letting go. Null
  /// for the original: nothing in the app moves it.
  ///
  /// ⚠️[poolPath] is taken in the POOL's spelling ([normalizedMediaPath]):
  /// a window hands on what the OS gave it — `C:\…` on Windows — and every
  /// key here (entry names, staged copies, holds) is the pool's. 🪦Asked
  /// with the OS spelling, a carried file missed its entry and read its
  /// original, and a staged copy was held under a key the save's
  /// retirement never asked about (audit 2026-09-24).
  ///
  /// 🚨★★★**THE CARRY THE POOL NAMES NOW, NOT THE PATH** ([mediaCarryFor]).
  /// Removed and carried again before a save, one path has two carries —
  /// the old one's entry still in the file for an undo to bring back — and
  /// asked by path, the old entry answered first (card
  /// `recarry-after-remove-reads-the-old`). An asset the pool points at
  /// rather than carries reads its file, whatever an earlier carry of the
  /// same path left in the file or the store.
  _Whereabouts _whereTheBytesAre(String poolPath) {
    final carry = mediaCarryFor(poolPath);
    if (carry == null) {
      final file = MediaFileBytes(poolPath);
      return (source: file, hold: null, carry: null, stored: file);
    }
    return _whereTheCarryIs(carry);
  }

  /// Where [carry]'s bytes are — [_whereTheBytesAre] for a carry already
  /// known: what a reader following its bytes asks ([HeldMediaBytes.again]),
  /// THESE bytes whatever the pool names at their path by then.
  _Whereabouts _whereTheCarryIs(MediaCarry carry) {
    final (:stored, :at) = _storedFor(
      carry,
      () => readableAnicelLayout(_projectFilePath),
    );
    return (
      carry: carry,
      stored: stored,
      // 🚨A framed entry is decoded HERE and nowhere downstream. Every
      // consumer asked for「the bytes of this asset」and must keep getting
      // them — the block index is this layer's business, and the reader
      // still serves a window rather than the whole file.
      source: mediaSourceDecodingFrames(stored),
      hold: switch (at) {
        MediaBytesAt.archive => () => _holdEntry(
          anicelMediaEntryName(carry, framed: stored.storedIsFramed),
        ),
        MediaBytesAt.staged => () => _staging.hold(carry),
        MediaBytesAt.original => null,
      },
    );
  }

  /// [carry]'s stored bytes and where they were found
  /// ([storedMediaBytesFor]) — asked for a reader, and again after a save
  /// for the readers already holding ([_tellTheHoldersWhatMoved]). [layout]
  /// is the project file's, read only when the file holds this carry — the
  /// pool asks per row, and a carry not saved yet has nothing in there to
  /// find.
  ({MediaByteSource stored, MediaBytesAt at}) _storedFor(
    MediaCarry carry,
    AnicelZipLayout? Function() layout,
  ) => storedMediaBytesFor(
    carry,
    layout: mediaEntryHeld(_mediaInFile, carry) ? layout() : null,
    archivePath: _projectFilePath,
    staging: _staging,
  );

  /// Every hold handed out and not given back yet that has a carry — what a
  /// save asks about: to store what they read ([heldCarries]), to tell each
  /// whose bytes it moved ([HeldMediaBytes.moved]), and to wait for the ones
  /// it asked to let go ([readersLetGoOf]).
  final List<_LiveHold> _liveHolds = [];

  /// What the readers hold that is the project's own — an entry of the file
  /// or a staged copy — by carry: what a save stores beside what the pool
  /// names (`ProjectFileDoor._carryFor`).
  ///
  /// ⛔A HELD carry does not leave, even when the project no longer carries
  /// it: something reads it by offset right now — a viewer on an asset just
  /// taken out of the pool, a canvas row an undo may bring back — and
  /// leaving would make its span a hole the push-down writes over. It leaves
  /// with the first save after the reader lets go (audit 2026-09-24,
  /// `carried-bytes-audit-0924`).
  /// 🆕STORED, not merely kept (audit 09-25, `audit-0925-carry-follow`): it
  /// used to be a name the in-place save declined to drop, so a whole write
  /// — a save-as, a torn tail healed — left it behind, and the record of
  /// what the file holds ([mediaInFile]) never listed it: a reader holding
  /// it was told its bytes had moved to the ORIGINAL and followed there, and
  /// an undo that brought the asset back read the original too.
  Map<MediaCarry, MediaByteSource> get heldCarries {
    late final layout = readableAnicelLayout(_projectFilePath);
    return {
      for (final live in _liveHolds)
        if (_storedFor(live.carry, () => layout) case (
          :final stored,
          :final at,
        ) when at != MediaBytesAt.original)
          live.carry: stored,
    };
  }

  /// Tells every live hold whose carry the file just saved answers from
  /// somewhere else — the save absorbed the staged copy it reads, or wrote
  /// the file it reads somewhere new ([HeldBytesMove.elsewhere]).
  ///
  /// 🚨★★★**THE READER MOVES, NOT THE BYTES.** The staged copy is retired by
  /// the save whether or not anyone holds it; held, it only waits for its
  /// reader to let go ([MediaStagingStore.hold]) — and a reader that holds
  /// for the session (a canvas's movie row) never did, so the copy stayed on
  /// disk beside the entry that replaced it until the app quit (card
  /// `canvas-holds-staged-for-session`). Told, the reader opens again on the
  /// entry and lets the copy go.
  ///
  /// ⚠️「Somewhere else」 is the ANSWER, not the kind of place: a stored
  /// source is equal to another only where it is the same stretch of the
  /// same file, so an entry of the file a save-as left behind has moved as
  /// surely as a staged copy has.
  void _tellTheHoldersWhatMoved() {
    // Read once for every holder — a central directory per movie row per
    // save is the cost this would otherwise add to every save.
    late final layout = readableAnicelLayout(_projectFilePath);
    for (final live in _liveHolds) {
      final now = _storedFor(live.carry, () => layout).stored;
      // Told once per answer: a reader still on its way there — or one
      // that could not follow — hears again only when the answer moves on.
      if (now != live.stored && now != live.toldOf) {
        live.toldOf = now;
        live.moves.add(HeldBytesMove.elsewhere);
      }
    }
  }

  /// Asks every reader holding [filePath] open to let go of it, and waits
  /// until they have — what a whole write needs before it can replace that
  /// file (`AnicelFileService.save`'s `beforeReplacing`).
  ///
  /// 🚨★★★**THE REPLACE FAILED UNDER EVERY READER, FOR AS LONG AS IT READ.**
  /// A whole write (a torn tail healed, refs the file no longer backs) is
  /// built beside the file and renamed onto it — and Windows refuses a
  /// rename onto a file anything in this process holds open. A canvas row
  /// holds its movie for the session, so a save that had to write whole
  /// went to the failed copy for as long as the row was there (card
  /// `rewrite-under-offset-readers`). The session's own cel handle already
  /// lets go first ([AnicelFileService.renameWithRetry]); this is the same
  /// for the readers, told [HeldBytesMove.replacing] — and each opens again
  /// once the save has ended, because the next hold waits for it
  /// ([holdMediaBytes]).
  ///
  /// ⚠️Bounded by [lettingGoAtMost]: a reader that does not follow its hold
  /// (a placement mid-render, the import window's preview) never lets go on
  /// being asked, and a save must not wait on it forever. Past the bound the
  /// replace is tried anyway, and meets the refusal it always met.
  Future<void> readersLetGoOf(String filePath) async {
    final holding = [
      for (final live in _liveHolds)
        if (live.stored.span?.path case final path?
            when namesTheSameFile(path, filePath))
          live,
    ];
    // Every one of them, told before or not: one that could not follow an
    // earlier move still holds this file.
    for (final live in holding) {
      live.moves.add(HeldBytesMove.replacing);
    }
    await Future.wait([
      for (final live in holding) live.released.future,
    ]).timeout(lettingGoAtMost, onTimeout: () => const []);
  }

  /// How long a save waits for the readers it asked to let go
  /// ([readersLetGoOf]). A reader that follows lets go within a decoder's
  /// round trip; one that does not, never. A test that must see the letting
  /// go rather than the bound sets it past its own timeout.
  @visibleForTesting
  static Duration lettingGoAtMost = const Duration(seconds: 2);

  /// Entries a reader holds by OFFSET right now ([holdMediaBytes]), and
  /// how many hold each.
  final Map<String, int> _heldEntries = {};

  /// The archive entries [holdMediaBytes] has handed out and not had back —
  /// what a save that packs the file in place must leave where it is.
  Set<String> get heldArchiveEntries => {..._heldEntries.keys};

  /// [poolPath]'s bytes — the answer [mediaByteSourceFor] gives — HELD until
  /// `release`: while held, no save moves or removes them.
  ///
  /// 🚨★★★**FOR A READER THAT KEEPS READING** — a document the viewer holds
  /// open: a movie the OS decoder reads by offset frame after frame, a PDF
  /// read a page at a time. [mediaByteSourceFor] is resolved per call and
  /// held by no one; a document is held by definition. Three steps of a
  /// save would pull bytes from under it, and each answer is kept from its
  /// own:
  ///  * an archive entry from the IN-PLACE push-down (since 2026-09-23 live
  ///    bytes slide down, and the next round writes over where they were —
  ///    where a save used to write a new file beside the old one, which an
  ///    open reader went on reading untouched) — [heldArchiveEntries];
  ///  * a staged copy from the retirement that follows its absorption —
  ///    [MediaStagingStore.hold];
  ///  * the file itself from a WHOLE write that replaces it — the reader is
  ///    asked to let go first, and holds again once the save has ended
  ///    ([readersLetGoOf], [HeldBytesMove.replacing]).
  /// And whatever a reader holds, the save stores ([heldCarries]). The
  /// original is the user's file, and nothing here moves it.
  ///
  /// ⚠️Waits out a save already running: it may be moving these very bytes,
  /// and a range read off the directory it is about to supersede would be
  /// the stale offset this exists to prevent.
  ///
  /// `release` is idempotent — call it once the reader has CLOSED, not
  /// when it decides to.
  Future<HeldMediaBytes> holdMediaBytes(String poolPath) =>
      _hold(() => _whereTheBytesAre(poolPath));

  /// [where]'s bytes, held — [holdMediaBytes] for any answer, and what
  /// [HeldMediaBytes.again] asks again.
  Future<HeldMediaBytes> _hold(_Whereabouts Function() where) async {
    // The wait and the hold in ONE step ([_saveEnded]): a save that
    // woke on the same completion must not begin between them, or it moves
    // what this is about to hold without having counted it.
    while (_saveInFlight) {
      await _saveEnded.future;
    }
    final whereabouts = where();
    final (:source, :hold, :carry, :stored) = whereabouts;
    final letGo = hold?.call();
    // A file the pool points at is not the project's to move: nothing
    // follows it.
    final live = carry == null ? null : _LiveHold(carry, stored);
    if (live != null) {
      _liveHolds.add(live);
    }
    var released = false;
    return HeldMediaBytes(
      source: source,
      release: () {
        if (released) {
          return;
        }
        released = true;
        _liveHolds.remove(live);
        letGo?.call();
        live?.released.complete();
        unawaited(live?.moves.close());
      },
      moved: live?.moves.stream ?? const Stream<HeldBytesMove>.empty(),
      again: carry == null
          ? () => _hold(() => whereabouts)
          : () => _hold(() => _whereTheCarryIs(carry)),
    );
  }

  /// Keeps archive entry [name] where it is until the answer is called —
  /// what [heldArchiveEntries] reports to a save that packs in place.
  void Function() _holdEntry(String name) {
    _heldEntries.update(name, (count) => count + 1, ifAbsent: () => 1);
    return () {
      final left = _heldEntries[name]! - 1;
      if (left == 0) {
        _heldEntries.remove(name);
      } else {
        _heldEntries[name] = left;
      }
    };
  }

  /// Resolved per call rather than cached: the cache root is a live
  /// setting and the project's rate and speed are live settings too, so a
  /// conform path held from before any of them would name a file nothing
  /// writes to.
  ///
  /// Never null now. It used to be, for a project with no path — the cache
  /// was named after the project, so an unsaved one had no name to cache
  /// under and re-decoded its audio every launch. Keying by source removed
  /// the question.
  String? conformPathFor(String sourcePath) {
    final project = _requireProject();
    return ConformCacheLayout.forAudio(
      sampleRate: project.audioSampleRate,
      speedNumerator: project.audioSpeedNumerator,
      speedDenominator: project.audioSpeedDenominator,
    ).conformPathFor(sourcePath);
  }

  /// What a save should do about conforms — the bytes to write and the
  /// entry names this project may hold — at the CURRENT audio settings.
  ///
  /// ⚠️Resolved fresh at every save, like the media sources beside it: the
  /// archive half is a byte range, and offsets belong to one layout.
  ProjectConforms conformsToStore() {
    final project = _requireProject();
    return projectConformSources(
      project: project,
      conformBasePathFor: conformPathFor,
      projectFilePath: _projectFilePath,
      sampleRate: project.audioSampleRate,
      speedNumerator: project.audioSpeedNumerator,
      speedDenominator: project.audioSpeedDenominator,
    );
  }

  /// The conform this project CARRIES for [sourcePath], as a range inside
  /// the `.anicel`, or null when it carries none.
  ///
  /// 🚨★★★**WHAT `conform-in-project` = always BUYS** (유저 2026-08-30).
  /// Open the project on another machine, or after the cache was emptied,
  /// and the pipeline copies this out instead of decoding and resampling
  /// every sound first. An hour of dialogue is the difference between
  /// playing now and playing after a full pass over 55MB of compressed
  /// audio.
  ///
  /// ⚠️Resolved per call and never held — the same rule
  /// [mediaByteSourceFor] follows: a compaction moves every byte, and a
  /// range kept from before would read whatever landed on those offsets.
  ///
  /// ⛔The entry name is DERIVED, not recorded: the path and the settings
  /// say it, and both spellings are asked. Media keeps a record of its names
  /// ([mediaInFile]) because a carry's name is its own
  /// ([MediaAsset.carriedAs]), not its path's; a conform has no such thing,
  /// and a second record would be a second thing to keep in step.
  ///
  /// A torn tail is read the way every reader reads it
  /// ([readableAnicelLayout]); nothing readable, and the decode still works
  /// — which is the entire fallback this optimisation stands on.
  MediaByteSource? carriedConformFor(String sourcePath) {
    final archivePath = _projectFilePath;
    final layout = readableAnicelLayout(archivePath);
    if (archivePath == null || layout == null) {
      return null;
    }
    final project = _requireProject();
    // Only the names the CURRENT settings produce. A conform carried at
    // another rate is not a conform for this project any more, and the
    // next save is what takes it away.
    for (final name in anicelConformEntryNames(
      sourcePath,
      sampleRate: project.audioSampleRate,
      speedNumerator: project.audioSpeedNumerator,
      speedDenominator: project.audioSpeedDenominator,
    )) {
      if (layout.entryNamed(name) case final entry?) {
        return MediaArchiveBytes.ofEntry(
          archivePath: archivePath,
          entry: entry,
        );
      }
    }
    return null;
  }

  /// The open project's file path; null until first saved/opened (Save
  /// falls back to Save As).
  String? get path => _projectFilePath;

  /// Whether this project HAS a file on disk and that file is gone.
  ///
  /// 🚨A clean cel lives as a ref into the project file — the store drops
  /// its cold blob on adoption — so the file disappearing puts those
  /// pixels out of reach of every future read. Two doors ask: the notice
  /// on resume, while the FILE can still be restored from a trash, and
  /// [ensureUnsavedWorkSettled], because closing the app is the last
  /// moment a session that is still holding the file can write them out.
  ///
  /// ⛔False for a never-saved project. There is no file to have lost, and
  /// a session with nothing on disk is the ordinary state.
  bool hasVanished() {
    final path = _projectFilePath;
    return path != null && !File(path).existsSync();
  }

  /// Every edit this session has made — [markDirty] counts one per history
  /// change.
  int _edits = 0;

  /// [_edits] as of the state a file holds — or [_noFileHoldsIt].
  ///
  /// 🚨★★★**UNSAVED IS A COMPARISON, NOT A FLAG** (F-128, 2026-09-15 — 유저:
  /// 「닫으려고 할때 편집한게 있으니 저장하라는 메시지가 언제부턴가 안뜸 …
  /// 최대한 규칙 단순화」). It was a bool that a save cleared at its END, so
  /// an edit that landed while the save was still writing — the autosave
  /// tick has no window, so nothing stops the pen — was marked and then
  /// un-marked: in no file, flagged nowhere, and the close asked nothing.
  /// A save now says which edits its file holds ([bindToSavedFile]'s
  /// `cleanAsOf`, captured before the save reads the project), so an edit
  /// after that count stays unsaved by construction — there is no clear
  /// left to put in the wrong place.
  int _editsInFile = 0;

  /// No count matches it: memory already differs from every file.
  static const int _noFileHoldsIt = -1;

  /// Whether this session holds edits no file has (autosave, the close
  /// gate, the title dots).
  bool get hasUnsavedChanges => _edits != _editsInFile;

  /// The count a save captures before it reads the project, and hands back
  /// as [bindToSavedFile]'s `cleanAsOf`.
  int get editCount => _edits;

  void markDirty() {
    _edits += 1;
  }

  /// True while a manual save is running, so the autosave tick stands down
  /// instead of racing it. Read through [autosaveShouldStandDown].
  bool _saveInFlight = false;

  /// Completes when the save in flight ends — what a writer and a hold wait
  /// on, each inside the step it acts in ([beginSaveWhenSettled],
  /// [holdMediaBytes]): two callers woken by the same save both find it
  /// over, and an `await` between the wait and the act lets the other one
  /// act first. 🪦`saveSettled` waited alone, and nothing called it once
  /// both did it this way (a0db20fa1).
  Completer<void> _saveEnded = Completer<void>()..complete();

  /// Raised for the WHOLE save, retirement included — see
  /// [ProjectFileDoor.saveProjectToFile], which says why the window has to
  /// be that wide. A writer raises it through [beginSaveWhenSettled].
  void beginSave() {
    _saveInFlight = true;
    _saveEnded = Completer<void>();
  }

  /// Waits out a save in flight and raises the flag for this one — IN ONE
  /// STEP, so two writers never run at once.
  ///
  /// 🚨★★★**THE CLOCK STOOD DOWN FOR A PERSON, AND A PERSON DID NOT STAND
  /// DOWN FOR THE CLOCK.** The tick skips while a save runs
  /// ([autosaveShouldStandDown]); a press of Save during a tick's save went
  /// straight in and started a SECOND writer appending to the same file —
  /// the torn tail the flag exists to prevent — and swapped the completer
  /// every waiter was waiting on. A save that carries a big movie runs for
  /// tens of seconds, which is plenty of time to press it (audit
  /// 2026-09-24, card `carried-bytes-audit-0924` ⑤).
  Future<void> beginSaveWhenSettled() async {
    while (_saveInFlight) {
      await _saveEnded.future;
    }
    beginSave();
  }

  void endSave() {
    _saveInFlight = false;
    if (!_saveEnded.isCompleted) {
      _saveEnded.complete();
    }
  }

  /// Bumped each time the bound file becomes a different set of bytes — a
  /// save COMPLETES, or another file is OPENED — the cache key for anything
  /// read out of the archive on disk ([_archivedBytes]).
  ///
  /// ⚠️Not a stand-in for [_saveInFlight], which is a point-in-time flag.
  /// This one only ever goes up, so a reader that captured it can tell
  /// whether the file it measured is still the file it measured.
  ///
  /// 🪦Bumped by saves alone, it kept the sizes of the LAST project's file
  /// after an open: the pool of the project just opened showed none, or
  /// another file's (found with `recarry-after-remove-reads-the-old`).
  int _fileGeneration = 0;

  /// Whether the autosave tick should do nothing right now: a save is
  /// already mid-flight, or the user threw this session's work away.
  ///
  /// 🪦A third term stood here — 「the session was recovered, so its refs
  /// point INTO a sidecar」 — and went with the sidecars themselves.
  bool get autosaveShouldStandDown => _saveInFlight || _discardedUnsavedWork;

  /// The user threw this session's unsaved work away (closed without
  /// saving), so nothing may write it back out on the way down.
  ///
  /// 🚨★★★**AND THAT IS NOW THE OFF POSITION OF A SWITCH, NOT A LAW OF THE
  /// APP.** With autosave ON the project file has been following the work
  /// every n minutes, so「저장 안 하고 닫기」keeps whatever the last tick
  /// wrote; with it OFF the discard is literal (유저 2026-09-07: 「기존
  /// 결정대로 자동저장이 파일갱신 … 그게 싫으면 자동저장 off하면된다」).
  ///
  /// 🪦It used to DELETE a sidecar as well, at each of the three moments
  /// unsaved work stopped existing, because a surviving one was the whole
  /// signal recovery read. Nothing writes one any more.
  ///
  /// Recorded even though there is nothing to delete: the shutdown that
  /// follows delivers the same lifecycle callbacks any close does, and
  /// without this flag a tick could fire on the way down and save the very
  /// work the user just discarded.
  void discardUnsavedWork() {
    _discardedUnsavedWork = true;
  }

  /// True once the user has closed without saving. The session is on its
  /// way out; nothing may save it again.
  bool _discardedUnsavedWork = false;

  /// [filePath] IS the project now, holding the media entries [mediaInFile]
  /// and every edit up to [cleanAsOf] — the tail BOTH writers share: the
  /// direct save and the picker-placed archive that is adopted without a
  /// second write.
  ///
  /// ⛔They used to state it twice, line for line, which is a copy by
  /// connascence even where the text drifted: one of them growing a step
  /// the other missed is a project that comes back holding the wrong
  /// media.
  ///
  /// ⚠️[cleanAsOf] is the [editCount] the writer captured BEFORE it read the
  /// project. An edit that lands after may or may not have made it into the
  /// bytes; either way it stays unsaved, which costs a question at most.
  void bindToSavedFile(
    String filePath, {
    required Set<String> mediaInFile,
    required int cleanAsOf,
  }) {
    _mediaInFile = mediaInFile;
    _projectFilePath = filePath;
    _editsInFile = cleanAsOf;
    _forgetFailedCopy();
    _fileGeneration += 1;
    invalidateConformStoredBytes();
    // A save is the session saying it is worth keeping after all; whatever
    // was discarded before it is not this session's state any more.
    _discardedUnsavedWork = false;
    // No conform refresh here any more. It existed because a take MOVED
    // into the project on first save, which changed the path a conform is
    // keyed by; takes stay put now, and the cache is keyed by source
    // rather than by anything the project owns, so a save moves nothing a
    // conform depends on.
    //
    // The readers are another matter: the file answers for what the save
    // absorbed now, and a reader still on a staged copy follows it.
    _tellTheHoldersWhatMoved();
  }

  /// The session is bound to [filePath], which was just OPENED: it holds
  /// the media entries [mediaInFile], and [unsaved] says whether memory
  /// already differs from the file.
  ///
  /// ⚠️Called AFTER the load has cleared the history. `clear()` runs the
  /// dirty listener, so a session that set [unsaved] any earlier would
  /// have it overwritten by its own reset.
  void bindToOpenedFile(
    String filePath, {
    required Set<String> mediaInFile,
    required bool unsaved,
  }) {
    _mediaInFile = mediaInFile;
    _projectFilePath = filePath;
    _fileGeneration += 1;
    invalidateConformStoredBytes();
    // A different project is a different session; a discard that belonged
    // to the last one must not silence this one's autosave.
    _discardedUnsavedWork = false;
    _editsInFile = unsaved ? _noFileHoldsIt : _edits;
    _forgetFailedCopy();
  }

  /// This session is bound to NO file — what an imported project is until
  /// it is saved for the first time.
  void unbind() {
    _projectFilePath = null;
    _discardedUnsavedWork = false;
    _forgetFailedCopy();
  }

  /// This binding's FAILED COPY (실패본): the file in this run's room its
  /// saves have gone to since its project file refused one — or null.
  ///
  /// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file, after Q2):
  /// 「실패하면 앱컨테이너에 같은파일로 계속 증분저장?」 — ONE file, which
  /// every later save the file will not take goes on appending to.
  ///
  /// ⚠️A fact about the BINDING, so the three moments a binding changes
  /// (a save the file took, an open, an unbind) let go of it here, in one
  /// place — the copy itself stays in the room, and on the list a backup
  /// reads, until the run ends.
  String? get failedCopy => _failedCopy;
  String? _failedCopy;

  /// The edit count [failedCopy] was written at.
  int? _failedCopyEdits;

  /// Whether [failedCopy] holds every edit there is — nothing new for the
  /// clock to put in it.
  bool get failedCopyIsCurrent =>
      _failedCopy != null && _failedCopyEdits == _edits;

  /// The work as of [asOf] edits went into [copy] rather than the project
  /// file.
  void keptInFailedCopy(String copy, {required int asOf}) {
    _failedCopy = copy;
    _failedCopyEdits = asOf;
  }

  void _forgetFailedCopy() {
    _failedCopy = null;
    _failedCopyEdits = null;
  }
}

/// Where a medium's bytes are, how to keep them there while they are read,
/// and whose they are ([ProjectFile._whereTheBytesAre]).
typedef _Whereabouts = ({
  MediaByteSource source,
  void Function() Function()? hold,
  MediaCarry? carry,
  MediaByteSource stored,
});

/// A hold handed out and not given back yet, that has a carry
/// ([ProjectFile.holdMediaBytes]) — what a save stores, tells when its bytes
/// move, and waits for when it must replace their file.
final class _LiveHold {
  _LiveHold(this.carry, this.stored);

  final MediaCarry carry;

  /// The answer the hold was given.
  final MediaByteSource stored;

  /// The answer it was last told its bytes moved to — so a save that finds
  /// them still there does not tell it again.
  MediaByteSource? toldOf;

  /// [HeldMediaBytes.moved]. ONE listener, the reader — and what is told
  /// before it listens waits for it: a movie opens slowly enough for a save
  /// to bind in between.
  final moves = StreamController<HeldBytesMove>();

  final released = Completer<void>();
}
