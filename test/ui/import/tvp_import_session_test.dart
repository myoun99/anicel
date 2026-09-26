import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart'
    show FolderPicker;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/session/tvpp_import_door.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../models/import/tvpp_test_builder.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';
import '../../helpers/opened_session.dart';
import '../../helpers/temp_dir.dart';

/// An open through the REAL mint, which is where the ids come from.
///
/// The planner takes its minting seam as an argument, so every planner
/// test supplies a counter of its own and gets unique ids for free. The
/// real mint was the thing that collided, and nothing exercised it: a layer
/// of ten drawings arrived as ten exposures of ONE drawing, because an id
/// formatter read a count it did not advance (gone since 2026-09-26) and the
/// only other ingredient — the wall clock — does not tick fast enough to
/// separate a mint loop on Windows. A .tvpp mints its ids before any session
/// holds it now (I-7), through the process's one frame mint.
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
      final opened = await openedTvpp(writeTvpp());
      expect(opened, isNotNull, reason: 'the file parses');
      final session = opened!.session;
      addTearDown(session.dispose);
      final warnings = opened.warnings;
      expect(
        warnings.where(
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

      // The file IS the project — no default cut, the file's name is the
      // project's, and so is its SHOOTING FRAME (288: fitting a layout
      // camera into our 16:9 default framed wider than TVPaint did).
      final project = session.repository.requireProject();
      expect(
        session.canUndo,
        isFalse,
        reason: 'the file\'s sounds are registered as the file\'s — an open '
            'is not an edit to undo',
      );
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

      final layerIds = [for (final layer in cuts.single.layers) layer.id];
      expect(
        layerIds.toSet(),
        hasLength(layerIds.length),
        reason: 'two rows under one id are one row to every verb that looks '
            'a row up — minted before any session holds the project',
      );
      expect(
        session.mediaPool.mediaAssets.map((asset) => asset.path),
        contains(endsWith('12.mp4')),
        reason: 'the clip\'s sound is in the pool, so relink and the '
            'existence check see it',
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

    final opened = await openedTvpp(writeTvpp());

    expect(opened, isNotNull, reason: 'the file parses');
    addTearDown(opened!.session.dispose);
    final warnings = opened.warnings;
    expect(
      warnings.where(
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
    // 🪦The session here used to be one already holding an .anicel, which
    // the open had to let go of, or the first save wrote the conversion
    // OVER the file opened before it. A .tvpp opens as a session of its own
    // now (I-7): there is nothing bound to let go of.
    final opened = await openedTvpp(writeTvpp());
    expect(opened, isNotNull);
    final session = opened!.session;
    addTearDown(session.dispose);

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
  });

  test('an unreadable pick goes through the COORDINATED read; only a '
      'parse failure answers null', () async {
    // A File Provider placeholder exists-but-refuses; the coordinated
    // fallback is what makes the provider materialise it (iPhone +
    // Drive, hands-on). Direct read of this path fails outright.
    final real = writeTvpp();
    final ghost = '${temp.path}${Platform.pathSeparator}ghost.tvpp';
    var staged = 0;
    String? stagedAt;
    FolderPicker.debugCoordinatedReader =
        ({required String sourcePath, required String destinationPath}) async {
          staged++;
          expect(sourcePath, ghost);
          File(real).copySync(destinationPath);
          stagedAt = destinationPath;
          return true;
        };
    addTearDown(() => FolderPicker.debugCoordinatedReader = null);

    final opened = await openedTvpp(ghost);
    expect(staged, 1);
    expect(
      opened,
      isNotNull,
      reason: 'the staged copy parses like the local file',
    );
    addTearDown(opened!.session.dispose);
    expect(
      opened.warnings.map((warning) => warning.key),
      contains('stagedCopy'),
      reason: '유저 2026-08-27: the last resort says so when it fires',
    );
    // The copy goes once the bake has read it (its delete is not waited
    // for, so it gets its turn).
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      File(stagedAt!).existsSync(),
      isFalse,
      reason: 'a staged copy is read-and-discard — left behind it is a '
          'second copy of the project nobody will ever read',
    );

    // A file that READS but does not parse is the only null.
    final junk = '${temp.path}${Platform.pathSeparator}junk.tvpp';
    File(junk).writeAsBytesSync(List<int>.filled(64, 7));
    expect(await readTvppProject(tvppPath: junk), isNull);

    // Unreadable AND unstageable throws — access, not format.
    FolderPicker.debugCoordinatedReader =
        ({required String sourcePath, required String destinationPath}) async =>
            false;
    expect(
      () => readTvppProject(
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
  /// of opening as an empty project.
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

    final opened = await openedTvpp(path);

    expect(opened, isNotNull, reason: 'the STRUCTURE parses');
    addTearDown(opened!.session.dispose);
    expect(
      opened.warnings.where(
        (w) => !w.english.startsWith('The sound file is not at this address'),
      ),
      isNotEmpty,
      reason: 'a cel the decoder refused has to be said out loud',
    );
    expect(
      opened.session.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'a conversion is unsaved by definition — with no sound to '
          'register, nothing else says so but the door',
    );
  });

  test('🚨a file that parses but holds NO clip is refused — opening an EMPTY '
      'project is worse than not opening', () async {
    final b = TvppBuilder();
    b.projectProperties(cameraWidth: 64, cameraHeight: 48);
    final path = '${temp.path}${Platform.pathSeparator}empty.tvpp';
    File(path).writeAsBytesSync(b.bytes);

    expect(await readTvppProject(tvppPath: path), isNull);
  });

  test('every clip becomes a cut of its OWN id — the project is named before '
      'any session holds it', () async {
    final b = TvppBuilder();
    b.projectProperties(cameraWidth: 64, cameraHeight: 48);
    for (final name in ['A', 'B']) {
      b.clipProperties(name);
      b.clipHeader(width: 64, height: 48);
      b.layerHead('L$name', end: 0, count: 1, layerId: 900);
      b.layerExt(const {});
      b.zchkSlot(srawRecord(List<int>.filled(64 * 48, 0), 64, 48));
      b.clipConfig();
    }
    final path = '${temp.path}${Platform.pathSeparator}two.tvpp';
    File(path).writeAsBytesSync(b.bytes);

    final opened = await openedTvpp(path);

    expect(opened, isNotNull, reason: 'the file parses');
    addTearDown(opened!.session.dispose);
    final cuts = [
      for (final track in opened.session.repository.requireProject().tracks)
        ...track.cuts,
    ];
    expect(cuts.map((cut) => cut.name), ['A', 'B']);
    expect(
      cuts.map((cut) => cut.id).toSet(),
      hasLength(2),
      reason: 'two cuts under one id are one cut to every verb that finds it',
    );
  });

  // 🪦「A .tvpp opened as the project leaves no sheet's ink of the project it
  // replaced」 lived here — 유저 2026-09-26: 「다 통일해줘」, when the
  // timesheet's ink lived in stores no reset reached and the conte's and
  // the envelope's were cleared by name, one line each. A .tvpp opens as a
  // session of its own now (I-7): no project is replaced, and every store
  // it bakes into was born empty with it.
}
