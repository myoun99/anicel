import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart'
    show FolderPicker;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../models/import/tvpp_test_builder.dart';

/// An import through the SESSION, which is where the ids come from.
///
/// The planner takes its minting seam as an argument, so every planner
/// test supplies a counter of its own and gets unique ids for free. The
/// session's real mint was the thing that collided, and nothing exercised
/// it: a layer of ten drawings arrived as ten exposures of ONE drawing,
/// because the id formatter reads a sequence it does not advance and the
/// only other ingredient — the wall clock — does not tick fast enough to
/// separate a mint loop on Windows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('tvpp-session'));
  tearDown(() => temp.deleteSync(recursive: true));

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

      final warnings = await session.openTvppAsProject(tvppPath: writeTvpp());
      expect(warnings, isNotNull, reason: 'the file parses');
      expect(
        warnings!.where((w) => w.startsWith('사운드 파일이')),
        isNotEmpty,
        reason:
            '🚨the PLANNER\'s warnings reach the caller. The fixture\'s '
            'rushes path is deliberately absent, so the plan says so — and '
            'dropping that forwarding is invisible to a test that only '
            'checks the OTHER warnings are empty.',
      );
      expect(
        warnings.where((w) => w.contains('뮤트')),
        isNotEmpty,
        reason:
            'the muted track is a PLANNER warning — this is the one the '
            'forwarding carries, and dropping it is silent otherwise',
      );
      expect(
        // The fixture's rushes path is deliberately absent, and that
        // warning is the flow's own answer to a missing sound — not a
        // decode failure.
        warnings.where((w) => !w.startsWith('사운드 파일이') && !w.contains('뮤트')),
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
    },
  );

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

    final warnings = await session.openTvppAsProject(tvppPath: ghost);
    expect(staged, 1);
    expect(
      warnings,
      isNotNull,
      reason: 'the staged copy parses like the local file',
    );

    // A file that READS but does not parse is the only null.
    final junk = '${temp.path}${Platform.pathSeparator}junk.tvpp';
    File(junk).writeAsBytesSync(List<int>.filled(64, 7));
    expect(await session.openTvppAsProject(tvppPath: junk), isNull);

    // Unreadable AND unstageable throws — access, not format.
    FolderPicker.debugCoordinatedReader =
        ({required String sourcePath, required String destinationPath}) async =>
            false;
    expect(
      () => session.openTvppAsProject(
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

    final warnings = await session.openTvppAsProject(tvppPath: path);

    expect(warnings, isNotNull, reason: 'the STRUCTURE parses');
    expect(
      warnings!.where((w) => !w.startsWith('사운드 파일이')),
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

    expect(await session.openTvppAsProject(tvppPath: path), isNull);
    expect(
      session.repository.requireProject().name,
      before,
      reason: 'the session it refused to replace is still there',
    );
  });
}
