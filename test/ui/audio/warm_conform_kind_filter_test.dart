import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// What the session actually hands the conform pipeline when it warms.
///
/// The kind filter itself is pinned as a pure function in
/// `test/services/project_lookup_test.dart`; this pins the WIRING, because
/// the two fail apart: a session that stopped calling the filtered walk —
/// or went back to iterating `mediaAssets` inline — leaves every pure test
/// green while a 3GB reference video is read into memory on open again.
/// Recording the runner is the honest observation point: a conform request
/// IS the read.
void main() {
  late List<String> conformed;

  EditorSessionManager sessionWith(List<MediaAsset> pool) {
    conformed = [];
    return EditorSessionManager(
      initialProject: createDefaultProject().copyWith(mediaAssets: pool),
      audioConformStore: AudioConformStore(
        resolveConformPath: (_) => null,
        runner: (request) async {
          conformed.add(request.sourcePath);
          return const ConformResult(
            outcome: ConformOutcome.undecodable,
            error: 'test stub',
          );
        },
        log: (_) {},
      ),
    );
  }

  /// A rate change is the cheapest of the three warm triggers to reach —
  /// the other two are a project open and a frame-rate change, and all
  /// three call the same walk.
  void warm(EditorSessionManager session) {
    session.setProjectAudioSampleRate(
      session.projectAudioSampleRate == 48000 ? 44100 : 48000,
    );
  }

  test('warming asks for the sound and never opens the movie', () {
    final session = sessionWith([
      const MediaAsset(
        path: 'dialogue.wav',
        name: 'dialogue',
        kind: MediaAssetKind.audio,
      ),
      const MediaAsset(
        path: 'reference.mp4',
        name: 'reference',
        kind: MediaAssetKind.video,
      ),
    ]);

    warm(session);

    expect(conformed, ['dialogue.wav']);
    session.dispose();
  });

  test('a pool of stills and documents warms nothing at all', () {
    final session = sessionWith([
      const MediaAsset(
        path: 'layout.png',
        name: 'layout',
        kind: MediaAssetKind.image,
      ),
      const MediaAsset(
        path: 'script.pdf',
        name: 'script',
        kind: MediaAssetKind.pdf,
      ),
    ]);

    warm(session);

    expect(conformed, isEmpty);
    session.dispose();
  });
}
