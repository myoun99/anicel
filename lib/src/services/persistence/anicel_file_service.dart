import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/project.dart';
import '../brush_frame_store.dart';
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
  const AnicelOpenResult({required this.project, required this.cels});

  final Project project;
  final Map<BrushFrameKey, AnicelCelFileRef> cels;
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

  Future<void> save({
    required Project project,
    required BrushFrameStore brushFrameStore,
    List<BrushFrameStore> auxCelStores = const [],
    required String filePath,
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

    return Isolate.run(() {
      final AnicelZipLayout layout;
      try {
        layout = parseAnicelZipLayoutFile(filePath);
      } on FormatException {
        return null; // Torn tail — compaction is the recovery.
      }
      final fileLength = File(filePath).lengthSync();
      final activeBytes = layout.entries.fold<int>(
        0,
        (sum, entry) => sum + entry.length,
      );
      if (fileLength - activeBytes > fileLength * _compactionGarbageRatio) {
        return null; // Garbage-heavy — compact instead of appending more.
      }

      final blobs = <(BrushFrameKey, String, AnicelCelBlob)>[
        for (final work in works) (work.key, work.name, work.resolveBlob()),
      ];
      final appended = appendAnicelEntries(
        path: filePath,
        newEntries: {
          'project.json': buildAnicelProjectJsonBytes(
            project: project,
            saveDirectory: saveDirectory,
          ),
          for (final (_, name, blob) in blobs) name: blob.bytes,
        },
        removeNames: removeNames,
      );
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
    });
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
    final refs = await Isolate.run(() {
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
            ),
          );
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
          }
        }(),
      );
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
    });

    // SYNC rename: existing refs into the replaced file carry offsets of
    // the OLD layout, so no event may run between the swap and the
    // caller's adoptSavedFile — sync-to-return is microtask-tight.
    temp.renameSync(filePath);
    return refs;
  }

  Future<AnicelOpenResult> open({required String filePath}) async {
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
        return (projectJsonBytes: projectJsonBytes, cels: cels);
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

    // Relative media resolution: an entry whose relative path exists next
    // to the .anicel wins (the folder traveled whole); otherwise the stored
    // absolute path stays and the existing missing-media relink flow takes
    // over.
    final directory = _parentDirectory(filePath);
    final remap = <String, String>{};
    for (final entry in mediaRelativePaths.entries) {
      final resolved = '$directory/${entry.value}';
      if (await File(resolved).exists()) {
        remap[entry.key] = resolved;
      }
    }

    return AnicelOpenResult(
      project: remapProjectMediaPaths(project, remap),
      cels: cels,
    );
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
