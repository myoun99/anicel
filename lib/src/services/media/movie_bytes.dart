import 'dart:io';

import '../../native/qa_video_decoder.dart' show QaVideoInfo;
import 'media_byte_source.dart';
import 'video_decode_worker.dart';

/// Where [backend]'s decoder is pointed at [source]: a file of its own by
/// its path, or the span of one it is stored in — or null when it cannot be
/// pointed there.
///
/// 🚨★★★**A MOVIE KEPT FRAMED IS READ IN PLACE.** It could not be until
/// 2026-09-24 — the OS decoders read nothing but the container's own bytes —
/// and the answer was to serve them decoded blocks through the engine's
/// one span reader, on every platform (유저 on board
/// `carried-movie-compressed-Q1`: 「압축 유지 + 풀면서 디코더에 먹이는 리더를
/// 플랫폼마다 만든다」). The one device that cannot be fed one is Android
/// below API 28 ([VideoDecodeBackend.readsFramed]), and there this answers
/// null — see [movieBytesToDecode] for what happens next.
///
/// ⚠️A whole file goes by its PATH even though it is also a span: the OS
/// opens a file it is handed by name itself, which is faster and better
/// tested than anything wrapped around one.
({String path, ({int offset, int length, bool framed})? span})? movieOpening(
  MediaByteSource source,
  VideoDecodeBackend backend,
) {
  final file = source.wholeFilePath;
  if (file != null) {
    return (path: file, span: null);
  }
  final at = source.span;
  if (at == null || (at.framed && !backend.readsFramed)) {
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
  final at = movieOpening(source, backend);
  return at == null ? null : backend.open(at.path, span: at.span);
}

/// A movie open on a decoder, and how it is put back: `close` shuts the
/// decoder and only THEN gives back the bytes it was reading — and `moved`,
/// when those bytes have an answer somewhere else now
/// ([HeldMediaBytes.moved]).
typedef HeldMovie = ({
  int token,
  QaVideoInfo info,
  Future<void> Function() close,
  Future<void> moved,
});

/// [backend] opened on the bytes [hold] answers for [path] — the project's
/// own copy first ([movieBytesToDecode]) — held until the movie is closed
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
    final opened = await openMovieOn(
      backend,
      movieBytesToDecode(source, path, backend),
    );
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
  ),
);

/// The bytes a movie decoder should read for a medium the project answers
/// with [carried]: those — or, when [backend]'s decoder cannot read them
/// where they lie and [original] is still there, the original.
///
/// 🚨★★★**THE ONE PLACE A READER PREFERS AN ORIGINAL TO THE PROJECT'S OWN
/// COPY** (「품은 순간 데이터를 가지고있고 불변」), and it is reached on one
/// device class only: Android below API 28 with a movie kept framed. 유저
/// accepted exactly that cost with the answer on board
/// `carried-movie-compressed-Q1` — such a device reads a carried movie
/// kept compressed only while its original exists. ONE function, so the
/// answer lives in one place.
///
/// 🪦Until that answer this was ⏸INTERIM and reached on every platform,
/// because no decoder anywhere read a framed movie in place.
MediaByteSource movieBytesToDecode(
  MediaByteSource carried,
  String original,
  VideoDecodeBackend backend,
) =>
    movieOpening(carried, backend) != null || !File(original).existsSync()
    ? carried
    : MediaFileBytes(original);
