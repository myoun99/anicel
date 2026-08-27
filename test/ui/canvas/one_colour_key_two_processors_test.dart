import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/cel_source_effect_pass.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';

/// 🚨★★★ONE COLOUR KEY, TWO PROCESSORS — and they agree BIT FOR BIT.
///
/// The button edits cel bytes on the CPU ([CelColorKey]); the fx keys a
/// composited picture on the GPU, where the pixels only exist. Two
/// implementations of one effect is a licence to drift, so this does not
/// sample the domain — it SWEEPS it.
///
/// 📐The decision factorises, which is what makes a sweep possible at all:
///  · the colour test is `max(|r-kr|, |g-kg|, |b-kb|) <= tolerance`, a max
///    over three INDEPENDENT per-channel comparisons. Proving one channel
///    over every (value, key) pair proves the predicate; the max over three
///    adds no new way to be wrong, and is checked separately.
///  · the alpha arithmetic does not look at colour at all. Swept over every
///    (alpha, amount) pair with a tolerance that matches everything.
///
/// ⚠️ALPHA IS WHAT IS COMPARED. RGB is never touched by either side, and a
/// composited image is premultiplied — so a straight RGB round trip through
/// it is lossy for its own reasons and would measure the round trip rather
/// than the key. The colour sweep therefore runs at alpha 255, where
/// premultiplied and straight are the same bytes.
///
/// ⚠️WHAT THIS PROVES AND WHERE. `flutter_tester` rasterises through Skia,
/// which is also what Windows ships in debug and release. Impeller on mobile
/// is not exercised here; the shader is written so no plausible float
/// precision can change an answer (see its 255-scale/half-step note), which
/// is a design that cannot go wrong rather than one that happens not to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ColourKeyShader.load);

  /// Builds a PREMULTIPLIED image from straight [pixels] — the convention
  /// `decodeImageFromPixels` takes and a composite hands over.
  Future<ui.Image> imageFromStraight(
    Uint8List straight,
    int width,
    int height,
  ) {
    final premultiplied = Uint8List.fromList(straight);
    for (var i = 0; i < premultiplied.length; i += 4) {
      final alpha = premultiplied[i + 3];
      if (alpha == 255) {
        continue;
      }
      premultiplied[i] = (premultiplied[i] * alpha + 127) ~/ 255;
      premultiplied[i + 1] = (premultiplied[i + 1] * alpha + 127) ~/ 255;
      premultiplied[i + 2] = (premultiplied[i + 2] * alpha + 127) ~/ 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      premultiplied,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  /// Runs the shader over [source] and returns the raw (premultiplied) bytes.
  Future<Uint8List> keyed(
    ui.Image source,
    CelColorKey key,
    int width,
    int height,
  ) async {
    final shader = ColourKeyShader.shaderFor(
      source: source,
      key: key,
      width: width.toDouble(),
      height: height.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..shader = shader,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    shader.dispose();
    return bytes!.buffer.asUint8List();
  }

  CelColorKey keyOf({
    int red = 0,
    int green = 0,
    int blue = 0,
    required int tolerance,
    required double amount,
    bool keepsMatches = false,
  }) => CelColorKey(
    red: red,
    green: green,
    blue: blue,
    tolerance: tolerance,
    amount: amount,
    keepsMatches: keepsMatches,
  );

  group('the colour decision, swept', () {
    /// x = the pixel's value in the channel, y = the key's value. One image
    /// covers every (value, key) pair for a tolerance.
    Future<void> sweepChannel({
      required int channel,
      required int tolerance,
      required bool keepsMatches,
    }) async {
      const side = 256;
      final straight = Uint8List(side * side * 4);
      for (var keyValue = 0; keyValue < side; keyValue++) {
        for (var value = 0; value < side; value++) {
          final at = (keyValue * side + value) * 4;
          // The two channels NOT under test sit on the key exactly, so their
          // gap is zero and the max is the channel under test.
          straight[at + channel] = value;
          straight[at + 3] = 255;
        }
      }
      final source = await imageFromStraight(straight, side, side);
      var mismatches = 0;
      var erasedSeen = 0;
      var keptSeen = 0;
      for (var keyValue = 0; keyValue < side; keyValue++) {
        final key = keyOf(
          red: channel == 0 ? keyValue : 0,
          green: channel == 1 ? keyValue : 0,
          blue: channel == 2 ? keyValue : 0,
          tolerance: tolerance,
          // Full strength: the decision, not the mix.
          amount: 1,
          keepsMatches: keepsMatches,
        );
        final bytes = await keyed(source, key, side, side);
        for (var value = 0; value < side; value++) {
          final at = (keyValue * side + value) * 4;
          final red = channel == 0 ? value : 0;
          final green = channel == 1 ? value : 0;
          final blue = channel == 2 ? value : 0;
          final expected = key.alphaFor(red, green, blue, 255);
          if (bytes[at + 3] != expected) {
            mismatches += 1;
          }
          if (expected == 0) {
            erasedSeen += 1;
          } else {
            keptSeen += 1;
          }
        }
      }
      source.dispose();
      // ⛔Prove the sweep saw BOTH answers. A tolerance that erased
      // everything (or nothing) would agree with a shader that always said
      // the same thing.
      expect(erasedSeen, greaterThan(0));
      expect(keptSeen, greaterThan(0));
      expect(
        mismatches,
        0,
        reason: 'channel $channel at tolerance $tolerance '
            '(keepsMatches: $keepsMatches): the GPU key must answer exactly '
            'what CelColorKey.alphaFor answers, for every value against '
            'every key',
      );
    }

    for (final tolerance in const [0, 1, 17, 128, 254]) {
      test('red, every value against every key, tolerance $tolerance', () async {
        await sweepChannel(
          channel: 0,
          tolerance: tolerance,
          keepsMatches: false,
        );
      });
    }

    test('KEEP is the same comparison with the opposite answer', () async {
      await sweepChannel(channel: 0, tolerance: 17, keepsMatches: true);
    });

    test('green and blue answer the same as red does', () async {
      await sweepChannel(channel: 1, tolerance: 17, keepsMatches: false);
      await sweepChannel(channel: 2, tolerance: 17, keepsMatches: false);
    });

    test('the widest gap decides, not the sum and not the first', () async {
      // 🚨THE MAX ITSELF. The per-channel sweep cannot see a shader that
      // added the gaps or stopped at the first one, because it only ever
      // moves one channel. This moves all three.
      const side = 64;
      final straight = Uint8List(side * side * 4);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final at = (y * side + x) * 4;
          straight[at] = x * 4;
          straight[at + 1] = y * 4;
          straight[at + 2] = ((x + y) * 2) % 256;
          straight[at + 3] = 255;
        }
      }
      final source = await imageFromStraight(straight, side, side);
      // The key is a pixel that is ACTUALLY in the fixture (x=25, y=15), so
      // the sweep straddles the threshold instead of missing it entirely.
      final key = keyOf(
        red: 100,
        green: 60,
        blue: 80,
        tolerance: 30,
        amount: 1,
      );
      final bytes = await keyed(source, key, side, side);
      source.dispose();
      var mismatches = 0;
      var erased = 0;
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final at = (y * side + x) * 4;
          final expected = key.alphaFor(
            straight[at],
            straight[at + 1],
            straight[at + 2],
            255,
          );
          if (bytes[at + 3] != expected) {
            mismatches += 1;
          }
          if (expected == 0) {
            erased += 1;
          }
        }
      }
      expect(erased, greaterThan(0));
      expect(erased, lessThan(side * side));
      expect(mismatches, 0);
    });
  });

  test('a TRANSLUCENT pixel is keyed by its own colour, not a darker one',
      () async {
    // 🚨THE PREMULTIPLY, AND WHY THE SWEEPS CANNOT SEE IT. Every sweep above
    // runs at alpha 255, where premultiplied and straight are the same
    // bytes — on purpose, so the colour comparison is not measuring a
    // round trip. That leaves the un-premultiply itself unpinned, and a
    // shader that skipped it passed all of them: a half-transparent red
    // reads as a dark red and simply stops matching a red key.
    //
    // ⚠️This is a PROPERTY, not an equivalence. What the shader recovers is
    // `premultiplied / alpha`, which is not the byte that went in — the
    // multiply threw information away. The CPU key, keying a cel's own
    // straight bytes, never has that problem, and that asymmetry is exactly
    // why the colour key on SOURCE pixels stays on the CPU
    // ([EffectKind.runsOnSourcePixels]) rather than following the fx onto
    // the GPU.
    const width = 224;
    const height = 2;
    final straight = Uint8List(width * height * 4);
    for (var row = 0; row < height; row++) {
      for (var i = 0; i < width; i++) {
        final at = (row * width + i) * 4;
        // Row 0 IS the key colour; row 1 sits far outside the tolerance.
        straight[at] = row == 0 ? 200 : 40;
        straight[at + 1] = row == 0 ? 120 : 240;
        straight[at + 2] = row == 0 ? 40 : 200;
        // 32…255: below that the round trip's own error swamps any
        // tolerance a user would type.
        straight[at + 3] = 32 + i;
      }
    }
    final source = await imageFromStraight(straight, width, height);
    // 8 leaves room for the round trip (at alpha 32 a byte can come back up
    // to ~4 out) without coming near the 160-wide gap the control row has.
    final key = keyOf(
      red: 200,
      green: 120,
      blue: 40,
      tolerance: 8,
      amount: 1,
    );
    final bytes = await keyed(source, key, width, height);
    source.dispose();
    var survivedOnTheKey = 0;
    var erasedOffTheKey = 0;
    for (var i = 0; i < width; i++) {
      if (bytes[(0 * width + i) * 4 + 3] != 0) {
        survivedOnTheKey += 1;
      }
      if (bytes[(1 * width + i) * 4 + 3] == 0) {
        erasedOffTheKey += 1;
      }
    }
    expect(
      survivedOnTheKey,
      0,
      reason: 'a pixel whose own colour IS the key must be erased at every '
          'alpha — $survivedOnTheKey of $width survived, which is what '
          'keying premultiplied bytes looks like',
    );
    expect(
      erasedOffTheKey,
      0,
      reason: 'a pixel far from the key must survive at every alpha',
    );
  });

  test('the alpha arithmetic, every alpha against every amount', () async {
    // 🚨THE OTHER HALF, and it is where a float goes wrong if it is going to.
    // Tolerance 255 matches everything, so colour cannot confound the count
    // and what is under test is `alpha * (1 - amount)`, rounded.
    const width = 256;
    const height = 101;
    final straight = Uint8List(width * height * 4);
    for (var amount = 0; amount < height; amount++) {
      for (var alpha = 0; alpha < width; alpha++) {
        final at = (amount * width + alpha) * 4;
        straight[at] = 200;
        straight[at + 1] = 120;
        straight[at + 2] = 40;
        straight[at + 3] = alpha;
      }
    }
    final source = await imageFromStraight(straight, width, height);
    var mismatches = 0;
    final worst = <String>[];
    for (var amount = 0; amount < height; amount++) {
      final key = keyOf(tolerance: 255, amount: amount / 100);
      final bytes = await keyed(source, key, width, height);
      for (var alpha = 0; alpha < width; alpha++) {
        final at = (amount * width + alpha) * 4;
        // ⚠️The straight RGB the shader sees is what SURVIVED premultiply,
        // not what went in — but tolerance 255 matches whatever it is, so
        // the colour cannot change the answer and the alpha is the subject.
        final expected = key.alphaFor(200, 120, 40, alpha);
        if (bytes[at + 3] != expected) {
          mismatches += 1;
          if (worst.length < 5) {
            worst.add(
              'alpha $alpha amount ${amount / 100}: '
              'gpu ${bytes[at + 3]} cpu $expected',
            );
          }
        }
      }
    }
    source.dispose();
    expect(
      mismatches,
      0,
      reason: 'the GPU alpha must be the CPU alpha exactly. First '
          'disagreements: ${worst.join('; ')}',
    );
  });

  test('a fresh effect changes nothing at all', () async {
    // The Amount default is 0 precisely because a colour key has no value
    // that is an identity. Adding one must be invisible.
    const side = 32;
    final straight = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i++) {
      straight[i * 4] = i % 256;
      straight[i * 4 + 1] = (i * 3) % 256;
      straight[i * 4 + 2] = (i * 7) % 256;
      straight[i * 4 + 3] = 255;
    }
    final source = await imageFromStraight(straight, side, side);
    final before = await source.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final after = await keyed(
      source,
      keyOf(red: 30, green: 30, blue: 30, tolerance: 40, amount: 0),
      side,
      side,
    );
    source.dispose();
    expect(after, equals(before!.buffer.asUint8List()));
  });

  test('an unloaded program refuses instead of dropping the effect', () {
    ColourKeyShader.debugUnload();
    addTearDown(ColourKeyShader.load);
    expect(ColourKeyShader.isReady, isFalse);
    expect(
      () => ColourKeyShader.shaderFor(
        source: _throwawayImage(),
        key: keyOf(tolerance: 0, amount: 1),
        width: 1,
        height: 1,
      ),
      throwsStateError,
    );
  });
}

ui.Image _throwawayImage() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = const Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1, 1);
  picture.dispose();
  return image;
}
