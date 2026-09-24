import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/movie_bytes.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/temp_dir.dart';

/// Where a movie decoder is pointed, asked once for every reader
/// ([movieOpening]), and the one place a reader still prefers an original
/// ([movieBytesToDecode]) — a movie kept compressed on a device whose decoder
/// cannot be fed one (board `carried-movie-compressed-Q1`).
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

  /// A device like every platform but Android below 9.
  final feeds = FakeVideoBackend();

  /// Android below 9: its decoder has no custom source to be fed through.
  final cannot = FakeVideoBackend(readsFramed: false);

  group('movieOpening', () {
    test('a file of its own goes by its PATH — the OS opens a file it is '
        'handed by name itself', () {
      final file = File('${directory.path}/take.mp4')
        ..writeAsBytesSync(const [1, 2, 3]);

      expect(movieOpening(MediaFileBytes(file.path), feeds), (
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

      expect(movieOpening(source, feeds), (
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
      expect(movieOpening(framedEntry, feeds), expected);
      expect(
        movieOpening(MediaFramedBytes(framedEntry), feeds),
        expected,
        reason: 'the stored entry and the reader of it name one movie',
      );
    });

    test('and where the decoder cannot be fed one, it cannot be pointed at',
        () {
      expect(movieOpening(framedEntry, cannot), isNull);
      expect(
        movieOpening(
          const MediaArchiveBytes(
            archivePath: 'C:/work/project.anicel',
            dataOffset: 4096,
            length: 512,
          ),
          cannot,
        ),
        isNotNull,
        reason: 'only FRAMED is beyond that device — a plain stretch is fine',
      );
    });
  });

  group('movieBytesToDecode', () {
    late File original;

    setUp(() {
      original = File('${directory.path}/take.mp4')
        ..writeAsBytesSync(const [1]);
    });

    test('what can be read in place is read in place, original or not', () {
      expect(
        movieBytesToDecode(framedEntry, original.path, feeds),
        same(framedEntry),
        reason: '「품은 순간 … 불변」 — the project\'s own copy wins',
      );
    });

    test('a framed movie on a device that cannot be fed one reads its '
        'original while there is one — the cost 유저 accepted', () {
      expect(
        movieBytesToDecode(framedEntry, original.path, cannot),
        MediaFileBytes(original.path),
      );
    });

    test('and without one stays what the project carries', () {
      expect(
        movieBytesToDecode(framedEntry, '${directory.path}/gone.mp4', cannot),
        same(framedEntry),
      );
    });
  });
}
