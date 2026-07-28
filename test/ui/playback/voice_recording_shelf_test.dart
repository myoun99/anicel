import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';

/// REC1-B2: the take shelf. A never-saved project records into the
/// visible app Recordings folder (never the hidden OS temp), and the
/// FIRST save adopts the referenced takes into the project's `Media/` —
/// file moved, pool + clips relinked, outside undo history. Undone
/// takes stay on the shelf, findable.
void main() {
  late Directory directory;
  late String shelf;
  String? previousDocumentsPath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-voice-shelf-test');
    // A FRESH documents home per test (the corpus-wide sandbox is shared,
    // and these tests pin exact take numbers) — restored afterwards.
    previousDocumentsPath = AppStorage.channelDocumentsPath;
    AppStorage.channelDocumentsPath =
        '${directory.path.replaceAll('\\', '/')}/docs';
    shelf = appRecordingsDirectory();
  });

  tearDown(() {
    AppStorage.channelDocumentsPath = previousDocumentsPath;
    AppSave.settings.value = const AppSaveSettings();
    return directory.delete(recursive: true);
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

  test('an unsaved project records onto the app shelf, and the walk '
      'continues past an earlier session\'s takes', () {
    final first = session();
    final lane = first.activeTrack.seLayers.first;
    expect(
      first.placeVoiceRecording(
        takeOfSeconds(1.0),
        laneId: lane.id,
        anchorFrame: 0,
      ),
      isTrue,
    );
    final clip = first.activeTrack.seLayers.first.audioClips.single;
    expect(clip.filePath, '$shelf/${lane.name}_T01.wav');
    expect(File(clip.filePath).existsSync(), isTrue);
    expect(first.mediaAssets.single.path, clip.filePath);
    first.dispose();

    // A NEW session sees T01 on the shared shelf and takes T02 — the
    // DAW take-number convention across sessions.
    final second = session();
    final laneB = second.activeTrack.seLayers.first;
    expect(
      second.placeVoiceRecording(
        takeOfSeconds(1.0),
        laneId: laneB.id,
        anchorFrame: 0,
      ),
      isTrue,
    );
    expect(
      second.activeTrack.seLayers.first.audioClips.single.filePath,
      '$shelf/${laneB.name}_T02.wav',
    );
    second.dispose();
  });

  test('the FIRST save adopts referenced takes into Media/: file moved, '
      'pool + clip relinked, undo history untouched', () async {
    final manager = session();
    final lane = manager.activeTrack.seLayers.first;
    manager.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
    );
    final shelfPath =
        manager.activeTrack.seLayers.first.audioClips.single.filePath;
    expect(shelfPath, startsWith('$shelf/'));

    await manager.saveProjectToFile('${directory.path}/scene.qap');

    final adopted =
        manager.activeTrack.seLayers.first.audioClips.single.filePath;
    expect(adopted, contains('.assets/Media/'));
    expect(adopted, endsWith('${lane.name}_T01.wav'));
    expect(File(adopted).existsSync(), isTrue);
    expect(File(shelfPath).existsSync(), isFalse, reason: 'moved, not copied');
    expect(manager.mediaAssets.single.path, adopted);

    // The adoption rode the save, not the edit history: ONE undo still
    // strips the whole take (pool + lane), exactly as before saving.
    manager.undo();
    expect(manager.activeTrack.seLayers.first.audioClips, isEmpty);
    expect(manager.mediaAssets, isEmpty);

    // After the save, new takes land straight in Media/ and the number
    // walk continues past the adopted file still on disk.
    manager.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
    );
    final second =
        manager.activeTrack.seLayers.first.audioClips.single.filePath;
    expect(second, contains('.assets/Media/'));
    expect(second, endsWith('${lane.name}_T02.wav'));
    manager.dispose();
  });

  test('an UNDONE take stays on the shelf — the save adopts only what '
      'the project still references', () async {
    final manager = session();
    final lane = manager.activeTrack.seLayers.first;
    manager.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
    );
    final shelfPath =
        manager.activeTrack.seLayers.first.audioClips.single.filePath;
    manager.undo();

    await manager.saveProjectToFile('${directory.path}/scene.qap');

    expect(File(shelfPath).existsSync(), isTrue,
        reason: 'a discarded take is still findable on the shelf');
    final media = Directory(
      ProjectAssetLayout('${directory.path}/scene.qap').mediaDirectory,
    );
    expect(
      !media.existsSync() || media.listSync().isEmpty,
      isTrue,
      reason: 'nothing referenced, nothing adopted',
    );
    manager.dispose();
  });

  test('a custom recordings folder (desktop setting) replaces the '
      'default shelf', () {
    final custom = '${directory.path.replaceAll('\\', '/')}/my-takes';
    AppSave.settings.value = AppSaveSettings(recordingsDirectory: custom);
    final manager = session();
    final lane = manager.activeTrack.seLayers.first;
    expect(
      manager.placeVoiceRecording(
        takeOfSeconds(1.0),
        laneId: lane.id,
        anchorFrame: 0,
      ),
      isTrue,
    );
    expect(
      manager.activeTrack.seLayers.first.audioClips.single.filePath,
      '$custom/${lane.name}_T01.wav',
    );
    manager.dispose();
  });
}
