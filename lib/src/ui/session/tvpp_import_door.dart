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
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/import/tvpp_convert.dart';
import '../../models/import/tvpp_parse.dart';
import '../../models/project.dart';
import '../../models/project_id.dart';
import '../../models/tile_coord.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/track_se_migration.dart';
import '../../services/diagnostics/memory_black_box.dart';
import '../../services/editing/default_layer_helpers.dart'
    show defaultLayerIdForSequence;
import '../../services/editing/frame_id_mint.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/import/tvp_import_planner.dart';
import '../../services/import/tvpp_raster_decoder.dart';
import '../../services/persistence/folder_grant.dart'
    show FileArrival, FolderPicker;
import 'import_landing.dart' show ImportLanding;
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
    required SessionInternals internals,
    required RenderCaches renderCaches,
    required ProjectFile file,
    required ProjectFileDoor projectDoor,
    required MediaPool mediaPool,
  }) : _project = project,
       _changes = changes,
       _internals = internals,
       _renderCaches = renderCaches,
       _file = file,
       _projectDoor = projectDoor,
       _mediaPool = mediaPool;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;
  final ProjectFile _file;
  final ProjectFileDoor _projectDoor;
  final MediaPool _mediaPool;

  /// The bytes of every slot in [wave], read by OFFSET one at a time.
  ///
  /// 🚨A slot knows where its record is, so the decode never needs the
  /// file resident: the alternative is holding the whole .tvpp AND the
  /// buffers the decode builds, and both scale with the FILE rather than
  /// with the work — which on a phone is the allocation that gets the app
  /// killed.
  static Future<List<Uint8List>> _readWaveWindows(
    RandomAccessFile reader,
    List<(TvpImportPlan, Cut, PlannedCelBake, TvppSlot)> wave,
  ) async {
    final windows = <Uint8List>[];
    for (final (_, _, _, slot) in wave) {
      await reader.setPosition(slot.chunkOffset);
      windows.add(await reader.read(slot.chunkLength));
    }
    return windows;
  }

  /// One wave decoded across worker isolates — the import's whole cost
  /// (zlib + PackBits per cel; on 288 about 30s single-threaded), and it
  /// is pure, so it fans out. A cel that will not decode comes back as
  /// its exception rather than throwing the wave away.
  @visibleForTesting
  static Future<List<Object?>> decodeWave(
    List<(TvpImportPlan, Cut, PlannedCelBake, TvppSlot)> wave,
    List<Uint8List> windows,
  ) => Future.wait([
    for (var w = 0; w < wave.length; w++)
      _decodeOnWorker(
        windows[w],
        slot: wave[w].$4,
        canvasSize: wave[w].$1.cut.canvasSize,
      ),
  ]);

  /// One record decoded on a worker isolate of its own.
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
  static Future<Object?> _decodeOnWorker(
    Uint8List window, {
    required TvppSlot slot,
    required CanvasSize canvasSize,
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
    final width = canvasSize.width;
    final height = canvasSize.height;
    return Isolate.run(() {
      try {
        return decodeTvppSlotTiles(
          recordBytes: window,
          slot: windowSlot,
          width: width,
          height: height,
        );
      } on TvppRasterDecodeException catch (error) {
        return error;
      }
    });
  }

  /// Lands one decoded cel, or says why it could not be landed.
  ///
  /// A blank instance (빈 셀) decodes to zero tiles: the cel stays, its
  /// pixels stay absent — the same shape the drawing store gives an empty
  /// cel.
  void _bakeDecodedCel(
    Object? decoded, {
    required Cut cut,
    required PlannedCelBake bake,
    required List<ImportWarning> warnings,
  }) {
    if (decoded is TvppRasterDecodeException) {
      warnings.add(
        ImportWarning(
          'celUnreadable',
          '{file}: the picture could not be read — {detail}',
          {'file': bake.sourceFile, 'detail': '$decoded'},
        ),
      );
      return;
    }
    final tiles = decoded as List<TvppCelTile>?;
    if (tiles == null || tiles.isEmpty) {
      return;
    }
    bakeCelSurface(
      _renderCaches.brushFrameStore,
      _internals.brushFrameKeyForCut(cut, bake.layerId, bake.frameId),
      BitmapSurface(canvasSize: cut.canvasSize).putTiles([
        for (final tile in tiles)
          (
            coord: TileCoord(x: tile.x, y: tile.y),
            tile: BitmapTile(

              size: defaultCelTileSize,
              pixels: tile.pixels,
            ),
          ),
      ]),
    );
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
  Future<List<ImportWarning>> bake(
    TvppProjectRead read, {
    void Function(double fraction)? onProgress,
  }) async {
    assert(
      _file.path == null && !_project.historyManager.canUndo,
      'a .tvpp bakes only into the session born for it — see '
      'TvppProjectRead',
    );
    // The other candidate for last-thing-the-app-ever-did: decoding a
    // whole TVPaint project holds every cel it builds.
    MemoryBlackBox.begin('tvpp-import');
    final warnings = [...read._warnings];
    await _bakeEveryCel(read, warnings: warnings, onProgress: onProgress);
    _registerSounds(read._audioPaths, warnings: warnings);
    _projectDoor.warmAudioConforms();
    _mediaPool.refreshMediaExistence();
    // A conversion is unsaved by definition — nothing on disk holds it.
    _file.markDirty();
    _changes.warmActiveCut();
    _changes.notifyChanged();
    MemoryBlackBox.end('tvpp-import');
    return warnings;
  }

  /// Every cel [read] planned, decoded out of its file and baked into the
  /// drawings' store; what would not decode joins [warnings].
  ///
  /// Decoding is the import's whole cost (zlib + PackBits per cel, on 288:
  /// ~30s of it, single-threaded) and it is pure — so it fans out over
  /// worker isolates, in WAVES the size of the pool so at most that many
  /// full-canvas RGBA buffers are ever alive at once. The GPU bake stays
  /// here: it needs the UI thread and is cheap next to the decode.
  /// Isolate.run moves its result out (no copy back).
  Future<void> _bakeEveryCel(
    TvppProjectRead read, {
    required List<ImportWarning> warnings,
    void Function(double fraction)? onProgress,
  }) async {
    final work = _tvppBakeWork(read._plans);
    final pool = math.max(1, math.min(Platform.numberOfProcessors - 1, 8));
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
    try {
      for (var at = 0; at < work.length; at += pool) {
        final wave = work.sublist(at, math.min(at + pool, work.length));
        final decoded = await decodeWave(
          wave,
          await _readWaveWindows(reader, wave),
        );
        for (var i = 0; i < wave.length; i++) {
          final (_, bakedCut, bake, _) = wave[i];
          bakedSoFar += 1;
          onProgress?.call(bakedSoFar / work.length);
          _bakeDecodedCel(
            decoded[i],
            cut: bakedCut,
            bake: bake,
            warnings: warnings,
          );
        }
      }
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
  final name = tvppPath
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceAll(RegExp(r'\.tvpp$', caseSensitive: false), '');
  // The planner still emits each clip's sound as a per-cut SE row (the
  // shape TVPaint stores); SE rows LIVE on the track's global axis now, so
  // the same lift the legacy-file migration uses promotes them — one law
  // for both doors.
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
  final mint = _newProjectIdMint();
  final plans = <(TvpImportPlan, Map<String, TvppSlot>)>[];
  for (var c = 0; c < parsed.clips.length; c++) {
    final conversion = convertTvppClip(parsed.clips[c], clipIndex: c);
    final plan = planTvpImport(
      parsed: conversion.result,
      // Block files are synthetic slot keys, resolved against
      // [conversion.slotsByFile] at bake time — not paths.
      resolveFile: (key) => key,
      mint: mint,
    );
    warnings.addAll(plan.warnings);
    plans.add((plan, conversion.slotsByFile));
  }
  return plans;
}

/// The ids of a project being MADE — before any session holds it, so there
/// is nothing in it to step past: each id is the next of its kind, in the
/// forms an import mints into a project that exists
/// ([ImportLanding.idMint]). The drawings' come from the process's one mint
/// ([mintFrameId]), which the session born for the project goes on counting
/// from.
ImportIdMint _newProjectIdMint() {
  var layers = 0;
  var cuts = 0;
  return ImportIdMint(
    nextLayerId: () => defaultLayerIdForSequence(layers += 1),
    nextFrameId: mintFrameId,
    nextCutId: () => CutId('import-cut-${cuts += 1}'),
  );
}
