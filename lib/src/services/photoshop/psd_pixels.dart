import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'photoshop_byte_reader.dart';
import '../../models/import/import_warning.dart';

/// The pixel half of the document reader: channel planes in, straight RGBA
/// out. Kept apart from `psd_reader.dart` so the structure parse stays a
/// walk over records and the colour maths stays in one place.

/// Photoshop's colour modes, by the code stored in the file header.
enum PsdColorMode {
  bitmap(0),
  grayscale(1),
  indexed(2),
  rgb(3),
  cmyk(4),
  multichannel(7),
  duotone(8),
  lab(9);

  const PsdColorMode(this.code);

  final int code;

  static PsdColorMode fromCode(int code) {
    for (final mode in values) {
      if (mode.code == code) {
        return mode;
      }
    }
    throw FormatException('Unknown Photoshop colour mode $code.');
  }

  /// How many planes carry colour (the rest are alpha and masks).
  int get colorPlaneCount => switch (this) {
    PsdColorMode.bitmap ||
    PsdColorMode.grayscale ||
    PsdColorMode.indexed ||
    PsdColorMode.duotone ||
    PsdColorMode.multichannel => 1,
    PsdColorMode.rgb || PsdColorMode.lab => 3,
    PsdColorMode.cmyk => 4,
  };
}

/// Bytes one scanline of a [width]-wide plane occupies at [depth].
int psdBytesPerRow({required int width, required int depth}) =>
    depth == 1 ? (width + 7) >> 3 : width * (depth >> 3);

/// Reads one channel plane and normalises it to 8 bits per sample.
///
/// [payloadLength] is what the record said this channel occupies AFTER its
/// two-byte compression tag — the ZIP branches need it because a deflate
/// stream does not announce its own length here.
///
/// Everything above 8 bits comes down to 8: the cel store is 8-bit RGBA, so
/// a 16-bit document is not refused, it is stepped down (and the caller
/// says so out loud).
Uint8List readPsdChannelPlane(
  PhotoshopByteReader reader, {
  required int width,
  required int height,
  required int depth,
  required bool psb,
  required int payloadLength,
  required List<ImportWarning> warnings,
}) {
  if (width <= 0 || height <= 0) {
    return Uint8List(0);
  }
  final compression = reader.readUint16();
  final bytesPerRow = psdBytesPerRow(width: width, depth: depth);
  final Uint8List raw;
  switch (compression) {
    case 0:
      raw = Uint8List.fromList(reader.readBytes(bytesPerRow * height));
    case 1:
      raw = decodePackBitsScanlines(
        reader,
        bytesPerRow: bytesPerRow,
        height: height,
        scanlineCountBytes: psb ? 4 : 2,
      );
    case 2:
    case 3:
      final deflated = reader.readBytes(payloadLength - 2);
      final inflated = Uint8List.fromList(ZLibDecoder().convert(deflated));
      raw = inflated.length >= bytesPerRow * height
          ? Uint8List.sublistView(inflated, 0, bytesPerRow * height)
          : (Uint8List(bytesPerRow * height)..setAll(0, inflated));
      if (compression == 3) {
        _undoPrediction(
          raw,
          width: width,
          height: height,
          depth: depth,
          bytesPerRow: bytesPerRow,
          warnings: warnings,
        );
      }
    default:
      throw FormatException('Unknown Photoshop compression $compression.');
  }
  return psdPlaneToEightBit(
    raw,
    width: width,
    height: height,
    depth: depth,
    bytesPerRow: bytesPerRow,
  );
}

/// ZIP-with-prediction stores each sample as its delta from the one before
/// it on the same row.
void _undoPrediction(
  Uint8List raw, {
  required int width,
  required int height,
  required int depth,
  required int bytesPerRow,
  required List<ImportWarning> warnings,
}) {
  if (depth == 8) {
    for (var y = 0; y < height; y += 1) {
      final start = y * bytesPerRow;
      for (var x = 1; x < width; x += 1) {
        raw[start + x] = (raw[start + x] + raw[start + x - 1]) & 0xFF;
      }
    }
    return;
  }
  if (depth == 16) {
    final view = ByteData.sublistView(raw);
    for (var y = 0; y < height; y += 1) {
      final start = y * bytesPerRow;
      for (var x = 1; x < width; x += 1) {
        final previous = view.getUint16(start + (x - 1) * 2);
        final current = view.getUint16(start + x * 2);
        view.setUint16(start + x * 2, (current + previous) & 0xFFFF);
      }
    }
    return;
  }
  // 32-bit prediction transposes the float bytes before delta-coding them,
  // and no animation PSD has ever arrived that way. Saying so beats
  // guessing: the plane reads as noise otherwise, which looks like our bug.
  warnings.add(
    const ImportWarning(
      'psd32Bit',
      '32-bit predicted channel data is not supported.',
    ),
  );
}

Uint8List psdPlaneToEightBit(
  Uint8List raw, {
  required int width,
  required int height,
  required int depth,
  required int bytesPerRow,
}) {
  final samples = Uint8List(width * height);
  switch (depth) {
    case 1:
      for (var y = 0; y < height; y += 1) {
        final rowStart = y * bytesPerRow;
        for (var x = 0; x < width; x += 1) {
          final bit = (raw[rowStart + (x >> 3)] >> (7 - (x & 7))) & 1;
          // Bitmap mode is ink coverage: a set bit is black.
          samples[y * width + x] = bit == 1 ? 0 : 255;
        }
      }
    case 8:
      for (var y = 0; y < height; y += 1) {
        samples.setRange(
          y * width,
          y * width + width,
          raw,
          y * bytesPerRow,
        );
      }
    case 16:
      final view = ByteData.sublistView(raw);
      for (var y = 0; y < height; y += 1) {
        final rowStart = y * bytesPerRow;
        for (var x = 0; x < width; x += 1) {
          samples[y * width + x] = view.getUint16(rowStart + x * 2) >> 8;
        }
      }
    case 32:
      final view = ByteData.sublistView(raw);
      for (var y = 0; y < height; y += 1) {
        final rowStart = y * bytesPerRow;
        for (var x = 0; x < width; x += 1) {
          samples[y * width + x] = _eightBitOf(
            view.getFloat32(rowStart + x * 4),
          );
        }
      }
    default:
      throw FormatException('Unsupported Photoshop bit depth $depth.');
  }
  return samples;
}

/// A 32-bit sample [value] (1.0 = full) as 8 bits, cut to 0…255.
///
/// 🧭관제 (gpu-export-path ③, 2026-11-05): a sample that is no number
/// stands at the end it leans to — NaN and −∞ 0, +∞ 255 — where `round`
/// used to throw and take the whole import with it.
int _eightBitOf(double value) {
  if (value.isNaN || value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 255;
  }
  return (value * 255).round();
}

/// Turns colour planes into straight (un-premultiplied) RGBA8.
///
/// A mode we cannot reproduce exactly is CONVERTED rather than refused —
/// the user's rule is "follow CSP", which opens these and changes their
/// colour rather than turning them away. [warnings] is where that gets
/// said; the import window shows it beside the file.
Uint8List psdPlanesToRgba({
  required PsdColorMode mode,
  required List<Uint8List> colorPlanes,
  required Uint8List? alphaPlane,
  required int width,
  required int height,
  required Uint8List? palette,
  required List<ImportWarning> warnings,
}) {
  final pixelCount = width * height;
  final rgba = Uint8List(pixelCount * 4);
  Uint8List plane(int index) => index < colorPlanes.length
      ? colorPlanes[index]
      : Uint8List(pixelCount);

  switch (mode) {
    case PsdColorMode.rgb:
      final r = plane(0);
      final g = plane(1);
      final b = plane(2);
      for (var i = 0; i < pixelCount; i += 1) {
        rgba[i * 4] = r[i];
        rgba[i * 4 + 1] = g[i];
        rgba[i * 4 + 2] = b[i];
      }
    case PsdColorMode.grayscale:
    case PsdColorMode.duotone:
    case PsdColorMode.bitmap:
      final v = plane(0);
      for (var i = 0; i < pixelCount; i += 1) {
        rgba[i * 4] = v[i];
        rgba[i * 4 + 1] = v[i];
        rgba[i * 4 + 2] = v[i];
      }
      if (mode == PsdColorMode.duotone) {
        warnings.add(
          const ImportWarning('psdDuotone', 'Duotone read as grayscale.'),
        );
      }
    case PsdColorMode.multichannel:
      final v = plane(0);
      for (var i = 0; i < pixelCount; i += 1) {
        rgba[i * 4] = v[i];
        rgba[i * 4 + 1] = v[i];
        rgba[i * 4 + 2] = v[i];
      }
      warnings.add(
        const ImportWarning(
          'psdMultichannel',
          'Multichannel read as grayscale of its first channel.',
        ),
      );
    case PsdColorMode.indexed:
      final index = plane(0);
      if (palette == null || palette.length < 768) {
        warnings.add(
          const ImportWarning(
            'psdIndexedNoPalette',
            'Indexed colour without a palette read as grayscale.',
          ),
        );
        for (var i = 0; i < pixelCount; i += 1) {
          rgba[i * 4] = index[i];
          rgba[i * 4 + 1] = index[i];
          rgba[i * 4 + 2] = index[i];
        }
      } else {
        for (var i = 0; i < pixelCount; i += 1) {
          final entry = index[i];
          rgba[i * 4] = palette[entry];
          rgba[i * 4 + 1] = palette[256 + entry];
          rgba[i * 4 + 2] = palette[512 + entry];
        }
      }
    case PsdColorMode.cmyk:
      // Photoshop stores CMYK inverted: 255 means no ink.
      final c = plane(0);
      final m = plane(1);
      final y = plane(2);
      final k = plane(3);
      for (var i = 0; i < pixelCount; i += 1) {
        final ink = 255 - k[i];
        rgba[i * 4] = _clampByte(255 - (255 - c[i]) - ink);
        rgba[i * 4 + 1] = _clampByte(255 - (255 - m[i]) - ink);
        rgba[i * 4 + 2] = _clampByte(255 - (255 - y[i]) - ink);
      }
      warnings.add(
        const ImportWarning(
          'psdCmyk',
          'CMYK converted to RGB without a profile — colour shifts.',
        ),
      );
    case PsdColorMode.lab:
      final l = plane(0);
      final a = plane(1);
      final b = plane(2);
      for (var i = 0; i < pixelCount; i += 1) {
        final rgb = _labToRgb(l[i] * 100 / 255, a[i] - 128.0, b[i] - 128.0);
        rgba[i * 4] = rgb.$1;
        rgba[i * 4 + 1] = rgb.$2;
        rgba[i * 4 + 2] = rgb.$3;
      }
      warnings.add(
        const ImportWarning(
          'psdLab',
          'Lab converted to RGB without a profile — colour shifts.',
        ),
      );
  }

  if (alphaPlane == null) {
    for (var i = 0; i < pixelCount; i += 1) {
      rgba[i * 4 + 3] = 255;
    }
  } else {
    for (var i = 0; i < pixelCount; i += 1) {
      rgba[i * 4 + 3] = alphaPlane[i];
    }
  }
  return rgba;
}

int _clampByte(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

/// Lab is defined against a white point; sRGB against D65. The conversion
/// below uses D65 straight through, which is the "no profile" answer the
/// warning beside it announces.

(int, int, int) _labToRgb(double l, double a, double b) {
  final fy = (l + 16) / 116;
  final fx = fy + a / 500;
  final fz = fy - b / 200;
  double inverse(double t) =>
      t > 6 / 29 ? t * t * t : 3 * (6 / 29) * (6 / 29) * (t - 4 / 29);
  // D65, the white point sRGB is defined against.
  final x = 0.95047 * inverse(fx);
  final y = 1.00000 * inverse(fy);
  final z = 1.08883 * inverse(fz);
  return (
    srgbByteOf(3.2406 * x - 1.5372 * y - 0.4986 * z),
    srgbByteOf(-0.9689 * x + 1.8758 * y + 0.0415 * z),
    srgbByteOf(0.0557 * x - 0.2040 * y + 1.0570 * z),
  );
}

/// The sRGB byte of a linear [c]: 255 · sRGB's transfer of it, rounded and
/// held to [0, 255] — 12.92 · c up to 0.0031308, 1.055 · c^(1/2.4) − 0.055
/// past it.
///
/// 🗣️gpu-same-formula-Q2 (유저 2026-11-05 「기기가 달라도 같아야 한다」):
/// the power part read `math.pow`, which IEEE does not require to round
/// correctly, so another device's libm could move a byte (gpu-export-path
/// ③-3). It is found among where each byte of the power part begins
/// ([powerByteStarts]) now: comparisons alone, the same on every device.
/// 🔬Measured against `math.pow` on this build's machine (2026-11-11): the
/// same byte for every 8-bit Lab colour (2²⁴ of them) and for every linear
/// value from −0.2 to 1.2 a ten-millionth apart. ⚠️A value within a few
/// ulps of a byte's start could still land a byte from where another
/// device's `pow` puts it — the new build is the one that counts (that
/// card's ③, 「다르면 새 빌드가 정본」).
@visibleForTesting
int srgbByteOf(double c) {
  if (c <= 0.0031308) {
    return _clampByte((12.92 * c * 255).round());
  }
  var low = 0;
  var high = powerByteStarts.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (powerByteStarts[middle] <= c) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return _firstPowerByte + low;
}

/// The byte the power part of [srgbByteOf] starts at: the linear part ends
/// at 255 · 12.92 · 0.0031308 = 10.31, which rounds to it.
const _firstPowerByte = 10;

/// Where each byte from 11 to 255 begins: the linear c at which
/// 255 · (1.055 · c^(1/2.4) − 0.055) reaches v + 0.5, byte v + 1 rounded
/// up from there — ((v + 0.5) / 255 + 0.055) / 1.055 to the power 2.4, v
/// from 10 to 254. Computed once with `math.pow` and written here, so no
/// device computes them (`psd_lab_is_the_same_on_every_device_test.dart`
/// holds them to the formula, and [srgbByteOf] to them: each start is its
/// own byte, and the double just below it the byte before).
@visibleForTesting
const List<double> powerByteStarts = [
  3.1883009044305320e-3,
  3.5092593495812301e-3,
  3.8483149330964263e-3,
  4.2057480301049468e-3,
  4.5818327405283800e-3,
  4.9768372502740233e-3,
  5.3910241598063811e-3,
  5.8246507840408980e-3,
  6.2779694269141078e-3,
  6.7512276334986228e-3,
  7.2446684221289213e-3,
  7.7585304986678601e-3,
  8.2930484547623293e-3,
  8.8484529516984975e-3,
  9.4249708912660900e-3,
  1.0022825574869039e-2,
  1.0642236851973576e-2,
  1.1283421258858298e-2,
  1.1946592148522129e-2,
  1.2631959812511863e-2,
  1.3339731595349034e-2,
  1.4070112002164469e-2,
  1.4823302800086416e-2,
  1.5599503113873273e-2,
  1.6398909516233677e-2,
  1.7221716113234104e-2,
  1.8068114625156378e-2,
  1.8938294463134074e-2,
  1.9832442801866853e-2,
  2.0750744648685510e-2,
  2.1693382909216234e-2,
  2.2660538449872064e-2,
  2.3652390157379497e-2,
  2.4669114995532006e-2,
  2.5710888059345766e-2,
  2.6777882626779784e-2,
  2.7870270208169259e-2,
  2.8988220593509972e-2,
  3.0131901897720907e-2,
  3.1301480604002861e-2,
  3.2497121605402225e-2,
  3.3718988244681086e-2,
  3.4967242352587947e-2,
  3.6242044284616387e-2,
  3.7543552956333111e-2,
  3.8871925877351582e-2,
  4.0227319184021844e-2,
  4.1609887670902887e-2,
  4.3019784821079411e-2,
  4.4457162835380919e-2,
  4.5922172660557460e-2,
  4.7414964016462821e-2,
  4.8935685422292978e-2,
  5.0484484221924877e-2,
  5.2061506608397201e-2,
  5.3666897647573375e-2,
  5.5300801301023862e-2,
  5.6963360448162942e-2,
  5.8654716907673543e-2,
  6.0375011458250812e-2,
  6.2124383858694746e-2,
  6.3902972867379240e-2,
  6.5710916261124602e-2,
  6.7548350853498043e-2,
  6.9415412512566110e-2,
  7.1312236178121435e-2,
  7.3238955878405426e-2,
  7.5195704746346667e-2,
  7.7182615035334343e-2,
  7.9199818134545033e-2,
  8.1247444583840409e-2,
  8.3325624088251643e-2,
  8.5434485532067034e-2,
  8.7574156992536831e-2,
  8.9744765753210623e-2,
  9.1946438316919774e-2,
  9.4179300418418391e-2,
  9.6443477036695036e-2,
  9.8739092406966933e-2,
  1.0106627003236780e-1,
  1.0342513269534023e-1,
  1.0581580246874270e-1,
  1.0823840072668099e-1,
  1.1069304815507364e-1,
  1.1317986476196008e-1,
  1.1569896988756009e-1,
  1.1825048221409341e-1,
  1.2083451977536606e-1,
  1.2345119996613248e-1,
  1.2610063955123937e-1,
  1.2878295467455941e-1,
  1.3149826086772048e-1,
  1.3424667305863719e-1,
  1.3702830557985107e-1,
  1.3984327217668513e-1,
  1.4269168601521828e-1,
  1.4557365969008559e-1,
  1.4848930523210871e-1,
  1.5143873411576272e-1,
  1.5442205726648320e-1,
  1.5743938506781890e-1,
  1.6049082736843370e-1,
  1.6357649348896341e-1,
  1.6669649222873040e-1,
  1.6985093187232053e-1,
  1.7303992019602688e-1,
  1.7626356447416250e-1,
  1.7952197148524762e-1,
  1.8281524751807332e-1,
  1.8614349837764563e-1,
  1.8950682939101379e-1,
  1.9290534541298454e-1,
  1.9633915083172693e-1,
  1.9980834957426891e-1,
  2.0331304511189069e-1,
  2.0685334046541501e-1,
  2.1042933821039977e-1,
  2.1404114048223255e-1,
  2.1768884898113222e-1,
  2.2137256497705879e-1,
  2.2509238931453279e-1,
  2.2884842241736916e-1,
  2.3264076429332461e-1,
  2.3646951453866302e-1,
  2.4033477234264017e-1,
  2.4423663649190830e-1,
  2.4817520537484558e-1,
  2.5215057698580889e-1,
  2.5616284892931379e-1,
  2.6021211842414343e-1,
  2.6429848230738662e-1,
  2.6842203703840828e-1,
  2.7258287870275355e-1,
  2.7678110301598524e-1,
  2.8101680532745971e-1,
  2.8529008062403893e-1,
  2.8960102353374223e-1,
  2.9394972832933958e-1,
  2.9833628893188452e-1,
  3.0276079891419333e-1,
  3.0722335150426627e-1,
  3.1172403958865513e-1,
  3.1626295571577850e-1,
  3.2084019209918369e-1,
  3.2545584062075916e-1,
  3.3010999283389664e-1,
  3.3480273996660304e-1,
  3.3953417292456833e-1,
  3.4430438229418264e-1,
  3.4911345834551089e-1,
  3.5396149103522073e-1,
  3.5884857000946707e-1,
  3.6377478460673490e-1,
  3.6874022386063821e-1,
  3.7374497650267891e-1,
  3.7878913096496591e-1,
  3.8387277538289261e-1,
  3.8899599759777848e-1,
  3.9415888515946967e-1,
  3.9936152532890540e-1,
  4.0460400508064542e-1,
  4.0988641110536289e-1,
  4.1520882981230195e-1,
  4.2057134733170159e-1,
  4.2597404951718398e-1,
  4.3141702194811221e-1,
  4.3690034993191296e-1,
  4.4242411850636970e-1,
  4.4798841244188325e-1,
  4.5359331624370169e-1,
  4.5923891415412094e-1,
  4.6492529015465522e-1,
  4.7065252796817919e-1,
  4.7642071106104089e-1,
  4.8222992264514680e-1,
  4.8808024568002051e-1,
  4.9397176287483296e-1,
  4.9990455669040795e-1,
  5.0587870934119983e-1,
  5.1189430279724724e-1,
  5.1795141878610140e-1,
  5.2405013879472884e-1,
  5.3019054407139199e-1,
  5.3637271562750366e-1,
  5.4259673423945975e-1,
  5.4886268045044928e-1,
  5.5517063457223936e-1,
  5.6152067668694239e-1,
  5.6791288664875739e-1,
  5.7434734408569166e-1,
  5.8082412840126207e-1,
  5.8734331877617363e-1,
  5.9390499416998066e-1,
  6.0050923332272510e-1,
  6.0715611475655584e-1,
  6.1384571677733113e-1,
  6.2057811747619895e-1,
  6.2735339473115903e-1,
  6.3417162620860912e-1,
  6.4103288936486924e-1,
  6.4793726144769204e-1,
  6.5488481949775290e-1,
  6.6187564035012247e-1,
  6.6890980063572592e-1,
  6.7598737678278087e-1,
  6.8310844501822221e-1,
  6.9027308136910925e-1,
  6.9748136166401642e-1,
  7.0473336153441068e-1,
  7.1202915641601039e-1,
  7.1936882155013127e-1,
  7.2675243198501716e-1,
  7.3418006257715418e-1,
  7.4165178799257336e-1,
  7.4916768270813605e-1,
  7.5672782101280722e-1,
  7.6433227700891460e-1,
  7.7198112461339308e-1,
  7.7967443755901666e-1,
  7.8741228939561736e-1,
  7.9519475349129032e-1,
  8.0302190303358689e-1,
  8.1089381103069336e-1,
  8.1881055031259986e-1,
  8.2677219353225406e-1,
  8.3477881316670599e-1,
  8.4283048151823714e-1,
  8.5092727071548080e-1,
  8.5906925271453016e-1,
  8.6725649930003423e-1,
  8.7548908208628184e-1,
  8.8376707251827691e-1,
  8.9209054187280101e-1,
  9.0045956125946547e-1,
  9.0887420162175181e-1,
  9.1733453373804386e-1,
  9.2584062822264912e-1,
  9.3439255552680667e-1,
  9.4299038593969020e-1,
  9.5163418958939683e-1,
  9.6032403644392739e-1,
  9.6905999631215900e-1,
  9.7784213884480442e-1,
  9.8667053353536605e-1,
  9.9554524972107761e-1,
];
