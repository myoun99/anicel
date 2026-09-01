import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';

import '../../helpers/native_engine_path.dart';

/// 🚨★★★**ONE NATIVE DOCUMENT, TWO PARTS OF THE APP THAT WANT ONE.**
///
/// The media viewer plays a movie. The import window scrubs one. Both used
/// to call `open` and then `frame`, and the second open silently closed the
/// first — the import preview said so in a comment and treated it as a
/// property to live with: 「opening one here is also what closes the last」.
///
/// What that reads as, to a person, is a viewer whose picture stops
/// changing. No error anywhere: `frame` simply answers null on a document
/// nobody opened, and the render is dropped.
///
/// ⛔The fix is not 「remember to re-open」 at each call site. A handle
/// carries WHICH movie, and the decoder puts it back — so the two consumers
/// interleave, at the price of a re-open, instead of one going blank.
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
    addTearDown(() => directory.deleteSync(recursive: true));

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
    final before = decoder.frameOf(viewer!, 0);
    expect(before, isNotNull, reason: 'the first movie must open and decode');

    // The import window opens ITS movie — the exact act that used to take
    // the viewer's away.
    final preview = decoder.openDocument(movies.second);
    expect(preview, isNotNull, reason: decoder.lastError);
    expect(decoder.frameOf(preview!, 0), isNotNull);

    // 🚨THE ASSERTION. Before the handle, this came back null.
    final after = decoder.frameOf(viewer, 1);
    expect(
      after,
      isNotNull,
      reason: 'the viewer must still be able to read its own movie after '
          'the import window opened another',
    );

    // And back the other way, so the rule is not 「whoever was first」.
    expect(decoder.frameOf(preview, 1), isNotNull);
  }, skip: skip);

  test('the same frame reads the same either side of a switch', () {
    // ⚠️Not just 「non-null」: a re-open that landed on the wrong frame, or
    // read out of the OTHER movie, would pass the test above.
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return;
    }
    final movies = twoMovies();
    if (movies == null) {
      return; // no encoder here — the fixtures cannot be made
    }
    final viewer = decoder.openDocument(movies.first)!;
    final wanted = Uint8List.fromList(decoder.frameOf(viewer, 3)!);

    final preview = decoder.openDocument(movies.second)!;
    decoder.frameOf(preview, 7);

    final again = decoder.frameOf(viewer, 3);
    expect(again, isNotNull);
    expect(
      again,
      orderedEquals(wanted),
      reason: 'frame 3 of the viewer\'s movie is frame 3 whatever the import '
          'window did in between',
    );
  }, skip: skip);

  test('staying on one movie costs NO re-opens, and switching costs exactly '
      'one', () {
    // 🚨★★★**THE COST, NOT THE OUTCOME.** Re-opening is self-healing — a
    // consumer whose movie was closed under it gets it back on the next
    // frame — so 「it still works」 stays true however badly this is done.
    // At a measured ~111ms per re-open on 1080p, the difference between an
    // interleave that costs nothing and one that stutters is exactly this
    // number, and nothing else in the app can see it.
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return;
    }
    final movies = twoMovies();
    if (movies == null) {
      return; // no encoder here — the fixtures cannot be made
    }
    final viewer = decoder.openDocument(movies.first)!;
    final preview = decoder.openDocument(movies.second)!;

    QaVideoDecoder.debugReopens = 0;
    // The preview is the one loaded, so its own frames are free.
    decoder.frameOf(preview, 0);
    decoder.frameOf(preview, 1);
    decoder.frameOf(preview, 2);
    expect(
      QaVideoDecoder.debugReopens,
      0,
      reason: 'reading the movie that is already loaded must not re-open it '
          '— that would make playback pay a random access per frame',
    );

    decoder.frameOf(viewer, 0);
    expect(QaVideoDecoder.debugReopens, 1, reason: 'one switch, one re-open');
    decoder.frameOf(viewer, 1);
    expect(
      QaVideoDecoder.debugReopens,
      1,
      reason: 'and then it stays put — the switch is what costs, not the '
          'reading after it',
    );
  }, skip: skip);

  test('closing a document that is not the loaded one costs nothing', () {
    // ⛔A bare `close` from one consumer took the other's movie with it. The
    // handle makes that recoverable rather than fatal, so what is left to
    // check is that it does not happen at all: the OTHER consumer must not
    // have to pay a re-open for somebody else's dispose.
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
    decoder.frameOf(preview, 0);

    // The viewer is disposed while the import preview's movie is loaded.
    decoder.closeDocument(viewer);

    QaVideoDecoder.debugReopens = 0;
    expect(decoder.frameOf(preview, 1), isNotNull);
    expect(
      QaVideoDecoder.debugReopens,
      0,
      reason: 'the viewer closed a document that was not open — the import '
          'window must not have to reload because of it',
    );
  }, skip: skip);
}
