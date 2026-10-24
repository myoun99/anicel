import '../../native/qa_video_decoder.dart' show QaVideoInfo;
import 'media_byte_source.dart';
import 'video_decode_worker.dart';

/// Where a movie decoder is pointed at [source]: a file of its own by its
/// path, or the span of one it is stored in — or null when its bytes are
/// not there to point at.
///
/// 🚨★★★**A MOVIE KEPT FRAMED IS READ IN PLACE.** It could not be until
/// 2026-09-24 — the OS decoders read nothing but the container's own bytes —
/// and the answer was to serve them decoded blocks through the engine's
/// one span reader, on every platform (유저 on board
/// `carried-movie-compressed-Q1`: 「압축 유지 + 풀면서 디코더에 먹이는 리더를
/// 플랫폼마다 만든다」).
/// 🪦Android below API 28 could not be fed one and read its original
/// instead while there was one, through a `movieBytesToDecode` and a
/// `readsFramed` of its own — the one place a reader preferred an original
/// to the project's copy. That device class left the release on 2026-10-24
/// (minSdk 29, board skia-devices-out-of-release) and both went with it.
///
/// ⚠️A whole file goes by its PATH even though it is also a span: the OS
/// opens a file it is handed by name itself, which is faster and better
/// tested than anything wrapped around one.
({String path, ({int offset, int length, bool framed})? span})? movieOpening(
  MediaByteSource source,
) {
  final file = source.wholeFilePath;
  if (file != null) {
    return (path: file, span: null);
  }
  final at = source.span;
  if (at == null) {
    return null;
  }
  return (
    path: at.path,
    span: (offset: at.offset, length: at.length, framed: at.framed),
  );
}

/// [backend] opened on [source] where it lies ([movieOpening]) — null when
/// no decoder can be pointed there, or when the one there could not read
/// what it found.
Future<({int token, QaVideoInfo info})?> openMovieOn(
  VideoDecodeBackend backend,
  MediaByteSource source,
) async {
  final at = movieOpening(source);
  return at == null ? null : backend.open(at.path, span: at.span);
}

/// A movie open on a decoder, and how it is put back: `close` shuts the
/// decoder and only THEN gives back the bytes it was reading — `moved`, each
/// time those bytes have an answer somewhere else or are about to
/// ([HeldMediaBytes.moved]), and `again`, the same bytes held wherever they
/// are now ([HeldMediaBytes.again]).
typedef HeldMovie = ({
  int token,
  QaVideoInfo info,
  Future<void> Function() close,
  Stream<HeldBytesMove> moved,
  Future<HeldMediaBytes> Function() again,
});

/// [backend] opened on the bytes [hold] answers for [path] — the project's
/// own copy, wherever it lies — held until the movie is closed
/// ([openOnHeldBytes]).
///
/// 🚨The one way a reader that decodes frames itself opens a medium's movie:
/// the canvas's reference rows, a placement, a reference baked into cels and
/// the import window's preview. (The viewer's document asks the same two
/// questions — [ProjectFile.holdMediaBytes] and [movieOpening] — through
/// `VideoViewerDocument`.)
Future<HeldMovie?> openHeldMovie(
  VideoDecodeBackend backend,
  HoldMediaBytes hold,
  String path,
) => openOnHeldBytes(
  hold,
  path,
  (source) async {
    final opened = await openMovieOn(backend, source);
    return opened == null
        ? null
        : (
            token: opened.token,
            info: opened.info,
            close: () => backend.close(opened.token),
          );
  },
  (movie, held) => (
    token: movie.token,
    info: movie.info,
    close: () async {
      try {
        await movie.close();
      } finally {
        held.release();
      }
    },
    moved: held.moved,
    again: held.again,
  ),
);

/// What [path]'s movie says of itself — its frame size, its rate, its
/// length — opened as [openHeldMovie] opens it and closed at once; null
/// when it does not open.
///
/// 🪦The import window (a pulldown's partner) and a reference sized to its
/// movie each opened, read and closed for themselves; the import window's
/// resolution column (F-375, 2026-10-17) would have been the third.
Future<QaVideoInfo?> readHeldMovieInfo(
  VideoDecodeBackend backend,
  HoldMediaBytes hold,
  String path,
) async {
  final opened = await openHeldMovie(backend, hold, path);
  if (opened == null) {
    return null;
  }
  try {
    return opened.info;
  } finally {
    await opened.close();
  }
}
