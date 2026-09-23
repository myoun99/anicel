import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// What the session actually hands the conform pipeline when it warms.
///
/// The walk itself is pinned as a pure function in
/// `test/services/project_lookup_test.dart`; this pins the WIRING, because
/// the two fail apart — a session that stopped calling the shared walk, or
/// went back to iterating `mediaAssets` inline with a rule of its own,
/// leaves every pure test green. Recording the runner is the honest
/// observation point: a conform request IS the ask.
///
/// 🪦This file was `warm_conform_kind_filter_test` and asserted that a movie
/// was NEVER asked for. That was a scar from when a conform read the whole
/// container into memory before any decoder saw it — a 3GB reference video,
/// on every project open. The decoder takes a path and a span now, so the
/// read is gone, and with it the reason to keep a movie's soundtrack
/// unreachable. What survived the round is the OTHER half of that rule: a
/// still has nowhere to put an audio track, so it is still left alone.
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
    session.projectAudio.setProjectAudioSampleRate(
      session.projectAudio.projectAudioSampleRate == 48000 ? 44100 : 48000,
    );
  }

  test('warming asks for the movie too — its soundtrack is a sound this '
      'project references', () {
    final session = sessionWith([
      MediaAsset(
        path: 'dialogue.wav',
        name: 'dialogue',
        kind: MediaAssetKind.audio,
      ),
      MediaAsset(
        path: 'reference.mp4',
        name: 'reference',
        kind: MediaAssetKind.video,
      ),
    ]);

    warm(session);

    expect(conformed, containsAll(['dialogue.wav', 'reference.mp4']));
    session.dispose();
  });

  test('a pool of stills and documents asks for nothing — they have nowhere '
      'to put a soundtrack', () {
    // ⛔Not a saving, a fact. And the cost it avoids is not one read: a
    // source with no conform can never match one, so a still asked once is
    // a still asked on every open, forever.
    final session = sessionWith([
      MediaAsset(
        path: 'layout.png',
        name: 'layout',
        kind: MediaAssetKind.image,
      ),
      MediaAsset(
        path: 'script.pdf',
        name: 'script',
        kind: MediaAssetKind.pdf,
      ),
    ]);

    warm(session);

    expect(conformed, isEmpty);
    session.dispose();
  });

  test('an empty pool asks for nothing — the walk is not a fixed list', () {
    final session = sessionWith(const []);

    warm(session);

    expect(conformed, isEmpty);
    session.dispose();
  });
}
