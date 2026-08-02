import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';

/// A stand-in for a production cel: flat white ground, a handful of solid
/// fills, and hard-edged strokes crossing at angles that make a point
/// sampler stumble. Deliberately two-valued at every edge — no soft pixels
/// anywhere, so any partial alpha or in-between colour in an output came
/// from the kernel and nowhere else.
Uint8List _lineArt(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  final words = Uint32List.view(bytes.buffer);
  const white = 0xffffffff;
  const ink = 0xff101010;
  const skin = 0xffc8dcf0;
  const cloth = 0xff604040;
  const translucent = 0x80305090;
  for (var i = 0; i < words.length; i += 1) {
    words[i] = white;
  }
  void plot(int x, int y, int token) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    words[y * width + x] = token;
  }

  // Two solid regions, so an argmax has something to weigh.
  for (var y = height ~/ 3; y < height * 2 ~/ 3; y += 1) {
    for (var x = width ~/ 4; x < width * 3 ~/ 4; x += 1) {
      plot(x, y, skin);
    }
  }
  // A PARTIALLY TRANSPARENT region and a fully transparent hole. Without
  // these the fixture is 100% opaque, and then "Pick never produces
  // partial alpha" is true of any kernel at all — including one that
  // averaged colours — because there is no partial alpha in the input to
  // preserve or destroy. The assertion could not fail.
  for (var y = 2; y < height ~/ 4; y += 1) {
    for (var x = 2; x < width ~/ 4; x += 1) {
      plot(x, y, translucent);
    }
  }
  for (var y = 4; y < 12; y += 1) {
    for (var x = width - 14; x < width - 4; x += 1) {
      plot(x, y, 0x00000000);
    }
  }
  for (var y = height * 2 ~/ 3; y < height; y += 1) {
    for (var x = width ~/ 5; x < width * 4 ~/ 5; x += 1) {
      plot(x, y, cloth);
    }
  }
  // Hairlines: one pixel wide, the thing reduction destroys first.
  for (var x = 0; x < width; x += 1) {
    plot(x, height ~/ 2, ink);
    plot(x, (x * 3 ~/ 7) % height, ink);
  }
  for (var y = 0; y < height; y += 1) {
    plot(width ~/ 3, y, ink);
    plot((y * 5 ~/ 3) % width, y, ink);
  }
  // Two-pixel strokes as well: production line art is not all hairlines,
  // and a reduction test built only from 1px strokes measures the one case
  // no area rule can rescue rather than the case the tool is used for.
  for (var x = 0; x < width; x += 1) {
    plot(x, height ~/ 4, ink);
    plot(x, height ~/ 4 + 1, ink);
  }
  for (var y = 0; y < height; y += 1) {
    plot(width * 2 ~/ 3, y, ink);
    plot(width * 2 ~/ 3 + 1, y, ink);
  }
  return bytes;
}

/// A point sampler — the "anti-aliasing off" every other tool ships, and
/// the thing Pick has to beat to be worth its cost.
Uint8List _nearest(
  Uint8List src,
  int srcWidth,
  int srcHeight,
  int dstWidth,
  int dstHeight,
  ResampleTransform t,
) {
  final out = Uint8List(dstWidth * dstHeight * 4);
  final srcWords = Uint32List.view(src.buffer, src.offsetInBytes,
      srcWidth * srcHeight);
  final dstWords = Uint32List.view(out.buffer, 0, dstWidth * dstHeight);
  for (var y = 0; y < dstHeight; y += 1) {
    for (var x = 0; x < dstWidth; x += 1) {
      final u = t.a * (x + 0.5) + t.b * (y + 0.5) + t.c - 0.5;
      final v = t.d * (x + 0.5) + t.e * (y + 0.5) + t.f - 0.5;
      final sx = u.round(), sy = v.round();
      dstWords[y * dstWidth + x] =
          (sx < 0 || sy < 0 || sx >= srcWidth || sy >= srcHeight)
              ? kResampleOutsideToken
              : srcWords[sy * srcWidth + sx];
    }
  }
  return out;
}

Set<int> _tokensOf(Uint8List bytes) =>
    Uint32List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 4)
        .toSet();

int _tokenAt(Uint8List bytes, int width, int x, int y) =>
    Uint32List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 4)[y * width + x];

/// Ink pixels whose eight neighbours hold at most one of the same colour —
/// the "spur" count the TVPaint comparison used as its quality yardstick.
int _isolatedPixels(Uint8List bytes, int width, int height) {
  final words =
      Uint32List.view(bytes.buffer, bytes.offsetInBytes, width * height);
  const white = 0xffffffff;
  var count = 0;
  for (var y = 1; y < height - 1; y += 1) {
    for (var x = 1; x < width - 1; x += 1) {
      final token = words[y * width + x];
      if (token == white || token == kResampleOutsideToken) continue;
      var same = 0;
      for (var dy = -1; dy <= 1; dy += 1) {
        for (var dx = -1; dx <= 1; dx += 1) {
          if (dx == 0 && dy == 0) continue;
          if (words[(y + dy) * width + x + dx] == token) same += 1;
        }
      }
      if (same <= 1) count += 1;
    }
  }
  return count;
}

ResampleTransform _rotationAbout(double degrees, double cx, double cy) {
  final theta = -degrees * math.pi / 180; // inverse rotation
  final cos = math.cos(theta), sin = math.sin(theta);
  return ResampleTransform(
    a: cos,
    b: -sin,
    c: cx - cos * cx + sin * cy,
    d: sin,
    e: cos,
    f: cy - sin * cx - cos * cy,
  );
}

void main() {
  const width = 96;
  const height = 96;
  late Uint8List source;
  late Set<int> sourceTokens;

  setUp(() {
    source = _lineArt(width, height);
    sourceTokens = _tokensOf(source);
  });

  group('Pick keeps its provenance contract', () {
    test('every output token came from the source, at every transform', () {
      final cases = <String, ResampleTransform>{
        'rotate 15': _rotationAbout(15, width / 2, height / 2),
        'rotate 37.4': _rotationAbout(37.4, width / 2, height / 2),
        'shrink 0.37': ResampleTransform.scaleTranslate(scale: 0.37),
        'shrink 0.8': ResampleTransform.scaleTranslate(scale: 0.8),
        'enlarge 4': ResampleTransform.scaleTranslate(scale: 4),
        'non-uniform': ResampleTransform(
          a: 1 / 0.6,
          b: 0,
          c: 0,
          d: 0,
          e: 1 / 1.3,
          f: 0,
        ),
        'sub-pixel shift': ResampleTransform(
          a: 1,
          b: 0,
          c: -0.37,
          d: 0,
          e: 1,
          f: -0.62,
        ),
        'perspective': ResampleTransform(
          a: 1,
          b: 0.12,
          c: -3,
          d: 0.05,
          e: 1,
          f: -2,
          g: 0.0012,
          h: 0.0007,
          i: 1,
        ),
      };
      for (final entry in cases.entries) {
        final out = resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: width,
          dstHeight: height,
          transform: entry.value,
          mode: ResampleMode.pick,
        );
        final novel = _tokensOf(out)
            .where((t) => t != kResampleOutsideToken)
            .where((t) => !sourceTokens.contains(t))
            .toList();
        expect(
          novel,
          isEmpty,
          reason: '${entry.key} invented '
              '${novel.map((t) => t.toRadixString(16)).toList()}',
        );
      }
    });

    test('alpha values are carried, never invented', () {
      // The fixture holds 0x80 as well as 0x00 and 0xff, so this asserts
      // something: Pick may emit the source's partial alpha, but must not
      // manufacture a NEW one the way an averaging kernel would.
      final sourceAlphas =
          sourceTokens.map((t) => (t >> 24) & 0xff).toSet()..add(0);
      for (final transform in <ResampleTransform>[
        _rotationAbout(15, width / 2, height / 2),
        _rotationAbout(37.4, width / 2, height / 2),
        ResampleTransform.scaleTranslate(scale: 0.37),
        ResampleTransform.scaleTranslate(scale: 3),
      ]) {
        final out = resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: width,
          dstHeight: height,
          transform: transform,
          mode: ResampleMode.pick,
        );
        final alphas = _tokensOf(out).map((t) => (t >> 24) & 0xff).toSet();
        expect(alphas.difference(sourceAlphas), isEmpty);
      }
    });

    test('the elected token overlapped the pixel it was elected for', () {
      // The contract as written is about PROVENANCE, not merely about the
      // colour existing somewhere in the source. This walks the preimage
      // box of every destination pixel and asserts the winner came from
      // inside it — the assertion that catches a footprint centred on the
      // wrong pixel, or a radius floor wide enough to elect a colour the
      // preimage never touched.
      for (final scale in <double>[2, 4, 0.5]) {
        final transform = ResampleTransform.scaleTranslate(scale: scale);
        final out = resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: width,
          dstHeight: height,
          transform: transform,
          mode: ResampleMode.pick,
        );
        final srcWords = Uint32List.view(source.buffer);
        final extent = 1 / scale;
        for (var y = 0; y < height; y += 1) {
          for (var x = 0; x < width; x += 1) {
            final token = _tokenAt(out, width, x, y);
            if (token == kResampleOutsideToken) continue;
            final u = (x + 0.5) / scale - 0.5;
            final v = (y + 0.5) / scale - 0.5;
            // Pixels whose unit square meets the preimage box, plus the
            // sampling floor the kernel is allowed to widen to.
            final reach = math.max(extent, resampleRadiusFloor(
              ResampleMode.pick,
            ));
            var found = false;
            for (var sy = (v - reach).floor(); sy <= (v + reach).ceil(); sy++) {
              for (var sx = (u - reach).floor();
                  sx <= (u + reach).ceil();
                  sx++) {
                if (sx < 0 || sy < 0 || sx >= width || sy >= height) continue;
                if (srcWords[sy * width + sx] == token) {
                  found = true;
                  break;
                }
              }
              if (found) break;
            }
            expect(found, isTrue,
                reason: 'scale $scale: ($x,$y) emitted '
                    '${token.toRadixString(16)} from outside its preimage');
          }
        }
      }
    });
  });

  group('magnification is replication, not a vote', () {
    test('integer magnification reproduces source blocks exactly', () {
      // Pick's radius floor exists to give rotation and reduction a
      // neighbourhood to vote in. Under magnification the preimage is
      // narrower than one source pixel, and applying the floor there let
      // neighbours the preimage never touched win — which deleted every
      // 1px feature that was not axis-aligned. Block replication is the
      // stronger oracle: it fails the moment the vote comes back.
      const smallWidth = 21;
      const smallHeight = 21;
      final tiny = Uint8List(smallWidth * smallHeight * 4);
      final tinyWords = Uint32List.view(tiny.buffer);
      for (var i = 0; i < tinyWords.length; i += 1) {
        tinyWords[i] = 0xffffffff;
      }
      tinyWords[10 * smallWidth + 10] = 0xff101010;
      tinyWords[3 * smallWidth + 17] = 0xff00ff00;

      for (final scale in <int>[2, 4, 8]) {
        final outWidth = smallWidth * scale;
        final outHeight = smallHeight * scale;
        final out = resampleRgbaReference(
          src: tiny,
          srcWidth: smallWidth,
          srcHeight: smallHeight,
          dstWidth: outWidth,
          dstHeight: outHeight,
          transform: ResampleTransform.scaleTranslate(scale: scale.toDouble()),
          mode: ResampleMode.pick,
        );
        final outWords = Uint32List.view(out.buffer);
        for (var y = 0; y < outHeight; y += 1) {
          for (var x = 0; x < outWidth; x += 1) {
            expect(
              outWords[y * outWidth + x],
              tinyWords[(y ~/ scale) * smallWidth + (x ~/ scale)],
              reason: 'x$scale at ($x,$y) is not block replication',
            );
          }
        }
      }
    });

    test('an isolated pixel survives magnification', () {
      const smallWidth = 21;
      const smallHeight = 21;
      final tiny = Uint8List(smallWidth * smallHeight * 4);
      final tinyWords = Uint32List.view(tiny.buffer);
      for (var i = 0; i < tinyWords.length; i += 1) {
        tinyWords[i] = 0xffffffff;
      }
      tinyWords[10 * smallWidth + 10] = 0xff101010;
      final out = resampleRgbaReference(
        src: tiny,
        srcWidth: smallWidth,
        srcHeight: smallHeight,
        dstWidth: smallWidth * 8,
        dstHeight: smallHeight * 8,
        transform: ResampleTransform.scaleTranslate(scale: 8),
        mode: ResampleMode.pick,
      );
      final ink = Uint32List.view(out.buffer).where((t) => t == 0xff101010);
      expect(ink.length, 64, reason: 'the single ink pixel did not survive');
    });
  });

  group('degenerate transforms are declared outside, not thrown', () {
    test('a non-finite map produces a transparent result in both modes', () {
      final cases = <String, ResampleTransform>{
        'scale zero': ResampleTransform.scaleTranslate(scale: 0),
        'infinite a': ResampleTransform(
          a: double.infinity,
          b: 0,
          c: 0,
          d: 0,
          e: 1,
          f: 0,
        ),
        'NaN offset': ResampleTransform(
          a: 1,
          b: 0,
          c: double.nan,
          d: 0,
          e: 1,
          f: 0,
        ),
        'infinite offset': ResampleTransform(
          a: 1,
          b: 0,
          c: double.infinity,
          d: 0,
          e: 1,
          f: 0,
        ),
      };
      for (final mode in ResampleMode.values) {
        for (final entry in cases.entries) {
          final out = resampleRgbaReference(
            src: source,
            srcWidth: width,
            srcHeight: height,
            dstWidth: 16,
            dstHeight: 16,
            transform: entry.value,
            mode: mode,
          );
          expect(_tokensOf(out), {kResampleOutsideToken},
              reason: '${entry.key} / $mode');
        }
      }
    });

    test('a steep perspective terminates and stays bounded', () {
      // Radius grows as 1/w², so without the ceiling one destination pixel
      // can ask for hundreds of millions of taps. This must simply finish.
      final out = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: 32,
        dstHeight: 32,
        transform: ResampleTransform(
          a: 1,
          b: 0,
          c: 0,
          d: 0,
          e: 1,
          f: 0,
          g: 0,
          h: -0.94 / 32,
          i: 1,
        ),
        mode: ResampleMode.pick,
      );
      final novel = _tokensOf(out)
          .where((t) => t != kResampleOutsideToken)
          .where((t) => !sourceTokens.contains(t));
      expect(novel, isEmpty);
    });
  });

  group('the vote table survives more colours than it has slots', () {
    test('a dominant colour still wins past 16 distinct tokens', () {
      // Dropping the newcomer on overflow let a colour covering 99% of a
      // footprint lose to one covering 0.1%. Eviction of the lightest slot
      // plus an exact re-weigh is what makes "the rarest lose" true.
      const size = 64;
      final crowded = Uint8List(size * size * 4);
      final crowdedWords = Uint32List.view(crowded.buffer);
      const dominant = 0xff0000ff;
      for (var i = 0; i < crowdedWords.length; i += 1) {
        crowdedWords[i] = dominant;
      }
      for (var i = 0; i < 16; i += 1) {
        crowdedWords[4 * size + (4 + i)] = 0xff000000 | (i * 0x080808);
      }
      final out = resampleRgbaReference(
        src: crowded,
        srcWidth: size,
        srcHeight: size,
        dstWidth: 8,
        dstHeight: 8,
        transform: ResampleTransform.scaleTranslate(scale: 1 / 8),
        mode: ResampleMode.pick,
      );
      expect(_tokenAt(out, 8, 1, 1), dominant,
          reason: 'a 0.1% colour outvoted a 99% one');
    });

    test('an edge footprint whose interior is opaque is not punched out', () {
      const size = 64;
      final crowded = Uint8List(size * size * 4);
      final crowdedWords = Uint32List.view(crowded.buffer);
      const dominant = 0xff0000ff;
      for (var i = 0; i < crowdedWords.length; i += 1) {
        crowdedWords[i] = dominant;
      }
      for (var i = 0; i < 16; i += 1) {
        crowdedWords[0 * size + i] = 0xff000000 | (i * 0x080808);
      }
      final out = resampleRgbaReference(
        src: crowded,
        srcWidth: size,
        srcHeight: size,
        dstWidth: 8,
        dstHeight: 8,
        transform: ResampleTransform.scaleTranslate(scale: 1 / 8),
        mode: ResampleMode.pick,
      );
      expect(_tokenAt(out, 8, 0, 0), isNot(kResampleOutsideToken),
          reason: 'a transparent hole was punched where the footprint is '
              'mostly opaque');
    });
  });

  group('footprint geometry is constrained', () {
    test('swapping the two radii changes the result', () {
      // Without this, a fixture symmetric enough to survive an axis swap
      // would let a transposed footprint pass every other test here.
      final anisotropic = ResampleTransform(
        a: 1 / 0.25,
        b: 0,
        c: 0,
        d: 0,
        e: 1,
        f: 0,
      );
      final swapped = ResampleTransform(
        a: 1,
        b: 0,
        c: 0,
        d: 0,
        e: 1 / 0.25,
        f: 0,
      );
      for (final mode in ResampleMode.values) {
        final a = resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: 32,
          dstHeight: 32,
          transform: anisotropic,
          mode: mode,
        );
        final b = resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: 32,
          dstHeight: 32,
          transform: swapped,
          mode: mode,
        );
        expect(a, isNot(b), reason: '$mode is blind to which axis reduces');
      }
    });

    test('a wider floor changes what Pick elects', () {
      // Pins that radiusFloor is actually consumed: a kernel that ignored
      // it would return identical bytes for both.
      final transform = _rotationAbout(15, width / 2, height / 2);
      final tight = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: height,
        transform: transform,
        mode: ResampleMode.pick,
        radiusFloor: 1.0,
      );
      final wide = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: height,
        transform: transform,
        mode: ResampleMode.pick,
        radiusFloor: 3.0,
      );
      expect(tight, isNot(wide));
    });
  });

  group('Blend cannot ring', () {
    test('output stays inside the min..max of its own footprint', () {
      // The halo TVPaint's Medium/High/VeryHigh filters produce is exactly
      // an excursion outside this interval. A tent is a convex combination,
      // so there must be zero of them.
      const scale = 0.8;
      final transform = ResampleTransform.scaleTranslate(scale: scale);
      final out = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: height,
        transform: transform,
        mode: ResampleMode.blend,
      );
      final srcWords = Uint32List.view(source.buffer);
      var excursions = 0;
      for (var y = 0; y < height; y += 1) {
        for (var x = 0; x < width; x += 1) {
          final u = (x + 0.5) / scale - 0.5;
          final v = (y + 0.5) / scale - 0.5;
          final cx = u.round(), cy = v.round();
          final radius = (1 / scale).ceil() + 1;
          var minR = 255, maxR = 0, minG = 255, maxG = 0, minB = 255, maxB = 0;
          var sawAny = false;
          for (var dy = -radius; dy <= radius; dy += 1) {
            for (var dx = -radius; dx <= radius; dx += 1) {
              final sx = cx + dx, sy = cy + dy;
              if (sx < 0 || sy < 0 || sx >= width || sy >= height) continue;
              final token = srcWords[sy * width + sx];
              final r = token & 0xff;
              final g = (token >> 8) & 0xff;
              final b = (token >> 16) & 0xff;
              if (r < minR) minR = r;
              if (r > maxR) maxR = r;
              if (g < minG) minG = g;
              if (g > maxG) maxG = g;
              if (b < minB) minB = b;
              if (b > maxB) maxB = b;
              sawAny = true;
            }
          }
          if (!sawAny) continue;
          final token = _tokenAt(out, width, x, y);
          if ((token >> 24) & 0xff == 0) continue;
          final r = token & 0xff;
          final g = (token >> 8) & 0xff;
          final b = (token >> 16) & 0xff;
          if (r < minR || r > maxR || g < minG || g > maxG || b < minB ||
              b > maxB) {
            excursions += 1;
          }
        }
      }
      expect(excursions, 0);
    });
  });

  group('exactness contracts', () {
    test('identity is byte-for-byte', () {
      for (final mode in ResampleMode.values) {
        final out = resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: width,
          dstHeight: height,
          transform: ResampleTransform.identity(),
          mode: mode,
        );
        expect(out, source, reason: '$mode changed an untransformed image');
      }
    });

    test('whole-pixel translation is byte-for-byte', () {
      for (final mode in ResampleMode.values) {
        final out = resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: width,
          dstHeight: height,
          transform: ResampleTransform(a: 1, b: 0, c: -7, d: 0, e: 1, f: 5),
          mode: mode,
        );
        for (var y = 0; y < height; y += 1) {
          for (var x = 0; x < width; x += 1) {
            final sx = x - 7, sy = y + 5;
            final expected = (sx < 0 || sy < 0 || sx >= width || sy >= height)
                ? kResampleOutsideToken
                : _tokenAt(source, width, sx, sy);
            expect(_tokenAt(out, width, x, y), expected,
                reason: '$mode at $x,$y');
          }
        }
      }
    });
  });

  group('band split is invisible', () {
    test('row bands reproduce the whole-image result exactly', () {
      // This is what lets the native kernel fan destination rows across the
      // worker pool: a band must not be able to tell it is a band.
      for (final mode in ResampleMode.values) {
        final transform = _rotationAbout(22.5, width / 2, height / 2);
        final whole = resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: width,
          dstHeight: height,
          transform: transform,
          mode: mode,
        );
        final banded = Uint8List(width * height * 4);
        for (var start = 0; start < height; start += 7) {
          resampleRgbaReferenceInto(
            src: source,
            srcWidth: width,
            srcHeight: height,
            dst: banded,
            dstWidth: width,
            dstHeight: height,
            transform: transform,
            mode: mode,
            rowStart: start,
            rowEnd: math.min(start + 7, height),
          );
        }
        expect(banded, whole, reason: '$mode differed when split into bands');
      }
    });
  });

  group('quality yardstick', () {
    test('Pick leaves fewer spurs than a point sampler on rotation', () {
      final transform = _rotationAbout(15, width / 2, height / 2);
      final pick = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: height,
        transform: transform,
        mode: ResampleMode.pick,
      );
      // Pick with the floor forced to 1.0 degenerates towards nearest; that
      // is the comparison the TVPaint measurement made, and the reason the
      // shipped floor is 1.5.
      final nearestish = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: height,
        transform: transform,
        mode: ResampleMode.pick,
        radiusFloor: 1.0,
      );
      final spursPick = _isolatedPixels(pick, width, height);
      final spursNearest = _isolatedPixels(nearestish, width, height);
      expect(spursPick, lessThan(spursNearest),
          reason: 'floor 1.5 produced $spursPick spurs, floor 1.0 produced '
              '$spursNearest');
    });

    test('a reduction still carries line art through', () {
      // NOT "more ink than nearest". Measured against the production cel,
      // Pick came out 0.4% BELOW the point sampler on raw ink count
      // (24,144 vs 24,244) — a majority vote discards a stroke narrower
      // than its own footprint, and nearest happens to keep whichever
      // pixels the sampling grid lands on. Pick's advantage is that what
      // survives is contiguous rather than a dotted line, which the spur
      // test below is the honest measurement of.
      //
      // What this test guards is the floor: the reduction must not come
      // back empty.
      const scale = 0.37;
      final outWidth = (width * scale).round();
      final outHeight = (height * scale).round();
      final pick = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: outWidth,
        dstHeight: outHeight,
        transform: ResampleTransform.scaleTranslate(scale: scale),
        mode: ResampleMode.pick,
      );
      final words = Uint32List.view(pick.buffer, 0, outWidth * outHeight);
      var inkPixels = 0;
      for (final token in words) {
        if (token == 0xff101010) inkPixels += 1;
      }
      expect(inkPixels, greaterThan(0),
          reason: 'the reduction lost every stroke');
    });

    test('Pick leaves fewer spurs than point sampling under reduction', () {
      const scale = 0.5;
      final outWidth = (width * scale).round();
      final outHeight = (height * scale).round();
      final transform = ResampleTransform.scaleTranslate(scale: scale);
      final pick = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: outWidth,
        dstHeight: outHeight,
        transform: transform,
        mode: ResampleMode.pick,
      );
      final nearest =
          _nearest(source, width, height, outWidth, outHeight, transform);
      expect(
        _isolatedPixels(pick, outWidth, outHeight),
        lessThan(_isolatedPixels(nearest, outWidth, outHeight)),
      );
    });
  });
}
