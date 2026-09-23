import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**A TAKE IS A CARRIED ASSET, AND CARRIED ASSETS LIVE IN THE RUN'S
/// ROOM** (유저 2026-09-08: 「위치를 앱컨테이너/실제파일 이렇게 두군데로만
/// 정리하고싶은거고. 그 외 위치엔 두고싶지않아」 — 기준은 모든 플랫폼).
///
/// 🪦This file was `voice_recording_shelf_test`, and the shelf it named was
/// a folder under the app documents home that a desktop setting could point
/// anywhere. Two things were wrong with it, and only the second was known:
///
/// • **The app wrote to a THIRD location.** One take produced TWO files —
///   the plain WAV on the shelf, and the staged copy the funnel made by
///   reading it straight back. 유저 2026-08-27: 「사본 남으면 진짜 용서
///   안할게」.
/// • **On Windows that location was the source repository.**
///   `%USERPROFILE%/Documents/Anicel` resolves case-insensitively onto the
///   checkout, so a desktop run dropped `.wav` files beside the source —
///   which `.gitignore` had a line and a paragraph about, instead of a fix.
///
/// ⛔What did NOT change is the law the shelf was protecting: **nothing
/// moves.** A take was once renamed into the project's `Media/` folder,
/// which made that folder the only copy of a performance. The save absorbs
/// it from where it already sits, and where it sits is now the same room
/// every other carried asset waits in.
void main() {
  late Directory directory;
  String? previousDocumentsPath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-voice-take-test');
    // A FRESH documents home per test, restored afterwards — these pin that
    // the app writes NOTHING there, and the corpus-wide sandbox is shared.
    previousDocumentsPath = AppStorage.channelDocumentsPath;
    AppStorage.channelDocumentsPath =
        '${directory.path.replaceAll('\\', '/')}/docs';
  });

  tearDown(() {
    AppStorage.channelDocumentsPath = previousDocumentsPath;
    deleteTempQuietly(directory);
  });

  EditorSessionManager session() => EditorSessionManager(
    initialProject: createDefaultProject(),
    audioConformStore: AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'test stub',
      ),
      log: (_) {},
    ),
  );

  AudioRecording takeOfSeconds(double seconds) {
    final length = (seconds * 48000).round();
    final samples = Float32List(length);
    for (var index = 0; index < samples.length; index += 1) {
      samples[index] = 0.25;
    }
    return AudioRecording(
      samples: samples,
      channels: 1,
      sampleRate: 48000,
      droppedFrames: 0,
    );
  }

  /// Every file the staging room holds, by name.
  List<String> stagedNames() {
    final room = Directory(SessionScratch.stagedFolder());
    if (!room.existsSync()) {
      return const [];
    }
    return [
      for (final entity in room.listSync())
        if (entity is File) entity.path.replaceAll(r'\', '/').split('/').last,
    ];
  }

  test('🚨 a take is ONE file, and it is in the run\'s room', () async {
    final manager = session();
    addTearDown(manager.dispose);
    final lane = manager.activeTrack.seLayers.first;
    final before = stagedNames().length;

    expect(
      await manager.voiceRecording.placeVoiceRecording(
        takeOfSeconds(1.0),
        laneId: lane.id,
        anchorFrame: 0,
      ),
      isTrue,
    );

    final clip = manager.activeTrack.seLayers.first.audioClips.single;
    expect(
      clip.filePath,
      '${SessionScratch.stagedFolder()}/${lane.name}_T01.wav',
      reason: 'the pool path is the take\'s address inside the run\'s room',
    );
    expect(
      manager.mediaPool.mediaAssets.single.path,
      clip.filePath,
      reason: 'and the pool knows it by the same one',
    );
    expect(
      stagedNames().length,
      before + 1,
      reason: '⛔ONE file. Writing a shelf copy and staging it from there '
          'put two on disk for one performance.',
    );
    expect(
      File(clip.filePath).existsSync(),
      isFalse,
      reason: 'the pool path is an ADDRESS — the bytes are at the name the '
          'staging store derives, which is what every carried asset does',
    );
    expect(
      manager.projectFile.projectHoldsMediaBytes(clip.filePath),
      isTrue,
      reason: 'and the project holds them from the moment the take lands',
    );
  });

  test('⛔ nothing is written outside the container', () async {
    // The regression this round exists for: the take shelf resolved to
    // `<documents>/Anicel/Recordings`, which on Windows IS the checkout.
    final manager = session();
    addTearDown(manager.dispose);
    final lane = manager.activeTrack.seLayers.first;
    await manager.voiceRecording.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
    );

    final documents = Directory(appDocumentsDirectory());
    expect(
      !documents.existsSync() || documents.listSync().isEmpty,
      isTrue,
      reason: 'the documents home is where the USER puts project files; the '
          'app writes to its container and to the project file, and to '
          'nowhere else',
    );
  });

  test('the take number walks past what the PROJECT already holds', () async {
    // REC1-B: `<lane>_T<n>` — the pool line alone says whose take it is and
    // which pass. 🚨The walk asks the pool rather than the disk: the room is
    // per-run, so a walk over files alone would restart at T01 every launch
    // and put two `S1_T01.wav` rows in one project.
    final manager = session();
    addTearDown(manager.dispose);
    final lane = manager.activeTrack.seLayers.first;
    for (var i = 0; i < 2; i += 1) {
      await manager.voiceRecording.placeVoiceRecording(
        takeOfSeconds(1.0),
        laneId: lane.id,
        anchorFrame: i * 100,
      );
    }

    final names = [
      for (final asset in manager.mediaPool.mediaAssets)
        asset.path.split('/').last,
    ];
    // ⚠️Relative, not `T01`/`T02`: the room belongs to the RUN, and a test
    // process is one run — earlier cases in this file have already staged
    // takes into it. Pinning absolute numbers would be pinning the order
    // the file happens to be written in.
    expect(names, hasLength(2));
    expect(names.toSet(), hasLength(2), reason: '⛔two takes, two names');
    final numbers = [
      for (final name in names)
        int.parse(name.split('_T').last.split('.').first),
    ];
    expect(
      numbers[1],
      numbers[0] + 1,
      reason: 'REC1-B: `<lane>_T<n>` walks, so the pool line alone says '
          'which pass a take was',
    );
    expect(names.every((name) => name.startsWith('${lane.name}_T')), isTrue);
  });

  test('🚨 and it walks past a name the pool already shows, wherever that '
      'asset came from', () async {
    // The half a walk over the room alone cannot see. The room is per-run,
    // so a project OPENED in a later run brings pool assets whose staged
    // files are in a room this one does not have — and an import can simply
    // be a file that happens to be called `S1_T01.wav`. Either way two rows
    // would show the same name, which is the whole of what the numbering
    // convention is for.
    final manager = session();
    addTearDown(manager.dispose);
    // ⚠️**THE SECOND SE LANE, ON PURPOSE.** The room belongs to the RUN and
    // a test process is one run, so the cases above have already staged
    // takes for lane one — a decoy on that lane would be skipped by the
    // room's own files and prove nothing about the pool check. A first
    // draft did exactly that and the mutation lived through it.
    final lane = manager.activeTrack.seLayers.last;
    final decoy = File('${directory.path}/${lane.name}_T01.wav')
      ..writeAsBytesSync(List<int>.filled(64, 1));
    manager.mediaPool.importMediaFiles([decoy.path], copyIntoProject: false);
    expect(
      manager.mediaPool.mediaAssets.single.path.split('/').last,
      '${lane.name}_T01.wav',
      reason: 'the decoy is in the pool under the name the walk wants first',
    );

    await manager.voiceRecording.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
    );

    final names = [
      for (final asset in manager.mediaPool.mediaAssets)
        asset.path.split('/').last,
    ];
    expect(
      names.toSet(),
      hasLength(names.length),
      reason: '⛔no two rows share a name — the decoy already had that one',
    );
    expect(
      names.where((name) => name == '${lane.name}_T01.wav'),
      hasLength(1),
      reason: 'and the one that has it is the decoy, not the take',
    );
    expect(names, contains('${lane.name}_T02.wav'));
  });

  test('a save carries the take into the .anicel, and moves nothing',
      () async {
    final manager = session();
    addTearDown(manager.dispose);
    final lane = manager.activeTrack.seLayers.first;
    await manager.voiceRecording.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
    );
    final takePath =
        manager.activeTrack.seLayers.first.audioClips.single.filePath;

    await manager.projectDoor.saveProjectToFile(
      asked: SaveAsked.byAPerson,
      '${directory.path}/scene.anicel',
    );

    expect(
      manager.activeTrack.seLayers.first.audioClips.single.filePath,
      takePath,
      reason: 'the clip still points at the take where it was recorded',
    );
    expect(
      manager.mediaPool.mediaAssets.single.carried,
      isTrue,
      reason: 'a take is the project\'s own recording, so it packs it',
    );
    expect(
      manager.projectFile.mediaEntryNames.keys,
      contains(takePath),
      reason: 'the save put it INSIDE the .anicel',
    );
    expect(
      Directory('${directory.path}/scene.assets/Media').existsSync(),
      isFalse,
      reason: 'and no sibling folder is created for it',
    );

    // Undo still strips the whole take in one step — the save never
    // touched the edit history.
    manager.undo();
    expect(manager.activeTrack.seLayers.first.audioClips, isEmpty);
    expect(manager.mediaPool.mediaAssets, isEmpty);
  });

  test('an UNDONE take keeps its bytes — the save carries only what the '
      'project still references', () async {
    final manager = session();
    addTearDown(manager.dispose);
    final lane = manager.activeTrack.seLayers.first;
    await manager.voiceRecording.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
    );
    final staged = stagedNames();
    manager.undo();

    await manager.projectDoor.saveProjectToFile(
      asked: SaveAsked.byAPerson,
      '${directory.path}/scene.anicel',
    );

    expect(
      stagedNames(),
      staged,
      reason: '⛔`removeMediaAsset` does not retire — an undo can bring the '
          'take back, and the room\'s own ending is what clears it',
    );
    expect(
      manager.projectFile.mediaEntryNames,
      isEmpty,
      reason: 'nothing referenced, nothing carried',
    );
  });
}
