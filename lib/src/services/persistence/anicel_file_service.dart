import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/media_asset.dart' show MediaCarry;
import '../../models/project.dart';
import '../brush_frame_store.dart';
import '../media/media_byte_source.dart';
import '../media/project_media_sources.dart'
    show ProjectConforms, mediaEntryNamesFor;
import 'brush_drawing_binary_codec.dart';
import 'anicel_incremental_writer.dart';
import 'open_project_file.dart';
import 'same_file.dart';
import 'save_failure.dart' show SaveNotSwappedIn;
import 'scratch_file.dart';
import 'session_scratch.dart';
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
    this.session = AnicelOpenedSessionFields.none,
  });

  /// What the file carried beside the project — its fingerprints already
  /// remapped to wherever the references actually resolved.
  final AnicelOpenedSessionFields session;

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
}

/// One dirty cel's save payload, resolved on the UI isolate to a
/// sendable form (hot surfaces are native-backed and cannot cross).
class _CelWork {
  const _CelWork({
    required this.key,
    required this.name,
    this.hotEntry,
    this.refPath,
    this.refOffset = 0,
    this.refLength = 0,
  });

  final BrushFrameKey key;
  final String name;
  final AnicelCelEntry? hotEntry;

  /// 🪦A `coldBlob` rode here while the cold tier was RAM. Cooled cels are
  /// files in the run's 이사대기 room now, so they arrive as a ref like
  /// any other file-backed cel — one road instead of two, and no blob
  /// resident while the save runs.
  final String? refPath;
  final int refOffset;
  final int refLength;

  /// The blob to write, resolved INSIDE the save isolate: hot encodes,
  /// cold passes through, a file ref reads back — and a stale key label
  /// (rekeyed cel) re-splices the header without touching pixels.
  ///
  /// 🚨★★★**NULL WHEN THE FILE A REF POINTS INTO IS GONE.**
  ///
  /// 유저 2026-08-30, on an iPad: open a project, delete the file in the
  /// Files app, draw a stroke, press Save — `PathNotFoundException:
  /// Cannot open file`. 「파일 확인해서 없으면 이런게아니라 새로
  /// 저장시키도록 하는게 좋을거같은데」.
  ///
  /// A successful save turns every cel into a file ref and drops its cold
  /// blob as「redundant with the file」, so once that file is deleted the
  /// untouched cels have their bytes in exactly one place that no longer
  /// exists. Opening it threw, and the throw came out of a background
  /// isolate as a raw exception with a path in it.
  ///
  /// ⛔It answers null rather than throwing, and NOT because the loss is
  /// acceptable — the caller counts these and the save reports them, so a
  /// person is told which work could not be carried forward instead of
  /// finding out later. What is not acceptable is refusing to save at all:
  /// everything still in RAM would go too, and the file the user is trying
  /// to write is the only place it could land.
  ///
  /// 🚨★★★**GONE IS NOT BUSY** (F-72, 2026-09-11). A file that is THERE but
  /// refuses a read right now — a cloud provider in the middle of a sync, a
  /// scanner, the Files app's "content unavailable" — was answered like a
  /// deleted one: the cel was left out, and a full save then renamed the
  /// short archive over the ONLY copy of it. It is retried the way the
  /// rename is, and still refused it stops the save: the old file stands
  /// with the cel in it, and the session still holds everything drawn since.
  AnicelCelBlob? resolveBlob() {
    if (hotEntry != null) {
      return AnicelCelBlob.encode(hotEntry!);
    }
    final file = File(refPath!);
    for (var attempt = 0; ; attempt += 1) {
      try {
        final raf = file.openSync();
        try {
          raf.setPositionSync(refOffset);
          final blob = AnicelCelBlob(raf.readSync(refLength));
          return blob.key == key ? blob : AnicelCelBlob.reKeyed(blob, key);
        } finally {
          raf.closeSync();
        }
      } on FileSystemException {
        if (!file.existsSync()) {
          return null;
        }
        if (attempt >= 3) {
          rethrow;
        }
        sleep(const Duration(milliseconds: 80));
      }
    }
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
    // Nothing to say if the last entry already landed on it. Saying it
    // twice is harmless on the wire and wrong as a signal: "the bar
    // arrives at the end once" is the property that catches an end
    // announced early, and it cannot be asserted if the normal path
    // announces it twice.
    if (_sent >= 1) {
      return;
    }
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

/// A writing isolate asking the session to move its cel refs off bytes it
/// is about to write over, and waiting on [reply] until they have
/// ([AnicelReaders.move]).
class _MoveRefs {
  const _MoveRefs(this.moved, this.reply);

  /// Old data offset → where those bytes are now.
  final Map<int, AnicelRelocation> moved;
  final SendPort reply;
}

/// The writing isolate's half of [_MoveRefs]: asks, and completes once the
/// session has answered.
Future<void> _askToMoveRefs(
  SendPort session,
  Map<int, AnicelRelocation> moved,
) async {
  if (moved.isEmpty) {
    return;
  }
  final answer = ReceivePort();
  session.send(_MoveRefs(moved, answer.sendPort));
  await answer.first;
}

/// Runs [write] with a port for it to report progress on — and, given
/// [onMoveRefs], to ask the session to move its refs on — and closes that
/// port afterwards. With neither there is no port and no cost.
///
/// ⚠️[onMoveRefs] is answered even when it throws: the isolate waits on
/// the answer, and a save that never hears back never finishes.
Future<R> _reportingProgress<R>(
  void Function(double)? onProgress,
  Future<R> Function(SendPort? port) write, {
  void Function(Map<int, AnicelRelocation> moved)? onMoveRefs,
}) async {
  if (onProgress == null && onMoveRefs == null) {
    return write(null);
  }
  final receive = ReceivePort();
  receive.listen((message) {
    if (message is double) {
      onProgress?.call(message);
    } else if (message is _MoveRefs) {
      try {
        onMoveRefs?.call(message.moved);
      } finally {
        message.reply.send(null);
      }
    }
  });
  try {
    return await write(receive.sendPort);
  } finally {
    receive.close();
  }
}

/// Saves/loads .anicel project files (P3 / R22-C).
///
/// Two save paths:
///  - INCREMENTAL (the normal autosave/manual-save path): only cels
///    edited since the last save append to the existing file, shadowing
///    their old entries by stable name. Superseded bytes stay as garbage
///    until garbage passes [_compactionGarbageRatio] — and then the same
///    save pushes the live bytes down over it and cuts the tail, in place
///    ([compactAnicelInPlace]).
///  - FULL (first save, save-as, or a tail that does not parse): the
///    archive rebuilds whole into a temp sibling then renames over the
///    target — atomic, and what heals a file a crash left torn.
///    🪦It was also the compaction until 2026-09-23 (유저,
///    deleting-save-compacts-Q1: 「전체 다시쓰기는 압축 정리에서
///    사라지고(첫 저장·Save As·복구에만 남음)」).
///
/// After every successful save the store adopts file refs for the
/// written cels, so their RAM copies can drop for free — the saved .anicel
/// IS the disk tier (no scratch/temp files, user rule).
class AnicelFileService {
  const AnicelFileService();

  /// The main store and its aux stores, their snapshots, and those
  /// snapshots merged.
  ///
  /// ⛔THE AUX STORES RIDE THE SAME ARCHIVE (the conte sheet ink, R5):
  /// their keys live in their own namespace, so the snapshots merge
  /// without collision and each store adopts back exactly its own refs.
  /// The save and the recovery overlay both need that, and only one of
  /// them used to say why. The per-store snapshots come back too, because
  /// adopting back is per store — the merge is for writing, the list is
  /// for handing each store its own.
  static ({
    List<BrushFrameStore> stores,
    List<
      ({
        Map<BrushFrameKey, BitmapSurface> hot,
        Map<BrushFrameKey, AnicelCelFileRef> cold,
        Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
        Map<BrushFrameKey, int> dirtyTicks,
      })
    >
    snapshots,
    ({
      Map<BrushFrameKey, BitmapSurface> hot,
      Map<BrushFrameKey, AnicelCelFileRef> cold,
      Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
    })
    baked,
  })
  _bakedAcrossStores(
    BrushFrameStore brushFrameStore,
    List<BrushFrameStore> auxCelStores,
  ) {
    final stores = [brushFrameStore, ...auxCelStores];
    final snapshots = [
      for (final store in stores) store.bakedSnapshotForSave(),
    ];
    return (
      stores: stores,
      snapshots: snapshots,
      baked: (
        hot: {for (final s in snapshots) ...s.hot},
        cold: {for (final s in snapshots) ...s.cold},
        fileRefs: {for (final s in snapshots) ...s.fileRefs},
      ),
    );
  }

  /// The save compacts — in place, [compactAnicelInPlace] — when
  /// shadowed/removed garbage exceeds this fraction of the file.
  static const double _compactionGarbageRatio = 0.5;

  /// Writes the project, answering the cels it could NOT write.
  ///
  /// 🚨An empty set is the normal answer and the only one anybody expected
  /// until 2026-08-30. A non-empty one means the file some cels' bytes
  /// lived in was deleted while the project was open (유저, on an iPad:
  /// delete it in the Files app, draw, press Save). Those cels are gone —
  /// what this returns is WHICH, so the app can say so instead of the
  /// person finding out later.
  Future<Set<BrushFrameKey>> save({
    required Project project,
    required BrushFrameStore brushFrameStore,
    List<BrushFrameStore> auxCelStores = const [],
    required String filePath,
    Map<MediaCarry, MediaByteSource> mediaToStore = const {},

    /// Pool path → the conform to carry alongside it, taken AS IT SITS
    /// (framed stays framed). Whatever is absent here has its conform
    /// entry REMOVED — that is the settings-change sweep.
    ProjectConforms conforms = const ProjectConforms.none(),

    /// What the document carries beside the project — the media grants and
    /// fingerprints, already reduced to JSON by the session. See
    /// [AnicelSessionFields].
    AnicelSessionFields sessionFields = AnicelSessionFields.none,

    /// Called on the UI isolate with 0..1 as the write proceeds. Null costs
    /// nothing — no port is opened and the writer reports into no one.
    void Function(double)? onProgress,

    /// Entries something reads by OFFSET right now
    /// (`ProjectFile.heldArchiveEntries`): a save that packs the file in
    /// place leaves them where they are ([compactAnicelInPlace]'s
    /// `staying`). That they stay in the directory at all is [mediaToStore]'s
    /// — the caller stores what its readers hold.
    Set<String> heldEntries = const {},

    /// False writes a COPY: the stores do not adopt refs into [filePath]
    /// and nothing about the session's idea of "where the project lives"
    /// may change. The Save As staging writer is the consumer — its file
    /// is about to be MOVED by a document picker, and refs adopted into a
    /// path that is about to stop existing are every cel dying at once.
    bool adoptRefs = true,

    /// 🚨★★★**TRUE FOR A SAVE AS, ALWAYS.**
    ///
    /// 유저 2026-08-31: 「다른이름저장은 항상 무조건 풀저장으로 작동하는게
    /// 좋을거같음 … 다른이름저장은 기본적으로 첫 저장이나 마찬가지니까.
    /// 기존 파일에 저장 덮어씌우기를 하더라도 고장난 프로젝트를 고치기위해
    /// 풀저장 시키는게 맞다고 생각됨」.
    ///
    /// A Save As onto a NEW name already rewrote — the file is not there to
    /// append to. The hole was Save As ONTO AN EXISTING copy of the same
    /// project: with every cel dirty the soundness test below passes, so
    /// the write APPENDED and the old copy's entries stayed underneath as
    /// dead bytes. The file opened correctly and carried a second project's
    /// worth of garbage, which is the opposite of what「고치기 위해」means.
    ///
    /// ⛔It does NOT rescue cels whose bytes are already gone. A clean cel
    /// lives as a ref into the file it was last written to — the store
    /// drops the cold blob on adoption — so ANY write, whole or appended,
    /// has to read it back from there. Rewriting reads MORE, not less.
    bool rewriteWhole = false,

    /// 🎯A CALLER WITH A FILE COORDINATOR SWAPS FOR ITSELF. When set, a
    /// save that turns out WHOLE is not renamed onto [filePath]: the
    /// finished archive is left beside it (`<filePath>.tmp-…`), the refs
    /// adopted point INTO it, and this is told where — the caller then
    /// replaces through the coordinator and repoints. An append is
    /// unaffected: it wrote into [filePath] and there is nothing to swap.
    ///
    /// Why a callback and not a return: the swap is synchronous below for a
    /// reason ([renameWithRetry] — the refs carry the OLD layout until the
    /// caller adopts), and a coordinated replace is a channel call that
    /// cannot be. So the caller takes the swap, and with it the shape the
    /// staging road already had: adopt the temp, replace, repoint.
    void Function(String tempPath)? onFullWriteLeftAt,

    /// Waited for just before a whole write is renamed onto [filePath]: the
    /// readers holding that file open let go of it
    /// (`ProjectFile.readersLetGoOf`) — Windows refuses a rename onto a file
    /// anything in this process holds open. The session's own cel handle is
    /// [renameWithRetry]'s to let go; the media readers are the session's.
    Future<void> Function()? beforeReplacing,
  }) async {
    // Aux stores (the conte sheet ink, R5) ride the same archive: their
    // keys live in their own namespace, so the snapshots merge without
    // collision and each store adopts back exactly its own refs.
    // A project file whose name vanished while we held it is copied out
    // before anything reads it — see [_rescueAVanishedProjectFile].
    _rescueAVanishedProjectFile([
      brushFrameStore,
      ...auxCelStores,
    ]);
    final saveSnapshot = _bakedAcrossStores(brushFrameStore, auxCelStores);
    final stores = saveSnapshot.stores;
    final snapshots = saveSnapshot.snapshots;
    final baked = saveSnapshot.baked;
    final dirtySets = [for (final store in stores) store.dirtyCelKeysSinceSave];
    final dirty = <BrushFrameKey>{for (final set in dirtySets) ...set};
    final saveDirectory = _parentDirectory(filePath);

    void adoptEach(Map<BrushFrameKey, AnicelCelFileRef> adopted) {
      if (!adoptRefs) {
        return;
      }
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
        }, dirtyTicksAtSnapshot: snapshots[index].dirtyTicks);
      }
    }

    /// A cel the save could not carry lets go of its ref — see
    /// [BrushFrameStore.forgetCelsLostWithTheirFile] for where it would
    /// still have pointed. Only a full save can lose one: an append runs
    /// only when every clean cel is already in the file it appends to.
    void forgetEach(Set<BrushFrameKey> lostKeys) {
      if (!adoptRefs) {
        return;
      }
      for (var index = 0; index < stores.length; index += 1) {
        stores[index].forgetCelsLostWithTheirFile([
          for (final key in lostKeys)
            if (snapshots[index].fileRefs.containsKey(key)) key,
        ]);
      }
    }

    /// How every save ends, whichever way it wrote: the lost refs go, the
    /// file the refs now point into is HELD ([OpenProjectFile.hold] — a full
    /// save's rename had to let go of it), and an archive waiting to go
    /// that nothing reads any more is retired ([retireWhenUnread]).
    Set<BrushFrameKey> settle(Set<BrushFrameKey> lostKeys) {
      forgetEach(lostKeys);
      if (adoptRefs) {
        OpenProjectFile.instance.hold(filePath);
      }
      _retireUnread(stores);
      return lostKeys;
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
        if (namesTheSameFile(entry.value.filePath, filePath)) entry.key,
    };
    final sound =
        !rewriteWhole &&
        File(filePath).existsSync() &&
        allKeys.every((key) => dirty.contains(key) || refsHere.contains(key));

    /// 🚨★★★**WHAT THE SAVE COULD NOT CARRY FORWARD.**
    ///
    /// Every cel that got written comes back with a ref. So the ones that
    /// did NOT are exactly the ones whose only copy was in a file that has
    /// since been deleted — see [_CelSaveWork.resolveBlob]. The answer was
    /// already here; nothing new has to be plumbed out of the isolate.
    ///
    /// 🚨An APPEND writes only what changed. Every clean cel stays where it
    /// already is — verified in this very file before a byte went down —
    /// and comes back with no new ref because it needs none: that is
    /// [carried]. Counted as「not carried forward」, they told the person on
    /// every save after the first that N pictures were lost while the file
    /// held them all (F-72, iPad + Drive, 2026-09-11: two pictures, one
    /// drawn on —「1장 저장 못 했다」).
    ///
    /// ⛔Named and returned rather than logged, because the person needs to
    /// be told. A save that quietly wrote fewer cels than it was given is
    /// the shape this repo refuses for media, and a cel is the picture.
    Set<BrushFrameKey> lost(
      Map<BrushFrameKey, AnicelCelFileRef> adopted, {
      Set<BrushFrameKey> carried = const {},
    }) => {
      for (final key in allKeys)
        if (!adopted.containsKey(key) && !carried.contains(key)) key,
    };

    /// Every ref into [filePath], in every store, follows its bytes before
    /// the push-down can write over them ([compactAnicelInPlace]).
    ///
    /// ⚠️Whatever [adoptRefs] says: that decides whether the session takes
    /// THIS save's file as its own, and these refs already point into it —
    /// one left behind reads whatever lands on its old bytes.
    void moveRefs(Map<int, AnicelRelocation> moved) {
      for (final store in stores) {
        store.relocateFileRefs(
          (path) => namesTheSameFile(path, filePath),
          moved,
        );
      }
    }

    if (sound) {
      final adopted = await _saveIncremental(
        project: project,
        baked: baked,
        dirty: dirty,
        filePath: filePath,
        saveDirectory: saveDirectory,
        mediaToStore: mediaToStore,
        conforms: conforms,
        sessionFields: sessionFields,
        onProgress: onProgress,
        heldEntries: heldEntries,
        onMoveRefs: moveRefs,
      );
      if (adopted != null) {
        adoptEach(adopted);
        return settle(lost(
          adopted,
          carried: {
            for (final key in allKeys)
              if (!dirty.contains(key)) key,
          },
        ));
      }
      // A torn tail, refs the file does not back, or somebody else's
      // archive → the whole write below.
    }

    final adopted = await _saveFull(
      project: project,
      baked: baked,
      dirty: dirty,
      filePath: filePath,
      saveDirectory: saveDirectory,
      mediaToStore: mediaToStore,
      conforms: conforms,
      sessionFields: sessionFields,
      onProgress: onProgress,
      onFullWriteLeftAt: onFullWriteLeftAt,
      beforeReplacing: beforeReplacing,
    );
    adoptEach(adopted);
    return settle(lost(adopted));
  }

  /// Splits the dirty set into the cels that still have content and the
  /// entry names of the ones that no longer do.
  ///
  /// The overlay and the incremental save both start here; the way they
  /// spell the removals differs (a list in the JSON, a set to subtract
  /// from the layout) but the partition itself is one law.
  ///
  /// ⛔Not _saveFull's loop: that one walks ALL keys, and a clean
  /// file-backed key there becomes a stream-through work rather than a
  /// removal.
  static ({List<_CelWork> works, List<String> removedNames}) _dirtyCelWork(
    Set<BrushFrameKey> dirty,
    ({
      Map<BrushFrameKey, BitmapSurface> hot,
      Map<BrushFrameKey, AnicelCelFileRef> cold,
      Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
    })
    baked,
  ) {
    final works = <_CelWork>[];
    final removedNames = <String>[];
    for (final key in dirty) {
      final work = _workForDirtyKey(key, baked);
      if (work == null) {
        removedNames.add(anicelCelEntryName(key));
      } else {
        works.add(work);
      }
    }
    return (works: works, removedNames: removedNames);
  }

  /// Resolves a dirty key's current content to a [_CelWork], or null for
  /// a removed cel (its entry name must vanish from the archive).
  static _CelWork? _workForDirtyKey(
    BrushFrameKey key,
    ({
      Map<BrushFrameKey, BitmapSurface> hot,
      Map<BrushFrameKey, AnicelCelFileRef> cold,
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
      // 🚨★★★**A PARKED CEL IS A REF, NOT A BLOB — and that is the whole
      // point of the round that parked it.** Cooled cels used to arrive
      // here as `AnicelCelBlob`s held in RAM, so a save of a project big
      // enough to have cooled anything had every one of those blobs
      // resident at once, on top of whatever the save itself needed. They
      // are files in the run's 이사대기 room now, and the isolate streams
      // them exactly the way it already streams a cel out of the saved
      // archive: same path/offset/length, different file.
      return _CelWork(
        key: key,
        name: name,
        refPath: cold.filePath,
        refOffset: cold.dataOffset,
        refLength: cold.length,
      );
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

  /// Whether the archive at [filePath] is the one [projectIdValue] names.
  ///
  /// Reads and decodes the target's own manifest, so it is asked only when
  /// nothing cheaper can answer — false for anything it cannot read, since
  /// an append onto a file whose identity is unknown is the loss this
  /// guards against.
  static bool _targetIsThisProject({
    required String filePath,
    required AnicelZipLayout layout,
    required String projectIdValue,
  }) {
    final targetProjectEntry = layout.projectEntry();
    if (targetProjectEntry == null) {
      return false; // Not an archive of ours — replace, don't append.
    }
    try {
      final raf = File(filePath).openSync();
      Object? targetId;
      try {
        raf.setPositionSync(targetProjectEntry.dataOffset);
        final decoded = jsonDecode(
          utf8.decode(
            decodeAnicelProjectEntryBytes(
              targetProjectEntry.name,
              raf.readSync(targetProjectEntry.length),
            ),
          ),
        );
        final targetProject = decoded is Map ? decoded['project'] : null;
        targetId = targetProject is Map ? targetProject['id'] : null;
      } finally {
        raf.closeSync();
      }
      final targetValue = targetId is Map ? targetId['value'] : null;
      return targetValue == projectIdValue;
    } on Object {
      return false; // Unreadable target manifest — replace, don't append.
    }
  }

  /// The layout of [filePath] when appending onto it is SOUND — with the
  /// names this save takes out of its directory, and whether it compacts —
  /// or null when the caller must rewrite the file whole instead.
  ///
  /// Two separate ways an append would lose data, asked in the order that
  /// costs the least: a torn tail, and refs whose bytes are not where they
  /// say. A file so full of garbage that appending more is the wrong move
  /// is not a third any more: it is [compact], and the same save packs it
  /// in place (유저 2026-09-23, deleting-save-compacts-Q1).
  ///
  /// 🚨THE GARBAGE IS JUDGED ON THE DIRECTORY THIS SAVE LEAVES BEHIND, not
  /// on the one it found. A save that dropped a carried 157MB PDF judged
  /// the file with the PDF still named — garbage ≈ 0, so it appended — and
  /// only the NEXT save saw the 157MB it had left unnamed and compacted
  /// (유저 2026-09-13: 「삭제하고 저장해도 파일 크기 안 줄어든다 … 두 번째
  /// 저장 시 줄어드네」). What a save REMOVES is known before a byte is
  /// written, so [namesLeaving] is counted here; what it REPLACES (a
  /// rewritten cel, the manifest) is not sized until it is written, and
  /// those old bytes count from the next save on, as they always did. One
  /// rule — the ratio — for a 157MB movie and a 79KB still alike; size
  /// only ever enters through the ratio (유저: 「큰 미디어든 아니든 법
  /// 하나로」).
  static ({AnicelZipLayout layout, Set<String> leaving, bool compact})?
  _layoutSafeToAppendOnto({
    required String filePath,
    required List<(String, int, int)> cleanRefsToVerify,
    required String projectIdValue,
    required Set<String> Function(AnicelZipLayout layout) namesLeaving,
  }) {
    final AnicelZipLayout layout;
    try {
      layout = parseAnicelZipLayoutFile(filePath);
    } on FormatException {
      return null; // Torn tail — the whole write is the recovery.
    }
    // The refs' claim — "my bytes are already in this file" — is verified
    // against the file itself before anything appends, because path
    // equality is not proof. Every cel this append will NOT write must be
    // in the layout exactly where its ref says: a name present at the
    // wrong offset or length means the file was replaced out from under
    // the refs (the pre-F-14 Save As placeholder did exactly that to the
    // live project), and appending onto it would silently drop every
    // clean cel. Replacing is the full rewrite's job, so a mismatch
    // answers null.
    final entriesByName = {
      for (final entry in layout.entries) entry.name: entry,
    };
    for (final (name, dataOffset, length) in cleanRefsToVerify) {
      final expected = entriesByName[name];
      if (expected == null ||
          expected.dataOffset != dataOffset ||
          expected.length != length) {
        return null;
      }
    }
    // With zero clean refs the check above proved nothing — a fresh
    // project's cels are all dirty, so the soundness precondition passed
    // VACUOUSLY and this could be anyone's archive (Save As onto an
    // existing name). Appending would keep every foreign entry alive
    // under the new project.json, silently retaining the replaced
    // project's content in the file. Only then is the target's own
    // manifest read and its project id compared — on the ordinary save
    // the verified refs already prove ownership, and project.json can be
    // megabytes this path must not decode every Ctrl+S.
    if (cleanRefsToVerify.isEmpty &&
        !_targetIsThisProject(
          filePath: filePath,
          layout: layout,
          projectIdValue: projectIdValue,
        )) {
      return null;
    }
    final leaving = namesLeaving(layout);
    final compact = anicelNeedsCompaction(
      fileLength: File(filePath).lengthSync(),
      entries: [
        for (final entry in layout.entries)
          if (!leaving.contains(entry.name))
            (name: entry.name, length: entry.length),
      ],
      garbageRatio: _compactionGarbageRatio,
    );
    return (layout: layout, leaving: leaving, compact: compact);
  }

  /// Appends only the dirty cels (+ a superseding project.json) — and, when
  /// garbage has passed the ratio, packs the file down in place in the same
  /// save. Returns the refs to adopt, or null when the file needs a full
  /// rewrite instead (unparseable tail, or refs it does not back).
  Future<Map<BrushFrameKey, AnicelCelFileRef>?> _saveIncremental({
    required Project project,
    required ({
      Map<BrushFrameKey, BitmapSurface> hot,
      Map<BrushFrameKey, AnicelCelFileRef> cold,
      Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
    })
    baked,
    required Set<BrushFrameKey> dirty,
    required String filePath,
    required String saveDirectory,
    required AnicelSessionFields sessionFields,
    Map<MediaCarry, MediaByteSource> mediaToStore = const {},

    /// Pool path → the conform to carry alongside it, taken AS IT SITS
    /// (framed stays framed). Whatever is absent here has its conform
    /// entry REMOVED — that is the settings-change sweep.
    ProjectConforms conforms = const ProjectConforms.none(),
    void Function(double)? onProgress,

    /// Entries the push-down leaves where they are — see `save`'s.
    Set<String> heldEntries = const {},

    /// Moves the session's refs off bytes the push-down is about to write
    /// over — see `save`'s `moveRefs`.
    required void Function(Map<int, AnicelRelocation> moved) onMoveRefs,
  }) async {
    final (:works, :removedNames) = _dirtyCelWork(dirty, baked);
    // Scalars only, resolved HERE: the isolate closure must not capture
    // [baked] — its hot surfaces are native-backed and cannot cross.
    final cleanRefsToVerify = <(String, int, int)>[
      for (final ref in baked.fileRefs.entries)
        if (!dirty.contains(ref.key) &&
            namesTheSameFile(ref.value.filePath, filePath))
          (anicelCelEntryName(ref.key), ref.value.dataOffset, ref.value.length),
    ];
    // 🚨Refs a DIRTY cel still holds into this file — a rekeyed cel keeps
    // pointing at the bytes of its old name (`rekeyFrames`), and this save
    // takes that name out of the directory. The push-down may write over
    // those bytes, so before it starts each ref moves to the entry this
    // save wrote for its key. By entry name → where the ref points now.
    final heldByDirtyCels = <String, int>{
      for (final key in dirty)
        if (baked.fileRefs[key] case final ref?
            when namesTheSameFile(ref.filePath, filePath))
          anicelCelEntryName(key): ref.dataOffset,
    };
    // ⛔A bool, not [onProgress]: the port now opens for the refs even with
    // no one watching the bar, and a callback reaching into the isolate
    // drags the session along with it — the send refuses (a `Future` deep
    // in its settings is unsendable), and every Save from the menu failed.
    final reportsProgress = onProgress != null;

    return _reportingProgress(
      onProgress,
      onMoveRefs: onMoveRefs,
      (port) => Isolate.run(() async {
        final sound = _layoutSafeToAppendOnto(
          filePath: filePath,
          cleanRefsToVerify: cleanRefsToVerify,
          projectIdValue: project.id.value,
          // Everything this save takes out of the directory — cels the
          // project no longer has, media it no longer carries, conforms
          // outside the current settings. Computed once: the judgment
          // above and the append below must agree on what leaves.
          namesLeaving: (layout) => {
            ...removedNames,
            // A held entry is not among them: what a reader holds is in
            // [mediaToStore] (`ProjectFileDoor._carryFor`).
            ..._namesToDrop(
              layout,
              mediaToStore: mediaToStore,
              conforms: conforms,
            ),
          },
        );
        if (sound == null) {
          return null;
        }
        final (:layout, :leaving, :compact) = sound;
        // Resolved BEFORE the cels so the progress count is complete: a
        // fraction needs its denominator before the first thing it divides.
        final newMedia = _mediaToAppend(layout, mediaToStore);
        final newConforms = _conformsToAppend(layout, conforms);
        // ⚠️ Media counts once PER PASS, not once. This writer reads every
        // streamed entry twice (checksum, then copy), and counting it once
        // put `_done` at `_total` when the checksum pass ended — the window
        // said 100% and then sat there through the whole byte copy, which on
        // a large import is most of the wait. The push-down is one more
        // unit, filled by the fraction of its bytes copied: on the save that
        // drops a big asset it IS the wait.
        final progress = _SaveProgress(
          reportsProgress ? port : null,
          1 +
              works.length +
              (newMedia.length + newConforms.length) * anicelAppendStreamPasses +
              (compact ? 1 : 0),
        );
        final projectEntry = buildAnicelProjectEntry(
          project: project,
          saveDirectory: saveDirectory,
          mediaEntryNames: mediaEntryNamesFor(mediaToStore),
          sessionFields: sessionFields,
        );
        progress.step();
        final blobs = _resolvedBlobs(works, progress);
        final appended = appendAnicelEntries(
          path: filePath,
          newEntries: {
            projectEntry.name: projectEntry.bytes,
            for (final (_, name, blob) in blobs) name: blob.bytes,
          },
          removeNames: leaving,
          streamedEntries: [
            for (final entry in newMedia) _progressed(entry, progress),
            for (final entry in newConforms) _progressed(entry, progress),
          ],
        );
        // The push-down and the cut, here in the isolate that just appended.
        // Before anything is written over, every ref a dirty cel holds into
        // the file moves to its new home; then each round's moves are
        // announced the same way.
        var written = appended;
        if (compact) {
          Future<void> moveRefs(Map<int, AnicelRelocation> moved) =>
              _askToMoveRefs(port!, moved);
          await moveRefs(_rehomedRefs(appended, heldByDirtyCels));
          written = await compactAnicelInPlace(
            path: filePath,
            layout: appended,
            readers: (move: moveRefs, holding: heldEntries),
            onProgress: progress.within,
          );
          progress.step();
        }
        progress.finish();
        return _refsForBlobs(blobs, appended: written, filePath: filePath);
      }),
    );
  }

  /// Where each ref a dirty cel holds into the file goes before the
  /// push-down may write over its bytes: the entry this save wrote for its
  /// key ([appended]) — by the offset the ref points at now.
  ///
  /// ⚠️Every one of them HAS that entry. A dirty cel's bytes resolve from
  /// the file its ref names, and a cel only gives up its bytes when that
  /// file is gone ([_CelWork.resolveBlob]) — this is the file the append
  /// just wrote into.
  static Map<int, AnicelRelocation> _rehomedRefs(
    AnicelZipLayout appended,
    Map<String, int> heldByDirtyCels,
  ) {
    final rehomed = <int, AnicelRelocation>{};
    for (final MapEntry(key: name, value: dataOffset)
        in heldByDirtyCels.entries) {
      final home = appended.entryNamed(name)!;
      rehomed[dataOffset] = (dataOffset: home.dataOffset, length: home.length);
    }
    return rehomed;
  }

  /// Every dirty cel's bytes, in [works] order.
  ///
  /// ⛔The progress steps for EVERY work, including the ones that resolve
  /// to nothing: the fraction has to reach its denominator or the window
  /// stops short of 100% and looks hung.
  static List<(BrushFrameKey, String, AnicelCelBlob)> _resolvedBlobs(
    List<_CelWork> works,
    _SaveProgress progress,
  ) {
    final blobs = <(BrushFrameKey, String, AnicelCelBlob)>[];
    for (final work in works) {
      final blob = work.resolveBlob();
      if (blob != null) {
        blobs.add((work.key, work.name, blob));
      }
      progress.step();
    }
    return blobs;
  }

  /// The refs to adopt: where each blob actually LANDED, read back from
  /// the layout the append returned rather than predicted.
  static Map<BrushFrameKey, AnicelCelFileRef> _refsForBlobs(
    List<(BrushFrameKey, String, AnicelCelBlob)> blobs, {
    required AnicelZipLayout appended,
    required String filePath,
  }) => {
    for (final (key, name, blob) in blobs)
      key: AnicelCelFileRef(
        filePath: filePath,
        dataOffset: appended.entryNamed(name)!.dataOffset,
        length: blob.bytes.length,
        canvasSize: blob.canvasSize,
        tileSize: blob.tileSize,
      ),
  };

  /// The media this append has to write: only what is not already in the
  /// file.
  ///
  /// Media is written once and never edited, so an asset already inside
  /// is a survivor of the append like any untouched cel — re-streaming it
  /// every save would rewrite the project's whole media area to change
  /// one drawing.
  ///
  /// 🚨That holds because the name is the CARRY's ([anicelMediaEntryName]).
  /// Named by the path, a file carried again after a removal found its old
  /// entry here and was never written — the save kept the old bytes (card
  /// `recarry-after-remove-reads-the-old`).
  static List<AnicelStreamedEntry> _mediaToAppend(
    AnicelZipLayout layout,
    Map<MediaCarry, MediaByteSource> mediaToStore,
  ) => [
    for (final entry in mediaToStore.entries)
      if (layout.entryNamed(
            anicelMediaEntryName(entry.key, framed: entry.value.storedIsFramed),
          ) ==
          null)
        AnicelStreamedEntry(
          name: anicelMediaEntryName(
            entry.key,
            framed: entry.value.storedIsFramed,
          ),
          length: entry.value.lengthSync(),
          readInto: entry.value.readIntoSync,
        ),
  ];

  /// The conforms this append has to write.
  ///
  /// A conform, unlike media, CAN be replaced under the same name: it is
  /// derived, and a rebuilt one lands at the same cache address. So
  /// presence is not enough — the LENGTH has to agree too.
  ///
  /// 🚨What being wrong costs, stated honestly: two different conforms of
  /// one source at one setting that happen to compress to the exact same
  /// byte count would leave the stale one carried. The pipeline checks
  /// the source fingerprint before it uses a conform, so that costs dead
  /// bytes until the next differing save and can never play the wrong
  /// sound. Re-streaming every conform on every save instead would
  /// rewrite hundreds of megabytes to change one line of dialogue.
  static List<AnicelStreamedEntry> _conformsToAppend(
    AnicelZipLayout layout,
    ProjectConforms conforms,
  ) => [
    for (final entry in conforms.entries.entries)
      if (_needsRestreaming(layout, entry.key, entry.value))
        AnicelStreamedEntry(
          name: entry.key,
          length: entry.value.lengthSync(),
          readInto: entry.value.readIntoSync,
        ),
  ];

  /// The names this save takes OUT of the central directory.
  ///
  /// Media the project no longer carries leaves with this save. An entry
  /// nothing names was invisible garbage that the compaction maths
  /// counted as ACTIVE media — raising the very floor that suppresses
  /// compaction, so a deleted 500MB track could sit in the file for ever
  /// — and worse, a live name silently reattached a RE-imported same-path
  /// asset to the OLD bytes (the presence check in [_mediaToAppend] skips
  /// streaming when the name already exists). That half is the carry's
  /// name's job now ([anicelMediaEntryName]): this sweep only ran at a
  /// save, and a file carried again BEFORE one still found the old name.
  ///
  /// 🚨★★★**AND THIS IS THE SETTINGS-CHANGE SWEEP** (유저 2026-08-30:
  /// 「레이트 변경 등 죽은파일만 깔끔하게 잘 걷어낼것」).
  ///
  /// ⛔Against [ProjectConforms.liveNames], NOT against what is being
  /// written. Those are different sets and the difference is the bug this
  /// shape exists to avoid: a machine that has only just opened the
  /// project writes NOTHING (its cache is empty and the bytes are already
  /// in the file), and sweeping by「what was written」would have taken
  /// every conform the project carried on exactly that journey.
  /// `liveNames` says what the project may legitimately HOLD at the
  /// current settings; a conform built under others is under a name
  /// outside it, and that is the whole test.
  static Set<String> _namesToDrop(
    AnicelZipLayout layout, {
    required Map<MediaCarry, MediaByteSource> mediaToStore,
    required ProjectConforms conforms,
  }) {
    final wantedMediaNames = {
      for (final entry in mediaToStore.entries)
        anicelMediaEntryName(entry.key, framed: entry.value.storedIsFramed),
    };
    return {
      for (final entry in layout.entries)
        if (entry.name.startsWith(anicelMediaEntryPrefix) &&
            !wantedMediaNames.contains(entry.name))
          entry.name,
      // 🚨★★★THE SETTINGS-CHANGE SWEEP, against what the project may
      // legitimately HOLD — see this method's doc for why that is not
      // the same as what is being written.
      for (final entry in layout.entries)
        if (entry.name.startsWith(anicelConformEntryPrefix) &&
            !conforms.entries.containsKey(entry.name))
          entry.name,
    };
  }

  /// Whether the entry called [name] has to be streamed again.
  ///
  /// Absent, or present at a different length. Media never takes the
  /// second branch — an asset is written once and never edited — but a
  /// conform is derived and a rebuilt one lands under the same name.
  static bool _needsRestreaming(
    AnicelZipLayout layout,
    String name,
    MediaByteSource source,
  ) {
    final existing = layout.entryNamed(name);
    return existing == null || existing.length != source.lengthSync();
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
      Map<BrushFrameKey, AnicelCelFileRef> cold,
      Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
    })
    baked,
    required Set<BrushFrameKey> dirty,
    required String filePath,
    required String saveDirectory,
    required AnicelSessionFields sessionFields,
    Map<MediaCarry, MediaByteSource> mediaToStore = const {},

    /// Pool path → the conform to carry alongside it, taken AS IT SITS
    /// (framed stays framed). Whatever is absent here has its conform
    /// entry REMOVED — that is the settings-change sweep.
    ProjectConforms conforms = const ProjectConforms.none(),
    void Function(double)? onProgress,
    void Function(String tempPath)? onFullWriteLeftAt,
    Future<void> Function()? beforeReplacing,
  }) async {
    final allKeys = <BrushFrameKey>{
      ...baked.hot.keys,
      ...baked.cold.keys,
      ...baked.fileRefs.keys,
    };
    final works = <_CelWork>[];
    // 🚨A CLEAN CEL THAT IS STILL HOT IS NOT ONLY IN THE FILE. Its ref is
    // the cheapest source, but when the file behind it is GONE — descriptor
    // and all, the one loss the rescue above cannot undo — the same bytes
    // are still in RAM (a clean promotion keeps its surface beside its ref
    // until cooling drops it for free), and taking the ref anyway reported
    // the picture lost while it sat in memory (F-72 follow-up, 2026-09-11).
    // Asked once per path, here on the UI isolate.
    final missing = <String, bool>{};
    bool fileMissing(String path) =>
        missing[path] ??= !File(path).existsSync();
    for (final key in allKeys) {
      final ref = baked.fileRefs[key];
      if (ref != null &&
          !dirty.contains(key) &&
          !(baked.hot.containsKey(key) && fileMissing(ref.filePath))) {
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
        // The refs name the file the bytes will be READ from: [filePath]
        // once the rename below has run, the temp itself when the caller is
        // taking the swap and the bytes stay there until it does.
        filePath: onFullWriteLeftAt == null ? filePath : tempPath,
        project: project,
        saveDirectory: saveDirectory,
        works: works,
        mediaToStore: mediaToStore,
        conforms: conforms,
        sessionFields: sessionFields,
        onProgress: onProgress,
      );
    } on Object {
      if (temp.existsSync()) {
        temp.deleteSync();
      }
      rethrow;
    }

    // The caller with a file coordinator swaps for itself (see `save`):
    // the archive stays beside the file, the refs already point into it,
    // and nothing is swept — the temp IS the save until the caller has
    // moved it, and the caller's next whole write collects strays.
    if (onFullWriteLeftAt != null) {
      onFullWriteLeftAt(tempPath);
      return refs;
    }
    // The readers of the file let go FIRST ([save]'s `beforeReplacing`) —
    // awaited here, before the swap, where the refs still read the old file
    // in its place; nothing may wait between the swap and the adopt below.
    await beforeReplacing?.call();
    // SYNC rename: existing refs into the replaced file carry offsets of
    // the OLD layout, so no event may run between the swap and the
    // caller's adoptSavedFile — sync-to-return is microtask-tight.
    //
    // Retried on failure: the moment after a file changes is exactly when
    // a sync client, indexer or AV holds it — and cloud-synced folders are
    // this app's home turf (Krita and Blender both landed on the same
    // absorb-the-transient-lock answer). A rename that still fails leaves
    // the temp IN PLACE — it holds the only complete copy of this save —
    // and SAYS where: the session keeps the work in its failed copy and
    // only then lets the temp go (유저 2026-09-23, whole-write-temp-beside-
    // the-file: 「실패 시 앱 룸으로 옮겨 보관」, never beside the file).
    try {
      renameWithRetry(temp, filePath);
    } on FileSystemException catch (error) {
      throw SaveNotSwappedIn(archive: tempPath, error: error);
    }
    sweepStaleSaveTemps(filePath);
    return refs;
  }

  /// [temp] onto [filePath], absorbing the moment-after-write lock a sync
  /// client or scanner can hold on the destination. Bounded: this blocks
  /// the UI isolate on purpose (the swap must stay microtask-tight), so
  /// the worst case is a beat, not a hang.
  static void renameWithRetry(File temp, String filePath) {
    // 🚨★★★**OUR OWN HANDLE FIRST, OR THE RETRY BELOW IS RETRYING US.**
    // The session holds the project file open so the user cannot delete the
    // cold tier out from under it ([OpenProjectFile]) — and renaming ONTO a
    // file this process holds open is blocked on Windows exactly like a
    // scanner's lock. Measured 2026-09-07: `PathAccessException`. Without
    // this line every full save and every compaction would spend the three
    // attempts and then throw, and the message would blame a sync client.
    // ⚠️Nothing to restore afterwards: the next cel read opens it again.
    OpenProjectFile.instance.releaseFor(filePath);
    for (var attempt = 0; ; attempt += 1) {
      try {
        temp.renameSync(filePath);
        return;
      } on FileSystemException {
        if (attempt >= 3) {
          rethrow;
        }
        sleep(const Duration(milliseconds: 80));
      }
    }
  }

  /// Collects `<project>.anicel.tmp-<micros>` strays beside the project.
  ///
  /// A process kill mid-full-save, or a rename the retry could not land,
  /// leaves a project-sized temp in the USER'S folder — visible, and in a
  /// cloud-synced folder, uploaded. Swept on the next successful save,
  /// like the recovery folder — but matching only this project's own temp
  /// prefix: the folder is the user's, so the recovery folder's broader
  /// `.tmp-` sweep must not run here.
  /// Deletes the `<filePath>.tmp-…` strays a failed swap left beside the
  /// file. [except] is the one temp a caller that swaps for itself has
  /// just moved in — or, when the platform copied instead, the one whose
  /// bytes keys dirty-again may still be read from; it is the NEXT whole
  /// write's stray, not this one's.
  static void sweepStaleSaveTemps(String filePath, {String? except}) {
    try {
      final prefix = '${filePath.replaceAll('\\', '/')}.tmp-';
      final keep = except?.replaceAll('\\', '/');
      for (final entity in File(filePath).parent.listSync()) {
        final path = entity.path.replaceAll('\\', '/');
        if (entity is File && path.startsWith(prefix) && path != keep) {
          entity.deleteSync();
        }
      }
    } on Object {
      // Housekeeping never fails a save.
    }
  }

  /// The archive write itself, off the UI isolate. Returns only the refs —
  /// the bytes never cross the port.
  static Future<Map<BrushFrameKey, AnicelCelFileRef>> _writeArchiveInIsolate({
    required String tempPath,
    required String filePath,
    required Project project,
    required String saveDirectory,
    required List<_CelWork> works,
    required Map<MediaCarry, MediaByteSource> mediaToStore,
    required ProjectConforms conforms,
    // Plain maps inside, so the closure carries values the port can copy —
    // the picker's grant type could not cross this boundary at all.
    required AnicelSessionFields sessionFields,
    void Function(double)? onProgress,
  }) {
    return _reportingProgress(
      onProgress,
      (port) => Isolate.run(() {
        // One pass here, unlike the append path above — this writer patches
        // the CRC by seeking back rather than pre-reading.
        //
        // 🚨Conforms count. They are streamed entries like the media, they
        // are written LAST, and they are the biggest things in the file —
        // so leaving them out of the denominator does not shave the bar, it
        // parks it at 100% for the whole of the largest write. The append
        // path above has always counted them; this one was missed when
        // conforms started riding in the archive, and nothing failed.
        final progress = _SaveProgress(
          port,
          1 +
              works.length +
              (mediaToStore.length + conforms.entries.length) *
                  anicelArchiveStreamPasses,
        );
        // Scalars only. Holding the BLOB here to read its geometry later
        // would keep every cel resident and give back exactly the memory
        // this streams to avoid.
        final geometry =
            <
              BrushFrameKey,
              ({String name, CanvasSize canvasSize, int tileSize, int length})
            >{};
        final layout = writeAnicelArchiveFile(
          path: tempPath,
          entries: () sync* {
            final projectEntry = buildAnicelProjectEntry(
              project: project,
              saveDirectory: saveDirectory,
              mediaEntryNames: mediaEntryNamesFor(mediaToStore),
              sessionFields: sessionFields,
            );
            yield (name: projectEntry.name, bytes: projectEntry.bytes);
            progress.step();
            for (final work in works) {
              // Resolved HERE rather than up front: the generator is pulled
              // lazily, so exactly one cel is resident at a time.
              final blob = work.resolveBlob();
              if (blob == null) {
                // The file this ref pointed into is gone. Skipping keeps
                // everything still readable — which is everything the user
                // can still see — instead of losing that too.
                progress.step();
                continue;
              }
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
                  name: anicelMediaEntryName(
                    entry.key,
                    framed: entry.value.storedIsFramed,
                  ),
                  length: entry.value.lengthSync(),
                  readInto: entry.value.readIntoSync,
                ),
                progress,
              ),
            // Conforms the same way, under their own prefix. A full
            // rewrite has no survivors to inherit from, so the sweep here
            // needs no removal list: an entry nothing hands over simply is
            // not written.
            for (final entry in conforms.entries.entries)
              _progressed(
                AnicelStreamedEntry(
                  name: entry.key,
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
      }),
    );
  }

  /// Opens [filePath].
  ///
  /// 🪦It took a recovery `overlayPath` to lay over the base until
  /// 2026-09-08 — a delta holding only the cels edited since the last save,
  /// merged in here so the caller never had to know which file a cel came
  /// from. The autosave tick saves the project file itself now, so there is
  /// no delta to merge and no stamp to refuse.
  Future<AnicelOpenResult> open({
    required String filePath,
  }) async {
    // Everything off the UI isolate; only the project + small refs come
    // back. No pixel bytes load here — each cel is a ~200-byte header
    // read for its key + geometry.
    final (:projectJsonBytes, :cels) = await Isolate.run(() {
      // A save that died partway opens as the last one that finished (plus,
      // if it died committing, what it had fully written). The file stays
      // torn on disk until the next save — which the service forces down
      // the FULL path (the incremental precondition re-parses this same
      // tail and fails) — so opening is enough to heal on save.
      final layout = readAnicelZipLayoutFile(filePath);
      final projectEntry = layout.projectEntry();
      if (projectEntry == null) {
        throw const FormatException('Not an Anicel project (.anicel).');
      }
      final raf = File(filePath).openSync();
      try {
        raf.setPositionSync(projectEntry.dataOffset);
        final projectJsonBytes = decodeAnicelProjectEntryBytes(
          projectEntry.name,
          raf.readSync(projectEntry.length),
        );
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

    final document = decodeAnicelProjectDocument(projectJsonBytes);
    final mediaEntryNames = document.mediaEntryNames;

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
    for (final entry in document.mediaRelativePaths.entries) {
      if (mediaEntryNames.containsKey(entry.key)) {
        continue;
      }
      final resolved = '$directory/${entry.value}';
      if (await File(resolved).exists()) {
        remap[entry.key] = resolved;
      }
    }

    final remapped = remapProjectMediaPaths(document.project, remap);
    return AnicelOpenResult(
      project: remapped,
      cels: cels,
      mediaEntryNames: mediaEntryNames,
      // Through the SAME remap the references just went through, and
      // narrowed to what the pool still holds. A fingerprint filed under a
      // path the project no longer uses describes nothing, and the one
      // moment that happens is this one — a project opened from a folder
      // that traveled has every reference rewritten to where it landed.
      session: document.session.withFingerprints(
        document.session.mediaFingerprints.narrowedTo(
          projectMediaPaths(remapped),
          moved: remap,
        ),
      ),
    );
  }

  static String _parentDirectory(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash <= 0 ? '.' : normalized.substring(0, slash);
  }

  /// 🚨★★★**A NAME THAT VANISHED WHILE WE HELD THE FILE IS NOT A LOSS.** On
  /// POSIX a delete or a move takes only the name; the bytes stay readable
  /// through the descriptor [OpenProjectFile] holds. The save's writer cannot
  /// use that descriptor — it runs in another isolate and opens by path — so
  /// the bytes are copied out through it into this run's room, every ref
  /// moves onto the copy, and the save goes on as though nothing had happened
  /// (F-72 follow-up; 유저 결정 2026-09-11 「복사 방향대로 가자」). Windows never
  /// gets here: it refuses to delete or move a file we hold.
  ///
  /// A no-op when there is nothing to rescue — or when the descriptor died with
  /// the name (a cloud provider evicting its local copy), the one loss left:
  /// the save then reports what it could not reach.
  static void _rescueAVanishedProjectFile(List<BrushFrameStore> stores) {
    final open = OpenProjectFile.instance;
    final held = open.heldPath;
    if (held == null || !open.heldNameVanished) {
      return;
    }
    final rescued = open.copyOut(
      held,
      '${SessionScratch.stagedFolder()}/rescued-'
      '${DateTime.now().microsecondsSinceEpoch}.anicel',
    );
    if (rescued == null) {
      return;
    }
    for (final store in stores) {
      store.repointFileRefs(held, rescued);
    }
    _retiring.add(rescued);
    // The refs read from the copy now; the vanished file's last descriptor
    // goes with this.
    open.hold(rescued);
  }

  /// Archives a ref may still read from, each to go the moment none does
  /// ([_retireUnread]): a rescue copy, an archive a save wrote and could not
  /// swap in, and a failed copy its project's next save superseded
  /// ([retireWhenUnread]).
  static final Set<String> _retiring = {};

  /// [archive] goes the moment no ref in [stores] reads from it — now, if
  /// none does. For an archive a save wrote and could not swap in once the
  /// work is safe elsewhere, and for a failed copy its project's next save
  /// superseded.
  static void retireWhenUnread(
    String archive,
    List<BrushFrameStore> stores,
  ) {
    _retiring.add(archive);
    _retireUnread(stores);
  }

  /// An archive in [_retiring] goes the moment no ref reads from it — the
  /// staged media's rule (유저 2026-08-27: 「사본 남으면 진짜
  /// 용서안할게」). A cel drawn on while the save ran keeps its old ref and
  /// its dirt, so the archive can outlive the save that made it, but only
  /// until the save that carries that cel.
  static void _retireUnread(List<BrushFrameStore> stores) {
    if (_retiring.isEmpty) {
      return;
    }
    final read = <String>{
      for (final store in stores)
        for (final ref in store.bakedSnapshotForSave().fileRefs.values)
          ref.filePath,
    };
    _retiring.removeWhere((archive) {
      if (read.any((path) => namesTheSameFile(path, archive))) {
        return false;
      }
      OpenProjectFile.instance.releaseFor(archive);
      ScratchFile.remove(archive);
      return true;
    });
  }

  // 🪦`samePath` stood here — one of five spellings of 「is this the same
  // project file」, and the only one that folded case (audit 09-25). It is
  // [namesTheSameFile] now, for all five.
}
