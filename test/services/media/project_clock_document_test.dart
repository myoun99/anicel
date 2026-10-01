import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/movie_clock.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/media/project_clock_document.dart';

import '../../helpers/fake_pdf_document.dart';

/// A movie counted on the PROJECT's clock — the frames a placement counts —
/// as a document every surface can draw and run (import-preview-plays-silent,
/// 2026-09-30).
///
/// 🚨Why a document and not a mapping in the surface: movie frame → project
/// frame has no inverse. A faster movie skips frames no project frame shows
/// and a slower one holds a frame over several, so a surface that kept the
/// MOVIE frame as the truth could not say which project frame it stood on,
/// and one that turned movie frames while counting project ones would run
/// fast or stall.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const project = ProjectFrameRate.fps24;

  /// A movie of [frames] frames as a stack of pages.
  FakePdfDocument movie(int frames) =>
      FakePdfDocument(pageSizes: List.filled(frames, const ui.Size(64, 36)));

  ProjectClockDocument onTheClock(
    FakePdfDocument movie, {
    required int framesPerSecond,
    ({int numerator, int denominator}) speed = (numerator: 1, denominator: 1),
  }) => ProjectClockDocument(
    movie,
    MovieClock(
      projectRate: project,
      audioSpeed: speed,
      movieRate: (numerator: framesPerSecond, denominator: 1),
    ),
    pace: project.inSourceTime(speed),
  );

  /// The movie frame [document] asks for to draw its [page].
  Future<int> frameShownOn(
    ProjectClockDocument document,
    FakePdfDocument movie,
    int page,
  ) async {
    final image = await document.renderPage(page, width: 64, height: 36);
    image.dispose();
    return movie.renderRequests.last.$1;
  }

  test('a movie SLOWER than the project holds a frame over two pages', () async {
    final twelve = movie(5);
    final document = onTheClock(twelve, framesPerSecond: 12);

    expect(document.pageCount, 10, reason: '5 frames at 12 are 10 at 24');
    expect(await frameShownOn(document, twelve, 2), 1);
    expect(await frameShownOn(document, twelve, 3), 1);
    expect(await frameShownOn(document, twelve, 9), 4);
  });

  test('a movie FASTER than the project skips the frames no page shows', () async {
    final fortyEight = movie(12);
    final document = onTheClock(fortyEight, framesPerSecond: 48);

    expect(document.pageCount, 6, reason: '12 frames at 48 are 6 at 24');
    expect(await frameShownOn(document, fortyEight, 1), 2);
    expect(await frameShownOn(document, fortyEight, 5), 10);
  });

  test('🚨its pages advance at the project\'s rate in the MOVIE\'s time, so '
      'a page\'s instant is the movie\'s own — the sound stays in step', () {
    final pulled = onTheClock(
      movie(48),
      framesPerSecond: 24,
      speed: (numerator: 1001, denominator: 1000),
    );

    // A project second is 1.001 seconds of a pulled take (the conform's
    // pull, EXPORT-AUDIO ④): page 24 begins 1.001 seconds into the movie.
    expect(24 / pulled.framesPerSecond!, closeTo(1.001, 1e-9));
    expect(
      onTheClock(movie(48), framesPerSecond: 30).framesPerSecond,
      24,
      reason: 'with no pull, the project\'s own rate — whatever the movie\'s',
    );
  });

  test('it reads the movie\'s own frames, and letting it go lets the movie '
      'go', () async {
    final twelve = movie(5);
    final document = onTheClock(twelve, framesPerSecond: 12);

    expect(document.pageSize(3), const ui.Size(64, 36));
    await document.dispose();
    expect(twelve.disposed, isTrue);
  });
}
