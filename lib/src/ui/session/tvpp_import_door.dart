// The door a TVPaint project comes in through — a .tvpp holds several
// cuts, so it arrives as a PROJECT rather than as an import into the one
// on screen.
//
// Its own object since round 8 (G4-2, 2026-09-08). It is the file door
// that did not leave with the others in G1: the image/PSD/PDF doors
// ([ProjectImportDoors]), the delivery folder ([CutFolderImportDoor]) and
// the .anicel ([ProjectFileDoor]) all moved out then, and this one stayed
// behind as the longest member on the session.

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/on_a_worker.dart';
import '../../core/turns.dart';
import '../../core/worker_count.dart';
import '../../models/app_frame_grid_settings.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/import/tvpp_convert.dart';
import '../../models/import/tvpp_parse.dart';
import '../../models/project.dart';
import '../../models/project_id.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/track_se_migration.dart';
import '../../services/diagnostics/memory_black_box.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/import/tvp_import_planner.dart';
import '../../services/import/tile_cutter.dart';
import '../../services/import/tvpp_raster_decoder.dart';
import '../../services/layer_pose_matrix.dart' show LayerPlacement;
import '../../services/persistence/brush_drawing_binary_codec.dart'
    show AnicelLaidCel, freeLaidCel;
import '../../services/persistence/folder_grant.dart'
    show FileArrival, FolderPicker, MaterializeCancelled;
import '../../services/persistence/provider_documents.dart'
    show ProviderDocuments;
import 'media_pool.dart';
import 'project_file.dart';
import 'project_file_door.dart';
import 'render_caches.dart';
import 'session_roles.dart';
import '../../models/import/import_warning.dart';

/// The TVPaint project door.
class TvppImportDoor {
  TvppImportDoor({
    required ProjectAccess project,
    required ChangeSink changes,
    required RenderCaches renderCaches,
    required ProjectFile file,
    required ProjectFileDoor projectDoor,
    required MediaPool mediaPool,
  }) : _project = project,
       _changes = changes,
       _renderCaches = renderCaches,
       _file = file,
       _projectDoor = projectDoor,
       _mediaPool = mediaPool;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final RenderCaches _renderCaches;
  final ProjectFile _file;
  final ProjectFileDoor _projectDoor;
  final MediaPool _mediaPool;

  /// Every cel of [work] decoded on workers, [atOnce] at a time, and
  /// handed to [landed] as its worker answers: its record cut into the
  /// tiles its [CelLay] lays it on, or the exception that says why it
  /// would not decode. The import's whole cost (zlib + PackBits per cel;
  /// on 288 about 30s single-threaded), and it is pure, so it fans out.
  ///
  /// 🚨A CEL LANDS AS ITS WORKER ANSWERS (card F-608 ③). ↩️Till 2026-11-16
  /// the work went in WAVES the size of the pool, and a wave landed when
  /// its slowest cel was done: the open showed no percent till the first
  /// wave was. A worker free now takes the next cel ([Turns]).
  ///
  /// A cel's record comes from [windowOf] as its turn begins, so no more
  /// records are held than there are turns. [stopped] is asked as a cel
  /// lands — a stop is honoured after the cel in hand — and once it says
  /// so no more is read, and what a worker still hands back is given back
  /// unlaid.
  @visibleForTesting
  static Future<void> decodeEach(
    List<(TvpImportPlan, Cut, PlannedCelBake, TvppSlot)> work, {
    required int atOnce,
    required Future<Uint8List> Function(TvppSlot slot) windowOf,
    required Future<void> Function(int index, CelLay lay, Object decoded)
    landed,
    required bool Function() stopped,
  }) async {
    final turns = Turns(atOnce);
    var halted = false;
    await Future.wait([
      for (var i = 0; i < work.length; i += 1)
        turns.run(() async {
          final (_, cut, _, slot) = work[i];
          final lay = celLayOf(
            picture: cut.canvasSize,
            canvas: cut.canvasSize,
            placement: const LayerPlacement.identity(),
          );
          if (lay == null || halted) {
            return;
          }
          final decoded = await _decodeOnWorker(
            await windowOf(slot),
            slot: slot,
            lay: lay,
          );
          if (halted) {
            if (decoded is AnicelLaidCel) {
              freeLaidCel(decoded);
            }
            return;
          }
          await landed(i, lay, decoded);
          halted = stopped();
        }),
    ]);
  }

  /// One record decoded on a worker isolate of its own, and cut there into
  /// the tiles [lay] lays it on — the road every picture a file holds is
  /// cut by (`cutFileInWorker`).
  ///
  /// 🚨ITS OWN FUNCTION, so the worker is built where nothing but its
  /// inputs is in scope. `Isolate.run` copies the closure's whole context
  /// chain, not only the names the closure reads. Until 2026-09-16 the
  /// closure was built inside the wave's loop: it read four values, yet
  /// its chain held the wave and every window in it, so each cel's message
  /// carried the other workers' records and every plan and cut the wave
  /// held. Measured by putting an object no message may carry in a slot no
  /// worker read: the send refused, JIT and AOT alike. The arguments are
  /// the only way in, and `a_cel_worker_is_sent_only_its_own_record_test`
  /// fails the moment anything else rides along.
  static Future<Object> _decodeOnWorker(
    Uint8List window, {
    required TvppSlot slot,
    required CelLay lay,
  }) {
    // The record's offsets count from the record, so a window rebased to
    // zero is the same input by a different name.
    final windowSlot = TvppSlot(
      kind: slot.kind,
      chunkOffset: 0,
      chunkLength: slot.chunkLength,
      compressed: slot.compressed,
      v10WholeCanvas: slot.v10WholeCanvas,
    );
    final size = lay.picture;
    final width = size.width;
    final layout = lay.layout;
    final cut = tileCutOf(lay.cut);
    return onAWorker<Object>(() {
      try {
        return laidCelOf(
          layout,
          TileCutter.cutting(
            cut,
            width,
            (row) => tvppSlotRows(
              recordBytes: window,
              slot: windowSlot,
              size: size,
              row: row,
            ),
          ),
        );
      } on TvppRasterDecodeException catch (error) {
        return error;
      }
    });
  }

  /// Lands one decoded cel — or answers why it could not be landed.
  ///
  /// A blank instance (빈 셀) decodes to zero tiles: the cel stays, its
  /// pixels stay absent — the same shape the drawing store gives an empty
  /// cel.
  Future<ImportWarning?> _landCel(
    Object decoded, {
    required CelLay lay,
    required Cut cut,
    required PlannedCelBake bake,
  }) async {
    if (decoded is TvppRasterDecodeException) {
      return ImportWarning(
        'celUnreadable',
        '{file}: the picture could not be read — {detail}',
        {'file': bake.sourceFile, 'detail': '$decoded'},
      );
    }
    final laid = decoded as AnicelLaidCel;
    if (laid.tiles.isEmpty) {
      return null;
    }
    bakeCelSurface(
      _renderCaches.brushFrameStore,
      _project.brushFrameKeyForCut(cut, bake.layerId, bake.frameId),
      await layCut(lay, laid),
    );
    return null;
  }

  /// Every cel this import has to bake, paired with the cut it landed in
  /// and the slot its bytes live in. A plan whose cut did not land, or a
  /// bake whose slot is missing, simply has no work.
  List<(TvpImportPlan, Cut, PlannedCelBake, TvppSlot)> _tvppBakeWork(
    List<(TvpImportPlan, Map<String, TvppSlot>)> plans,
  ) {
    final work = <(TvpImportPlan, Cut, PlannedCelBake, TvppSlot)>[];
    for (final (plan, slotsByFile) in plans) {
      final bakedCut = _project.cutById(plan.cut.id);
      if (bakedCut == null) {
        continue;
      }
      for (final bake in plan.bakes) {
        final slot = slotsByFile[bake.sourceFile];
        if (slot != null) {
          work.add((plan, bakedCut, bake, slot));
        }
      }
    }
    return work;
  }

  /// Bakes every cel of [read] into THIS session — the session born for it
  /// (`OpenProjects.prepare(read.project)`), and no other: a .tvpp opens AS
  /// A PROJECT of its own (I-7, and the user's rule — a .tvpp holds several
  /// cuts), so its cuts are this session's from birth, and what is left is
  /// their pictures, their sounds, and the word that nothing on disk holds
  /// any of it. See [ProjectFileRead] for the replace this used to be.
  ///
  /// The result is a NEW UNSAVED project (no [ProjectFile.path]); the first
  /// save asks where the .anicel goes. Answers the accumulated warnings.
  ///
  /// A stop [isCancelled] reports is honoured after the cel in hand
  /// ([MaterializeCancelled]): the session is in no tab yet, so the door
  /// drops it and the app is where it was.
  Future<List<ImportWarning>> bake(
    TvppProjectRead read, {
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    assert(
      _file.path == null && !_project.historyManager.canUndo,
      'a .tvpp bakes only into the session born for it — see '
      'TvppProjectRead',
    );
    // The other candidate for last-thing-the-app-ever-did: decoding a
    // whole TVPaint project holds every cel it builds.
    MemoryBlackBox.begin('tvpp-import');
    try {
      final warnings = [...read._warnings];
      await _bakeEveryCel(
        read,
        warnings: warnings,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      _registerSounds(read._audioPaths, warnings: warnings);
      _projectDoor.warmAudioConforms();
      _mediaPool.refreshMediaExistence();
      // A conversion is unsaved by definition — nothing on disk holds it.
      _file.markDirty();
      _changes.warmActiveCut();
      _changes.notifyChanged();
      return warnings;
    } finally {
      // A stop or a throw is not a kill, and an entry left open says one.
      MemoryBlackBox.end('tvpp-import');
    }
  }

  /// Every cel [read] planned, decoded out of its file and baked into the
  /// drawings' store; what would not decode joins [warnings].
  ///
  /// Decoding is the import's whole cost and it is pure, so it fans out
  /// over worker isolates ([decodeEach]); the bake stays here — it needs
  /// the UI thread and is cheap next to the decode.
  Future<void> _bakeEveryCel(
    TvppProjectRead read, {
    required List<ImportWarning> warnings,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final work = _tvppBakeWork(read._plans);
    var bakedSoFar = 0;
    // 🚨READ BY OFFSET, ONE SLOT AT A TIME.
    //
    // A slot knows where its record is, so the decode never needs the
    // file resident — the reader seeks, takes that record, and nothing
    // else is held. Two costs went with the old shape of handing the
    // whole `Uint8List` around:
    //
    // - `Isolate.run` COPIES what its closure captures, so capturing the
    //   file gave every worker its own copy: a pool of eight meant eight
    //   whole projects at once, on top of the original and everything the
    //   import had already built;
    // - and the file stayed reachable for the WHOLE import, which on a
    //   200MB project is 200MB held for minutes beside the cels being
    //   made.
    //
    // Both scale with the FILE rather than with the work, which on a
    // phone is the allocation that gets the app killed.
    final source = read._source;
    final reader = await File(source.path).open();
    // One read at a time: a seek and a read are two steps, and a turn that
    // came between them would read another cel's record.
    final reading = Turns(1);
    try {
      await decodeEach(
        work,
        atOnce: workersFor(Platform.numberOfProcessors, ceiling: 8),
        windowOf: (slot) => reading.run(() async {
          await reader.setPosition(slot.chunkOffset);
          return reader.read(slot.chunkLength);
        }),
        landed: (index, lay, decoded) async {
          final (_, bakedCut, bake, _) = work[index];
          final unread = await _landCel(
            decoded,
            lay: lay,
            cut: bakedCut,
            bake: bake,
          );
          if (unread != null) {
            warnings.add(unread);
          }
          bakedSoFar += 1;
          onProgress?.call(bakedSoFar / work.length);
        },
        stopped: () => isCancelled?.call() ?? false,
      );
      MaterializeCancelled.throwIf(isCancelled);
    } finally {
      await reader.close();
      // The staged copy outlives the decode now, because the decode
      // reads FROM it. It was deleted the moment the bytes were in hand
      // back when the whole file was held in memory.
      if (source.staged) {
        unawaited(
          File(source.path).delete().then<void>((_) {}, onError: (_) {}),
        );
      }
    }
  }

  /// The sounds the file's clips play become pool assets, so relink and
  /// existence checks see them — registered as the file's, not as an edit
  /// to undo; a missing file surfaces as a warning, not a crash.
  void _registerSounds(
    Set<String> audioPaths, {
    required List<ImportWarning> warnings,
  }) {
    if (audioPaths.isEmpty) {
      return;
    }
    unawaited(_mediaPool.addMediaAssets(audioPaths.toList()));
    _project.historyManager.clear();
    for (final path in audioPaths) {
      if (!File(path).existsSync()) {
        warnings.add(
          ImportWarning(
            'soundMissing',
            'The sound file is not at this address: {path}',
            {'path': path},
          ),
        );
      }
    }
  }
}

/// A .tvpp as READ and converted — the project it becomes and every cel
/// still to be baked out of it — before any session holds it.
///
/// A .tvpp opens the way a .anicel does ([ProjectFileRead]): read first,
/// then the session is born with [project], and [TvppImportDoor.bake] fills
/// in the pictures. Nothing is replaced, so nothing is reset.
class TvppProjectRead {
  TvppProjectRead._({
    required this.project,
    required List<(TvpImportPlan, Map<String, TvppSlot>)> plans,
    required ({String path, bool staged}) source,
    required List<ImportWarning> warnings,
    required Set<String> audioPaths,
  }) : _plans = plans,
       _source = source,
       _warnings = warnings,
       _audioPaths = audioPaths;

  /// The project the file becomes — every clip a cut, the timeline,
  /// folders, marks, camera and sound straight out of the file.
  final Project project;

  final List<(TvpImportPlan, Map<String, TvppSlot>)> _plans;

  /// The bytes the cels are baked from — a staged copy the bake deletes
  /// when it is done with it.
  final ({String path, bool staged}) _source;
  final List<ImportWarning> _warnings;
  final Set<String> _audioPaths;
}

/// Reads the TVPaint project at [tvppPath] and converts it into the project
/// it opens as — or null when it is not readable as one ([TvppProjectRead]).
Future<TvppProjectRead?> readTvppProject({
  required String tvppPath,
  void Function(Duration waited, FileArrival arrival)? onWaiting,
  bool Function()? isCancelled,
}) async {
  // A read failure THROWS (FileSystemException, out of the
  // materializer) and only a parse failure answers null — the door
  // used to show 「읽을 수 없는 파일」 for both, which sent the user
  // chasing a format problem when the real one was access (실측
  // 08-26: Drive on iPhone). Same materializer as the .anicel open;
  // the staged copy is read-and-discard here.
  final source = await FolderPicker.materializeOpenedFile(
    tvppPath,
    // A door that can be cancelled waits as long as the file takes;
    // one that cannot keeps the default backstop.
    within: isCancelled == null ? const Duration(minutes: 10) : null,
    onWaiting: onWaiting,
    isCancelled: isCancelled,
  );
  final parsed = await _readTvppStructure(source);
  if (parsed == null) {
    return null;
  }
  final warnings = [...parsed.warnings];
  if (source.staged) {
    // The last resort fired. Said out loud on purpose (유저 2026-08-27:
    // 「최후 수단이 발동됐다는 걸 표시해줬으면」): the wait is supposed to
    // make this road unreachable, so a build that still takes it should
    // be visible rather than quietly slower — and if it never appears
    // in the field, the road comes out.
    warnings.add(
      const ImportWarning(
        'stagedCopy',
        'Opened through a temporary copy because the file could not be '
        'read in place — please report seeing this.',
      ),
    );
  }
  final plans = _planTvppClips(parsed, warnings: warnings);
  // ⛔EQUIVALENT to the parser's own refusal today: a structure with no
  // clip header does not parse at all, so `plans` is empty only when
  // `parsed.clips` is — and mutating this away leaves the suite green
  // (2026-09-05). Kept because it is the statement of the door's
  // contract: opening an EMPTY project is worse than not opening.
  if (plans.isEmpty) {
    return null;
  }
  return TvppProjectRead._(
    project: _projectOf(tvppPath, parsed, plans),
    plans: plans,
    source: source,
    warnings: warnings,
    audioPaths: {
      for (final clip in parsed.clips)
        for (final track in clip.audioTracks) track.filePath,
    },
  );
}

/// The project the .tvpp at [tvppPath] becomes — every clip of [parsed] a
/// cut, as [plans] made them, under the file's own name.
Project _projectOf(
  String tvppPath,
  TvppParseResult parsed,
  List<(TvpImportPlan, Map<String, TvppSlot>)> plans,
) {
  // The .tvpp becomes the WHOLE project, so its shooting frame does
  // too — fitting a 960×430 layout camera into our 16:9 default framed
  // wider than TVPaint did (288, hands-on).
  final cameraSize =
      parsed.projectCameraWidth != null && parsed.projectCameraHeight != null
      ? CanvasSize(
          width: parsed.projectCameraWidth!,
          height: parsed.projectCameraHeight!,
        )
      : defaultProjectCameraSize;
  // By the provider's name for a document (PICK-7): its URI's last
  // segment is an id.
  final name = ProviderDocuments.nameOf(
    tvppPath,
  ).replaceAll(RegExp(r'\.tvpp$', caseSensitive: false), '');
  // The planner still emits each clip's sound as a per-cut SE row (the
  // shape TVPaint stores); SE rows LIVE on the track's global axis now, so
  // the lift promotes them — the one the .clip door's cuts go through too.
  final lifted = liftCutSeLayersToTrack(
    const TrackId('default-track'),
    [for (final (plan, _) in plans) plan.cut],
  );
  return Project(
    id: ProjectId('tvpp-${DateTime.now().toUtc().millisecondsSinceEpoch}'),
    name: name,
    createdAt: DateTime.now().toUtc(),
    cameraSize: cameraSize,
    tracks: [
      Track(
        id: const TrackId('default-track'),
        name: 'Track 1',
        cuts: lifted.cuts,
        seLayers: lifted.seLayers,
      ),
    ],
    // The sound tracks reference their files; the bake registers them so
    // the pool knows the paths and RELINK can say when one is missing.
    mediaAssets: const [],
  );
}

/// The structure of the .tvpp at [source], or null when it is not one.
///
/// ⛔SCOPED, so the whole-file bytes are collectable the moment the
/// structure is out of them. Everything after this reads the file by
/// OFFSET — a slot knows where its record is, so the long half of an
/// import (decoding every cel) never needs the file resident. Before
/// this the bytes stayed reachable for the entire import, which on a
/// 200MB project is 200MB held for minutes next to everything the
/// decode is building.
Future<TvppParseResult?> _readTvppStructure(
  ({String path, bool staged}) source,
) async {
  try {
    final bytes = await File(source.path).readAsBytes();
    return parseTvppStructure(bytes);
  } on TvppParseException {
    if (source.staged) {
      unawaited(
        File(source.path).delete().then<void>((_) {}, onError: (_) {}),
      );
    }
    return null;
  }
}

/// One import plan per clip, with the slots its bakes will read from.
/// Every plan's warnings join [warnings] as they are made.
List<(TvpImportPlan, Map<String, TvppSlot>)> _planTvppClips(
  TvppParseResult parsed, {
  required List<ImportWarning> warnings,
}) {
  final mint = ImportIdMint.forANewProject();
  final plans = <(TvpImportPlan, Map<String, TvppSlot>)>[];
  for (var c = 0; c < parsed.clips.length; c++) {
    final conversion = convertTvppClip(parsed.clips[c], clipIndex: c);
    final plan = planTvpImport(
      parsed: conversion.result,
      // Block files are synthetic slot keys, resolved against
      // [conversion.slotsByFile] at bake time — not paths.
      resolveFile: (key) => key,
      mint: mint,
      unnamedMark: AppFrameGridSettings.settings.value.unnamedMark,
    );
    warnings.addAll(plan.warnings);
    plans.add((plan, conversion.slotsByFile));
  }
  return plans;
}
