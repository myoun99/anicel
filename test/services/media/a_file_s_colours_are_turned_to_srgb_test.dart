// A picture file's colours are turned to sRGB's by what its file says of
// them, as the engine's decoder turns them (🗣️유저 2026-11-14,
// a-raster-import-goes-gpu-cpu-gpu-cpu-Q1 「프로파일대로 바꿔 읽는다(크기
// 상관없이)」): a PNG's profile, sRGB word, chromaticities and gamma in
// their order, a JPEG's profile however many pieces it is written in. Each
// is held to the colour science worked out here by `math.pow` — another
// working of it than the reader's own.
import 'dart:io' show zlib;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/services/media/png_writing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  /// Four pixels and a clear one — all zero, as a reader hands one
  /// (`readPngRows`): greys and colours across the range.
  const pixels = [
    (32, 32, 32, 255),
    (128, 128, 128, 255),
    (200, 60, 20, 255),
    (40, 150, 230, 128),
    (0, 0, 0, 0),
  ];

  /// Every grey, opaque.
  final greys = [for (var v = 0; v < 256; v += 1) (v, v, v, 255)];

  Uint8List rgbaOf(List<(int, int, int, int)> of) => Uint8List.fromList([
    for (final (r, g, b, a) in of) ...[r, g, b, a],
  ]);

  /// [of] as a one-row RGBA PNG, with [chunks] before its pixels.
  Uint8List pngOf(
    List<(int, int, int, int)> of, {
    List<Uint8List> chunks = const [],
  }) => (BytesBuilder(copy: false)
        ..add(pngSignature)
        ..add(pngHeader(width: of.length, height: 1, colourType: pngRgba))
        ..add(Uint8List.fromList([for (final c in chunks) ...c]))
        ..add(pngChunk('IDAT', zlib.encode([0, ...rgbaOf(of)])))
        ..add(pngChunk('IEND', const [])))
      .takeBytes();

  List<int> read(Uint8List file, int width) {
    final out = <int>[];
    readFileRows(
      file,
      width: width,
      height: 1,
      row: (_, rgba) => out.addAll(rgba),
    );
    return out;
  }

  List<int> u32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];
  List<int> s15(double v) => u32((v * 65536).round() & 0xffffffff);

  /// sRGB's curve, linear light to a byte, by `math.pow`.
  int srgbByte(double linear) {
    final c = linear.clamp(0.0, 1.0);
    final encoded = c <= 0.0031308
        ? 12.92 * c
        : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
    return (encoded * 255).round();
  }

  /// sRGB's primaries under D50, as its ICC profile writes them.
  const srgbD50 = [
    [0.436065674, 0.385147095, 0.143066406],
    [0.222488403, 0.716873169, 0.060607910],
    [0.013916016, 0.097076416, 0.714096069],
  ];

  /// [m]'s inverse, by cofactors.
  List<List<double>> inverse(List<List<double>> m) {
    final [[a, b, c], [d, e, f], [g, h, i]] = m;
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    return [
      [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
      [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
      [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det],
    ];
  }

  /// [of] as sRGB shows it, where each channel's byte is [linear] light
  /// and [toXyzD50] carries the linear light to XYZ: a clear pixel kept.
  List<int> expected(
    List<(int, int, int, int)> of,
    double Function(int byte) linear,
    List<List<double>> toXyzD50,
  ) {
    final back = inverse(srgbD50);
    final out = <int>[];
    for (final (r, g, b, a) in of) {
      if (a == 0) {
        out.addAll([r, g, b, a]);
        continue;
      }
      final rgb = [linear(r), linear(g), linear(b)];
      final xyz = [
        for (final row in toXyzD50)
          row[0] * rgb[0] + row[1] * rgb[1] + row[2] * rgb[2],
      ];
      for (final row in back) {
        out.add(srgbByte(row[0] * xyz[0] + row[1] * xyz[1] + row[2] * xyz[2]));
      }
      out.add(a);
    }
    return out;
  }

  /// An ICC v2 profile of [space] whose tags are [tags], each name and
  /// body.
  Uint8List profileOf(String space, List<(String, List<int>)> tags) {
    final tableLength = 4 + tags.length * 12;
    var offset = 128 + tableLength;
    final table = <int>[...u32(tags.length)];
    final data = <int>[];
    for (final (name, body) in tags) {
      table.addAll([...name.codeUnits, ...u32(offset), ...u32(body.length)]);
      data.addAll(body);
      offset += body.length;
      while (offset % 4 != 0) {
        data.add(0);
        offset += 1;
      }
    }
    final header = <int>[
      ...u32(128 + table.length + data.length), 0, 0, 0, 0, 2, 0x10, 0, 0,
      ...'mntr'.codeUnits, ...space.codeUnits, ...'XYZ '.codeUnits,
      ...List.filled(12, 0), ...'acsp'.codeUnits,
      ...List.filled(32, 0),
      ...u32(0),
      ...s15(0.9642), ...s15(1.0), ...s15(0.8249),
    ];
    header.addAll(List.filled(128 - header.length, 0));
    return Uint8List.fromList([...header, ...table, ...data]);
  }

  List<int> xyz(List<double> v) => [
    ...'XYZ '.codeUnits, 0, 0, 0, 0, ...s15(v[0]), ...s15(v[1]), ...s15(v[2]),
  ];
  List<int> gammaCurve(double gamma) => [
    ...'curv'.codeUnits, 0, 0, 0, 0, ...u32(1),
    (gamma * 256).round() >> 8, (gamma * 256).round() & 255,
  ];
  List<int> parametric(int type, List<double> p) => [
    ...'para'.codeUnits, 0, 0, 0, 0, 0, type, 0, 0,
    for (final v in p) ...s15(v),
  ];

  /// Adobe RGB (1998)'s primaries under D50, as its profile writes them.
  const adobeD50 = [
    [0.6097, 0.2053, 0.1492],
    [0.3111, 0.6257, 0.0632],
    [0.0195, 0.0609, 0.7446],
  ];
  const adobeGamma = 563 / 256;

  /// sRGB's curve as an ICC parametric curve of type 3.
  const srgbCurve = [2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045];

  /// White, red, green and blue x y × 100000: sRGB's and Adobe RGB's.
  const srgbChromaticities = [
    31270, 32900, 64000, 33000, 30000, 60000, 15000, 6000, //
  ];
  const adobeChromaticities = [
    31270, 32900, 64000, 33000, 21000, 71000, 15000, 6000, //
  ];

  Uint8List matrixProfile(List<List<double>> m, List<int> curve) =>
      profileOf('RGB ', [
        ('rXYZ', xyz([m[0][0], m[1][0], m[2][0]])),
        ('gXYZ', xyz([m[0][1], m[1][1], m[2][1]])),
        ('bXYZ', xyz([m[0][2], m[1][2], m[2][2]])),
        ('rTRC', curve),
        ('gTRC', curve),
        ('bTRC', curve),
      ]);

  Uint8List iccp(Uint8List profile) => pngChunk('iCCP', [
    ...'p'.codeUnits, 0, 0, ...zlib.encode(profile),
  ]);

  /// [m] as written in s15Fixed16 — what a profile's reader reads back.
  List<List<double>> fixed(List<List<double>> m) => [
    for (final row in m) [for (final v in row) (v * 65536).round() / 65536],
  ];

  double gammaLinear(int byte, double gamma) =>
      math.pow(byte / 255, gamma).toDouble();

  /// An opaque JPEG of [width] × 1 whose profile is [profile], written in
  /// [pieces] `APP2` segments put in the file last first.
  Uint8List jpegOf(
    Uint8List rgba,
    int width,
    Uint8List? profile,
    int pieces,
  ) {
    final plain = img.encodeJpg(
      img.Image.fromBytes(
        width: width,
        height: 1,
        bytes: rgba.buffer,
        numChannels: 4,
      ),
      quality: 100,
    );
    if (profile == null) {
      return plain;
    }
    final size = (profile.length / pieces).ceil();
    final segments = <int>[];
    for (var piece = pieces; piece >= 1; piece -= 1) {
      final from = (piece - 1) * size;
      final to = math.min(profile.length, piece * size);
      final payload = [
        ...'ICC_PROFILE'.codeUnits, 0, piece, pieces,
        ...profile.sublist(from, to),
      ];
      segments.addAll([0xff, 0xe2, (payload.length + 2) >> 8,
          (payload.length + 2) & 255, ...payload]);
    }
    return Uint8List.fromList([
      ...plain.sublist(0, 2),
      ...segments,
      ...plain.sublist(2),
    ]);
  }

  group('a PNG', () {
    test('🎯with a profile of Adobe RGB\'s primaries and curve: read to '
        'linear light, carried to sRGB\'s primaries, written by its '
        'curve', () {
      final file = pngOf(
        pixels,
        chunks: [iccp(matrixProfile(adobeD50, gammaCurve(adobeGamma)))],
      );
      final ours = read(file, pixels.length);

      expect(
        ours,
        expected(pixels, (v) => gammaLinear(v, adobeGamma), fixed(adobeD50)),
      );
      // Adobe RGB's 128 is 0.2196 of linear light, which sRGB writes 129.
      expect(ours.sublist(4, 8), [129, 129, 129, 255], reason: 'a mid grey');
      expect(ours.sublist(16), [0, 0, 0, 0], reason: 'a clear pixel');
    });

    test('with a profile that is sRGB\'s, its bytes are kept — every grey, '
        'its curve\'s straight foot too', () {
      for (final of in [pixels, greys]) {
        final file = pngOf(
          of,
          chunks: [
            iccp(matrixProfile(srgbD50, parametric(3, srgbCurve))),
          ],
        );

        expect(read(file, of.length), rgbaOf(of));
      }
    });

    test('with a grey profile, each channel by its grey', () {
      final file = pngOf(
        pixels,
        chunks: [
          iccp(profileOf('GRAY', [('kTRC', gammaCurve(1))])),
        ],
      );

      expect(
        read(file, pixels.length),
        expected(pixels, (v) => v / 255, srgbD50),
      );
    });

    test('with a profile of tables alone, its bytes are as stored — a '
        'profile this does not turn yet', () {
      final file = pngOf(
        pixels,
        chunks: [
          iccp(
            profileOf('RGB ', [
              ('A2B0', [...'mAB '.codeUnits, ...List.filled(28, 0)]),
            ]),
          ),
        ],
      );

      expect(read(file, pixels.length), rgbaOf(pixels));
    });

    test('🎯with a gamma alone, on sRGB\'s primaries — every grey', () {
      for (final gamma in [45455, 100000]) {
        for (final of in [pixels, greys]) {
          final file = pngOf(of, chunks: [pngChunk('gAMA', u32(gamma))]);

          expect(
            read(file, of.length),
            expected(of, (v) => gammaLinear(v, 100000 / gamma), srgbD50),
            reason: 'gAMA $gamma',
          );
        }
      }
    });

    test('saying it is sRGB\'s, its gamma is not read', () {
      final file = pngOf(
        pixels,
        chunks: [
          pngChunk('sRGB', const [0]),
          pngChunk('gAMA', u32(100000)),
        ],
      );

      expect(read(file, pixels.length), rgbaOf(pixels));
    });

    Uint8List chromaticities(List<int> of) => pngChunk('cHRM', [
      for (final v in of) ...u32(v),
    ]);

    test('with sRGB\'s chromaticities, its bytes are kept: the turn moves '
        'none past one', () {
      final file = pngOf(
        pixels,
        chunks: [
          chromaticities(srgbChromaticities),
        ],
      );

      expect(read(file, pixels.length), rgbaOf(pixels));
    });

    test('🎯with Adobe RGB\'s chromaticities and gamma: its primaries under '
        'its white carried to D50 by Bradford\'s cones — what Adobe RGB\'s '
        'profile turns, within one', () {
      final byChunks = read(
        pngOf(
          pixels,
          chunks: [
            chromaticities(adobeChromaticities),
            pngChunk('gAMA', u32((100000 / adobeGamma).round())),
          ],
        ),
        pixels.length,
      );
      final byProfile = read(
        pngOf(
          pixels,
          chunks: [iccp(matrixProfile(adobeD50, gammaCurve(adobeGamma)))],
        ),
        pixels.length,
      );

      expect(byChunks, isNot(rgbaOf(pixels)));
      for (var i = 0; i < byChunks.length; i += 1) {
        expect((byChunks[i] - byProfile[i]).abs(), lessThanOrEqualTo(1),
            reason: 'byte $i: $byChunks against $byProfile');
      }
    });

    test('with no word of its colours, its bytes are as stored', () {
      expect(read(pngOf(pixels), pixels.length), rgbaOf(pixels));
    });
  });

  group('a JPEG', () {
    test('🎯with a profile in pieces: put together in their order and '
        'turned as a PNG\'s is', () {
      final opaque = [
        for (final (r, g, b, _) in pixels) (r, g, b, 255),
      ];
      final rgba = rgbaOf(opaque);
      final stored = read(jpegOf(rgba, opaque.length, null, 1), opaque.length);
      final asStored = [
        for (var i = 0; i < stored.length; i += 4)
          (stored[i], stored[i + 1], stored[i + 2], 255),
      ];
      final profile = matrixProfile(adobeD50, gammaCurve(adobeGamma));

      for (final pieces in [1, 3]) {
        expect(
          read(jpegOf(rgba, opaque.length, profile, pieces), opaque.length),
          expected(
            asStored,
            (v) => gammaLinear(v, adobeGamma),
            fixed(adobeD50),
          ),
          reason: '$pieces piece(s)',
        );
      }
    });
  });

  // 🧪Held to the reader, not to the engine: the test engine decodes a
  // file's colours as stored (an Adobe RGB 32 grey stays 32) — it is the
  // device's, Impeller, that turns them (🔬the Surface, 2026-11-14).
  group('within the engine\'s side', () {
    /// The one picture [decodeImageFrames] holds of [file], and its pixels.
    Future<(CelPicture, Uint8List)> held(Uint8List file) async {
      final frames = await decodeImageFrames(file);
      expect(frames, hasLength(1));
      final picture = frames.single.picture;
      try {
        return (picture, await picture.straightRgba());
      } finally {
        picture.dispose();
      }
    }

    final profile = matrixProfile(adobeD50, gammaCurve(adobeGamma));

    testWidgets('🎯a still PNG or JPEG whose colours this reads is held as '
        'its file, its colours turned', (tester) async {
      final opaque = [for (final (r, g, b, _) in pixels) (r, g, b, 255)];
      await tester.runAsync(() async {
        for (final (file, width) in [
          (pngOf(pixels, chunks: [iccp(profile)]), pixels.length),
          (pngOf(pixels), pixels.length),
          (jpegOf(rgbaOf(opaque), opaque.length, profile, 1), opaque.length),
        ]) {
          final (picture, rgba) = await held(file);

          expect(picture, isA<FilePicture>());
          expect(rgba, read(file, width));
        }
      });
    });

    testWidgets('one whose profile this does not read is the engine\'s, '
        'which turns its colours', (tester) async {
      final file = pngOf(
        pixels,
        chunks: [
          iccp(
            profileOf('RGB ', [
              ('A2B0', [...'mAB '.codeUnits, ...List.filled(28, 0)]),
            ]),
          ),
        ],
      );
      await tester.runAsync(() async {
        final (picture, _) = await held(file);

        expect(picture, isA<EnginePicture>());
      });
    });
  });
}
