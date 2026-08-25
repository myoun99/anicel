import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/media_fingerprints.dart';

/// `moved()` must accept paths as the MOVERS spell them.
///
/// The store's keys are normalized to forward slashes, but open() hands
/// the remap over with the manifest's RAW keys — backslashes and all on
/// Windows. The lookup missed every time, the un-moved fingerprint then
/// failed the keep-filter built from the REMAPPED paths, and opening a
/// traveled folder silently erased the content fingerprints of every
/// asset in it at the next save — the exact facts relink needs.
void main() {
  test('a raw backslash move key still moves the normalized row', () {
    final prints = MediaFingerprints.fromJson({
      'C:/work/a/대사.wav': '400:deadbeef',
    });
    expect(prints['C:/work/a/대사.wav']?.crc32, isNotNull);

    final movedPrints = prints.moved({r'C:\work\a\대사.wav': 'D:/new/대사.wav'});

    expect(
      movedPrints['D:/new/대사.wav']?.crc32,
      prints['C:/work/a/대사.wav']?.crc32,
      reason: 'the fact traveled with the file',
    );
    expect(movedPrints['C:/work/a/대사.wav'], isNull);
  });

  test('narrowedTo keeps a row whose move arrived raw-keyed', () {
    final prints = MediaFingerprints.fromJson({
      'C:/work/a/take.wav': '400:0000abcd',
    });
    final narrowed = prints.narrowedTo(
      {'D:/new/take.wav'},
      moved: {r'C:\work\a\take.wav': 'D:/new/take.wav'},
    );
    expect(
      narrowed['D:/new/take.wav'],
      isNotNull,
      reason: 'this is open()\'s exact call shape for a traveled folder',
    );
  });
}
