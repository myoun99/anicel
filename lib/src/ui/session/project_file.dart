// The .anicel this session is BOUND to: which file it is, what that file
// carries, whether memory has drifted from it, and where a pool path's
// bytes actually are right now.
//
// Its own object since round 8 (G1, 2026-09-06). It owns the state the
// save and the open both move — the path, the carried entry names, the
// dirty flag and the completed-save generation — so the two doors push
// facts DOWN into it and nothing has to reach sideways for them.
// [ProjectFileDoor] is the writer; this is the record.

import 'dart:async';
import 'dart:io';

import '../../models/project.dart';
import '../../services/audio/audio_conform_pipeline.dart'
    show ConformCacheLayout;
import '../../services/media/media_byte_source.dart';
import '../../services/media/project_media_sources.dart'
    show ProjectConforms, projectConformSources;
import '../../services/persistence/anicel_incremental_writer.dart'
    show parseAnicelZipLayoutFile;
import '../../services/persistence/anicel_project_archive.dart'
    show anicelConformEntryNames;
import '../../services/persistence/media_blob_codec.dart';
import '../../services/persistence/media_staging_store.dart';
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

  /// Pool path → archive entry, for the media this project carries.
  ///
  /// NAMES, not offsets. A compaction moves every byte in the file, so a
  /// remembered offset would read a window of whatever landed in its
  /// place — a project that opens fine and plays the wrong sound. The
  /// offset is looked up from the layout at the moment it is wanted, and
  /// the layout is already being parsed then.
  Map<String, String> _mediaEntryNames = const {};

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
  int? mediaStoredBytesFor(String poolPath) {
    final staged = _staging.find(poolPath);
    if (staged != null) {
      return staged.storedLength;
    }
    return _archivedMediaBytes()[poolPath];
  }

  /// Stored lengths for the media inside the project file, parsed ONCE per
  /// completed save and kept until the next one.
  ///
  /// ⚠️Keyed on [_completedSaveGeneration] rather than time: a compaction
  /// moves every byte, so a length from before one describes nothing. The
  /// generation is the thing that already changes exactly when that
  /// happens.
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
    if (_archivedBytesGeneration == _completedSaveGeneration) {
      return (media: _mediaStoredBytes, conform: _conformArchivedBytes);
    }
    var media = const <String, int>{};
    var conform = const <String, int>{};
    try {
      final layout = parseAnicelZipLayoutFile(path);
      media = {
        for (final entry in _mediaEntryNames.entries)
          if (layout.entryNamed(entry.value) case final found?)
            entry.key: found.length,
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
    } on Object {
      // A torn or momentarily unreadable archive answers nothing rather
      // than a wrong number; the row falls back to what it always showed.
    }
    _mediaStoredBytes = media;
    _conformArchivedBytes = conform;
    _archivedBytesGeneration = _completedSaveGeneration;
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
  /// dropped by [AudioConformStore.releaseDiskBacked]). Keying on the save
  /// generation alone — what the media map does — would leave a freshly
  /// conformed sound showing nothing until the next save.
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

  /// What the project carries, for tests and for anything that needs to
  /// resolve an asset's bytes without going through a save.
  Map<String, String> get mediaEntryNames =>
      Map<String, String>.unmodifiable(_mediaEntryNames);

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
  /// ⚠️Cheap on purpose: a map lookup and a stat. The pool draws a row per
  /// asset and must not open the archive to do it.
  bool projectHoldsMediaBytes(String poolPath) =>
      _mediaEntryNames.containsKey(poolPath) || _staging.find(poolPath) != null;

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

  /// THE order a medium's bytes are looked for in — the archive, then the
  /// staged copy, then the file it came from — and how to keep the answer
  /// where it is while a reader reads it ([holdMediaBytes]), which returns
  /// the letting go. Null for the original: nothing in the app moves it.
  ({MediaByteSource source, void Function() Function()? hold})
  _whereTheBytesAre(String poolPath) {
    final entryName = _mediaEntryNames[poolPath];
    final archivePath = _projectFilePath;
    if (entryName != null && archivePath != null) {
      try {
        final entry = parseAnicelZipLayoutFile(
          archivePath,
        ).entryNamed(entryName);
        if (entry != null) {
          final range = MediaArchiveBytes.ofEntry(
            archivePath: archivePath,
            entry: entry,
          );
          // 🚨A framed entry is decoded HERE and nowhere downstream. Every
          // consumer asked for「the bytes of this asset」and must keep
          // getting them — the block index is this layer's business, and
          // the reader still serves a window rather than the whole file.
          return (
            source: mediaSourceDecodingFrames(range),
            hold: () => _holdEntry(entryName),
          );
        }
      } on Object {
        // A torn or momentarily unreadable archive: the file fallback
        // below still answers for assets whose original survives, and the
        // conform store's transient handling covers the rest.
      }
    }
    // ⚠️Not in the archive yet — but 품기 may have staged it, and after an
    // import that is the only place its bytes are.
    final staged = _staging.find(poolPath);
    if (staged != null) {
      // Through [mediaAppFileSource] rather than assembling the pair here:
      // framed-or-not is written into the name, and one place reads it.
      return (
        source: mediaAppFileSource(staged.path),
        hold: () => _staging.hold(poolPath),
      );
    }
    return (source: MediaFileBytes(poolPath), hold: null);
  }

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
  /// held by no one; a document is held by definition. Two steps of a save
  /// would pull bytes from under it, and each answer is kept from its own:
  ///  * an archive entry from the IN-PLACE push-down (since 2026-09-23 live
  ///    bytes slide down, and the next round writes over where they were —
  ///    where a save used to write a new file beside the old one, which an
  ///    open reader went on reading untouched) — [heldArchiveEntries];
  ///  * a staged copy from the retirement that follows its absorption —
  ///    [MediaStagingStore.hold].
  /// The original is the user's file, and nothing here moves it.
  ///
  /// ⚠️Waits out a save already running: it may be moving these very bytes,
  /// and a range read off the directory it is about to supersede would be
  /// the stale offset this exists to prevent.
  ///
  /// `release` is idempotent — call it once the reader has CLOSED, not
  /// when it decides to.
  Future<HeldMediaBytes> holdMediaBytes(String poolPath) async {
    await saveSettled();
    final (:source, :hold) = _whereTheBytesAre(poolPath);
    final letGo = hold?.call();
    var released = false;
    return (
      source: source,
      release: () {
        if (released) {
          return;
        }
        released = true;
        letGo?.call();
      },
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
  /// ⛔The entry name is DERIVED, not recorded. Media records its entry
  /// names because an old project may have been written under a different
  /// rule; a conform is younger than that problem, and recording a second
  /// map would be a second thing to keep in step.
  MediaByteSource? carriedConformFor(String sourcePath) {
    final archivePath = _projectFilePath;
    if (archivePath == null) {
      return null;
    }
    final project = _requireProject();
    try {
      final layout = parseAnicelZipLayoutFile(archivePath);
      // Only the names the CURRENT settings produce. A conform carried at
      // another rate is not a conform for this project any more, and the
      // next save is what takes it away.
      for (final name in anicelConformEntryNames(
        sourcePath,
        sampleRate: project.audioSampleRate,
        speedNumerator: project.audioSpeedNumerator,
        speedDenominator: project.audioSpeedDenominator,
      )) {
        final entry = layout.entryNamed(name);
        if (entry != null) {
          return MediaArchiveBytes.ofEntry(
            archivePath: archivePath,
            entry: entry,
          );
        }
      }
    } on Object {
      // A torn or momentarily unreadable archive: the decode below still
      // works, which is the entire fallback this optimisation stands on.
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

  /// Completes when the save in flight ends — what [saveSettled] waits on.
  Completer<void> _saveEnded = Completer<void>()..complete();

  /// Waits out a save in flight, and the next if one starts in between —
  /// what a reader of an archive a save may be writing does first: a range
  /// held for a document ([holdMediaBytes]), a failed copy backed up.
  Future<void> saveSettled() async {
    while (_saveInFlight) {
      await _saveEnded.future;
    }
  }

  /// Raised for the WHOLE save, retirement included — see
  /// [ProjectFileDoor.saveProjectToFile], which is the only caller and
  /// says why the window has to be that wide.
  void beginSave() {
    _saveInFlight = true;
    _saveEnded = Completer<void>();
  }

  void endSave() {
    _saveInFlight = false;
    if (!_saveEnded.isCompleted) {
      _saveEnded.complete();
    }
  }

  /// Bumped each time a save COMPLETES — the cache key for anything read
  /// out of the archive on disk ([_archivedBytes]).
  ///
  /// ⚠️Not a stand-in for [_saveInFlight], which is a point-in-time flag.
  /// This one only ever goes up, so a reader that captured it can tell
  /// whether the file it measured is still the file it measured.
  int _completedSaveGeneration = 0;

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

  /// [filePath] IS the project now, carrying [entryNames] and every edit up
  /// to [cleanAsOf] — the tail BOTH writers share: the direct save and the
  /// picker-placed archive that is adopted without a second write.
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
    required Map<String, String> entryNames,
    required int cleanAsOf,
  }) {
    _mediaEntryNames = entryNames;
    _projectFilePath = filePath;
    _editsInFile = cleanAsOf;
    _forgetFailedCopy();
    _completedSaveGeneration += 1;
    invalidateConformStoredBytes();
    // A save is the session saying it is worth keeping after all; whatever
    // was discarded before it is not this session's state any more.
    _discardedUnsavedWork = false;
    // No conform refresh here any more. It existed because a take MOVED
    // into the project on first save, which changed the path a conform is
    // keyed by; takes stay put now, and the cache is keyed by source
    // rather than by anything the project owns, so a save moves nothing a
    // conform depends on.
  }

  /// The session is bound to [filePath], which was just OPENED: it carries
  /// [entryNames], and [unsaved] says whether memory already differs from
  /// the file.
  ///
  /// ⚠️Called AFTER the load has cleared the history. `clear()` runs the
  /// dirty listener, so a session that set [unsaved] any earlier would
  /// have it overwritten by its own reset.
  void bindToOpenedFile(
    String filePath, {
    required Map<String, String> entryNames,
    required bool unsaved,
  }) {
    _mediaEntryNames = entryNames;
    _projectFilePath = filePath;
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
