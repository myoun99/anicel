import 'dart:async' show unawaited;

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/media_asset.dart' show MediaCarry;
import '../../models/movie_cel.dart';
import '../../models/movie_clock.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_video_decoder.dart' show QaVideoInfo;
import '../../services/cut_frame_composite_plan.dart'
    show resolveCutFrameCompositeEntries;
import '../../services/import/raster_cel_import.dart'
    show rasterizeImageToSurface;
import '../../services/media/media_byte_source.dart' show HoldMediaBytes;
import '../../services/media/movie_bytes.dart';
import '../../services/media/video_decode_worker.dart';
import '../../services/straight_rgba_image.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// One movie open for reading. The token is the READER's — it minted it and
/// only it can read or close by it (「a handle says which movie is whose」),
/// so the reader is kept beside it rather than asked for again; `close` puts
/// the movie back and only then the bytes it was reading ([openHeldMovie]).
typedef _OpenMovie = ({
  VideoDecodeBackend reader,
  int token,
  QaVideoInfo info,
  Future<void> Function() close,
});

/// A movie by the bytes it shows: the row's pool path, and the carry the
/// pool names there (`ProjectFile.mediaCarryFor`; null for a file the pool
/// points at).
///
/// 🚨★★★**THE PATH ALONE DOES NOT SAY WHICH BYTES.** Removed and carried
/// again, a path means another carry's bytes — and an undo can bring the
/// first back. Kept by path, the first carry's document and pictures
/// answered the new rows (card `recarry-after-remove-reads-the-old`), and a
/// row placed as a link read the original even after the file was carried.
typedef _Movie = ({String path, MediaCarry? carry});

/// One picture of a movie, as a canvas shows it: the movie, the movie
/// frame, and the canvas it was fitted to.
typedef _MoviePicture = (_Movie movie, int movieFrame, CanvasSize canvas);

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
    required HoldMediaBytes holdBytes,
    required MediaCarry? Function(String path) carryFor,
  }) : _project = project,
       _internals = internals,
       _changes = changes,
       _renderCaches = renderCaches,
       _frameRate = frameRate,
       _holdBytes = holdBytes,
       _carryFor = carryFor;

  final ProjectAccess _project;
  final SessionInternals _internals;
  final ChangeSink _changes;
  final RenderCaches _renderCaches;
  final ProjectFrameRate Function() _frameRate;

  /// Where a movie row's bytes are — the project's own copy first
  /// (`ProjectFile.holdMediaBytes`). 🪦This opened the ROW'S PATH, the
  /// file the movie was imported from: a carried movie went blank on the
  /// canvas the moment that file was deleted — or on another machine — and
  /// played the edited file once it was changed (card
  /// `carried-bytes-every-reader`).
  final HoldMediaBytes _holdBytes;

  /// Which carry the pool names at a path right now
  /// (`ProjectFile.mediaCarryFor`) — the other half of what a movie is
  /// ([_Movie]).
  final MediaCarry? Function(String path) _carryFor;

  /// [path] as the movie it shows right now.
  _Movie _movieAt(String path) => (path: path, carry: _carryFor(path));

  /// Each movie's open document — opened once; a movie that would not open
  /// is remembered as such instead of retried at every frame. Only one
  /// carry of a path is open at a time ([_movieFor]).
  final Map<_Movie, Future<_OpenMovie?>> _opened = {};

  /// What each movie TURNED OUT TO BE, once its open has answered.
  final Map<_Movie, QaVideoInfo> _facts = {};

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
  ///
  /// ⚠️Of the carry the pool names at [path] NOW — another carry's facts
  /// describe other bytes.
  QaVideoInfo? factsFor(String path) => _facts[_movieAt(path)];

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
    // Costs one open per movie for the life of the session ([_opened]).
    final jobs = <Future<void>>[
      for (final layer in cut.layers)
        if (isMovieReference(layer))
          _movieFor(_movieAt(layer.mediaReference!.assetPath)),
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
    final at = _movieAt(path);
    final movie = await _movieFor(at);
    if (movie == null || _disposed) {
      return;
    }
    final movieFrame = movieClockFor(
      projectRate: _frameRate(),
      audioSpeed: _project.repository.requireProject().audioSpeed,
      movie: movie.info,
    ).movieFrameAt(elapsed);
    final picture = await _pictureOf(movie, (
      at,
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
    final ((:path, carry: _), movieFrame, canvas) = at;
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
        fit: _project.repository.requireProject().mediaFitModeFor(path),
      );
      _decoded[at] = WeakReference(surface);
      return surface;
    } finally {
      image.dispose();
    }
  }

  /// [movie]'s open document — opened once, and the moment it answers its
  /// facts become askable ([factsFor]).
  ///
  /// 🚨THE FACT ARRIVES LATE, SO WHOEVER DREW WITHOUT IT IS TOLD. A rail
  /// that read [factsFor] before the open landed drew the row as if the file
  /// were long enough; nothing else would ever call it back.
  Future<_OpenMovie?> _movieFor(_Movie movie) async {
    final opened = await (_opened[movie] ??= _openAnew(movie));
    if (opened == null || _disposed || _facts.containsKey(movie)) {
      return opened;
    }
    _facts[movie] = opened.info;
    _changes.notifyChanged();
    return opened;
  }

  /// Opens [movie] — after letting go of any other carry of its path, the
  /// one the pool no longer names. ⛔One carry of a path open at a time:
  /// the other would hold its bytes for the rest of the session — a staged
  /// copy a save cannot retire, an entry a push-down has to step around.
  Future<_OpenMovie?> _openAnew(_Movie movie) {
    _letGoOf([
      for (final other in _opened.keys)
        if (other.path == movie.path && other != movie) other,
    ]);
    return _open(movie.path);
  }

  /// Closes [movies] and forgets what each turned out to be, and showed.
  void _letGoOf(List<_Movie> movies) {
    for (final movie in movies) {
      final document = _opened.remove(movie);
      _facts.remove(movie);
      _decoded.removeWhere((at, _) => at.$1 == movie);
      if (document != null) {
        unawaited(_close(document));
      }
    }
  }

  Future<_OpenMovie?> _open(String path) async {
    final reader = videoDecodeBackend;
    final movie = await openHeldMovie(reader, _holdBytes, path);
    return movie == null
        ? null
        : (
            reader: reader,
            token: movie.token,
            info: movie.info,
            close: movie.close,
          );
  }


  /// Closes every movie this opened, each by the reader that opened it.
  Future<void> dispose() {
    _disposed = true;
    return _closeEveryMovie();
  }

  /// Lets go of every movie this opened and forgets what each turned out
  /// to be — for a session whose whole project is about to be REPLACED
  /// (`PlaybackRig.letGoOfTheProject`).
  ///
  /// 🚨A movie is kept by its path and carry ([_Movie]) — and a file the
  /// pool points at has no carry, in this project or the next: kept across
  /// a load, a row of the next project with the same path decoded the LAST
  /// project's bytes and facts, and that project's file stayed open until
  /// the app quit (audit 2026-09-24).
  Future<void> reset() => _closeEveryMovie();

  Future<void> _closeEveryMovie() async {
    final opened = [..._opened.values];
    _opened.clear();
    _facts.clear();
    _decoded.clear();
    for (final document in opened) {
      await _close(document);
    }
  }

  /// Closes one movie this opened, by the reader that opened it.
  ///
  /// ⚠️Each on its own: one movie that failed to open, or will not close,
  /// must not keep the rest open — and the bytes they hold.
  static Future<void> _close(Future<_OpenMovie?> document) async {
    try {
      final movie = await document;
      if (movie != null) {
        await movie.close();
      }
    } on Object {
      // Nothing further to put back for that one.
    }
  }
}
