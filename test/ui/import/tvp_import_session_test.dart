import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart'
    show FolderPicker;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/session/tvpp_import_door.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../models/import/tvpp_test_builder.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';
import '../../helpers/temp_dir.dart';

/// An import through the SESSION, which is where the ids come from.
///
/// The planner takes its minting seam as an argument, so every planner
/// test supplies a counter of its own and gets unique ids for free. The
/// session's real mint was the thing that collided, and nothing exercised
/// it: a layer of ten drawings arrived as ten exposures of ONE drawing,
/// because the id formatter reads a sequence it does not advance and the
/// only other ingredient — the wall clock — does not tick fast enough to
/// separate a mint loop on Windows.
/// The TVPaint door itself — named so `tool/mutation_run.dart` has a suite
/// to run for it.
TvppImportDoor tvppDoorOf(EditorSessionManager session) => session.tvppDoor;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('tvpp-session'));
  tearDown(() => deleteTempQuietly(temp));

  String writeTvpp() {
    final b = TvppBuilder();
    b.projectProperties(cameraWidth: 960, cameraHeight: 540);
    b.clipProperties('番号');
    b.clipHeader(width: 64, height: 48);
    b.layerHead('카메라레이어', headerChunk: 'LRCA');
    b.layerExt(const {});
    // TEN drawings back to back — the mint loop the wall clock could
    // not separate.
    b.layerHead('A', end: 9, count: 10, layerId: 901);
    b.layerExt(const {});
    for (var i = 0; i < 10; i++) {
      // The FIRST drawing carries ink. Every cel used to be blank here,
      // and a blank cel decodes to zero tiles whether the bytes were
      // read from the right place or not — so a decode fed the wrong
      // offset looked exactly like a correct one.
      final px = List.filled(64 * 48, 0);
      if (i == 0) {
        for (var y = 8; y < 20; y++) {
          for (var x = 8; x < 24; x++) {
            px[y * 64 + x] = premulBgra(200, 30, 40, 255);
          }
        }
      }
      b.zchkSlot(srawRecord(px, 64, 48));
    }
    // One drawing held across the same span.
    b.layerHead('TAP', end: 9, count: 10, layerId: 902);
    b.layerExt(const {});
    b.zchkSlot(srawRecord(List.filled(64 * 48, 0), 64, 48));
    for (var i = 0; i < 9; i++) {
      b.zchkHold();
    }
    // MUTED on purpose: that is a PLANNER warning, and it is how this
    // test can see whether the planner's warnings reach the caller at
    // all (the missing-sound one is raised by the session itself).
    b.clipConfig(audio: const [('G:/rushes/12.mp4', 0.5, 1.0, true)]);
    final path = '${temp.path}${Platform.pathSeparator}番号.tvpp';
    File(path).writeAsBytesSync(b.bytes);
    return path;
  }

  test(
    'a .tvpp opens AS the project and every cel is its own drawing',
    () async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      final door = tvppDoorOf(session);
      final warnings = await door.openAsProject(
        tvppPath: writeTvpp(),
      );
      expect(warnings, isNotNull, reason: 'the file parses');
      expect(
        warnings!.where(
          (w) => w.english.startsWith('The sound file is not at this address'),
        ),
        isNotEmpty,
        reason:
            '🚨the PLANNER\'s warnings reach the caller. The fixture\'s '
            'rushes path is deliberately absent, so the plan says so — and '
            'dropping that forwarding is invisible to a test that only '
            'checks the OTHER warnings are empty.',
      );
      expect(
        warnings.where((w) => w.english.contains('the track was muted')),
        isNotEmpty,
        reason:
            'the muted track is a PLANNER warning — this is the one the '
            'forwarding carries, and dropping it is silent otherwise',
      );
      expect(
        // The fixture's rushes path is deliberately absent, and that
        // warning is the flow's own answer to a missing sound — not a
        // decode failure.
        warnings.where(
          (w) =>
              !w.english.startsWith('The sound file is not at this address') &&
              !w.english.contains('the track was muted'),
        ),
        isEmpty,
        reason:
            '🚨every cel DECODED. The import reads each record out of '
            'the file by offset — a seek that lands anywhere else produces '
            'a decode failure, which arrives as a warning rather than a '
            'throw, so an import that "worked" can still have read nothing.',
      );

      // The open REPLACES the project — the default cut is gone, the
      // file's name is the project's, and so is its SHOOTING FRAME (288:
      // fitting a layout camera into our 16:9 default framed wider than
      // TVPaint did).
      final project = session.repository.requireProject();
      expect(project.name, '番号');
      expect(project.cameraSize.width, 960);
      expect(project.cameraSize.height, 540);
      final cuts = project.tracks.expand((track) => track.cuts).toList();
      expect(cuts, hasLength(1));
      expect(cuts.single.name, '番号');

      // The clip's sound lands on the TRACK's global SE rows — per-cut SE
      // layers are the legacy shape the timeline no longer renders (288:
      // the SE section vanished entirely).
      final track = project.tracks.single;
      // The lift pads to the timesheet's standard two rows (S1·S2); the
      // clip's sound rides the first.
      expect(track.seLayers, hasLength(2));
      expect(track.seLayers.first.audioClips, hasLength(1));
      expect(
        cuts.single.layers.where((l) => l.kind == LayerKind.se),
        isEmpty,
        reason: 'lifted onto the track, not left on the cut',
      );

      final ids = <FrameId>[];
      for (final layer in cuts.single.layers) {
        ids.addAll(layer.frames.map((frame) => frame.id));
      }
      expect(ids, isNotEmpty);
      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason:
            'two cels sharing an id are ONE drawing — the timeline shows '
            'the same picture in every block and the first cel\'s name in '
            'every cell',
      );

      // The count is the other half: unique ids would also be satisfied by
      // minting one per BLOCK, which would break exposure runs (one drawing
      // held ten frames must stay one cel).
      final a = cuts.single.layers.firstWhere((layer) => layer.name == 'A');
      expect(a.frames, hasLength(10), reason: 'ten drawings, ten cels');
      final tap = cuts.single.layers.firstWhere((layer) => layer.name == 'TAP');
      expect(
        tap.frames,
        hasLength(1),
        reason: 'one drawing held across the clip stays one cel',
      );
      expect(tap.timeline[0]!.length, 10);

      // 🚨AND THE PIXELS ARE IN THE STORE. Everything above is satisfied
      // by an import that decoded every record and then threw the tiles
      // away — the warnings would still be empty, the cels would still be
      // ten, and the timeline would still be right. The fixture's first
      // drawing is the only one carrying ink (a 16×12 rect), so the store
      // is the only place that can say the picture arrived.
      final inked = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
        session.brushFrameKeyForCut(cuts.single, a.id, a.frames.first.id),
      );
      expect(inked, isNotNull, reason: 'the first drawing baked');
      var painted = 0;
      for (final tile in inked!.tiles.values) {
        final bytes = tile.pixels;
        for (var p = 0; p < bytes.length; p += 4) {
          if (bytes[p] != 0 ||
              bytes[p + 1] != 0 ||
              bytes[p + 2] != 0 ||
              bytes[p + 3] != 0) {
            painted += 1;
          }
        }
      }
      expect(
        painted,
        16 * 12,
        reason:
            'the rect the fixture drew, pixel for pixel — a count that is '
            'zero means the bake was skipped, and one that is 64×48 means '
            'the decode filled the canvas instead of the drawing',
      );
    },
  );

  test('F-124: the warnings an import raises speak the program language', () async {
    // 🚨THE THREE THAT WERE KOREAN. The planner's muted-track warning and
    // the door's missing-sound warning were written in Korean, so a
    // Japanese — or French, or Chinese — reader met Korean in the notice
    // the import puts up. The English ones were no better: a sentence
    // built where it is raised can only be said in the language it was
    // typed in.
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ja,
    );
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    final warnings = await session.tvppDoor.openAsProject(
      tvppPath: writeTvpp(),
    );

    expect(warnings, isNotNull, reason: 'the file parses');
    expect(
      warnings!.where(
        (w) => w.textFor(AppLanguage.ja).contains('ミュート'),
      ),
      isNotEmpty,
      reason: 'the planner says the track was muted, in the app\'s language',
    );
    expect(
      warnings.where(
        (w) => w.textFor(AppLanguage.ja).contains('音声ファイルがありません'),
      ),
      isNotEmpty,
      reason: 'and the door says the sound file is not where it points',
    );
  });

  test('🚨the converted project is bound to NO file and is UNSAVED — the '
      'first save has to ask where the .anicel goes', () async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // A session that was already holding an .anicel: the open has to let
    // go of it, or the first save writes the conversion OVER the file the
    // user opened before it.
    session.projectFile.bindToOpenedFile(
      '${temp.path}${Platform.pathSeparator}held.anicel',
      mediaInFile: const {},
      unsaved: false,
    );
    final seeksBefore = session.frameSeekCommitted.value;

    expect(
      await session.tvppDoor.openAsProject(tvppPath: writeTvpp()),
      isNotNull,
    );

    expect(
      session.projectFile.path,
      isNull,
      reason: 'the conversion is a NEW project — it is bound to no file',
    );
    expect(
      session.projectFile.hasUnsavedChanges,
      isTrue,
      reason:
          'a conversion is unsaved by definition — nothing on disk '
          'holds it, so the title dot and the exit gate have to say so',
    );
    expect(
      session.frameSeekCommitted.value,
      greaterThan(seeksBefore),
      reason:
          'the playhead now stands in a different project, and the '
          'seek-dependent panels only hear about it here',
    );
  });

  test('an unreadable pick goes through the COORDINATED read; only a '
      'parse failure answers null', () async {
    // A File Provider placeholder exists-but-refuses; the coordinated
    // fallback is what makes the provider materialise it (iPhone +
    // Drive, hands-on). Direct read of this path fails outright.
    final real = writeTvpp();
    final ghost = '${temp.path}${Platform.pathSeparator}ghost.tvpp';
    var staged = 0;
    FolderPicker.debugCoordinatedReader =
        ({required String sourcePath, required String destinationPath}) async {
          staged++;
          expect(sourcePath, ghost);
          File(real).copySync(destinationPath);
          return true;
        };
    addTearDown(() => FolderPicker.debugCoordinatedReader = null);

    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    final warnings = await session.tvppDoor.openAsProject(tvppPath: ghost);
    expect(staged, 1);
    expect(
      warnings,
      isNotNull,
      reason: 'the staged copy parses like the local file',
    );

    // A file that READS but does not parse is the only null.
    final junk = '${temp.path}${Platform.pathSeparator}junk.tvpp';
    File(junk).writeAsBytesSync(List<int>.filled(64, 7));
    expect(await session.tvppDoor.openAsProject(tvppPath: junk), isNull);

    // Unreadable AND unstageable throws — access, not format.
    FolderPicker.debugCoordinatedReader =
        ({required String sourcePath, required String destinationPath}) async =>
            false;
    expect(
      () => session.tvppDoor.openAsProject(
        tvppPath: '${temp.path}${Platform.pathSeparator}nowhere.tvpp',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  /// 🚨WHAT THE IMPORT DOOR SAYS WHEN SOMETHING IS WRONG.
  ///
  /// Three answers, and all three were mutable to green (2026-09-05): a
  /// cel that will not decode leaves a WARNING naming the file rather
  /// than throwing the wave away, the planner's own warnings reach the
  /// caller, and a file that parses but holds no clip is refused instead
  /// of replacing the session with an empty project.
  test('🚨a cel that will not decode names itself in the warnings — the '
      'import goes on, so silence here is a cel that vanished', () async {
    final b = TvppBuilder();
    b.projectProperties(cameraWidth: 64, cameraHeight: 48);
    b.clipProperties('broken');
    b.clipHeader(width: 64, height: 48);
    b.layerHead('A', end: 0, count: 1, layerId: 901);
    b.layerExt(const {});
    // A record the raster decoder cannot read: the tile table is missing
    // (its bytes are simply not a tiled SRAW record).
    b.zchkSlot(Uint8List.fromList(List<int>.filled(64, 7)));
    b.clipConfig();
    final path = '${temp.path}${Platform.pathSeparator}broken.tvpp';
    File(path).writeAsBytesSync(b.bytes);

    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    final warnings = await session.tvppDoor.openAsProject(tvppPath: path);

    expect(warnings, isNotNull, reason: 'the STRUCTURE parses');
    expect(
      warnings!.where(
        (w) => !w.english.startsWith('The sound file is not at this address'),
      ),
      isNotEmpty,
      reason: 'a cel the decoder refused has to be said out loud',
    );
  });

  test('🚨a file that parses but holds NO clip is refused — replacing the '
      'session with an empty project is worse than not opening', () async {
    final b = TvppBuilder();
    b.projectProperties(cameraWidth: 64, cameraHeight: 48);
    final path = '${temp.path}${Platform.pathSeparator}empty.tvpp';
    File(path).writeAsBytesSync(b.bytes);

    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final before = session.repository.requireProject().name;

    expect(await session.tvppDoor.openAsProject(tvppPath: path), isNull);
    expect(
      session.repository.requireProject().name,
      before,
      reason: 'the session it refused to replace is still there',
    );
  });

  // 유저 2026-09-26: 「다 통일해줘」 — the timesheet's ink lived in stores
  // of its own that no reset reached; the conte's and the envelope's
  // were cleared by name, one line each.
  test('🚨a .tvpp opened as the project leaves no sheet\'s ink of the '
      'project it replaced', () async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final caches = session.renderCaches;
    final cutId = session.requireActiveCut.id;
    final written = <BrushFrameStore, BrushFrameKey>{
      caches.conteInkRowStore: conteInkRowKey(cutId, const FrameId('f')),
      caches.conteInkPageStore: conteInkPageKey(0),
      caches.envelopeInkStore: envelopeInkBoxKey(cutId, 'memo'),
      caches.timesheetInkStripStore: timesheetInkStripKey(cutId, 0),
      caches.timesheetInkPageStore: timesheetInkPageKey(cutId, 0),
    };
    for (final MapEntry(key: store, value: key) in written.entries) {
      store.storeBakedSurface(key, _inkedSurface());
      expect(store.bakedSurfaceOrNull(key), isNotNull, reason: 'fixture');
    }

    expect(
      await session.tvppDoor.openAsProject(tvppPath: writeTvpp()),
      isNotNull,
    );
    for (final MapEntry(key: store, value: key) in written.entries) {
      expect(store.bakedSurfaceOrNull(key), isNull, reason: '$key');
    }
  });
}

/// A small inked surface — what a landed stroke leaves in a store.
BitmapSurface _inkedSurface() => BitmapSurface(
  canvasSize: const CanvasSize(width: 16, height: 16),
  tileSize: 8,
  tiles: {
    TileCoord(x: 0, y: 0): BitmapTile(
      size: 8,
      pixels: Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 255),
    ),
  },
);
