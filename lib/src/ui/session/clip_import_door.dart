// The door a CLIP STUDIO PAINT file comes in through. A .clip holds every
// timeline the file was cut into, so it arrives as a PROJECT rather than as
// an import into the one on screen — the .tvpp door's shape (I-7): read and
// planned first, then the session is born with the project, and this bakes
// the pictures into it.

import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/bitmap_surface.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/camera_pose.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/import/import_warning.dart';
import '../../models/project.dart';
import '../../models/project_frame_rate.dart';
import '../../models/project_id.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/track_se_migration.dart';
import '../../services/diagnostics/memory_black_box.dart';
import '../../services/import/clip_cel_raster.dart';
import '../../services/import/clip_container.dart';
import '../../services/import/clip_document.dart';
import '../../services/import/clip_import_planner.dart';
import '../../services/import/media_import_planner.dart' show ImportIdMint;
import '../../services/import/raster_cel_import.dart' show bakeCelTiles;
import '../../services/persistence/folder_grant.dart'
    show FileArrival, FolderPicker;
import '../../services/persistence/provider_documents.dart'
    show ProviderDocuments;
import '../../services/persistence/session_scratch.dart';
import '../text/app_strings.dart';
import 'project_file.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// The track every cut of a CLIP STUDIO file lands on.
const _track = TrackId('default-track');

/// A .clip as READ and planned — the project it becomes and every picture
/// still to be baked out of it — before any session holds it.
final class ClipProjectRead {
  ClipProjectRead._({
    required this.project,
    required ClipImportPlan plan,
    required ({String path, bool staged}) source,
  }) : _plan = plan,
       _source = source;

  /// The project the file becomes — every timeline a 겸용 cut, its layers
  /// and cels as the planner shaped them.
  final Project project;
  final ClipImportPlan _plan;

  /// The bytes the pictures are baked from — a staged copy the bake
  /// deletes when it is done with it.
  final ({String path, bool staged}) _source;
}

/// Reads the CLIP STUDIO file at [clipPath] and plans the project it opens
/// as — or null when it is not one.
///
/// The embedded database is read on a worker (a large file's is tens of
/// megabytes); its copy waits in this run's room, not the system's temp,
/// and goes the moment it is read.
Future<ClipProjectRead?> readClipProject({
  required String clipPath,
  void Function(Duration waited, FileArrival arrival)? onWaiting,
  bool Function()? isCancelled,
}) async {
  final source = await FolderPicker.materializeOpenedFile(
    clipPath,
    within: isCancelled == null ? const Duration(minutes: 10) : null,
    onWaiting: onWaiting,
    isCancelled: isCancelled,
  );
  final scratch = Directory(SessionScratch.volatileFolder())
    ..createSync(recursive: true);
  final document = await _readStructure(source.path, scratch.path);
  if (document == null) {
    if (source.staged) {
      unawaited(
        File(source.path).delete().then<void>((_) {}, onError: (_) {}),
      );
    }
    return null;
  }
  final name = ProviderDocuments.nameOf(
    clipPath,
  ).replaceAll(RegExp(r'\.clip$', caseSensitive: false), '');
  final plan = planClipImport(
    document: document,
    name: name,
    hiddenFolderName: AppText.strings.clipHiddenLayers,
    trackId: _track,
    mint: ImportIdMint.forANewProject(),
  );
  return ClipProjectRead._(
    project: _projectOf(name, document, plan),
    plan: plan,
    source: source,
  );
}

/// The structure of the file at [path], read on a worker of its own — or
/// null when it is not a CLIP STUDIO file.
///
/// ⛔ITS OWN FUNCTION, so the worker carries the two paths and nothing
/// else: `Isolate.run` copies the closure's whole context chain (the .tvpp
/// door's measured lesson).
Future<ClipDocument?> _readStructure(String path, String scratch) =>
    Isolate.run(() {
      try {
        return readClipDocument(path, scratch: Directory(scratch));
      } on ClipFormatException {
        return null;
      }
    });

/// The project [plan] makes of [document]: its timelines' cuts on one
/// track, its rate, and its shooting frame as the camera — the frame's
/// size the project's, its centre where every cut's camera stands. A file
/// with no frame is shot whole.
Project _projectOf(String name, ClipDocument document, ClipImportPlan plan) {
  final frame = document.frame;
  final camera = frame == null
      ? null
      : CutCamera(
          keyframes: {
            0: CameraPose(
              center: CanvasPoint(x: frame.centerX, y: frame.centerY),
            ),
          },
        );
  final lifted = liftCutSeLayersToTrack(_track, [
    for (final cut in plan.cuts)
      if (camera == null) cut else cut.copyWith(camera: camera),
  ]);
  final fps = plan.fps;
  return Project(
    id: ProjectId('clip-${DateTime.now().toUtc().millisecondsSinceEpoch}'),
    name: name,
    createdAt: DateTime.now().toUtc(),
    cameraSize: frame == null
        ? CanvasSize(width: document.width, height: document.height)
        : CanvasSize(width: frame.width, height: frame.height),
    frameRate: fps == null
        ? ProjectFrameRate.fps24
        : ProjectFrameRate.integer(fps),
    tracks: [
      Track(
        id: _track,
        name: 'Track 1',
        cuts: lifted.cuts,
        seLayers: lifted.seLayers,
      ),
    ],
    linkRegistry: plan.links,
  );
}

/// One picture to bake, the cut it lands in, and where its bytes are.
typedef _ClipWork = ({
  ClipCelBake bake,
  Cut cut,
  ClipPicture picture,
  ClipPlace blocks,
});

/// The CLIP STUDIO door.
final class ClipImportDoor {
  ClipImportDoor({
    required ProjectAccess project,
    required ChangeSink changes,
    required RenderCaches renderCaches,
    required ProjectFile file,
  }) : _project = project,
       _changes = changes,
       _renderCaches = renderCaches,
       _file = file;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final RenderCaches _renderCaches;
  final ProjectFile _file;

  /// Bakes every picture of [read] into THIS session — the one born for it
  /// (`OpenProjects.prepare(read.project)`) — and answers what the import
  /// could not carry over. The result is a NEW UNSAVED project; the first
  /// save asks where the .anicel goes.
  Future<List<ImportWarning>> bake(
    ClipProjectRead read, {
    void Function(double fraction)? onProgress,
  }) async {
    assert(
      _file.path == null && !_project.historyManager.canUndo,
      'a .clip bakes only into the session born for it — see '
      'ClipProjectRead',
    );
    MemoryBlackBox.begin('clip-import');
    final warnings = [...read._plan.warnings];
    await _bakeEveryCel(read, warnings: warnings, onProgress: onProgress);
    _file.markDirty();
    _changes.warmActiveCut();
    _changes.notifyChanged();
    MemoryBlackBox.end('clip-import');
    return warnings;
  }

  /// Every picture [read] planned, decoded out of its file and baked into
  /// the drawings' store, in WAVES the size of the worker pool — read by
  /// offset one at a time, so the file is never held whole (the .tvpp
  /// door's reasons: a worker copies what it is given, and a resident file
  /// scales with the FILE rather than with the work).
  Future<void> _bakeEveryCel(
    ClipProjectRead read, {
    required List<ImportWarning> warnings,
    void Function(double fraction)? onProgress,
  }) async {
    final source = read._source;
    final reader = await File(source.path).open();
    try {
      final work = _workOf(read._plan, ClipContainer.indexOf(reader), warnings);
      final pool = math.max(1, math.min(Platform.numberOfProcessors - 1, 8));
      for (var at = 0; at < work.length; at += pool) {
        final wave = work.sublist(at, math.min(at + pool, work.length));
        final windows = <Uint8List>[];
        for (final item in wave) {
          await reader.setPosition(item.blocks.offset);
          windows.add(await reader.read(item.blocks.length));
        }
        final decoded = await Future.wait([
          for (var w = 0; w < wave.length; w += 1)
            _decodeOnWorker(windows[w], wave[w].picture.source.attribute, (
              left: wave[w].picture.left,
              top: wave[w].picture.top,
              canvasWidth: wave[w].cut.canvasSize.width,
              canvasHeight: wave[w].cut.canvasSize.height,
              alpha: wave[w].bake.alpha,
              tileSize: defaultCelTileSize,
            )),
        ]);
        for (var w = 0; w < wave.length; w += 1) {
          _bakeDecoded(decoded[w], wave[w], warnings);
          onProgress?.call((at + w + 1) / work.length);
        }
      }
    } finally {
      await reader.close();
      if (source.staged) {
        unawaited(
          File(source.path).delete().then<void>((_) {}, onError: (_) {}),
        );
      }
    }
  }

  /// Every bake of [plan] with the cut it landed in and where its blocks
  /// are. A picture the file does not hold the blocks of is said.
  List<_ClipWork> _workOf(
    ClipImportPlan plan,
    ClipContainer container,
    List<ImportWarning> warnings,
  ) {
    final work = <_ClipWork>[];
    final turned = <int>{};
    for (final bake in plan.bakes) {
      final cut = _project.cutById(bake.cutId);
      final picture = clipPictureOf(bake.source);
      if (cut == null || picture == null) {
        continue;
      }
      final blocks = container.externals[picture.source.blocksId];
      if (blocks == null) {
        warnings.add(_unreadable(bake, 'its picture is not in the file'));
        continue;
      }
      if (!picture.moveOnly && turned.add(bake.source.id)) {
        warnings.add(
          ImportWarning(
            'clipTransform',
            '{name}: the picture\'s scale or turn is not applied.',
            {'name': bake.label},
          ),
        );
      }
      work.add((bake: bake, cut: cut, picture: picture, blocks: blocks));
    }
    return work;
  }

  /// Lands one decoded picture, or says why it could not be landed. No
  /// tiles is a picture with no ink: the cel stays, empty.
  void _bakeDecoded(
    Object? decoded,
    _ClipWork item,
    List<ImportWarning> warnings,
  ) {
    if (decoded == null) {
      warnings.add(
        ImportWarning(
          'clipNotColour',
          '{name}: a grey or monochrome layer — not drawn.',
          {'name': item.bake.label},
        ),
      );
      return;
    }
    if (decoded is! List<ClipCelTile>) {
      warnings.add(_unreadable(item.bake, '$decoded'));
      return;
    }
    if (decoded.isEmpty) {
      return;
    }
    bakeCelTiles(
      _renderCaches.brushFrameStore,
      _project.brushFrameKeyForCut(
        item.cut,
        item.bake.layerId,
        item.bake.frameId,
      ),
      item.cut.canvasSize,
      decoded,
    );
  }

  ImportWarning _unreadable(ClipCelBake bake, String detail) => ImportWarning(
    'celUnreadable',
    '{file}: the picture could not be read — {detail}',
    {'file': bake.label, 'detail': detail},
  );
}

/// One picture decoded on a worker of its own — its tiles, null for a
/// picture that is not colour, or the reason it would not decode.
///
/// ⛔ITS OWN FUNCTION, given plain values: the worker is built where
/// nothing but its inputs is in scope (`Isolate.run` copies the closure's
/// whole context chain — the .tvpp door's measured lesson).
Future<Object?> _decodeOnWorker(
  Uint8List blocks,
  Uint8List attribute,
  ClipCelTarget target,
) {
  return Isolate.run<Object?>(() {
    try {
      return clipCelTiles(attribute, blocks, target);
    } on ClipFormatException catch (error) {
      return error;
    } on FormatException catch (error) {
      return error;
    }
  });
}
