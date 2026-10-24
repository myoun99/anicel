import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/movie_bytes.dart';

import '../../helpers/temp_dir.dart';

/// Where a movie decoder is pointed, asked once for every reader
/// ([movieOpening]).
///
/// 🪦It also pinned the one place a reader preferred an original — a movie
/// kept compressed on a device whose decoder could not be fed one (board
/// `carried-movie-compressed-Q1`). That device class left the release on
/// 2026-10-24 (minSdk 29) and the place with it.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-movie-bytes');
  });

  tearDown(() => deleteTempQuietly(directory));

  /// A carried movie the save kept FRAMED — a 6.7%-smaller MP4.
  const framedEntry = MediaArchiveBytes(
    archivePath: 'C:/work/project.anicel',
    dataOffset: 4096,
    length: 512,
    framed: true,
  );

  group('movieOpening', () {
    test('a file of its own goes by its PATH — the OS opens a file it is '
        'handed by name itself', () {
      final file = File('${directory.path}/take.mp4')
        ..writeAsBytesSync(const [1, 2, 3]);

      expect(movieOpening(MediaFileBytes(file.path)), (
        path: file.path,
        span: null,
      ));
    });

    test('a stretch of the project file goes by that stretch', () {
      const source = MediaArchiveBytes(
        archivePath: 'C:/work/project.anicel',
        dataOffset: 4096,
        length: 512,
      );

      expect(movieOpening(source), (
        path: 'C:/work/project.anicel',
        span: (offset: 4096, length: 512, framed: false),
      ));
    });

    test('🚨a movie kept FRAMED goes by its stretch too, SAYING it is framed '
        '— the decoder is fed the blocks decoded', () {
      const expected = (
        path: 'C:/work/project.anicel',
        span: (offset: 4096, length: 512, framed: true),
      );
      expect(movieOpening(framedEntry), expected);
      expect(
        movieOpening(MediaFramedBytes(framedEntry)),
        expected,
        reason: 'the stored entry and the reader of it name one movie',
      );
    });

    test('and a framed copy that is not there cannot be pointed at', () {
      expect(
        movieOpening(
          MediaAppFileBytes(
            path: '${directory.path}/gone.mp4.framed',
            framed: true,
          ),
        ),
        isNull,
      );
    });
  });
}
