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

import '../../core/worker_count.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cel_text.dart';
import '../../models/cut.dart';
import '../../models/import/import_warning.dart';
import '../../models/media_asset.dart' show normalizedMediaPath;
import '../../models/pasteboard_bounds.dart';
import '../../models/project.dart';
import '../../models/project_background.dart';
import '../../models/project_frame_rate.dart';
import '../../models/project_id.dart';
import '../../models/tile_coord.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/track_se_migration.dart';
import '../../services/diagnostics/memory_black_box.dart';
import '../../services/import/clip_cel_raster.dart';
import '../../services/import/clip_container.dart';
import '../../services/import/clip_document.dart';
import '../../services/import/clip_import_planner.dart';
import '../../services/import/clip_vector_raster.dart' show clipVectorTiles;
import '../../services/import/media_import_planner.dart' show ImportIdMint;
import '../../services/import/raster_cel_import.dart'
    show bakeCelSurface, bakeCelTiles, celTilesOf;
import '../../services/persistence/folder_grant.dart'
    show FileArrival, FolderPicker;
import '../../services/persistence/provider_documents.dart'
    show ProviderDocuments;
import '../../services/persistence/session_scratch.dart';
import '../text/cel_text_bake.dart' show bakeCelTextPlate;
import '../text/cel_text_layout.dart'
    show celTextFacesArriving, layoutCelText;
import 'media_pool.dart';
import 'project_file.dart';
import 'project_file_door.dart' show ProjectFileDoor;
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
    required List<String> sounds,
  }) : _plan = plan,
       _source = source,
       _sounds = sounds;

  /// The project the file becomes — every timeline a 겸용 cut, its layers
  /// and cels as the planner shaped them.
  final Project project;
  final ClipImportPlan _plan;

  /// The bytes the pictures are baked from — a staged copy the bake
  /// deletes when it is done with it.
  final ({String path, bool staged}) _source;

  /// The sounds taken out of the file, where the project's SE rows play
  /// them from until the bake carries them into the project.
  final List<String> _sounds;
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
  final sounds = await _takeSoundsOut(
    source.path,
    [
      for (final layer in document.root.everyLayer)
        for (final sound in layer.sounds)
          (
            objectUuid: sound.objectUuid,
            binaryId: sound.binaryId,
            fileName: _soundFileName(sound, layer.name),
          ),
    ],
    '${scratch.path}/clip-sound-${DateTime.now().microsecondsSinceEpoch}',
  );
  final plan = planClipImport(
    document: document,
    name: name,
    trackId: _track,
    mint: ImportIdMint.forANewProject(),
    soundPaths: sounds,
  );
  return ClipProjectRead._(
    project: _projectOf(name, document, plan),
    plan: plan,
    source: source,
    sounds: [...sounds.values],
  );
}

/// What a sound taken out of the file is called: the name CLIP STUDIO took
/// it in by — its layer's when it kept none — with the extension it was
/// kept under, in characters every file system takes.
String _soundFileName(ClipSound sound, String layerName) {
  final own = sound.name.isNotEmpty
      ? sound.name
      : (layerName.isNotEmpty ? layerName : 'sound');
  final dotted = '.${sound.extension}'.toLowerCase();
  final named = sound.extension.isEmpty || own.toLowerCase().endsWith(dotted)
      ? own
      : '$own.${sound.extension}';
  return named.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

/// Each of [sounds] written out of the file at [path] into [folder], under
/// its own name — a second one of a name taken gets ` (2)` — by its
/// [ClipSound.objectUuid]. A sound whose bytes the file does not hold is
/// not there.
///
/// ⛔ITS OWN FUNCTION on a worker, for [_readStructure]'s reason: the
/// index walk and the bytes are the file's size and kind of work.
Future<Map<String, String>> _takeSoundsOut(
  String path,
  List<({String objectUuid, String binaryId, String fileName})> sounds,
  String folder,
) {
  if (sounds.isEmpty) {
    return Future.value(const {});
  }
  return Isolate.run(() {
    final file = File(path).openSync();
    try {
      final container = ClipContainer.indexOf(file);
      final out = <String, String>{};
      final taken = <String>{};
      Directory(folder).createSync(recursive: true);
      for (final sound in sounds) {
        final place = container.externals[sound.binaryId];
        if (place == null) {
          continue;
        }
        var name = sound.fileName;
        for (var n = 2; !taken.add(name.toLowerCase()); n += 1) {
          final dot = sound.fileName.lastIndexOf('.');
          name = dot <= 0
              ? '${sound.fileName} ($n)'
              : '${sound.fileName.substring(0, dot)} ($n)'
                    '${sound.fileName.substring(dot)}';
        }
        final target = File('$folder/$name')
          ..writeAsBytesSync(readClipPlace(file, place), flush: true);
        out[sound.objectUuid] = normalizedMediaPath(target.path);
      }
      return out;
    } finally {
      file.closeSync();
    }
  });
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
/// track — each with the camera the plan gave it — its rate, and its
/// shooting frame's size as the project's camera. A file with no frame is
/// shot whole.
Project _projectOf(String name, ClipDocument document, ClipImportPlan plan) {
  final frame = document.frame;
  final lifted = liftCutSeLayersToTrack(_track, plan.cuts);
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
    // 🗣️F-370-Q2 (유저 2026-10-17: 「용지 「없음」으로 — 클립 스튜디오에서
    // 보이던 그대로」): a file with no paper of its own shows its sheet
    // open in CLIP STUDIO, and opens so — white was this app's default,
    // never what the file said. White stays the colour the paper keeps.
    background:
        plan.paper ??
        const ProjectBackground.color(
          ProjectBackground.defaultPaperArgb,
          none: true,
        ),
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

/// One picture to bake, the cut it lands in, what its pixels come out of,
/// and where that is in the file — and the mask it is baked through, with
/// where that mask's blocks are.
typedef _ClipWork = ({
  ClipCelBake bake,
  Cut cut,
  _ClipSource source,
  List<ClipPlace> places,
  ({ClipBakedMask mask, ClipPlace place})? mask,
});

/// What a bake's pixels come out of.
sealed class _ClipSource {
  const _ClipSource();
}

/// A stored picture — [_ClipWork.places] is its blocks.
final class _StoredPicture extends _ClipSource {
  const _StoredPicture(this.picture);

  final ClipPicture picture;
}

/// A vector layer's strokes — [_ClipWork.places] is their bodies.
final class _Strokes extends _ClipSource {
  const _Strokes();
}

/// A text layer's texts ([ClipCelBake.texts]) — [_ClipWork.places] is the
/// blocks of each of [pictures], the pictures CLIP STUDIO drew of them that
/// the file holds, each naming the text it is of.
final class _Letters extends _ClipSource {
  const _Letters(this.pictures);

  final List<({int text, ClipPictureSource picture})> pictures;
}

/// The CLIP STUDIO door.
final class ClipImportDoor {
  ClipImportDoor({
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
    await _carrySounds(read._sounds);
    _file.markDirty();
    _changes.warmActiveCut();
    _changes.notifyChanged();
    MemoryBlackBox.end('clip-import');
    return warnings;
  }

  /// The sounds taken out of the file become the project's own — CARRIED,
  /// as a recording is: their bytes held in the project, so the copies
  /// taken out go once held (the pool does not call a carried asset whose
  /// original left 「missing」). Registered as the file's, not as an edit
  /// to undo — the .tvpp door's way with its sounds.
  Future<void> _carrySounds(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    await _mediaPool.addMediaAssets(paths, carried: true);
    _project.historyManager.clear();
    _projectDoor.warmAudioConforms();
    for (final path in paths) {
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // The run's room goes at its end; a copy still held open waits.
      }
    }
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
      final pool = workersFor(Platform.numberOfProcessors, ceiling: 8);
      for (var at = 0; at < work.length; at += pool) {
        final wave = work.sublist(at, math.min(at + pool, work.length));
        Future<Uint8List> read(ClipPlace place) async {
          await reader.setPosition(place.offset);
          return reader.read(place.length);
        }

        final windows = <List<Uint8List>>[];
        final masks = <Uint8List?>[];
        for (final item in wave) {
          final bytes = <Uint8List>[];
          for (final place in item.places) {
            bytes.add(await read(place));
          }
          windows.add(bytes);
          masks.add(switch (item.mask) {
            final mask? => await read(mask.place),
            null => null,
          });
        }
        final decoded = await Future.wait([
          for (var w = 0; w < wave.length; w += 1)
            _decodeOne(wave[w], windows[w], masks[w]),
        ]);
        for (var w = 0; w < wave.length; w += 1) {
          await _bakeDecoded(decoded[w], wave[w], warnings);
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
      if (cut == null) {
        continue;
      }
      // A vector layer is drawn from its strokes, however few: the render
      // it keeps beside them has no blocks in the file.
      if (bake.source.kind == ClipLayerKind.vector) {
        final places = [
          for (final id in bake.source.vectorData) container.externals[id],
        ];
        if (places.contains(null)) {
          warnings.add(_unreadable(bake, 'its strokes are not in the file'));
          continue;
        }
        work.add((
          bake: bake,
          cut: cut,
          source: const _Strokes(),
          places: [...places.nonNulls],
          mask: _maskOf(bake, container, warnings),
        ));
        continue;
      }
      // A text layer is its texts: a text whose picture the file does not
      // hold is set here when it is baked ([_setLetters]).
      if (bake.source.kind == ClipLayerKind.lettering) {
        final drawn = [
          for (final (i, text) in bake.texts.indexed)
            if (text.picture case final picture?)
              if (container.externals[picture.blocksId] case final place?)
                (text: i, picture: picture, place: place),
        ];
        work.add((
          bake: bake,
          cut: cut,
          source: _Letters([
            for (final one in drawn) (text: one.text, picture: one.picture),
          ]),
          places: [for (final one in drawn) one.place],
          mask: null,
        ));
        continue;
      }
      final picture = clipPictureOf(bake.source);
      if (picture == null) {
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
      work.add((
        bake: bake,
        cut: cut,
        source: _StoredPicture(picture),
        places: [blocks],
        mask: _maskOf(bake, container, warnings),
      ));
    }
    return work;
  }

  /// The mask [bake]'s picture is baked through ([clipBakedMaskOf]) and
  /// where its blocks are — said, and the picture baked without it, where
  /// the file does not hold them.
  ({ClipBakedMask mask, ClipPlace place})? _maskOf(
    ClipCelBake bake,
    ClipContainer container,
    List<ImportWarning> warnings,
  ) {
    final mask = clipBakedMaskOf(bake.source);
    if (mask == null) {
      return null;
    }
    final place = container.externals[mask.source.blocksId];
    if (place == null) {
      warnings.add(layerMaskNotApplied(bake.label));
      return null;
    }
    return (mask: mask, place: place);
  }

  /// [item] decoded on a worker of its own out of [bytes] — its blocks, its
  /// strokes, or its texts' pictures — through its mask's [maskBlocks].
  Future<Object?> _decodeOne(
    _ClipWork item,
    List<Uint8List> bytes,
    Uint8List? maskBlocks,
  ) {
    ClipCelTarget at(int left, int top) => (
      left: left,
      top: top,
      canvasWidth: item.cut.canvasSize.width,
      canvasHeight: item.cut.canvasSize.height,
      alpha: item.bake.alpha,
      tileSize: defaultCelTileSize,
    );
    final bake = item.bake;
    final mask = switch ((item.mask?.mask, maskBlocks)) {
      (final baked?, final blocks?) => (
        attribute: baked.source.attribute,
        blocks: blocks,
        left: baked.left,
        top: baked.top,
      ),
      _ => null,
    };
    return switch (item.source) {
      _StoredPicture(:final picture) => _decodeOnWorker(
        bytes.single,
        picture.source.attribute,
        at(picture.left, picture.top),
        mask,
      ),
      _Strokes() => _drawOnWorker(
        bytes,
        (x: bake.source.offsetX, y: bake.source.offsetY),
        at(0, 0),
        mask,
      ),
      _Letters(:final pictures) when pictures.isEmpty => Future.value(
        const <Object?>[],
      ),
      _Letters(:final pictures) => _readOnWorker(
        bytes,
        [for (final one in pictures) one.picture.attribute],
        [
          for (final one in pictures)
            at(bake.texts[one.text].left, bake.texts[one.text].top),
        ],
      ),
    };
  }

  /// Lands one decoded picture, or says why it could not be landed. No
  /// tiles is a picture with no ink: the cel stays, empty.
  Future<void> _bakeDecoded(
    Object? decoded,
    _ClipWork item,
    List<ImportWarning> warnings,
  ) async {
    if (item.source case final _Letters letters) {
      await _setLetters(letters, decoded, item, warnings);
      return;
    }
    if (decoded case (
      tiles: final List<ClipCelTile> tiles,
      unread: final int unread,
    )) {
      if (unread > 0) {
        warnings.add(
          ImportWarning(
            'clipVectorUnread',
            '{name}: {count} vector strokes of a kind this import does not '
                'read — not drawn.',
            {'name': item.bake.label, 'count': '$unread'},
          ),
        );
      }
      _bakeTiles(tiles, item);
      return;
    }
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
    _bakeTiles(decoded, item);
  }

  void _bakeTiles(List<ClipCelTile> tiles, _ClipWork item) {
    if (tiles.isEmpty) {
      return;
    }
    bakeCelTiles(
      _renderCaches.brushFrameStore,
      _keyOf(item),
      item.cut.canvasSize,
      tiles,
    );
  }

  /// Lands a text layer's texts as its cel's, each with its plate: the
  /// picture CLIP STUDIO drew of it, [decoded] in the order of [letters]'
  /// pictures — or, for a text the file holds no picture of that reads, the
  /// one this app sets, said.
  Future<void> _setLetters(
    _Letters letters,
    Object? decoded,
    _ClipWork item,
    List<ImportWarning> warnings,
  ) async {
    final drawn = <int, Map<TileCoord, BitmapTile>>{};
    if (decoded case final List<Object?> pictures) {
      for (var k = 0; k < letters.pictures.length; k += 1) {
        if (pictures[k] case final List<ClipCelTile> tiles) {
          drawn[letters.pictures[k].text] = celTilesOf(tiles);
        }
      }
    }
    final texts = <CelText>[];
    var setHere = false;
    for (final (i, text) in item.bake.texts.indexed) {
      var plate = drawn[i];
      if (plate == null) {
        setHere = true;
        try {
          plate = await _plateSetHere(text.content, item.cut.canvasSize);
        } on Object catch (error) {
          warnings.add(_unreadable(item.bake, '$error'));
          continue;
        }
      }
      texts.add(CelText(id: i + 1, content: text.content, plate: plate));
    }
    if (setHere) {
      warnings.add(
        ImportWarning(
          'clipTextSetHere',
          '{name}: a text is set by this app — CLIP STUDIO\'s picture of it '
              'is not in the file, or could not be read.',
          {'name': item.bake.label},
        ),
      );
    }
    if (texts.isEmpty) {
      return;
    }
    bakeCelSurface(
      _renderCaches.brushFrameStore,
      _keyOf(item),
      BitmapSurface(canvasSize: item.cut.canvasSize, texts: texts),
    );
  }

  /// [content]'s plate as this app sets it — once the faces it is set in
  /// that are on their way have arrived, as the text tool waits for them.
  Future<Map<TileCoord, BitmapTile>> _plateSetHere(
    CelTextContent content,
    CanvasSize canvas,
  ) async {
    final arriving = celTextFacesArriving(content);
    if (arriving != null) {
      await arriving;
    }
    final layout = layoutCelText(content);
    try {
      return await bakeCelTextPlate(
        layout,
        // Cut at the wall of the store it is laid in.
        pasteboard: canvas.pasteboardAt(
          _renderCaches.brushFrameStore.pasteboardReach,
        ),
        tileSize: defaultCelTileSize,
      );
    } finally {
      layout.dispose();
    }
  }

  BrushFrameKey _keyOf(_ClipWork item) => _project.brushFrameKeyForCut(
    item.cut,
    item.bake.layerId,
    item.bake.frameId,
  );

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
  ClipStoredMask? mask,
) => Isolate.run<Object?>(
  () => _tilesOf(attribute, blocks, target, mask: mask),
);

/// Several pictures — a text layer's — decoded on one worker of its own,
/// each as [_decodeOnWorker] answers for one. Its own function for the same
/// reason.
Future<Object?> _readOnWorker(
  List<Uint8List> blocks,
  List<Uint8List> attributes,
  List<ClipCelTarget> targets,
) => Isolate.run<Object?>(
  () => [
    for (var k = 0; k < blocks.length; k += 1)
      _tilesOf(attributes[k], blocks[k], targets[k]),
  ],
);

/// The tiles a picture's [attribute] and [blocks] make on [target] through
/// [mask] — null for a picture that is not colour, or the reason it would
/// not decode.
Object? _tilesOf(
  Uint8List attribute,
  Uint8List blocks,
  ClipCelTarget target, {
  ClipStoredMask? mask,
}) {
  try {
    return clipCelTiles(attribute, blocks, target, mask: mask);
  } on ClipFormatException catch (error) {
    return error;
  } on FormatException catch (error) {
    return error;
  }
}

/// One vector layer drawn on a worker of its own ([clipVectorTiles]) — its
/// tiles and its unread strokes, or the reason its strokes would not read.
/// Its own function for the same reason as [_decodeOnWorker].
Future<Object?> _drawOnWorker(
  List<Uint8List> bodies,
  ({int x, int y}) offset,
  ClipCelTarget target,
  ClipStoredMask? mask,
) {
  return Isolate.run<Object?>(() {
    try {
      return clipVectorTiles(bodies, offset, target, mask: mask);
    } on ClipFormatException catch (error) {
      return error;
    }
  });
}
