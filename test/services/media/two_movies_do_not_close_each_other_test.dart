import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★**EVERY MOVIE THAT IS OPEN STAYS OPEN.**
///
/// The media viewer plays a movie. The placement window scrubs one. A movie
/// kept as a reference decodes where the canvas stands, the playback warmer
/// fills the frames ahead of it, and export walks a whole cut. They used to
/// share ONE native document: the second open silently closed the first —
/// the import preview said so in a comment and treated it as a property to
/// live with — and the fix after that was a handle the decoder could put
/// BACK, at a measured ~111ms per switch.
///
/// ⛔A price per switch is not a price you pay once. Two of those callers
/// interleaving frame by frame paid it per frame, which is a stutter with
/// nothing on screen to explain it. The document is a native handle now, so
/// 「whose movie is loaded」 is not a question anything asks.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaVideoDecoder.instance?.close();
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  /// Two movies that LOOK DIFFERENT.
  ///
  /// 🚨★★★**THE FIRST DRAFT COPIED ONE FIXTURE TWICE AND MEASURED NOTHING.**
  /// With identical bytes, reading the wrong movie returns the right
  /// picture — so the mutation that removes the re-open passed every
  /// assertion. The whole question here is 「did I get MY movie back」, and
  /// it cannot be asked of two files that are the same movie.
  ///
  /// So they are encoded here, with the app's own encoder, in colours no
  /// comparison can confuse.
  ({String first, String second})? twoMovies() {
    final encoder = QaVideoEncoder.instance;
    if (encoder == null || !encoder.isSupported) {
      return null;
    }
    final directory = Directory.systemTemp.createTempSync('qa_two');
    deleteAfterSessionEnds(directory);

    String write(String name, int red, int blue) {
      final path = '${directory.path}${Platform.pathSeparator}$name';
      expect(
        encoder.open(
          path: path,
          width: 64,
          height: 48,
          fpsNumerator: 24,
          fpsDenominator: 1,
          sampleRate: 44100,
          channels: 2,
        ),
        isTrue,
        reason: encoder.lastError,
      );
      for (var frame = 0; frame < 8; frame += 1) {
        final rgba = Uint8List(64 * 48 * 4);
        for (var i = 0; i < 64 * 48; i += 1) {
          rgba[i * 4] = red;
          rgba[i * 4 + 1] = (frame * 30) & 0xFF;
          rgba[i * 4 + 2] = blue;
          rgba[i * 4 + 3] = 255;
        }
        expect(encoder.writeFrame(rgba), isTrue, reason: encoder.lastError);
      }
      expect(encoder.finish(), isTrue, reason: encoder.lastError);
      return path;
    }

    return (first: write('red.mp4', 230, 20), second: write('blue.mp4', 20, 230));
  }

  test('the instrument first: the two movies do NOT look alike', () {
    // ★The premise every assertion below stands on, checked before them.
    // The first draft of this file copied one fixture twice, and every test
    // passed with the product code turned off — because reading the wrong
    // movie gave back the right picture.
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return;
    }
    final movies = twoMovies();
    if (movies == null) {
      return;
    }
    final red = Uint8List.fromList(
      decoder.frameOf(decoder.openDocument(movies.first)!, 2)!,
    );
    final blue = Uint8List.fromList(
      decoder.frameOf(decoder.openDocument(movies.second)!, 2)!,
    );
    expect(
      red,
      isNot(orderedEquals(blue)),
      reason: 'if these are the same picture, nothing below is measuring '
          'anything',
    );
  }, skip: skip);

  test('a second movie does not blind the first — both keep answering', () {
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return; // no reader in this build; absence is an answer elsewhere
    }
    final movies = twoMovies();
    if (movies == null) {
      return; // no encoder here — the fixtures cannot be made
    }

    final viewer = decoder.openDocument(movies.first);
    expect(viewer, isNotNull, reason: decoder.lastError);
    expect(decoder.frameOf(viewer!, 0), isNotNull);

    // The placement window opens ITS movie — the exact act that used to
    // take the viewer's away.
    final preview = decoder.openDocument(movies.second);
    expect(preview, isNotNull, reason: decoder.lastError);
    expect(decoder.frameOf(preview!, 0), isNotNull);

    expect(
      decoder.frameOf(viewer, 1),
      isNotNull,
      reason: 'the viewer must still read its own movie after the window '
          'opened another',
    );
    // And back the other way, so the rule is not 「whoever was first」.
    expect(decoder.frameOf(preview, 1), isNotNull);
    expect(
      viewer.handle,
      isNot(preview.handle),
      reason: 'two documents, two handles — that IS the law',
    );
  }, skip: skip);

  test('the same frame reads the same either side of a switch', () {
    // ⚠️Not just 「non-null」: a document that had been put back on the wrong
    // frame, or read out of the OTHER movie, would pass the test above.
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return;
    }
    final movies = twoMovies();
    if (movies == null) {
      return;
    }
    final viewer = decoder.openDocument(movies.first)!;
    final wanted = Uint8List.fromList(decoder.frameOf(viewer, 3)!);

    final preview = decoder.openDocument(movies.second)!;
    decoder.frameOf(preview, 7);

    expect(
      decoder.frameOf(viewer, 3),
      orderedEquals(wanted),
      reason: 'frame 3 of the viewer\'s movie is frame 3 whatever the '
          'placement window did in between',
    );
  }, skip: skip);

  test('reading one movie, then the other, then back — each answers with '
      'ITS OWN picture every time', () {
    // 🚨The interleave the app actually does now: the canvas stands on one
    // movie while the warmer fills another's frames. Alternating used to
    // mean a re-open per frame; what a test can still see is that neither
    // side ever answers with the other's picture.
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return;
    }
    final movies = twoMovies();
    if (movies == null) {
      return;
    }
    final first = decoder.openDocument(movies.first)!;
    final second = decoder.openDocument(movies.second)!;
    final red = Uint8List.fromList(decoder.frameOf(first, 0)!);
    final blue = Uint8List.fromList(decoder.frameOf(second, 0)!);

    for (var round = 0; round < 3; round += 1) {
      expect(decoder.frameOf(first, 0), orderedEquals(red));
      expect(decoder.frameOf(second, 0), orderedEquals(blue));
    }
  }, skip: skip);

  test('closing one document leaves the other reading', () {
    // ⛔A bare close from one consumer took the other's movie with it. Each
    // handle is its own document now, so a dispose over here cannot be felt
    // over there.
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return;
    }
    final movies = twoMovies();
    if (movies == null) {
      return;
    }
    final viewer = decoder.openDocument(movies.first)!;
    final preview = decoder.openDocument(movies.second)!;
    final wanted = Uint8List.fromList(decoder.frameOf(viewer, 1)!);

    // ⚠️The one closed is the SECOND, and the one that must go on reading is
    // the first: closing 「whichever document came first」 would be right for
    // half the pairs in the app and wrong for the other half, and a test
    // that disposes the first document cannot tell those apart.
    decoder.closeDocument(preview);

    expect(
      decoder.frameOf(viewer, 1),
      orderedEquals(wanted),
      reason: 'somebody else\'s dispose is not an event this document has',
    );
    expect(
      decoder.frameOf(preview, 0),
      isNull,
      reason: 'and the closed one IS closed — a handle nothing holds any '
          'more reads nothing',
    );
  }, skip: skip);

  test('the slots run out HONESTLY — and a close hands one back', () {
    // ⚠️A fixed row of documents is a refusal that has to be readable: the
    // alternative is an open that answers a handle nothing can read.
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return;
    }
    final movies = twoMovies();
    if (movies == null) {
      return;
    }
    final open = <QaVideoDocument>[];
    for (var i = 0; i < 8; i += 1) {
      final document = decoder.openDocument(movies.first);
      if (document == null) {
        break;
      }
      open.add(document);
    }
    expect(open, hasLength(8), reason: decoder.lastError);
    expect(
      decoder.openDocument(movies.second),
      isNull,
      reason: 'the ninth has nowhere to go',
    );
    expect(decoder.lastError, contains('too many'));

    decoder.closeDocument(open.removeLast());
    final after = decoder.openDocument(movies.second);
    expect(after, isNotNull, reason: 'the closed slot is free again');
    expect(decoder.frameOf(after!, 0), isNotNull);
  }, skip: skip);
}
