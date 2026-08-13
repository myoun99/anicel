import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/project.dart';
import '../brush_frame_store.dart';
import '../media/media_byte_source.dart';
import 'brush_drawing_binary_codec.dart';
import 'anicel_incremental_writer.dart';
import 'anicel_project_archive.dart';

/// A loaded .anicel: the project with media paths already RESOLVED (relative
/// manifest entries that exist next to the file win over the stored
/// absolute paths — the Drive-portability rule) plus every baked cel as a
/// FILE REF into the .anicel itself (R22-C): opening costs a central-
/// directory walk plus one tiny header read per cel — no pixel bytes
/// load until a cel is first shown.
class AnicelOpenResult {
  const AnicelOpenResult({
    required this.project,
    required this.cels,
    this.mediaEntryNames = const {},
    this.grants = const [],
  });

  final Project project;
  final Map<BrushFrameKey, AnicelCelFileRef> cels;

  /// Pool path → the archive entry holding that asset's bytes, for the
  /// media that travels INSIDE the project.
  ///
  /// Names, not offsets. An offset belongs to one layout and a compaction
  /// rewrites the file, so anything holding one across a save would read a
  /// window of whatever moved into those bytes — a project that opens fine
  /// and plays the wrong sound. A name survives that, and the layout is
  /// already parsed whenever the bytes are actually wanted.
  final Map<String, String> mediaEntryNames;

  /// Security-scoped tokens for the media this project REFERENCES, as
  /// written. Raw JSON: the type that understands them reaches for a
  /// `MethodChannel`, and this file is read from inside an isolate.
  ///
  /// ⚠️ NOT resolved. A bookmark only becomes usable by being handed back
  /// to the OS, and the answer may carry a different path — a bookmark
  /// follows a file that moved, which is most of why it exists.
  final List<Map<String, Object?>> grants;
}

/// One dirty cel's save payload, resolved on the UI isolate to a
/// sendable form (hot surfaces are native-backed and cannot cross).
class _CelWork {
  const _CelWork({
    required this.key,
    required this.name,
    this.hotEntry,
    this.coldBlob,
    this.refPath,
    this.refOffset = 0,
    this.refLength = 0,
  });

  final BrushFrameKey key;
  final String name;
  final AnicelCelEntry? hotEntry;
  final AnicelCelBlob? coldBlob;
  final String? refPath;
  final int refOffset;
  final int refLength;

  /// The blob to write, resolved INSIDE the save isolate: hot encodes,
  /// cold passes through, a file ref reads back — and a stale key label
  /// (rekeyed cel) re-splices the header without touching pixels.
  AnicelCelBlob resolveBlob() {
    if (hotEntry != null) {
      return AnicelCelBlob.encode(hotEntry!);
    }
    var blob = coldBlob;
    if (blob == null) {
      final raf = File(refPath!).openSync();
      try {
        raf.setPositionSync(refOffset);
        blob = AnicelCelBlob(raf.readSync(refLength));
      } finally {
        raf.closeSync();
      }
    }
    return blob.key == key ? blob : AnicelCelBlob.reKeyed(blob, key);
  }
}

/// Counts a save's entries as they land, inside the writing isolate, and
/// pushes the running fraction back out through [port].
///
/// 🔑 How anything gets out at all: `Isolate.run` hands back a value and
/// nothing else — there is no port to listen on. But the closure it sends
/// across may CAPTURE one, and a [SendPort] is sendable, so the caller
/// makes the [ReceivePort] and the isolate simply talks into the sendPort
/// it was closed over. That is the whole trick, and it is why this needed
/// no change to the writer.
///
/// The unit is one ENTRY, except that a streaming entry advances by the
/// fraction of ITSELF that has been read. One imported track can outweigh
/// every cel in the project; counted flat, the bar would run to nearly
/// full and then sit still through the only part that takes time, which
/// reads as a hang rather than as progress.
class _SaveProgress {
  _SaveProgress(this._port, this._total);

  final SendPort? _port;
  final int _total;
  int _done = 0;
  double _sent = -1;

  /// An entry is finished.
  void step() {
    _done += 1;
    _emit(_done / _total);
  }

  /// [fraction] of the entry currently streaming has been read.
  void within(double fraction) => _emit((_done + fraction) / _total);

  /// Said outright at the end rather than inferred. Zero-length assets are
  /// never read from, rounding leaves crumbs, and a bar that stops at 99%
  /// on a finished save is the exact doubt this whole window answers.
  void finish() {
    _sent = -1;
    _emit(1);
  }

  void _emit(double value) {
    final port = _port;
    if (port == null) {
      return;
    }
    final clamped = value.clamp(0.0, 1.0);
    // 256KB chunks across a large asset would otherwise put thousands of
    // messages on the port to move the label by less than one digit.
    if (clamped - _sent < 0.005 && clamped < 1) {
      return;
    }
    _sent = clamped;
    port.send(clamped);
  }
}

/// [entry] with its reads reported to [progress], and its own [step] taken
/// when the last byte is handed over.
AnicelStreamedEntry _progressed(
  AnicelStreamedEntry entry,
  _SaveProgress progress,
) {
  final length = entry.length;
  return AnicelStreamedEntry(
    name: entry.name,
    length: length,
    readInto: (buffer, position, size) {
      progress.within(length <= 0 ? 1 : position / length);
      final read = entry.readInto(buffer, position, size);
      if (position + read >= length) {
        progress.step();
      }
      return read;
    },
  );
}

/// Runs [write] with a port for it to report progress on, and closes that
/// port afterwards. With no [onProgress] there is no port and no cost.
Future<R> _reportingProgress<R>(
  void Function(double)? onProgress,
  Future<R> Function(SendPort? port) write,
) async {
  if (onProgress == null) {
    return write(null);
  }
  final receive = ReceivePort();
  receive.listen((message) {
    if (message is double) {
      onProgress(message);
    }
  });
  try {
    return await write(receive.sendPort);
  } finally {
    receive.close();
  }
}

/// Whether the snapshot at [path] is a recovery OVERLAY (holds only what
/// changed, needs its base) rather than a complete archive.
///
/// Builds before overlays wrote whole projects, and those are still found
/// and offered — the two have to be told apart before deciding what to
/// open. Cheap: a tail parse, no pixel bytes.
bool anicelSnapshotIsOverlay(String path) {
  try {
    return parseAnicelZipLayoutFile(
          path,
        ).entryNamed(AnicelFileService.recoveryStampEntry) !=
        null;
  } on Object {
    return false;
  }
}

/// Saves/loads .anicel project files (P3 / R22-C).
///
/// Two save paths:
///  - INCREMENTAL (the normal autosave/manual-save path): only cels
///    edited since the last save append to the existing file, shadowing
///    their old entries by stable name. Superseded bytes stay as garbage
///    until compaction.
///  - FULL (first save, save-as, torn tail, or garbage past
///    [_compactionGarbageRatio]): the archive rebuilds whole into a temp
///    sibling then renames over the target — atomic, and the recovery/
///    durability point of the append contract.
///
/// After every successful save the store adopts file refs for the
/// written cels, so their RAM copies can drop for free — the saved .anicel
/// IS the disk tier (no scratch/temp files, user rule).
class AnicelFileService {
  const AnicelFileService();

  /// A full rewrite is forced when shadowed/removed garbage exceeds this
  /// fraction of the file.
  static const double _compactionGarbageRatio = 0.5;

  /// The entry naming the base a recovery overlay was built against.
  /// Its presence is also what tells an overlay apart from a standalone
  /// archive, which is how snapshots written by older builds — complete
  /// projects, no base — keep opening.
  static const String recoveryStampEntry = 'recovery.json';

  /// Writes a RECOVERY OVERLAY for [baseFilePath]: only the cels edited
  /// since the last manual save, plus the project and a stamp naming the
  /// base.
  ///
  /// Small on purpose. This runs when the app is going away — a few
  /// seconds on mobile, and no promise of coming back — so it must cost
  /// what the user drew since their last save, not what the project
  /// weighs. Everything it leaves out is already in the base, unchanged.
  ///
  /// Deliberately does NOT adopt refs. Adopting would point the store at
  /// the overlay and clear the dirty set, which is exactly how the timer
  /// broke incremental saving: the next manual save could no longer find
  /// its own work in the project file. The set keeps growing until a save
  /// clears it, so each overlay is complete with respect to that save.
  Future<void> writeRecoveryOverlay({
    required Project project,
    required BrushFrameStore brushFrameStore,
    List<BrushFrameStore> auxCelStores = const [],
    required String filePath,
    required String baseFilePath,
    bool Function()? isStale,
    /// 🚨 Required in practice, though the default keeps the signature
    /// kind. The overlay's `project.json` WINS OUTRIGHT over the base
    /// file's on recovery, so anything missing here is missing from the
    /// recovered session — and a recovered session is dirty by
    /// construction, so its first save writes that absence back over the
    /// real file. Leaving grants out would make the one path built to
    /// protect unsaved work the path that destroys the permission record.
    ///
    /// ⛔ REQUIRED, and so is [mediaInArchive] below. A default is exactly
    /// what let this be forgotten — twice: the overlay shipped without
    /// grants, that was found and fixed, and then the same shape was found
    /// again for media entries. Both were data loss, and both were a
    /// parameter quietly taking its default at one call site.
    ///
    /// 🔑 The rule these two are instances of: **the overlay's
    /// `project.json` must carry everything a SAVE's would, because it
    /// replaces it outright.** `test/services/persistence/
    /// recovery_overlay_carries_everything_test.dart` states that as a
    /// property, so a third field added to the writer fails a test instead
    /// of quietly defaulting here.
    required List<Map<String, Object?>> grants,

    /// The pool paths whose bytes already live INSIDE the base file.
    ///
    /// 🚨 Same reasoning as [grants], and a worse failure. The overlay's
    /// `project.json` replaces the base file's outright, so leaving this
    /// out hands the recovered session an EMPTY `mediaEntryNames` — it no
    /// longer knows its own audio is inside the archive.
    /// `projectMediaSources` then falls back to the path the asset was
    /// imported from, and if that file is gone — which is the entire
    /// point of having carried it in — the asset is silently OMITTED from
    /// the next save, and `_saveFull` renames a media-less archive over
    /// the one that still held the bytes.
    required Set<String> mediaInArchive,
  }) async {
    final stores = [brushFrameStore, ...auxCelStores];
    final snapshots = [for (final store in stores) store.bakedSnapshotForSave()];
    final baked = (
      hot: {for (final s in snapshots) ...s.hot},
      cold: {for (final s in snapshots) ...s.cold},
      fileRefs: {for (final s in snapshots) ...s.fileRefs},
    );
    final dirty = <BrushFrameKey>{
      for (final store in stores) ...store.dirtyCelKeysSinceSave,
    };
    final works = <_CelWork>[];
    final removed = <String>[];
    for (final key in dirty) {
      final work = _workForDirtyKey(key, baked);
      if (work == null) {
        removed.add(anicelCelEntryName(key));
      } else {
        works.add(work);
      }
    }
    final stamp = anicelBaseStamp(baseFilePath);
    if (stamp == null) {
      // No stamp, no overlay. A snapshot that cannot name its base is
      // worse than none in both directions: the reader compares
      // `stamp != anicelBaseStamp(base)`, so null on both sides passes and
      // merges a delta nobody checked; and a base that was merely
      // unreadable at this moment — a cloud file locking, an Apple
      // security scope momentarily gone — would write a null stamp that
      // never matches again, which makes the project refuse to open and
      // then loses the overlay to the decline path. Skipping is the
      // honest answer; the next trigger tries again.
      return;
    }
    final saveDirectory = _parentDirectory(baseFilePath);
    final temp = File('$filePath.tmp-${DateTime.now().microsecondsSinceEpoch}');
    await temp.parent.create(recursive: true);
    final tempPath = temp.path;

    try {
      await Isolate.run(() {
        writeAnicelArchiveFile(
          path: tempPath,
          entries: () sync* {
            yield (
              name: recoveryStampEntry,
              bytes: Uint8List.fromList(
                utf8.encode(
                  jsonEncode({
                    'base': stamp,
                    // Cels the session DELETED since the save. The base
                    // still holds them, so the overlay has to say they are
                    // gone rather than merely not mention them.
                    'removed': removed,
                  }),
                ),
              ),
            );
            yield (
              name: 'project.json',
              bytes: buildAnicelProjectJsonBytes(
                project: project,
                saveDirectory: saveDirectory,
                grants: grants,
                mediaInArchive: mediaInArchive,
              ),
            );
            for (final work in works) {
              yield (name: work.name, bytes: work.resolveBlob().bytes);
            }
          }(),
        );
      });
    } on Object {
      if (temp.existsSync()) {
        temp.deleteSync();
      }
      rethrow;
    }
    // Re-asked at the LAST moment, not only on entry. A manual save can
    // start and finish while this is in the isolate, and it retires the
    // snapshot on its way out — renaming onto that path afterwards
    // recreates one for a project that was just saved cleanly, stamped
    // against the base as it was BEFORE the save. The next open would then
    // offer to recover it and throw on the mismatch, which is a project
    // that refuses to open.
    if (isStale?.call() ?? false) {
      if (temp.existsSync()) {
        temp.deleteSync();
      }
      return;
    }
    temp.renameSync(filePath);
    _sweepStaleTemps(temp.parent, keep: temp.path);
  }

  /// Removes `.tmp-<micros>` leftovers beside a snapshot.
  ///
  /// The write runs as the app is being killed, so a torn attempt is a
  /// normal outcome rather than an exceptional one — and the catch above
  /// only covers a throw, not a process that stops existing. Nothing
  /// enumerates this folder otherwise (the candidate paths are literal),
  /// and the user cannot see it to tidy it, so the next successful write
  /// takes the bodies with it.
  static void _sweepStaleTemps(Directory folder, {required String keep}) {
    try {
      for (final entity in folder.listSync()) {
        if (entity is File &&
            entity.path != keep &&
            entity.path.contains('.tmp-')) {
          entity.deleteSync();
        }
      }
    } on Object {
      // Housekeeping never fails a save.
    }
  }

  Future<void> save({
    required Project project,
    required BrushFrameStore brushFrameStore,
    List<BrushFrameStore> auxCelStores = const [],
    required String filePath,
    Map<String, MediaByteSource> mediaToStore = const {},
    /// The security-scoped tokens for referenced media, already reduced to
    /// JSON by the session — see [buildAnicelProjectJsonBytes].
    List<Map<String, Object?>> grants = const [],
    /// Called on the UI isolate with 0..1 as the write proceeds. Null costs
    /// nothing — no port is opened and the writer reports into no one.
    void Function(double)? onProgress,
  }) async {
    // Aux stores (the conte sheet ink, R5) ride the same archive: their
    // keys live in their own namespace, so the snapshots merge without
    // collision and each store adopts back exactly its own refs.
    final stores = [brushFrameStore, ...auxCelStores];
    final snapshots = [for (final store in stores) store.bakedSnapshotForSave()];
    final baked = (
      hot: {for (final s in snapshots) ...s.hot},
      cold: {for (final s in snapshots) ...s.cold},
      fileRefs: {for (final s in snapshots) ...s.fileRefs},
    );
    final dirtySets = [for (final store in stores) store.dirtyCelKeysSinceSave];
    final dirty = <BrushFrameKey>{for (final set in dirtySets) ...set};
    final saveDirectory = _parentDirectory(filePath);

    void adoptEach(Map<BrushFrameKey, AnicelCelFileRef> adopted) {
      for (var index = 0; index < stores.length; index += 1) {
        final ownKeys = <BrushFrameKey>{
          ...snapshots[index].hot.keys,
          ...snapshots[index].cold.keys,
          ...snapshots[index].fileRefs.keys,
          ...dirtySets[index],
        };
        stores[index].adoptSavedFile({
          for (final entry in adopted.entries)
            if (ownKeys.contains(entry.key)) entry.key: entry.value,
        });
      }
    }

    // Incremental soundness: the target must already exist and every cel
    // we would NOT write must already be IN that exact file (a fresh
    // ref). First saves, save-as and test-seeded stores (cold blobs with
    // no refs) all fail this and take the full path.
    final allKeys = <BrushFrameKey>{
      ...baked.hot.keys,
      ...baked.cold.keys,
      ...baked.fileRefs.keys,
    };
    final refsHere = <BrushFrameKey>{
      for (final entry in baked.fileRefs.entries)
        if (_samePath(entry.value.filePath, filePath)) entry.key,
    };
    final sound =
        File(filePath).existsSync() &&
        allKeys.every((key) => dirty.contains(key) || refsHere.contains(key));

    if (sound) {
      final adopted = await _saveIncremental(
        project: project,
        baked: baked,
        dirty: dirty,
        filePath: filePath,
        saveDirectory: saveDirectory,
        mediaToStore: mediaToStore,
        grants: grants,
        onProgress: onProgress,
      );
      if (adopted != null) {
        adoptEach(adopted);
        return;
      }
      // Torn tail or garbage over threshold → compaction below.
    }

    adoptEach(
      await _saveFull(
        project: project,
        baked: baked,
        dirty: dirty,
        filePath: filePath,
        saveDirectory: saveDirectory,
        mediaToStore: mediaToStore,
        grants: grants,
        onProgress: onProgress,
      ),
    );
  }

  /// Resolves a dirty key's current content to a [_CelWork], or null for
  /// a removed cel (its entry name must vanish from the archive).
  static _CelWork? _workForDirtyKey(
    BrushFrameKey key,
    ({
      Map<BrushFrameKey, BitmapSurface> hot,
      Map<BrushFrameKey, AnicelCelBlob> cold,
      Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
    })
    baked,
  ) {
    final name = anicelCelEntryName(key);
    final hot = baked.hot[key];
    if (hot != null) {
      return _CelWork(
        key: key,
        name: name,
        hotEntry: AnicelCelEntry.fromSurface(key, hot),
      );
    }
    final cold = baked.cold[key];
    if (cold != null) {
      return _CelWork(key: key, name: name, coldBlob: cold);
    }
    final ref = baked.fileRefs[key];
    if (ref != null) {
      // Dirty yet file-backed = a rekeyed cel: pixels unchanged, label
      // stale — the isolate re-splices the header.
      return _CelWork(
        key: key,
        name: name,
        refPath: ref.filePath,
        refOffset: ref.dataOffset,
        refLength: ref.length,
      );
    }
    return null;
  }

  /// Appends only the dirty cels (+ a superseding project.json). Returns
  /// the refs to adopt, or null when the file needs a full rewrite
  /// instead (unparseable tail, or garbage past the threshold).
  Future<Map<BrushFrameKey, AnicelCelFileRef>?> _saveIncremental({
    required Project project,
    required ({
      Map<BrushFrameKey, BitmapSurface> hot,
      Map<BrushFrameKey, AnicelCelBlob> cold,
      Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
    })
    baked,
    required Set<BrushFrameKey> dirty,
    required String filePath,
    required String saveDirectory,
    List<Map<String, Object?>> grants = const [],
    Map<String, MediaByteSource> mediaToStore = const {},
    void Function(double)? onProgress,
  }) async {
    final works = <_CelWork>[];
    final removeNames = <String>{};
    for (final key in dirty) {
      final work = _workForDirtyKey(key, baked);
      if (work == null) {
        removeNames.add(anicelCelEntryName(key));
      } else {
        works.add(work);
      }
    }

    return _reportingProgress(onProgress, (port) => Isolate.run(() {
      final AnicelZipLayout layout;
      try {
        layout = parseAnicelZipLayoutFile(filePath);
      } on FormatException {
        return null; // Torn tail — compaction is the recovery.
      }
      if (anicelNeedsCompaction(
        fileLength: File(filePath).lengthSync(),
        entries: [
          for (final entry in layout.entries)
            (name: entry.name, length: entry.length),
        ],
        garbageRatio: _compactionGarbageRatio,
      )) {
        return null; // Garbage-heavy — compact instead of appending more.
      }

      // Only what is not already in the file. Media is written once and
      // never edited, so an asset already inside is a survivor of the
      // append like any untouched cel — re-streaming it every save would
      // rewrite the project's whole media area to change one drawing.
      //
      // Resolved BEFORE the cels so the count is complete: a fraction needs
      // its denominator before the first thing it divides.
      final newMedia = [
        for (final entry in mediaToStore.entries)
          if (layout.entryNamed(anicelMediaEntryName(entry.key)) == null)
            AnicelStreamedEntry(
              name: anicelMediaEntryName(entry.key),
              length: entry.value.lengthSync(),
              readInto: entry.value.readIntoSync,
            ),
      ];
      final progress = _SaveProgress(port, 1 + works.length + newMedia.length);
      final projectJson = buildAnicelProjectJsonBytes(
        project: project,
        saveDirectory: saveDirectory,
        mediaInArchive: mediaToStore.keys.toSet(),
        grants: grants,
      );
      progress.step();
      final blobs = <(BrushFrameKey, String, AnicelCelBlob)>[];
      for (final work in works) {
        blobs.add((work.key, work.name, work.resolveBlob()));
        progress.step();
      }
      final appended = appendAnicelEntries(
        path: filePath,
        newEntries: {
          'project.json': projectJson,
          for (final (_, name, blob) in blobs) name: blob.bytes,
        },
        removeNames: removeNames,
        streamedEntries: [
          for (final entry in newMedia) _progressed(entry, progress),
        ],
      );
      progress.finish();
      return {
        for (final (key, name, blob) in blobs)
          key: AnicelCelFileRef(
            filePath: filePath,
            dataOffset: appended.entryNamed(name)!.dataOffset,
            length: blob.bytes.length,
            canvasSize: blob.canvasSize,
            tileSize: blob.tileSize,
          ),
      };
    }));
  }

  /// Full atomic rewrite (first save, save-as, compaction, recovery):
  /// clean file-backed cels stream through from their source file (which
  /// may be a DIFFERENT path on save-as), cold blobs pass through
  /// byte-identically, hot cels encode — all off the UI isolate. Returns
  /// refs into the finished file for every cel.
  Future<Map<BrushFrameKey, AnicelCelFileRef>> _saveFull({
    required Project project,
    required ({
      Map<BrushFrameKey, BitmapSurface> hot,
      Map<BrushFrameKey, AnicelCelBlob> cold,
      Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
    })
    baked,
    required Set<BrushFrameKey> dirty,
    required String filePath,
    required String saveDirectory,
    List<Map<String, Object?>> grants = const [],
    Map<String, MediaByteSource> mediaToStore = const {},
    void Function(double)? onProgress,
  }) async {
    final allKeys = <BrushFrameKey>{
      ...baked.hot.keys,
      ...baked.cold.keys,
      ...baked.fileRefs.keys,
    };
    final works = <_CelWork>[];
    for (final key in allKeys) {
      final ref = baked.fileRefs[key];
      if (ref != null && !dirty.contains(key)) {
        // Clean + file-backed: the cheapest source is the file itself
        // (no re-encode; the isolate streams the exact bytes through).
        works.add(
          _CelWork(
            key: key,
            name: anicelCelEntryName(key),
            refPath: ref.filePath,
            refOffset: ref.dataOffset,
            refLength: ref.length,
          ),
        );
      } else {
        works.add(_workForDirtyKey(key, baked)!);
      }
    }

    final temp = File('$filePath.tmp-${DateTime.now().microsecondsSinceEpoch}');
    await temp.parent.create(recursive: true);
    final tempPath = temp.path;

    // The isolate writes STRAIGHT to the temp file, one entry at a time,
    // and hands back only the refs. Building a whole-project `Uint8List`
    // here and returning it held the project twice — once built, once
    // copied across the port — before anything reached the disk, and the
    // full-save path is exactly what a backgrounding tablet runs when it
    // has the least headroom to spare.
    // A throw inside the isolate leaves the temp behind — it is created the
    // moment the write starts, before the first entry is even resolved.
    // Nothing else in the app knows the name (the suffix is a timestamp),
    // and a failing save RETRIES, so orphans would accumulate one per
    // attempt at project size each. The old builder could not leak because
    // it only touched the disk after the isolate returned.
    final Map<BrushFrameKey, AnicelCelFileRef> refs;
    try {
      refs = await _writeArchiveInIsolate(
        tempPath: tempPath,
        filePath: filePath,
        project: project,
        saveDirectory: saveDirectory,
        works: works,
        mediaToStore: mediaToStore,
        grants: grants,
        onProgress: onProgress,
      );
    } on Object {
      if (temp.existsSync()) {
        temp.deleteSync();
      }
      rethrow;
    }

    // SYNC rename: existing refs into the replaced file carry offsets of
    // the OLD layout, so no event may run between the swap and the
    // caller's adoptSavedFile — sync-to-return is microtask-tight.
    temp.renameSync(filePath);
    return refs;
  }

  /// The archive write itself, off the UI isolate. Returns only the refs —
  /// the bytes never cross the port.
  static Future<Map<BrushFrameKey, AnicelCelFileRef>> _writeArchiveInIsolate({
    required String tempPath,
    required String filePath,
    required Project project,
    required String saveDirectory,
    required List<_CelWork> works,
    required Map<String, MediaByteSource> mediaToStore,
    // Plain maps, so the closure carries values the port can copy — the
    // picker's grant type could not cross this boundary at all.
    required List<Map<String, Object?>> grants,
    void Function(double)? onProgress,
  }) {
    return _reportingProgress(onProgress, (port) => Isolate.run(() {
      final progress = _SaveProgress(
        port,
        1 + works.length + mediaToStore.length,
      );
      // Scalars only. Holding the BLOB here to read its geometry later
      // would keep every cel resident and give back exactly the memory
      // this streams to avoid.
      final geometry =
          <BrushFrameKey, ({String name, CanvasSize canvasSize, int tileSize, int length})>{};
      final layout = writeAnicelArchiveFile(
        path: tempPath,
        entries: () sync* {
          yield (
            name: 'project.json',
            bytes: buildAnicelProjectJsonBytes(
              project: project,
              saveDirectory: saveDirectory,
              mediaInArchive: mediaToStore.keys.toSet(),
              grants: grants,
            ),
          );
          progress.step();
          for (final work in works) {
            // Resolved HERE rather than up front: the generator is pulled
            // lazily, so exactly one cel is resident at a time.
            final blob = work.resolveBlob();
            geometry[work.key] = (
              name: work.name,
              canvasSize: blob.canvasSize,
              tileSize: blob.tileSize,
              length: blob.bytes.length,
            );
            yield (name: work.name, bytes: blob.bytes);
            progress.step();
          }
        }(),
        // Every asset, every time — a full rewrite has no survivors to
        // inherit from. The sources may point INTO the file being
        // replaced (a compaction) or into the one being left behind (a
        // save-as); either way the writer streams them across without
        // re-encoding, which is what makes save-as carry media without a
        // copy step of its own.
        streamedEntries: [
          for (final entry in mediaToStore.entries)
            _progressed(
              AnicelStreamedEntry(
                name: anicelMediaEntryName(entry.key),
                length: entry.value.lengthSync(),
                readInto: entry.value.readIntoSync,
              ),
              progress,
            ),
        ],
      );
      progress.finish();
      return <BrushFrameKey, AnicelCelFileRef>{
        for (final entry in geometry.entries)
          entry.key: AnicelCelFileRef(
            filePath: filePath,
            dataOffset: layout.entryNamed(entry.value.name)!.dataOffset,
            length: entry.value.length,
            canvasSize: entry.value.canvasSize,
            tileSize: entry.value.tileSize,
          ),
      };
    }));
  }

  /// Opens [filePath], optionally laying a recovery [overlayPath] over it.
  ///
  /// The overlay holds only what changed since the last save, so it is
  /// applied on top rather than opened alone: its cels win by name, its
  /// project.json wins outright, and cels it lists as removed disappear.
  ///
  /// Throws when the overlay was built against a DIFFERENT base. The whole
  /// hazard of a delta is that laying it over the wrong file produces a
  /// project that looks fine and is not, so a mismatch is refused loudly
  /// instead of being merged hopefully. An overlay with no stamp is a
  /// snapshot from a build that wrote complete archives, and opening it
  /// directly is the caller's job — not something to guess at here.
  Future<AnicelOpenResult> open({
    required String filePath,
    String? overlayPath,
  }) async {
    // Everything off the UI isolate; only the project + small refs come
    // back. No pixel bytes load here — each cel is a ~200-byte header
    // read for its key + geometry.
    final (:projectJsonBytes, :cels) = await Isolate.run(() {
      AnicelZipLayout layout;
      try {
        layout = parseAnicelZipLayoutFile(filePath);
      } on FormatException {
        // Torn tail (an append crashed mid-rewrite): reconstruct from
        // the intact local entries (R24-D1). The file stays torn on
        // disk until the next save — which the service forces down the
        // FULL path (the incremental precondition re-parses this same
        // tail and fails) — so opening is enough to heal on save.
        layout = recoverAnicelZipLayoutFile(filePath);
      }
      final projectEntry = layout.entryNamed('project.json');
      if (projectEntry == null) {
        throw const FormatException('Not an Anicel project (.anicel).');
      }
      final raf = File(filePath).openSync();
      try {
        raf.setPositionSync(projectEntry.dataOffset);
        final projectJsonBytes = raf.readSync(projectEntry.length);
        final cels = <BrushFrameKey, AnicelCelFileRef>{};
        for (final entry in layout.entries) {
          if (!entry.name.endsWith('.celz')) {
            continue;
          }
          raf.setPositionSync(entry.dataOffset);
          final headerBytes = raf.readSync(
            entry.length < 4096 ? entry.length : 4096,
          );
          final header = AnicelCelBlob(headerBytes); // Header-only parse.
          cels[header.key] = AnicelCelFileRef(
            filePath: filePath,
            dataOffset: entry.dataOffset,
            length: entry.length,
            canvasSize: header.canvasSize,
            tileSize: header.tileSize,
          );
        }
        if (overlayPath == null) {
          return (projectJsonBytes: projectJsonBytes, cels: cels);
        }
        return _applyOverlay(
          basePath: filePath,
          overlayPath: overlayPath,
          projectJsonBytes: projectJsonBytes,
          cels: cels,
        );
      } finally {
        raf.closeSync();
      }
    });

    final decoded =
        jsonDecode(utf8.decode(projectJsonBytes)) as Map<String, dynamic>;
    if ((decoded['formatVersion'] as int? ?? 0) > anicelFormatVersion) {
      throw const FormatException(
        'This project was saved by a newer Anicel.',
      );
    }
    final project = Project.fromJson(
      decoded['project'] as Map<String, dynamic>,
    );
    final mediaPathsJson = decoded['mediaPaths'];
    final mediaRelativePaths = <String, String>{
      if (mediaPathsJson is Map)
        for (final entry in mediaPathsJson.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
    };

    final mediaEntriesJson = decoded['mediaEntries'];
    final mediaEntryNames = <String, String>{
      if (mediaEntriesJson is Map)
        for (final entry in mediaEntriesJson.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
    };

    // Media resolution, INSIDE FIRST. A copy the project carries cannot be
    // moved away or renamed out from under it, so it answers before any
    // path does — and a file that happens to sit at the old location must
    // not win over the bytes that travel with the document.
    //
    // Then the relative one: an entry whose relative path exists next to
    // the .anicel wins (the folder traveled whole); otherwise the stored
    // absolute path stays and the existing missing-media relink flow takes
    // over.
    final directory = _parentDirectory(filePath);
    final remap = <String, String>{};
    for (final entry in mediaRelativePaths.entries) {
      if (mediaEntryNames.containsKey(entry.key)) {
        continue;
      }
      final resolved = '$directory/${entry.value}';
      if (await File(resolved).exists()) {
        remap[entry.key] = resolved;
      }
    }

    final grantsJson = decoded['grants'];
    return AnicelOpenResult(
      project: remapProjectMediaPaths(project, remap),
      cels: cels,
      mediaEntryNames: mediaEntryNames,
      grants: [
        if (grantsJson is List)
          for (final entry in grantsJson)
            if (entry is Map)
              {
                for (final field in entry.entries)
                  if (field.key is String) field.key as String: field.value,
              },
      ],
    );
  }

  /// Lays a recovery overlay over what the base gave, INSIDE the open
  /// isolate — the base's refs and the overlay's have to be merged before
  /// anything leaves it, or the caller would have to know which file each
  /// cel came from.
  static ({Uint8List projectJsonBytes, Map<BrushFrameKey, AnicelCelFileRef> cels})
  _applyOverlay({
    required String basePath,
    required String overlayPath,
    required Uint8List projectJsonBytes,
    required Map<BrushFrameKey, AnicelCelFileRef> cels,
  }) {
    final layout = parseAnicelZipLayoutFile(overlayPath);
    final stampEntry = layout.entryNamed(recoveryStampEntry);
    if (stampEntry == null) {
      throw const FormatException(
        'This recovery snapshot carries no base, so it cannot be laid over '
        'one. Open it directly instead.',
      );
    }
    final raf = File(overlayPath).openSync();
    try {
      raf.setPositionSync(stampEntry.dataOffset);
      final stampJson =
          jsonDecode(utf8.decode(raf.readSync(stampEntry.length)))
              as Map<String, dynamic>;
      final recorded = stampJson['base'];
      final actual = anicelBaseStamp(basePath);
      // `recorded == null` cannot happen from this app — the writer
      // refuses to make one — but a hand-edited or truncated snapshot can
      // carry it, and `null != null` would wave that through unchecked.
      if (recorded is! String || actual == null || recorded != actual) {
        // Refused rather than merged: a delta over the wrong base gives a
        // project that opens, looks right, and is not.
        throw const FormatException(
          'This recovery snapshot was made from a different version of the '
          'project, so it cannot be restored onto this one.',
        );
      }
      final removed = <String>{
        for (final name in (stampJson['removed'] as List? ?? const []))
          if (name is String) name,
      };
      cels.removeWhere((key, _) => removed.contains(anicelCelEntryName(key)));

      Uint8List? overlayProjectJson;
      for (final entry in layout.entries) {
        if (entry.name == 'project.json') {
          raf.setPositionSync(entry.dataOffset);
          overlayProjectJson = raf.readSync(entry.length);
          continue;
        }
        if (!entry.name.endsWith('.celz')) {
          continue;
        }
        raf.setPositionSync(entry.dataOffset);
        final header = AnicelCelBlob(
          raf.readSync(entry.length < 4096 ? entry.length : 4096),
        );
        cels[header.key] = AnicelCelFileRef(
          filePath: overlayPath,
          dataOffset: entry.dataOffset,
          length: entry.length,
          canvasSize: header.canvasSize,
          tileSize: header.tileSize,
        );
      }
      return (
        // The overlay's project is the newer one by construction — it was
        // written after the base and describes the session being restored.
        projectJsonBytes: overlayProjectJson ?? projectJsonBytes,
        cels: cels,
      );
    } finally {
      raf.closeSync();
    }
  }

  static String _parentDirectory(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash <= 0 ? '.' : normalized.substring(0, slash);
  }

  static bool _samePath(String a, String b) =>
      a.replaceAll('\\', '/').toLowerCase() ==
      b.replaceAll('\\', '/').toLowerCase();
}
