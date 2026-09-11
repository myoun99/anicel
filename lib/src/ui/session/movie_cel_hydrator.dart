import 'dart:async' show unawaited;

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/media_asset.dart';
import '../../models/movie_cel.dart';
import '../../models/movie_clock.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_video_decoder.dart' show QaVideoInfo;
import '../../services/cut_frame_composite_plan.dart'
    show resolveCutFrameCompositeEntries;
import '../../services/import/raster_cel_import.dart'
    show rasterizeImageToSurface;
import '../../services/media/video_decode_worker.dart';
import '../../services/straight_rgba_image.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// One movie open for reading. The token is the READER's — it minted it and
/// only it can read or close by it (「a handle says which movie is whose」),
/// so the reader is kept beside it rather than asked for again.
typedef _OpenMovie = ({VideoDecodeBackend reader, int token, QaVideoInfo info});

/// One picture of a movie, as a canvas shows it: the file, the movie frame,
/// and the canvas it was fitted to.
typedef _MoviePicture = (String path, int movieFrame, CanvasSize canvas);

/// Decodes the MOVIE cels a cut shows into the cel store (미디어 배치 라운드
/// 6; 08-31 「굽지 않고 재생할 때 디코드」).
///
/// The compositor only ever asks the store; this is what fills it. The
/// playback warmer awaits it before a frame composes (「초록 바는 지금 그림에
/// 쓰는 그 캐시와 예산이다」) and the editing canvas asks for the frame it
/// shows — a movie is decoded where it is looked at, never all at once. A
/// movie that will not open leaves its span empty; a relink, which is a new
/// path, brings it back.
///
/// ⚠️It holds no pixels of its own. The store keeps the pictures, under the
/// hot tier's byte budget; this only knows which decode is running, and
/// which picture is still somewhere to be shared.
class MovieCelHydrator {
  MovieCelHydrator({
    required ProjectAccess project,
    required SessionInternals internals,
    required RenderCaches renderCaches,
    required ProjectFrameRate Function() frameRate,
  }) : _project = project,
       _internals = internals,
       _renderCaches = renderCaches,
       _frameRate = frameRate;

  final ProjectAccess _project;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;
  final ProjectFrameRate Function() _frameRate;

  /// Each movie's open document, by path — opened once; a movie that would
  /// not open is remembered as such instead of retried at every frame.
  final Map<String, Future<_OpenMovie?>> _opened = {};

  /// Pictures being decoded right now: positions that show one frame of the
  /// file — and askers that come back before it lands — wait for ONE
  /// decode.
  final Map<_MoviePicture, Future<BitmapSurface?>> _decoding = {};

  /// Pictures decoded before, for as long as the store still holds them —
  /// the next position showing the same movie frame takes the same
  /// surface. Weak, because the store's budget decides how long a picture
  /// lives, not this.
  final Map<_MoviePicture, WeakReference<BitmapSurface>> _decoded = {};

  /// Set by [dispose]. A decode still on its way installs nothing: the store
  /// it would fill goes with the session.
  bool _disposed = false;

  /// Decodes every movie cel [cut] composes at [frameIndex] that the store
  /// has not got at the cut's canvas — the rows the composite plan itself
  /// resolves, so a hidden row is never decoded.
  Future<void> hydrate(Cut cut, int frameIndex) {
    // Asked on every session change: a cut with no movie in it answers
    // before the composite visit runs.
    if (_disposed || !cut.layers.any(isMovieReference)) {
      return Future<void>.value();
    }
    final store = _renderCaches.brushFrameStore;
    final jobs = <Future<void>>[];
    for (final entry in resolveCutFrameCompositeEntries(
      cut: cut,
      frameIndex: frameIndex,
    )) {
      final movieCel = movieCelOf(entry.frame.id);
      final reference = entry.layer.mediaReference;
      if (movieCel == null || reference == null) {
        continue;
      }
      final key = _internals.brushFrameKeyForCut(
        cut,
        entry.layer.id,
        entry.frame.id,
      );
      if (store.hasMovieCel(key, cut.canvasSize)) {
        continue;
      }
      jobs.add(_fill(key, cut, reference.assetPath, movieCel.elapsed));
    }
    return Future.wait(jobs);
  }

  Future<void> _fill(
    BrushFrameKey key,
    Cut cut,
    String path,
    int elapsed,
  ) async {
    final movie = await (_opened[path] ??= _open(path));
    if (movie == null || _disposed) {
      return;
    }
    final project = _project.repository.requireProject();
    final movieFrame = MovieClock(
      projectRate: _frameRate(),
      audioSpeed: (
        numerator: project.audioSpeedNumerator,
        denominator: project.audioSpeedDenominator,
      ),
      movieRate: (
        numerator: movie.info.fpsNumerator,
        denominator: movie.info.fpsDenominator,
      ),
    ).movieFrameAt(elapsed);
    final picture = await _pictureOf(movie, (
      path,
      movieFrame,
      cut.canvasSize,
    ));
    if (picture == null || _disposed) {
      return;
    }
    _renderCaches.brushFrameStore.installMovieCel(key, picture);
  }

  Future<BitmapSurface?> _pictureOf(_OpenMovie movie, _MoviePicture at) {
    final kept = _decoded[at]?.target;
    if (kept != null) {
      return Future.value(kept);
    }
    _decoded.remove(at);
    return _decoding[at] ??= _decode(movie, at).whenComplete(() {
      // 🚨A BLOCK, NOT AN ARROW. `remove` answers what it removed — this
      // very future — and a `whenComplete` callback that returns a future
      // is waited for: the arrow made the decode wait on itself, and the
      // playback warmer stopped for good at the first movie frame.
      // What `remove` answers is dropped on purpose.
      unawaited(_decoding.remove(at));
    });
  }

  Future<BitmapSurface?> _decode(_OpenMovie movie, _MoviePicture at) async {
    final (path, movieFrame, canvas) = at;
    final rgba = await movie.reader.frame(movie.token, movieFrame);
    if (rgba == null || _disposed) {
      return null;
    }
    final image = await decodeStraightRgbaImage(
      rgba: rgba,
      width: movie.info.width,
      height: movie.info.height,
    );
    try {
      final surface = await rasterizeImageToSurface(
        image: image,
        canvas: canvas,
        fit: _fitOf(_project.repository.requireProject().mediaAssets, path),
      );
      _decoded[at] = WeakReference(surface);
      return surface;
    } finally {
      image.dispose();
    }
  }

  static Future<_OpenMovie?> _open(String path) async {
    final reader = videoDecodeBackend;
    final opened = await reader.open(path);
    return opened == null
        ? null
        : (reader: reader, token: opened.token, info: opened.info);
  }

  /// The fit the file was placed with — the pool entry records it.
  static MediaFitMode _fitOf(List<MediaAsset> pool, String path) {
    for (final asset in pool) {
      if (asset.path == path) {
        return asset.fitMode;
      }
    }
    return MediaFitMode.contain;
  }

  /// Closes every movie this opened, each by the reader that opened it.
  Future<void> dispose() async {
    _disposed = true;
    final opened = [..._opened.values];
    _opened.clear();
    _decoded.clear();
    for (final document in opened) {
      final movie = await document;
      if (movie != null) {
        await movie.reader.close(movie.token);
      }
    }
  }
}
