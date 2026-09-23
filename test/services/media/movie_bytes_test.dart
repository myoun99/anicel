import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/movie_bytes.dart';

import '../../helpers/temp_dir.dart';

/// Where a movie decoder is pointed, asked once for every reader
/// ([movieOpening]), and the interim answer for a movie kept compressed
/// ([movieBytesToDecode], board `carried-movie-compressed-Q1`).
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-movie-bytes');
  });

  tearDown(() => deleteTempQuietly(directory));

  MediaFramedBytes framed() => MediaFramedBytes.reading(
    readStored: (buffer, position, size) => 0,
    storedExists: () => true,
  );

  group('movieOpening', () {
    test('a file of its own goes by its PATH — Windows and Apple refuse a '
        'range by name', () {
      final file = File('${directory.path}/take.mp4')
        ..writeAsBytesSync(const [1, 2, 3]);

      expect(movieOpening(MediaFileBytes(file.path)), (
        path: file.path,
        range: null,
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
        range: (offset: 4096, length: 512),
      ));
    });

    test('a movie kept framed cannot be pointed at at all', () {
      expect(movieOpening(framed()), isNull);
    });
  });

  group('movieBytesToDecode (interim)', () {
    test('what can be read in place is read in place', () {
      const carried = MediaArchiveBytes(
        archivePath: 'C:/work/project.anicel',
        dataOffset: 0,
        length: 8,
      );
      final original = File('${directory.path}/take.mp4')
        ..writeAsBytesSync(const [1]);

      expect(movieBytesToDecode(carried, original.path), same(carried));
    });

    test('a framed movie is read from its original while there is one', () {
      final original = File('${directory.path}/take.mp4')
        ..writeAsBytesSync(const [1]);

      expect(
        movieBytesToDecode(framed(), original.path),
        MediaFileBytes(original.path),
      );
    });

    test('and without one stays what the project carries', () {
      final carried = framed();

      expect(
        movieBytesToDecode(carried, '${directory.path}/gone.mp4'),
        same(carried),
      );
    });
  });
}
