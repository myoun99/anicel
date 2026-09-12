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
    required ChangeSink changes,
    required RenderCaches renderCaches,
    required ProjectFrameRate Function() frameRate,
  }) : _project = project,
       _internals = internals,
       _changes = changes,
       _renderCaches = renderCaches,
       _frameRate = frameRate;

  final ProjectAccess _project;
  final SessionInternals _internals;
  final ChangeSink _changes;
  final RenderCaches _renderCaches;
  final ProjectFrameRate Function() _frameRate;

  /// Each movie's open document, by path — opened once; a movie that would
  /// not open is remembered as such instead of retried at every frame.
  final Map<String, Future<_OpenMovie?>> _opened = {};

  /// What each movie TURNED OUT TO BE, once its open has answered.
  final Map<String, QaVideoInfo> _facts = {};

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

  /// What the DECODER said [path] is, or null while nothing has opened it.
  ///
  /// 🚨★★★THE FILE'S OWN TRUTH, ASKED SYNCHRONOUSLY — the shape
  /// [AudioConformStore.failureFor] already has, and for the same reason: a
  /// widget cannot await, so the fact is learned where it is learned anyway
  /// and left here to be read. ⛔NOT the pool's copy. `MediaAsset.sourceFps`
  /// is a `double` and its `frameCount` was written at registration, while
  /// this is what the decoder answered about the file that is there now.
  QaVideoInfo? factsFor(String path) => _facts[path];

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
    // EVERY movie row of the cut is OPENED, not only the ones composing at
    // this frame. What the file turns out to be is what the rail's reference
    // button says about the row, and a row whose block the playhead has not
    // reached yet is exactly the row someone is looking at when they wonder.
    // Costs one open per path for the life of the session ([_opened]).
    final jobs = <Future<void>>[
      for (final layer in cut.layers)
        if (isMovieReference(layer))
          _movieFor(layer.mediaReference!.assetPath),
    ];
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
    final movie = await _movieFor(path);
    if (movie == null || _disposed) {
      return;
    }
    final movieFrame = movieClockFor(
      projectRate: _frameRate(),
      audioSpeed: _project.repository.requireProject().audioSpeed,
      movie: movie.info,
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
        fit: mediaFitModeFor(
          _project.repository.requireProject().mediaAssets,
          path,
        ),
      );
      _decoded[at] = WeakReference(surface);
      return surface;
    } finally {
      image.dispose();
    }
  }

  /// [path]'s open movie — opened once, and the moment it answers its facts
  /// become askable ([factsFor]).
  ///
  /// 🚨THE FACT ARRIVES LATE, SO WHOEVER DREW WITHOUT IT IS TOLD. A rail
  /// that read [factsFor] before the open landed drew the row as if the file
  /// were long enough; nothing else would ever call it back.
  Future<_OpenMovie?> _movieFor(String path) async {
    final movie = await (_opened[path] ??= _open(path));
    if (movie == null || _disposed || _facts.containsKey(path)) {
      return movie;
    }
    _facts[path] = movie.info;
    _changes.notifyChanged();
    return movie;
  }

  static Future<_OpenMovie?> _open(String path) async {
    final reader = videoDecodeBackend;
    final opened = await reader.open(path);
    return opened == null
        ? null
        : (reader: reader, token: opened.token, info: opened.info);
  }


  /// Closes every movie this opened, each by the reader that opened it.
  Future<void> dispose() async {
    _disposed = true;
    final opened = [..._opened.values];
    _opened.clear();
    _facts.clear();
    _decoded.clear();
    for (final document in opened) {
      final movie = await document;
      if (movie != null) {
        await movie.reader.close(movie.token);
      }
    }
  }
}
