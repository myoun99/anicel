import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';

import 'coverage_truth.dart';

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
  final srcWords = Uint32List.view(
    src.buffer,
    src.offsetInBytes,
    srcWidth * srcHeight,
  );
  final dstWords = Uint32List.view(out.buffer, 0, dstWidth * dstHeight);
  for (var y = 0; y < dstHeight; y += 1) {
    for (var x = 0; x < dstWidth; x += 1) {
      final u = t.a * (x + 0.5) + t.b * (y + 0.5) + t.c - 0.5;
      final v = t.d * (x + 0.5) + t.e * (y + 0.5) + t.f - 0.5;
      final sx = u.round(), sy = v.round();
      dstWords[y * dstWidth +
          x] = (sx < 0 || sy < 0 || sx >= srcWidth || sy >= srcHeight)
          ? kResampleOutsideToken
          : srcWords[sy * srcWidth + sx];
    }
  }
  return out;
}

Set<int> _tokensOf(Uint8List bytes) => Uint32List.view(
  bytes.buffer,
  bytes.offsetInBytes,
  bytes.length ~/ 4,
).toSet();

int _tokenAt(Uint8List bytes, int width, int x, int y) => Uint32List.view(
  bytes.buffer,
  bytes.offsetInBytes,
  bytes.length ~/ 4,
)[y * width + x];

/// Ink pixels whose eight neighbours hold at most one of the same colour —
/// the "spur" count the TVPaint comparison used as its quality yardstick.
int _isolatedPixels(Uint8List bytes, int width, int height) {
  final words = Uint32List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    width * height,
  );
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

/// Rotate by [degrees] and scale by [scale] about ([cx], [cy]), inverted
/// into the kernel's destination-index → source-index form. Independent
/// x/y scales, because anisotropy is where every previous design broke.
ResampleTransform _rotateScaleAbout(
  double degrees,
  double sx,
  double sy,
  double cx,
  double cy,
) {
  final r = degrees * math.pi / 180;
  final cos = math.cos(r), sin = math.sin(r);
  return ResampleTransform(
    a: cos / sx,
    b: sin / sx,
    c: (-cx * cos - cy * sin) / sx + cx,
    d: -sin / sy,
    e: cos / sy,
    f: (cx * sin - cy * cos) / sy + cy,
  );
}

/// A bare 1px cross on white.
///
/// `_lineArt`'s horizontal rule sits at a phase where the axis-aligned tie
/// never forms, so it is structurally unable to see the failure that band
/// produces. This one is chosen for the opposite reason: nothing but
/// hairlines, at a phase that does tie.
Uint8List _hairlines(int size) {
  final bytes = Uint8List(size * size * 4);
  final words = Uint32List.view(bytes.buffer);
  for (var i = 0; i < words.length; i += 1) {
    words[i] = 0xffffffff;
  }
  for (var i = 0; i < size; i += 1) {
    words[(size ~/ 2 + 1) * size + i] = 0xff101010;
    words[i * size + (size ~/ 2 + 1)] = 0xff101010;
  }
  return bytes;
}

/// Reduce by [scale] and rotate by [degrees], with the DESTINATION centred
/// on the source centre — otherwise a reduction throws most of the picture
/// out of frame and an ink count measures the crop instead of the kernel.
///
/// Quarter turns take their cos and sin from a TABLE, because the product
/// path does: `SelectionAffine.cosTheta` exists precisely so that 90° is
/// `cos == 0` rather than 6.1e-17. Computing them here with `math.cos`
/// would leave `b` and `d` a hair off zero, miss the kernel's exact
/// branch, and quietly test a path the app never runs.
ResampleTransform _reduceAbout(
  double degrees,
  double scale,
  int srcSize,
  int dstSize,
) {
  final turn = ((degrees % 360) + 360) % 360;
  final quarter = turn % 90 == 0;
  final radians = degrees * math.pi / 180;
  final cos = quarter
      ? (turn == 0
            ? 1.0
            : turn == 180
            ? -1.0
            : 0.0)
      : math.cos(radians);
  final sin = quarter
      ? (turn == 90
            ? 1.0
            : turn == 270
            ? -1.0
            : 0.0)
      : math.sin(radians);
  final a = cos / scale;
  final b = sin / scale;
  final d = -sin / scale;
  final e = cos / scale;
  final dstCentre = dstSize / 2;
  final srcCentre = srcSize / 2;
  return ResampleTransform(
    a: a,
    b: b,
    c: -a * dstCentre - b * dstCentre + srcCentre,
    d: d,
    e: e,
    f: -d * dstCentre - e * dstCentre + srcCentre,
  );
}

/// Solid colour everywhere, no transparency at all, so a transparent
/// output pixel can only be a hole the kernel punched.
Uint8List _opaqueArt(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  final words = Uint32List.view(bytes.buffer);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final band = ((x ~/ 3) + (y ~/ 5)) % 3;
      words[y * width + x] = band == 0
          ? 0xffffffff
          : band == 1
          ? 0xff101010
          : 0xffc8dcf0;
    }
  }
  return bytes;
}

int _countToken(Uint8List bytes, int token) {
  var n = 0;
  for (final word in Uint32List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.length ~/ 4,
  )) {
    if (word == token) n += 1;
  }
  return n;
}

int _disagreements(Uint8List a, Uint8List b) {
  final wa = Uint32List.view(a.buffer, a.offsetInBytes, a.length ~/ 4);
  final wb = Uint32List.view(b.buffer, b.offsetInBytes, b.length ~/ 4);
  var n = 0;
  for (var i = 0; i < wa.length; i += 1) {
    if (wa[i] != wb[i]) n += 1;
  }
  return n;
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

  group('Pick is the area argmax its oracle defines', () {
    // `coverage_truth.dart` computes Pick the slow honest way: it cuts the
    // destination pixel into 32×32 or 48×48 points, maps every one, and
    // counts. That is the definition, so measuring against it says how far
    // the kernel is from RIGHT rather than how far it is from its own
    // previous behaviour — which is what the two rounds before this one
    // measured, and why both shipped a kernel whose error was invisible.
    //
    // The angle steps here are five degrees. The round before used ten,
    // and ten stepped straight over the angles where its footprint failed.

    test('agrees with the truth, and keeps the line art the truth keeps', () {
      // Two assertions over one sweep because they share the expensive
      // half: the oracle costs a thousand inverse maps per pixel, and
      // running the grid twice to state the two properties separately
      // spent fifty seconds saying the same thing.
      //
      // The second assertion is the failure this whole feature exists to
      // end. Rotating while shrinking — an ordinary Ctrl+T — erased line
      // art, because the boxed footprint kept a 1px feature only while
      // scale > (|cos| + |sin|)/2: 0.5 axis-aligned but 0.707 at 45°. A
      // 0.7× at 25° kept 16 ink pixels of 67, and a 0.65× at 25° kept 2.
      // Stated against the oracle rather than against fixed counts, so it
      // says "the kernel keeps what is really there" instead of pinning
      // numbers a later change would simply edit.
      //
      // ⚠️ THE GRID IS PART OF THE ASSERTION. An earlier version of this
      // test walked five scales — 1.0, 0.85, 0.7, 0.55, 0.4 — and both
      // thresholds below were measured on them, which made both true of
      // the grid rather than of the kernel. One step in from 0.55 the
      // kernel deleted whole hairlines and this test stayed green. Steps
      // of 0.025 are what catch that; do not thin them to buy time.
      //
      // ⚠️ SO IS THE FIXTURE. `_lineArt`'s horizontal rule happens to sit
      // at a phase where the axis-aligned tie never forms, so it cannot
      // see that failure at all. `_hairlines` is a bare 1px cross chosen
      // for the opposite reason. Both are swept.
      final fixtures = <String, Uint8List>{
        'line art': _lineArt(64, 64),
        'hairlines': _hairlines(64),
      };
      var inkCasesChecked = 0;
      var tiedCasesSkipped = 0;
      for (final entry in fixtures.entries) {
        for (var degrees = 0; degrees <= 90; degrees += 5) {
          for (var step = 0; step <= 24; step += 1) {
            final scale = 0.4 + step * 0.025;
            final out = (64 * scale).round();
            final transform = _reduceAbout(degrees.toDouble(), scale, 64, out);
            final got = resampleRgbaReference(
              src: entry.value,
              srcWidth: 64,
              srcHeight: 64,
              dstWidth: out,
              dstHeight: out,
              transform: transform,
              mode: ResampleMode.pick,
            );
            final truth = coverageTruth(
              src: entry.value,
              srcWidth: 64,
              srcHeight: 64,
              dstWidth: out,
              dstHeight: out,
              transform: transform,
              samples: 32,
            );
            final where =
                '${entry.key} $degrees° × '
                '${scale.toStringAsFixed(3)}';
            // EXACTLY half is a genuine tie — a 1px feature covers exactly
            // one of the two source pixels its preimage spans, so the two
            // areas are equal and the winner is whichever tie-break each
            // implementation happens to use. The oracle's is a map's
            // insertion order and the kernel's is its scan order. Comparing
            // them there measures the two tie-breaks, not the kernel, so
            // neither assertion below is meaningful and both are skipped.
            // The tie itself is pinned on its own, exactly, below.
            if (scale == 0.5) {
              tiedCasesSkipped += 1;
              continue;
            }
            // Not zero: the supersampled half of the kernel reads an
            // ordinary pixel 64 times and the oracle 1024, so pixels whose
            // top two colours sit within a hair of each other can land
            // either way. 6% is the measured worst over this grid (45° ×
            // 0.4, a strong rotated reduction where nearly every edge
            // pixel is a near-tie); the boxed footprint this replaces
            // peaks far above it and fails.
            expect(
              _disagreements(got, truth) / (out * out),
              lessThan(0.06),
              reason: '$where disagrees with the truth too often',
            );
            final truthInk = _countToken(truth, 0xff101010);
            // Only where the truth still has a drawing to keep. Past the
            // half-scale threshold a 1px line genuinely loses its own area
            // argmax and the oracle is down to single digits, where
            // "within 80%" is a statement about two or three pixels.
            if (truthInk < 20) {
              continue;
            }
            inkCasesChecked += 1;
            expect(
              _countToken(got, 0xff101010),
              greaterThanOrEqualTo((truthInk * 0.8).floor()),
              reason: '$where dropped ink the truth keeps',
            );
          }
        }
      }
      // The guard on the guard: a fixture or a scale list edited until the
      // ink assertion never runs would leave this test green while saying
      // nothing, which is how the provenance test spent a round unable to
      // fail.
      expect(
        inkCasesChecked,
        greaterThan(300),
        reason: 'the ink assertion stopped running on most of the sweep',
      );
      expect(
        tiedCasesSkipped,
        lessThan(inkCasesChecked ~/ 10),
        reason: 'the tie carve-out grew into a way of not asserting',
      );
    });

    test('an exact tie is decided by scan order, without inventing a '
        'colour', () {
      // The one case the sweep declines to judge, pinned here exactly
      // rather than statistically — a two-pixel source reduced to one
      // destination pixel, where the preimage is precisely the two source
      // pixels and the two areas are precisely equal. No oracle needed and
      // no phase to get lucky with: this IS the tie.
      //
      // At exactly half scale a 1px line meets this everywhere along its
      // length at once, which is why the whole line flips together and
      // looks like the defect this feature exists to prevent. It is not
      // one. There is no larger area to elect, the kernel this replaced
      // answers the same way, and BOTH tie-breaks that were tried instead
      // won one scale by losing another — deciding by the pixel's own
      // centre fixed 0.500 and cost 0.750 ninety-five ink pixels of
      // ninety-five. If this assertion is ever flipped, the tie-break has
      // changed, and the 0.750 sweep is what says whether that was worth
      // it.
      final source = Uint8List(2 * 4);
      final sourceWords = Uint32List.view(source.buffer);
      sourceWords[0] = 0xff101010;
      sourceWords[1] = 0xffffffff;
      // dst 1×1 over src 2×1: the preimage spans u ∈ [−0.5, 1.5], which is
      // source pixel 0 and source pixel 1, each covered exactly 1.0.
      final out = resampleRgbaReference(
        src: source,
        srcWidth: 2,
        srcHeight: 1,
        dstWidth: 1,
        dstHeight: 1,
        transform: ResampleTransform(a: 2, b: 0, c: 0, d: 0, e: 1, f: 0),
        mode: ResampleMode.pick,
      );
      expect(
        _tokenAt(out, 1, 0, 0),
        0xff101010,
        reason:
            'the tie went to the token met SECOND — the scan order that '
            'makes this answer identical on every platform and worker '
            'count has changed',
      );
      // Whatever wins, it is a colour that was already in the source.
      expect(_tokensOf(out).difference(_tokensOf(source)), isEmpty);
    });

    test('opaque artwork never comes back transparent, at any anisotropy '
        'or angle', () {
      // The way the previous design died, twice, by two different
      // mechanisms: a footprint box that had to be shrunk to match a
      // rotated parallelogram's area either scored no tap at all (a hole)
      // or scored taps outside the image (a hole). Supersampling cannot do
      // either — every subsample lands somewhere — and this walks the
      // shape that broke it: strong anisotropy, rotated.
      final solid = _opaqueArt(width, height);
      const out = 6;
      // TWO placements, and the second is what gives the test teeth. At
      // the CENTRE the preimage is wholly inside the source, so the gate
      // below (`the truth says this pixel is opaque`) never fires — it
      // fired on 0 of 26,460 cells, which is why the boxed kernel this
      // test exists to indict used to pass it. At the CORNER half the
      // preimage hangs off the image, the gate goes live, and that kernel
      // punches 13 holes through artwork the truth calls opaque.
      var gatedCells = 0;
      for (final shift in <double>[0, 0.5 * (width - out)]) {
        for (var degrees = 0; degrees < 90; degrees += 6) {
          for (final sx in <double>[0.2, 0.5, 1.0, 2.0, 4.0, 12.0, 20.0]) {
            for (final sy in <double>[0.2, 0.5, 1.0, 2.0, 4.0, 12.0, 20.0]) {
              final t = _rotateScaleAbout(
                degrees.toDouble(),
                sx,
                sy,
                width / 2,
                height / 2,
              );
              final inner = ResampleTransform(
                a: t.a,
                b: t.b,
                c: t.c + t.a * shift + t.b * shift,
                d: t.d,
                e: t.e,
                f: t.f + t.d * shift + t.e * shift,
              );
              final got = resampleRgbaReference(
                src: solid,
                srcWidth: width,
                srcHeight: height,
                dstWidth: out,
                dstHeight: out,
                transform: inner,
                mode: ResampleMode.pick,
              );
              final truth = coverageTruth(
                src: solid,
                srcWidth: width,
                srcHeight: height,
                dstWidth: out,
                dstHeight: out,
                transform: inner,
                samples: 32,
              );
              final gotWords = Uint32List.view(got.buffer);
              final truthWords = Uint32List.view(truth.buffer);
              for (var i = 0; i < gotWords.length; i += 1) {
                if (truthWords[i] != kResampleOutsideToken) {
                  gatedCells += 1;
                  expect(
                    gotWords[i],
                    isNot(kResampleOutsideToken),
                    reason:
                        'shift $shift $degrees° sx=$sx sy=$sy punched a '
                        'hole at $i',
                  );
                }
              }
            }
          }
        }
      }
      // A hole test whose gate never fires is a hole test that cannot
      // fail. This is the assertion that says the gate fired.
      expect(
        gatedCells,
        greaterThan(1000),
        reason:
            'the truth never called a pixel opaque, so nothing was '
            'checked — the placements stopped straddling the edge',
      );
    });
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
          reason:
              '${entry.key} invented '
              '${novel.map((t) => t.toRadixString(16)).toList()}',
        );
      }
    });

    test('alpha values are carried, never invented', () {
      // The fixture holds 0x80 as well as 0x00 and 0xff, so this asserts
      // something: Pick may emit the source's partial alpha, but must not
      // manufacture a NEW one the way an averaging kernel would.
      final sourceAlphas = sourceTokens.map((t) => (t >> 24) & 0xff).toSet()
        ..add(0);
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
            final reach = math.max(
              extent,
              resampleRadiusFloor(ResampleMode.pick),
            );
            var found = false;
            for (var sy = (v - reach).floor(); sy <= (v + reach).ceil(); sy++) {
              for (
                var sx = (u - reach).floor();
                sx <= (u + reach).ceil();
                sx++
              ) {
                if (sx < 0 || sy < 0 || sx >= width || sy >= height) continue;
                if (srcWords[sy * width + sx] == token) {
                  found = true;
                  break;
                }
              }
              if (found) break;
            }
            expect(
              found,
              isTrue,
              reason:
                  'scale $scale: ($x,$y) emitted '
                  '${token.toRadixString(16)} from outside its preimage',
            );
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
          expect(_tokensOf(out), {
            kResampleOutsideToken,
          }, reason: '${entry.key} / $mode');
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
      // 24 DISTINCT greys inside ONE destination pixel's preimage. At
      // scale 1/8 that is dst(0,0), whose preimage is source [0,8)×[0,8).
      // Seeded along a single row instead — as they were — no preimage
      // ever sees more than eight of them, the sixteen-slot table never
      // overflows, and the eviction policy this test is named for is
      // never exercised at all.
      for (var y = 0; y < 3; y += 1) {
        for (var x = 0; x < 8; x += 1) {
          crowdedWords[y * size + x] = 0xff000000 | ((y * 8 + x) * 0x040404);
        }
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
      expect(
        _tokenAt(out, 8, 0, 0),
        dominant,
        reason: 'a 1.5% colour outvoted a 62% one',
      );
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
      expect(
        _tokenAt(out, 8, 0, 0),
        isNot(kResampleOutsideToken),
        reason:
            'a transparent hole was punched where the footprint is '
            'mostly opaque',
      );
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

    test('a wider floor changes what Blend produces and nothing Pick '
        'elects', () {
      // Two contracts in one fixture, because they are the same
      // measurement pointed in opposite directions. Blend still gathers
      // taps, so its floor has to be consumed — a kernel that ignored it
      // would return identical bytes. Pick does not gather taps at all any
      // more, so its bytes must NOT move: a floor that reached the vote
      // would mean a footprint had grown back around the preimage, and a
      // footprint is what deleted line art under rotation for three
      // rounds.
      final transform = _rotationAbout(15, width / 2, height / 2);
      Uint8List at(ResampleMode mode, double floor) => resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: height,
        transform: transform,
        mode: mode,
        radiusFloor: floor,
      );
      expect(
        at(ResampleMode.blend, 1.0),
        isNot(at(ResampleMode.blend, 3.0)),
        reason: 'Blend ignored its radius floor',
      );
      expect(
        at(ResampleMode.pick, 3.0),
        at(ResampleMode.pick, 1.0),
        reason: 'Pick read a radius floor it is not supposed to have',
      );
    });

    test('the sample rate follows each axis, not the area they multiply '
        'to', () {
      // The rule that came before this one took the rate from the
      // preimage's AREA, and an anisotropic map is exactly where that is
      // wrong: shrinking 5:1 across while magnifying 2× down is an area of
      // 2.5 — the same as a gentle uniform reduction — while needing ten
      // samples across and eight down. It dropped a whole column of an
      // opaque image when it got four.
      expect(resampleSamplesPerAxis(25), 10, reason: 'a 5px step');
      expect(resampleSamplesPerAxis(0.25), kResampleMinSamplesPerAxis);
      expect(resampleSamplesPerAxis(1), kResampleMinSamplesPerAxis);
      expect(resampleSamplesPerAxis(10000), kResampleMaxSamplesPerAxis);
      expect(
        resampleSamplesPerAxis(double.nan),
        kResampleMaxSamplesPerAxis,
        reason: 'a degenerate rate must terminate, not run away',
      );
      // ⌈2√q⌉ at each threshold, so the chain cannot drift from the rule
      // it stands for.
      for (
        var n = kResampleMinSamplesPerAxis;
        n <= kResampleMaxSamplesPerAxis;
        n += 1
      ) {
        final atThreshold = n * n / 4;
        expect(resampleSamplesPerAxis(atThreshold), n, reason: 'q = $n²/4');
        if (n < kResampleMaxSamplesPerAxis) {
          expect(
            resampleSamplesPerAxis(atThreshold + 1e-9),
            n + 1,
            reason: 'just past q = $n²/4',
          );
        }
      }
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
          if (r < minR ||
              r > maxR ||
              g < minG ||
              g > maxG ||
              b < minB ||
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
            expect(
              _tokenAt(out, width, x, y),
              expected,
              reason: '$mode at $x,$y',
            );
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
    test('Pick keeps more of a reduced drawing than a point sampler, and '
        'keeps it in one piece', () {
      // This test used to compare Pick at floor 1.5 against Pick at floor
      // 1.0 and call the second one "nearest-ish" — so it measured a
      // TUNING KNOB against itself, not the tool it has to beat. Once the
      // weight became coverage the floor stopped meaning anything and the
      // comparison became 55 against 55: a tautology that had been reading
      // as a quality guarantee.
      //
      // The honest yardstick is the real point sampler, at the transform
      // where the difference is decided. A halving is where a point
      // sampler starts dropping whole strokes — its grid either lands on
      // a stroke or misses it, and a stroke narrower than the step is a
      // coin flip — while an area rule sees every stroke that covers half
      // its destination pixel.
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
      final nearest = _nearest(
        source,
        width,
        height,
        outWidth,
        outHeight,
        transform,
      );
      int inkOf(Uint8List bytes) => Uint32List.view(
        bytes.buffer,
        0,
        outWidth * outHeight,
      ).where((token) => token == 0xff101010).length;

      final inkPick = inkOf(pick);
      final inkNearest = inkOf(nearest);
      expect(
        inkPick,
        greaterThan(inkNearest),
        reason:
            'Pick kept $inkPick ink pixels, the point sampler '
            '$inkNearest — if this ever inverts, Pick is costing its '
            'footprint arithmetic for nothing',
      );
      // And what survives has to read as line, not as dust: more ink AND
      // more spurs would be a worse picture reported as a better number.
      final spursPick = _isolatedPixels(pick, outWidth, outHeight);
      final spursNearest = _isolatedPixels(nearest, outWidth, outHeight);
      expect(
        spursPick,
        lessThanOrEqualTo(spursNearest),
        reason:
            'Pick left $spursPick isolated pixels against the point '
            "sampler's $spursNearest",
      );
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
      expect(
        inkPixels,
        greaterThan(0),
        reason: 'the reduction lost every stroke',
      );
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
      final nearest = _nearest(
        source,
        width,
        height,
        outWidth,
        outHeight,
        transform,
      );
      expect(
        _isolatedPixels(pick, outWidth, outHeight),
        lessThan(_isolatedPixels(nearest, outWidth, outHeight)),
      );
    });
  });
}
