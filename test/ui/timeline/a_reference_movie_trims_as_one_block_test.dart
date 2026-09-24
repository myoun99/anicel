// A REFERENCE MOVIE TRIMS AS ONE BLOCK (미디어 배치 라운드 6, the video spec
// the user approved on 2026-09-11): its block moves whole and trims at both
// ends — a head trim moves the file's in point, so every frame left shows
// what it showed, and growing back stops at the file's first frame — and no
// reshaping verb reaches it until it is rasterized.
import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/temp_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String moviePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-movie-trims');
    moviePath = '${tempDir.path}${Platform.pathSeparator}take3.mov';
    await File(moviePath).writeAsBytes(const [0, 0, 0, 24]);
  });

  tearDown(() async {
    debugVideoDecodeBackend = null;
    deleteTempQuietly(tempDir);
  });

  Layer movieRow(EditorSessionManager s) =>
      s.requireActiveCut.layers.firstWhere(isMovieReference);

  /// A session holding a 24-frame movie as a reference kept from frame 4 —
  /// a 20-frame block, 4 frames into the file — with the playback warmer
  /// held: these tests are about timing, not pictures.
  Future<(EditorSessionManager, Layer)> placed() async {
    debugVideoDecodeBackend = FakeVideoBackend(frameCount: 24);
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    await s.importDoors.importVideoFile(
      path: moviePath,
      settings: const ImportFileSettings(
        mode: ImportFileMode.reference,
        sound: false,
        inFrame: 4,
      ),
    );
    return (s, movieRow(s));
  }

  /// One edge drag, press to release.
  void drag(
    EditorSessionManager s,
    Layer layer, {
    required int blockStart,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    expect(
      s.edgeDrag.beginExposureEdgeDrag(
        layerId: layer.id,
        blockStartIndex: blockStart,
        edge: edge,
      ),
      isTrue,
    );
    s.edgeDrag.updateExposureEdgeDrag(delta);
    s.edgeDrag.endExposureEdgeDrag();
  }

  test('a head trim moves the file\'s in point by what the start moved — '
      'the frames left show what they showed', () async {
    final (s, before) = await placed();
    final held = before.frames.single.id;
    expect(resolveExposedFrameAt(before, 2)!.id, movieCelFrameId(held, 6));

    drag(s, before, blockStart: 0, edge: TimelineBlockEdge.start, delta: 2);

    final after = movieRow(s);
    expect(after.timeline.keys, [2]);
    expect(after.timeline[2]!.length, 18);
    expect(after.mediaReference!.frameOffset, 6);
    expect(
      resolveExposedFrameAt(after, 2)!.id,
      movieCelFrameId(held, 6),
      reason: 'the same movie frame, where it was',
    );

    s.historyManager.undo();
    expect(
      movieRow(s).mediaReference!.frameOffset,
      4,
      reason: 'one undo puts both back',
    );
    expect(movieRow(s).timeline.keys, [0]);
  });

  test('growing the head back stops at the file\'s first frame', () async {
    final (s, placedRow) = await placed();
    // The block stands at 10: ten frames of room before it, four of file.
    s.repository.replaceLayer(
      layer: placedRow.copyWith(
        timeline: SplayTreeMap<int, TimelineExposure>()
          ..[10] = placedRow.timeline[0]!,
      ),
    );

    drag(
      s,
      movieRow(s),
      blockStart: 10,
      edge: TimelineBlockEdge.start,
      delta: -8,
    );

    final after = movieRow(s);
    expect(after.timeline.keys, [6]);
    expect(after.timeline[6]!.length, 24);
    expect(after.mediaReference!.frameOffset, 0);
  });

  test('a tail trim leaves the in point where it is', () async {
    final (s, before) = await placed();

    drag(s, before, blockStart: 0, edge: TimelineBlockEdge.end, delta: -5);

    final after = movieRow(s);
    expect(after.timeline[0]!.length, 15);
    expect(after.mediaReference!.frameOffset, 4);
  });

  test('it moves whole, but no reshaping verb reaches it', () async {
    final (s, layer) = await placed();

    expect(s.blockMoveEligible(layer.id), isTrue);
    expect(s.standsDownFromRetime(layer.id), isTrue);
    s.selectFrameIndex(3);
    expect(
      s.activeLayer?.id,
      layer.id,
      reason: 'fixture: the placed row is the one worked on',
    );
    expect(
      s.exposureVerbs.canBlankExposureAtCurrentFrame,
      isFalse,
      reason: 'an X inside the block would restart the movie after it',
    );
  });

  test('a grip on it inside a selection trims it alone', () async {
    final (s, movie) = await placed();
    // Two baked rows beside it, so the selection has a retime of its own.
    debugVideoDecodeBackend = FakeVideoBackend(frameCount: 4);
    for (var i = 0; i < 2; i += 1) {
      await s.importDoors.importVideoFile(
        path: moviePath,
        settings: const ImportFileSettings(
          mode: ImportFileMode.reference,
          bake: true,
          sound: false,
        ),
      );
    }
    final baked = [
      for (final layer in s.requireActiveCut.layers)
        if (layer.mediaReference == null && layer.frames.length == 4) layer,
    ];
    expect(baked, hasLength(2), reason: 'fixture: two baked rows');
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: movie.id,
      startIndex: 0,
      endIndexExclusive: 4,
      layerIds: [movie.id, for (final layer in baked) layer.id],
    );

    drag(
      s,
      movieRow(s),
      blockStart: 0,
      edge: TimelineBlockEdge.end,
      delta: -3,
    );

    expect(movieRow(s).timeline[0]!.length, 17);
    for (final layer in baked) {
      expect(
        s.layerById(layer.id)!.timeline,
        layer.timeline,
        reason: 'the rows beside it stay as they were',
      );
    }
  });
}
