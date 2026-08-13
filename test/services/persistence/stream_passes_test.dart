import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';

/// 🔑 THE COUPLING: how many times each writer reads a streamed entry.
///
/// It is not a private detail. Anything measuring the work of a save has to
/// know, and the one thing that did guessed wrong — a progress bar counted
/// an append's media as a single traversal, reached 100% at the end of the
/// checksum pass, and then held there through the entire byte copy.
///
/// The number now has a name ([anicelAppendStreamPasses],
/// [anicelArchiveStreamPasses]). A name that nothing checks is just a
/// comment, so these tests count the passes for real: if either writer ever
/// changes how many times it walks an entry, the constant it broke fails
/// here rather than quietly mis-drawing a window.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-stream-passes-');
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // Windows handles.
    }
  });

  /// A streamed entry that answers reads from [bytes] and counts how many
  /// times it is walked from the beginning.
  ({AnicelStreamedEntry entry, int Function() passes}) counted(
    String name,
    Uint8List bytes,
  ) {
    var passes = 0;
    return (
      entry: AnicelStreamedEntry(
        name: name,
        length: bytes.length,
        readInto: (buffer, position, size) {
          // A read starting at zero is a fresh walk of this entry.
          if (position == 0) {
            passes += 1;
          }
          buffer.setRange(0, size, bytes, position);
          return size;
        },
      ),
      passes: () => passes,
    );
  }

  /// Big enough to span several chunks, so a pass is many reads and the
  /// position==0 test is meaningfully distinguishing walks from reads.
  Uint8List payload() =>
      Uint8List.fromList([for (var i = 0; i < 900 * 1024; i += 1) i % 251]);

  test('appendAnicelEntries walks a streamed entry '
      '$anicelAppendStreamPasses times', () {
    // Two, and both are real work over the whole asset: the checksum has to
    // finish before the file is touched, because a source that turns out to
    // be unreadable must not have already truncated the archive.
    final path = '${directory.path.replaceAll('\\', '/')}/a.anicel';
    writeAnicelArchiveFile(
      path: path,
      entries: [(name: 'project.json', bytes: Uint8List.fromList([1, 2, 3]))],
    );

    final media = counted('Media/take.wav', payload());
    appendAnicelEntries(
      path: path,
      newEntries: {'project.json': Uint8List.fromList([4, 5, 6])},
      streamedEntries: [media.entry],
    );

    expect(media.passes(), anicelAppendStreamPasses);
  });

  test('writeAnicelArchiveFile walks one '
      '$anicelArchiveStreamPasses time', () {
    // One, because this writer puts a placeholder CRC ahead of the data and
    // seeks back to patch it — which is exactly why the two constants are
    // separate and a single shared number would be wrong for one of them.
    final media = counted('Media/take.wav', payload());
    writeAnicelArchiveFile(
      path: '${directory.path.replaceAll('\\', '/')}/b.anicel',
      entries: [(name: 'project.json', bytes: Uint8List.fromList([1, 2, 3]))],
      streamedEntries: [media.entry],
    );

    expect(media.passes(), anicelArchiveStreamPasses);
  });

  test('and the two writers still disagree, which is the point', () {
    // If these ever converge, the separate constants are dead weight and
    // somebody should say so deliberately rather than leave two names for
    // one number.
    expect(anicelAppendStreamPasses, isNot(anicelArchiveStreamPasses));
  });
}
