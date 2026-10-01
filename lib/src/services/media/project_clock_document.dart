import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/movie_clock.dart';
import '../../models/project_frame_rate.dart';
import 'video_viewer_document.dart';
import 'viewer_document.dart';

/// A movie counted on the PROJECT's clock: page n is project frame n, and
/// it shows the movie frame that holds that frame's instant ([MovieClock]).
///
/// 🚨For a surface that shows a movie as it will LAND — the import window's
/// preview, whose IN/OUT are the frames a placement counts (유저
/// 2026-09-11: 「영상의 시간은 소리와 같은 시계로 맞춘다」). Whatever draws
/// or plays a [ViewerDocument] works on it unchanged — the transport counts
/// its pages, the page cache keys them, the run turns them — and the sound
/// stays in step, because [framesPerSecond] is the project's rate in the
/// MOVIE's time ([ProjectFrameRate.inSourceTime]): a page's instant is the
/// movie's own.
///
/// ⚠️A movie slower than the project shows one frame on more than one
/// page, and each page is its own render — the page cache keys pages.
final class ProjectClockDocument implements ViewerDocument {
  ProjectClockDocument(
    this._movie,
    this._clock, {
    required ProjectFrameRate pace,
  }) : _pace = pace;

  /// [movie] on [project]'s clock, assembled from what the decoder said
  /// ([movieClockFor]) as a placement's is.
  factory ProjectClockDocument.of(
    VideoViewerDocument movie,
    ProjectClock project,
  ) => ProjectClockDocument(
    movie,
    movieClockFor(
      projectRate: project.rate,
      audioSpeed: project.speed,
      movie: movie.info,
    ),
    pace: project.rate.inSourceTime(project.speed),
  );

  final ViewerDocument _movie;
  final MovieClock _clock;

  /// Pages per second of the movie's own time.
  final ProjectFrameRate _pace;

  int _frameOf(int page) => _clock.movieFrameAt(page);

  @override
  int get pageCount => _clock.projectFramesCovering(_movie.pageCount);

  @override
  double? get framesPerSecond => _pace.approximateFps;

  @override
  ui.Size pageSize(int pageIndex) => _movie.pageSize(_frameOf(pageIndex));

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) => _movie.renderPage(_frameOf(pageIndex), width: width, height: height);

  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) => _movie.readRegionRgba(_frameOf(pageIndex), box);

  @override
  Future<void> dispose() => _movie.dispose();
}
