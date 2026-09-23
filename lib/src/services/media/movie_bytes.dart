import 'dart:io';

import '../../native/qa_video_decoder.dart' show QaVideoInfo;
import 'media_byte_source.dart';
import 'video_decode_worker.dart';

/// Where a movie decoder is pointed at [source]: a file of its own by its
/// path, or a plain stretch of one by its range — or null when it cannot
/// be. A movie kept FRAMED (compressed in blocks) is not the container's own
/// bytes, and the OS decoders read nothing else (board
/// `carried-movie-compressed`).
///
/// ⚠️A whole file goes by its PATH even though it is also a range: Windows
/// and Apple refuse a range by name while they decode paths perfectly well.
({String path, ({int offset, int length})? range})? movieOpening(
  MediaByteSource source,
) {
  final file = source.wholeFilePath;
  if (file != null) {
    return (path: file, range: null);
  }
  final stretch = source.range;
  return stretch == null
      ? null
      : (
          path: stretch.path,
          range: (offset: stretch.offset, length: stretch.length),
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
  return at == null ? null : backend.open(at.path, range: at.range);
}

/// A movie open on a decoder, and how it is put back: `close` shuts the
/// decoder and only THEN gives back the bytes it was reading.
typedef HeldMovie = ({
  int token,
  QaVideoInfo info,
  Future<void> Function() close,
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
) => openOnHeldBytes<HeldMovie>(
  hold,
  path,
  (source) async {
    final opened = await openMovieOn(
      backend,
      movieBytesToDecode(source, path),
    );
    return opened == null
        ? null
        : (
            token: opened.token,
            info: opened.info,
            close: () => backend.close(opened.token),
          );
  },
  (movie, release) => (
    token: movie.token,
    info: movie.info,
    close: () async {
      try {
        await movie.close();
      } finally {
        release();
      }
    },
  ),
);

/// ⏸**INTERIM, until board `carried-movie-compressed-Q1` is answered.** The
/// bytes a movie decoder should read for a medium the project answers with
/// [carried]: those — or, when no decoder can read them where they lie and
/// [original] is still there, the original, which is what every reader of a
/// carried movie read before 2026-09-24. Without it, [carried] goes on, and
/// its reader says it cannot be read in place.
///
/// ⚠️The one place a reader still prefers an original to the project's own
/// copy (「품은 순간 데이터를 가지고있고 불변」) — which is exactly what the
/// card asks. ONE function, so the answer changes in one place.
MediaByteSource movieBytesToDecode(MediaByteSource carried, String original) =>
    movieOpening(carried) != null || !File(original).existsSync()
    ? carried
    : MediaFileBytes(original);
