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
import '../../services/import/media_import_planner.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/import/tvp_import_planner.dart';
import '../../services/import/tvpp_raster_decoder.dart';
import '../../services/persistence/folder_grant.dart' show FolderPicker;
import 'active_cut_controllers.dart';
import 'frame_clipboard.dart';
import 'import_landing.dart';
import 'layer_clipboard.dart';
import 'media_pool.dart';
import 'playback_rig.dart';
import 'project_file.dart';
import 'project_file_door.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// The TVPaint project door.
class TvppImportDoor {
  TvppImportDoor({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required RenderCaches renderCaches,
    required ImportLanding landing,
    required ActiveCutControllers controllers,
    required PlaybackRig playbackRig,
    required ProjectFile file,
    required ProjectFileDoor projectDoor,
    required MediaPool mediaPool,
    required FrameClipboard clipboard,
    required LayerClipboard layerClipboard,
    required ValueNotifier<int> frameSeekCommitted,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _internals = internals,
       _renderCaches = renderCaches,
       _landing = landing,
       _controllers = controllers,
       _playbackRig = playbackRig,
       _file = file,
       _projectDoor = projectDoor,
       _mediaPool = mediaPool,
       _clipboard = clipboard,
       _layerClipboard = layerClipboard,
       _frameSeekCommitted = frameSeekCommitted;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;
  final ImportLanding _landing;
  final ActiveCutControllers _controllers;
  final PlaybackRig _playbackRig;
  final ProjectFile _file;
  final ProjectFileDoor _projectDoor;
  final MediaPool _mediaPool;
  final FrameClipboard _clipboard;
  final LayerClipboard _layerClipboard;
  final ValueNotifier<int> _frameSeekCommitted;

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
  static Future<List<Object?>> _decodeWave(
    List<(TvpImportPlan, Cut, PlannedCelBake, TvppSlot)> wave,
    List<Uint8List> windows,
  ) => Future.wait([
    for (var w = 0; w < wave.length; w++)
      () {
        final (plan, _, _, slot) = wave[w];
        final window = windows[w];
        // The record's offsets count from the record, so a window
        // rebased to zero is the same input by a different name.
        final windowSlot = TvppSlot(
          kind: slot.kind,
          chunkOffset: 0,
          chunkLength: slot.chunkLength,
          compressed: slot.compressed,
          v10WholeCanvas: slot.v10WholeCanvas,
        );
        final width = plan.cut.canvasSize.width;
        final height = plan.cut.canvasSize.height;
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
      }(),
  ]);

  /// Lands one decoded cel, or says why it could not be landed.
  ///
  /// A blank instance (빈 셀) decodes to zero tiles: the cel stays, its
  /// pixels stay absent — the same shape the drawing store gives an empty
  /// cel.
  void _bakeDecodedCel(
    Object? decoded, {
    required Cut cut,
    required PlannedCelBake bake,
    required List<String> warnings,
  }) {
    if (decoded is TvppRasterDecodeException) {
      warnings.add('${bake.sourceFile}: $decoded');
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
          BitmapTile(
            coord: TileCoord(x: tile.x, y: tile.y),
            size: defaultCelTileSize,
            pixels: tile.pixels,
          ),
      ]),
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
  static Future<TvppParseResult?> _readTvppStructure(
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
    required List<String> warnings,
  }) {
    final mint = _landing.idMint();
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

  /// The whole-state reset an .anicel open performs, minus the parts that
  /// only exist for saved files (cel restore, healing).
  void _resetSessionForImportedProject(CutId firstCutId) {
    _renderCaches.brushFrameStore.restoreFromFile(const {});
    _renderCaches.conteInkRowStore.restoreFromFile(const {});
    _renderCaches.conteInkPageStore.restoreFromFile(const {});
    _renderCaches.envelopeInkStore.restoreFromFile(const {});
    _project.historyManager.clear();
    _clipboard.clear();
    _layerClipboard.clear();
    _selection.clearAllSelections();
    _selection.trackFrameRangeSelection.value = null;
    _timeline.editingSession.setActiveCutId(firstCutId);
    _controllers.rebuild();
    _file.unbind();
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

  /// Opens a TVPaint project file AS A PROJECT — a .tvpp holds several
  /// cuts, so it replaces the session's project the way an .anicel open
  /// does: every clip a cut, pixels/timeline/folders/marks/camera/audio
  /// straight out of the file. The result is a NEW UNSAVED project (no
  /// [ProjectFile.path]); the first save asks where the .anicel goes.
  ///
  /// Returns the accumulated warnings, or null when the file is not
  /// readable as a TVPaint project. The CALLER gates unsaved work — this
  /// replaces everything.
  Future<List<String>?> openAsProject({
    required String tvppPath,
    void Function(double fraction)? onProgress,
    void Function(Duration waited)? onWaiting,
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
    // The other candidate for last-thing-the-app-ever-did: decoding a
    // whole TVPaint project holds every cel it builds.
    MemoryBlackBox.begin('tvpp-import');

    _playbackRig.playback.stop();
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
    final warnings = [...parsed.warnings];
    if (source.staged) {
      // The last resort fired. Said out loud on purpose (유저 2026-08-27:
      // 「최후 수단이 발동됐다는 걸 표시해줬으면」): the wait is supposed to
      // make this road unreachable, so a build that still takes it should
      // be visible rather than quietly slower — and if it never appears
      // in the field, the road comes out.
      warnings.add('제자리에서 읽지 못해 임시 사본으로 열었습니다 — 이 문구가 보이면 알려주세요.');
    }
    final plans = _planTvppClips(parsed, warnings: warnings);
    // ⛔EQUIVALENT to the parser's own refusal today: a structure with no
    // clip header does not parse at all, so `plans` is empty only when
    // `parsed.clips` is — and mutating this away leaves the suite green
    // (2026-09-05). Kept because it is the statement of the door's
    // contract: replacing the session with an EMPTY project is worse
    // than not opening.
    if (plans.isEmpty) {
      return null;
    }

    final name = tvppPath
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'\.tvpp$', caseSensitive: false), '');
    _project.repository.replaceProject(
      Project(
        id: ProjectId('tvpp-${DateTime.now().toUtc().millisecondsSinceEpoch}'),
        name: name,
        createdAt: DateTime.now().toUtc(),
        cameraSize: cameraSize,
        tracks: [
          // The planner still emits each clip's sound as a per-cut SE
          // row (the shape TVPaint stores); SE rows LIVE on the track's
          // global axis now, so the same lift the legacy-file migration
          // uses promotes them — one law for both doors.
          () {
            final lifted = liftCutSeLayersToTrack(
              const TrackId('default-track'),
              [for (final (plan, _) in plans) plan.cut],
            );
            return Track(
              id: const TrackId('default-track'),
              name: 'Track 1',
              cuts: lifted.cuts,
              seLayers: lifted.seLayers,
            );
          }(),
        ],
        // The sound tracks reference their files; register them so the
        // pool knows the paths and RELINK can say when one is missing.
        mediaAssets: const [],
      ),
    );

    _resetSessionForImportedProject(plans.first.$1.cut.id);

    // Decoding is the import's whole cost (zlib + PackBits per cel, on
    // 288: ~30s of it, single-threaded) and it is pure — so it fans out
    // over worker isolates, in WAVES the size of the pool so at most
    // that many full-canvas RGBA buffers are ever alive at once. The
    // GPU bake stays here: it needs the UI thread and is cheap next to
    // the decode. Isolate.run moves its result out (no copy back).
    final work = _tvppBakeWork(plans);
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
    final reader = await File(source.path).open();
    try {
      for (var at = 0; at < work.length; at += pool) {
        final wave = work.sublist(at, math.min(at + pool, work.length));
        final decoded = await _decodeWave(
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

    // The audio references become pool assets so relink and existence
    // checks see them; a missing file surfaces as a warning, not a crash.
    final audioPaths = <String>{
      for (final clip in parsed.clips)
        for (final track in clip.audioTracks) track.filePath,
    };
    if (audioPaths.isNotEmpty) {
      unawaited(_mediaPool.addMediaAssets(audioPaths.toList()));
      _project.historyManager.clear();
      for (final path in audioPaths) {
        if (!File(path).existsSync()) {
          warnings.add('사운드 파일이 이 자리에 없다: $path');
        }
      }
    }

    _projectDoor.settleConformCache();
    _projectDoor.warmAudioConforms();
    _mediaPool.refreshMediaExistence();
    // A conversion is unsaved by definition — nothing on disk holds it.
    // ⛔MUTANT SURVIVES, an inner guard already answers (2026-09-08): the
    // `historyManager.clear()` in the reset above runs the dirty listener
    // the session registers at construction, so deleting this line leaves
    // the suite green. Kept as the statement of the law.
    _file.markDirty();
    _changes.warmActiveCut();
    _frameSeekCommitted.value += 1;
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
    MemoryBlackBox.end('tvpp-import');
    return warnings;
  }
}
