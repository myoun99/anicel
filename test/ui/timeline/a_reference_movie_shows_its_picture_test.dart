// A REFERENCE MOVIE SHOWS ITS PICTURE (미디어 배치 라운드 6): the one held cel
// resolves to a movie cel per position, the hydrator decodes the frame the
// sound's clock picks into the store — where the canvas stands, and ahead of
// the playback warmer — fitted the way the file was placed; positions that
// show one movie frame share one decode, a movie that will not open leaves
// its span empty, and closing the session puts every movie back.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/temp_dir.dart';

/// A hydrate that never answers must FAIL here, not hang the suite — the
/// playback warmer waits on it before every frame, so a hang is a warmer
/// that stops for good.
const Duration _answersWithin = Duration(seconds: 30);

/// A reader that will not open anything — a take that is not there.
class _Refusing extends FakeVideoBackend {
  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length})? range,
  }) async => null;
}

/// A reader that hands every open its own token, and remembers what was put
/// back.
class _Counting extends FakeVideoBackend {
  _Counting() : super(frameCount: 24);

  final List<int> opened = [];
  final List<int> closed = [];

  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length})? range,
  }) async {
    final answer = await super.open(path, range: range);
    opened.add(opened.length + 1);
    return (token: opened.last, info: answer!.info);
  }

  @override
  Future<void> close(int token) async => closed.add(token);
}

void main() {
  late Directory tempDir;
  late String moviePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-movie-shows');
    moviePath = '${tempDir.path}${Platform.pathSeparator}take3.mov';
    await File(moviePath).writeAsBytes(const [0, 0, 0, 24]);
  });

  tearDown(() async {
    debugVideoDecodeBackend = null;
    deleteTempQuietly(tempDir);
  });

  EditorSessionManager session() => EditorSessionManager(
    initialProject: createDefaultProject(),
    audioConformStore: soundConformStore(),
  );

  Future<void> place(
    WidgetTester tester,
    EditorSessionManager s, {
    int inFrame = 0,
    MediaFitMode fit = MediaFitMode.contain,
  }) => tester.runAsync(
    () => s.importDoors.importVideoFile(
      path: moviePath,
      settings: ImportFileSettings(
        mode: ImportFileMode.reference,
        sound: false,
        inFrame: inFrame,
        fit: fit,
      ),
    ),
  );

  /// A session with [backend]'s movie placed as a reference from [inFrame].
  ///
  /// The playback warmer is HELD, as it is while someone works — so what a
  /// test sees decoded is the canvas's asking and its own.
  Future<(EditorSessionManager, Layer)> placed(
    WidgetTester tester,
    FakeVideoBackend backend, {
    int inFrame = 0,
    MediaFitMode fit = MediaFitMode.contain,
  }) async {
    debugVideoDecodeBackend = backend;
    final s = session();
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    await place(tester, s, inFrame: inFrame, fit: fit);
    return (s, s.requireActiveCut.layers.firstWhere(isMovieReference));
  }

  BitmapSurface? pictureAt(EditorSessionManager s, Layer layer, int frame) =>
      s.brushSurfaceForLayerFrame(layer, resolveExposedFrameAt(layer, frame)!);

  testWidgets('each position of the one held cel is its own movie cel, '
      'counted from the file\'s IN point', (tester) async {
    final (_, layer) = await placed(
      tester,
      FakeVideoBackend(frameCount: 24),
      inFrame: 4,
    );
    final held = layer.frames.single.id;

    expect(resolveExposedFrameAt(layer, 0)!.id, movieCelFrameId(held, 4));
    expect(resolveExposedFrameAt(layer, 7)!.id, movieCelFrameId(held, 11));
    await tester.pumpAndSettle();
  });

  testWidgets('positions that show one movie frame share ONE decode — asked '
      'together, or one after the other', (tester) async {
    final fake = FakeVideoBackend(frameCount: 12, fpsNumerator: 12);
    final (s, layer) = await placed(tester, fake);
    final cut = s.requireActiveCut;

    await tester.runAsync(() async {
      await Future.wait([
        s.movieCels.hydrate(cut, 2),
        s.movieCels.hydrate(cut, 3),
      ]).timeout(_answersWithin);
      await s.movieCels.hydrate(cut, 4).timeout(_answersWithin);
      await s.movieCels.hydrate(cut, 5).timeout(_answersWithin);
    });

    expect(pictureAt(s, layer, 2), isNotNull);
    expect(
      identical(pictureAt(s, layer, 2), pictureAt(s, layer, 3)),
      isTrue,
      reason: 'a 12 fps take holds each frame for two project frames',
    );
    expect(identical(pictureAt(s, layer, 4), pictureAt(s, layer, 5)), isTrue);
    expect(
      fake.asked.where((frame) => frame == 1),
      hasLength(1),
      reason: 'asked together: one decode',
    );
    expect(
      fake.asked.where((frame) => frame == 2),
      hasLength(1),
      reason: 'asked after it landed: the same picture',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('the picture sits the way the file was placed — the pool '
      'entry\'s fit, not a stretch over the canvas', (tester) async {
    final (s, layer) = await placed(
      tester,
      FakeVideoBackend(frameCount: 24),
      fit: MediaFitMode.none,
    );

    await tester.runAsync(
      () => s.movieCels.hydrate(s.requireActiveCut, 0).timeout(_answersWithin),
    );

    expect(
      pictureAt(s, layer, 0)!.tiles.length,
      lessThanOrEqualTo(4),
      reason: 'a 64×36 take at its own size, centred',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a placed movie\'s picture is asked for as it lands, at the '
      'frame the canvas stands on', (tester) async {
    final fake = FakeVideoBackend(frameCount: 24);
    await placed(tester, fake, inFrame: 4);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );

    expect(fake.asked, [4], reason: 'frame 0 of the block, 4 into the movie');
    await tester.pumpAndSettle();
  });

  testWidgets('a scrub asks for the frame the canvas moves to — no session '
      'change needed', (tester) async {
    final fake = FakeVideoBackend(frameCount: 24);
    final (s, _) = await placed(tester, fake);

    await tester.runAsync(() async {
      s.editingFrameCursor.value = 7;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(fake.asked, contains(7));
    await tester.pumpAndSettle();
  });

  testWidgets('the playback warmer decodes a movie frame before it composes '
      'it', (tester) async {
    final fake = FakeVideoBackend(frameCount: 24);
    final (s, layer) = await placed(tester, fake);
    final warmer = s.playbackRig.prerenderScheduler..endInputHold();

    await tester.runAsync(() async {
      warmer.requestWarmCut(
        cutId: s.requireActiveCut.id,
        quality: PlaybackQuality.quarter,
        aroundFrameIndex: 10,
      );
      final deadline = DateTime.now().add(_answersWithin);
      while (pictureAt(s, layer, 10) == null) {
        if (DateTime.now().isAfter(deadline)) {
          fail('the warmer composed frame 10 without its movie picture');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });

    expect(fake.asked, contains(10), reason: 'the canvas stands on 0');
    await tester.pumpAndSettle();
  });

  testWidgets('a movie that will not open leaves its span empty', (
    tester,
  ) async {
    final (s, layer) = await placed(tester, FakeVideoBackend(frameCount: 24));
    debugVideoDecodeBackend = _Refusing();
    final gone = layer.copyWith(
      mediaReference: MediaReference(assetPath: '${moviePath}_gone.mov'),
    );
    s.repository.replaceLayer(layer: gone);

    await tester.runAsync(
      () => s.movieCels.hydrate(s.requireActiveCut, 0).timeout(_answersWithin),
    );

    expect(pictureAt(s, gone, 0), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('closing the session puts back every movie it opened — each '
      'to the reader that opened it', (tester) async {
    final reader = _Counting();
    debugVideoDecodeBackend = reader;
    final s = session();
    s.playbackRig.prerenderScheduler.beginInputHold();
    await place(tester, s);

    await tester.runAsync(() async {
      await s.movieCels.hydrate(s.requireActiveCut, 0).timeout(_answersWithin);
      expect(reader.opened, hasLength(2), reason: 'the import, the canvas');
      // A token is its reader's: whoever answers for movies NOW did not
      // open this one, and must not be the one asked to close it.
      debugVideoDecodeBackend = FakeVideoBackend();
      s.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(reader.closed.toSet(), reader.opened.toSet());
  });
}
