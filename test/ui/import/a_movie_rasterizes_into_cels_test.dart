// A MOVIE RASTERIZES INTO CELS (미디어 배치 라운드 6, the video spec the user
// approved on 2026-09-11): every position of the block becomes a cel — one
// per movie frame the sound's clock shows there, consecutive duplicates
// folded into held exposure — counted from the file's IN point and standing
// where the block stood. The reference is let go of, the pool entry stays
// (「구워도 풀에 남음」), and one undo puts the held cel and its file back.
import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String moviePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-movie-bakes');
    moviePath = '${tempDir.path}${Platform.pathSeparator}take3.mov';
    await File(moviePath).writeAsBytes(const [0, 0, 0, 24]);
  });

  tearDown(() async {
    debugVideoDecodeBackend = null;
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
  });

  Layer rowOf(EditorSessionManager s, Layer layer) =>
      s.requireActiveCut.layers.firstWhere(
        (candidate) => candidate.id == layer.id,
      );

  /// A session holding [frameCount] frames of an [fps] take as a reference,
  /// kept from [inFrame]. The playback warmer is held — what the decoder is
  /// asked for afterwards is the rasterize's own asking.
  Future<(EditorSessionManager, Layer)> placed({
    int frameCount = 24,
    int fps = 24,
    int inFrame = 0,
  }) async {
    debugVideoDecodeBackend = FakeVideoBackend(
      frameCount: frameCount,
      fpsNumerator: fps,
    );
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    await s.importDoors.importVideoFile(
      path: moviePath,
      settings: ImportFileSettings(
        mode: ImportFileMode.reference,
        sound: false,
        inFrame: inFrame,
      ),
    );
    return (s, s.requireActiveCut.layers.firstWhere(isMovieReference));
  }

  test('a 12 fps take becomes ONE cel per movie frame, each held for two — '
      'and the pool entry stays', () async {
    final (s, layer) = await placed(frameCount: 12, fps: 12);

    expect(
      await s.importDoors.rasterizeMovieReference(
        cutId: s.requireActiveCut.id,
        layerId: layer.id,
      ),
      isTrue,
    );

    final after = rowOf(s, layer);
    expect(after.mediaReference, isNull, reason: 'the file is let go of');
    expect(after.frames, hasLength(12));
    expect(after.timeline.keys, [for (var i = 0; i < 12; i += 1) i * 2]);
    expect([
      for (final exposure in after.timeline.values) exposure.length,
    ], [for (var i = 0; i < 12; i += 1) 2]);
    expect(
      s.brushSurfaceForLayerFrame(after, after.frames.first),
      isNotNull,
      reason: 'the pixels are the row\'s own now',
    );
    expect(s.mediaPool.mediaAssets, hasLength(1), reason: '구워도 풀에 남음');
  });

  test('the cels stand where the block stood, counted from the file\'s IN '
      'point', () async {
    final (s, placedRow) = await placed(inFrame: 4);
    // The block moved to 5 before the bake: 20 frames of it, 4 into the
    // file.
    s.repository.replaceLayer(
      layer: placedRow.copyWith(
        timeline: SplayTreeMap<int, TimelineExposure>()
          ..[5] = placedRow.timeline[0]!,
      ),
    );
    final reader = FakeVideoBackend(frameCount: 24);
    debugVideoDecodeBackend = reader;

    expect(
      await s.importDoors.rasterizeMovieReference(
        cutId: s.requireActiveCut.id,
        layerId: placedRow.id,
      ),
      isTrue,
    );

    final after = rowOf(s, placedRow);
    expect(after.timeline.keys, [for (var i = 5; i < 25; i += 1) i]);
    expect(after.frames, hasLength(20));
    expect(
      reader.asked,
      [for (var frame = 4; frame < 24; frame += 1) frame],
      reason: 'frames 4 through 23 of the file, in order',
    );
  });

  test('one undo puts the held cel and its file back', () async {
    final (s, layer) = await placed(frameCount: 12, fps: 12);
    await s.importDoors.rasterizeMovieReference(
      cutId: s.requireActiveCut.id,
      layerId: layer.id,
    );

    s.historyManager.undo();

    final back = rowOf(s, layer);
    expect(back.frames, hasLength(1));
    expect(back.timeline.keys, [0]);
    expect(isMovieReference(back), isTrue);
  });

  test('a row that points at no movie is not this verb\'s', () async {
    final (s, layer) = await placed();
    await s.importDoors.rasterizeMovieReference(
      cutId: s.requireActiveCut.id,
      layerId: layer.id,
    );

    expect(
      await s.importDoors.rasterizeMovieReference(
        cutId: s.requireActiveCut.id,
        layerId: layer.id,
      ),
      isFalse,
      reason: 'already cels',
    );
  });
}
