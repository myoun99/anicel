import 'dart:typed_data';

import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/project_font_sources.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool's faces): A FONT THAT READS WRONG OUT OF THE
/// PROJECT FILE IS LOOKED FOR AGAIN — a save may pack the file under the
/// very read, and the font is then somewhere else in it, and whole.
///
/// The policy alone, with the looking and the reading stood in for: what
/// the read itself checks is measured on a real file
/// (`a_project_file_carries_its_fonts_test`).
void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  /// An entry of a project file, by where it lies.
  MediaArchiveBytes entryAt(int offset) => MediaArchiveBytes(
    archivePath: 'scene.anicel',
    dataOffset: offset,
    length: 3,
    entryCrc32: 7,
  );

  /// Looks where [places] say in turn — the last of them for good — and
  /// reads [bytes] wherever [readable] says they are; a note of both.
  ({
    Future<Uint8List?> Function({int attempts}) read,
    List<MediaByteSource?> looked,
    List<MediaByteSource> tried,
  })
  reading(
    List<MediaByteSource?> places, {
    required bool Function(MediaByteSource source) readable,
  }) {
    final looked = <MediaByteSource?>[];
    final tried = <MediaByteSource>[];
    return (
      read: ({int attempts = 3}) => readLookingAgain(
        find: () {
          final place = places[looked.length < places.length
              ? looked.length
              : places.length - 1];
          looked.add(place);
          return place;
        },
        read: (source) async {
          tried.add(source);
          return readable(source) ? bytes : null;
        },
        attempts: attempts,
      ),
      looked: looked,
      tried: tried,
    );
  }

  /// Where each of [entries] lies in the file.
  List<int> offsetsOf(List<MediaByteSource> entries) => [
    for (final entry in entries) (entry as MediaArchiveBytes).dataOffset,
  ];

  test('a font that reads is read once, from where it was found', () async {
    final r = reading([entryAt(10)], readable: (source) => true);

    expect(await r.read(), bytes);
    expect(r.looked, hasLength(1));
    expect(offsetsOf(r.tried), [10]);
  });

  test('🚨an entry of the file that reads WRONG is looked for again, and '
      'read from where it is THEN', () async {
    final moved = entryAt(4);
    final r = reading([
      entryAt(10),
      moved,
    ], readable: (source) => identical(source, moved));

    expect(await r.read(), bytes);
    expect(r.looked, hasLength(2));
    expect(offsetsOf(r.tried), [10, 4]);
  });

  test('bytes that were never moved and still read wrong are a broken '
      'file: it gives up on them after three looks — or as many as it is '
      'told', () async {
    final broken = reading([entryAt(10)], readable: (source) => false);

    expect(await broken.read(), isNull);
    expect(broken.looked, hasLength(3));

    final once = reading([entryAt(10)], readable: (source) => false);
    expect(await once.read(attempts: 1), isNull);
    expect(once.looked, hasLength(1));
  });

  test('⛔a copy that does not move — in the room, in the device\'s '
      'library — is not looked for again: one that will not read is a '
      'font nobody has', () async {
    for (final copy in <MediaByteSource>[
      const MediaFileBytes('fonts/ab12-cd34-Probe.ttf'),
      const MediaAppFileBytes(path: 'Staged/ab12-cd34-P.ttf', framed: false),
    ]) {
      final r = reading([copy], readable: (source) => false);

      expect(await r.read(), isNull);
      expect(r.looked, hasLength(1), reason: '$copy');
    }
  });

  test('a font that is nowhere is not read at all', () async {
    final r = reading([null], readable: (source) => true);

    expect(await r.read(), isNull);
    expect(r.tried, isEmpty);
  });

  test('found in the file, wrong, and then nowhere: nothing', () async {
    final r = reading([entryAt(10), null], readable: (source) => false);

    expect(await r.read(), isNull);
    expect(r.looked, hasLength(2));
    expect(r.tried, hasLength(1));
  });
}
