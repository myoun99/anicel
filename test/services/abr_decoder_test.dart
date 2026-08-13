import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/services/photoshop/photoshop_byte_reader.dart';
import 'package:anicel/src/services/abr/abr_decoder.dart';
import 'package:anicel/src/services/abr/photoshop_descriptor.dart';

/// Big-endian byte builder mirroring the ABR/descriptor wire format, used
/// to construct synthetic fixture files.
class _AbrBytes {
  final BytesBuilder _builder = BytesBuilder();

  Uint8List get bytes => _builder.toBytes();
  int get length => _builder.length;

  void u8(int value) => _builder.addByte(value & 0xFF);

  void i16(int value) {
    u8(value >> 8);
    u8(value);
  }

  void i32(int value) {
    u8(value >> 24);
    u8(value >> 16);
    u8(value >> 8);
    u8(value);
  }

  void f64(double value) {
    final data = ByteData(8)..setFloat64(0, value);
    _builder.add(data.buffer.asUint8List());
  }

  void asciiChars(String value) => _builder.add(ascii.encode(value));

  void raw(List<int> value) => _builder.add(value);

  void pascal(String value) {
    u8(value.length);
    asciiChars(value);
  }

  /// Descriptor key/classID: zero length means four characters.
  void key(String value) {
    if (value.length == 4) {
      i32(0);
    } else {
      i32(value.length);
    }
    asciiChars(value);
  }

  /// Photoshop unicode string with a trailing NUL, as Photoshop writes.
  void unicode(String value) {
    i32(value.length + 1);
    for (final unit in value.codeUnits) {
      i16(unit);
    }
    i16(0);
  }

  void untf(String unit, double value) {
    asciiChars('UntF');
    asciiChars(unit);
    f64(value);
  }

  void text(String value) {
    asciiChars('TEXT');
    unicode(value);
  }
}

/// One samp-section entry (subversion 2 layout: 301-byte preamble).
void _writeSampEntry(
  _AbrBytes samp, {
  required String uuid,
  required int width,
  required int height,
  required List<int> pixels,
  bool rle = false,
  int depth = 8,
}) {
  final entry = _AbrBytes();
  entry.pascal(uuid);
  // Pad the preamble (key + coordinates + unknown) out to 301 bytes.
  entry.raw(List<int>.filled(301 - 1 - uuid.length, 0));
  entry.i32(0); // top
  entry.i32(0); // left
  entry.i32(height); // bottom
  entry.i32(width); // right
  entry.i16(depth);
  entry.u8(rle ? 1 : 0);
  if (rle) {
    final rows = <List<int>>[];
    for (var y = 0; y < height; y += 1) {
      final row = pixels.sublist(y * width, (y + 1) * width);
      // Naive PackBits: encode the whole row as one literal chunk.
      rows.add([row.length - 1, ...row]);
    }
    for (final row in rows) {
      entry.i16(row.length);
    }
    for (final row in rows) {
      entry.raw(row);
    }
  } else {
    entry.raw(pixels);
  }

  final entryBytes = entry.bytes;
  samp.i32(entryBytes.length);
  samp.raw(entryBytes);
  // Entries are padded to four-byte boundaries.
  final padding = (4 - entryBytes.length % 4) % 4;
  samp.raw(List<int>.filled(padding, 0));
}

void _write8bimSection(_AbrBytes file, String tag, Uint8List payload) {
  file.asciiChars('8BIM');
  file.asciiChars(tag);
  file.i32(payload.length);
  file.raw(payload);
}

/// Writes a `brVr` dynamics descriptor (control type + jitter).
void _writeBrVr(
  _AbrBytes desc,
  String key, {
  required int control,
  required double jitterPercent,
}) {
  desc.key(key);
  desc.asciiChars('Objc');
  desc.unicode('');
  desc.key('brVr');
  desc.i32(2);
  desc.key('bVTy');
  desc.asciiChars('long');
  desc.i32(control);
  desc.key('jitter');
  desc.untf('#Prc', jitterPercent);
}

/// Sampled + computed brush descriptor payload (`desc` section).
Uint8List _descPayload({required String sampledUuid}) {
  final desc = _AbrBytes();
  desc.i32(16); // descriptor version
  desc.unicode(''); // root class name
  desc.key('null'); // root classID
  desc.i32(1); // one item: the brush list
  desc.key('Brsh');
  desc.asciiChars('VlLs');
  desc.i32(2);

  // Brush 1: sampled, wrapped element with a name, nested tip object, and
  // preset-level dynamics (as real Photoshop writes them).
  desc.asciiChars('Objc');
  desc.unicode('');
  desc.key('null');
  desc.i32(14);
  desc.key('Nm  ');
  desc.text('Fancy Chalk');
  // Photoshop's tool-settings bundle: opacity and flow import, blend mode
  // and smoothing must NOT (they are hand settings, R26 #10).
  desc.key('toolOptions');
  desc.asciiChars('Objc');
  desc.unicode('');
  desc.key('PbTl');
  desc.i32(4);
  desc.key('Opct');
  desc.asciiChars('long');
  desc.i32(70);
  desc.key('flow');
  desc.asciiChars('long');
  desc.i32(60);
  desc.key('Md  ');
  desc.asciiChars('enum');
  desc.key('BlnM');
  desc.key('Mltp');
  desc.key('smoothing');
  desc.asciiChars('bool');
  desc.u8(1);
  desc.key('dualBrush');
  desc.asciiChars('Objc');
  desc.unicode('');
  desc.key('dualBrush');
  desc.i32(2);
  desc.key('useDualBrush');
  desc.asciiChars('bool');
  desc.u8(1);
  desc.key('Brsh');
  desc.asciiChars('Objc');
  desc.unicode('');
  desc.key('sampledBrush');
  desc.i32(2);
  desc.key('sampledData');
  desc.text('tip-two-uuid');
  desc.key('Dmtr');
  desc.untf('#Pxl', 22);
  desc.key('useTipDynamics');
  desc.asciiChars('bool');
  desc.u8(1);
  desc.key('minimumDiameter');
  desc.untf('#Prc', 65);
  _writeBrVr(desc, 'szVr', control: 2, jitterPercent: 30);
  _writeBrVr(desc, 'angleDynamics', control: 6, jitterPercent: 10);
  desc.key('usePaintDynamics');
  desc.asciiChars('bool');
  desc.u8(1);
  _writeBrVr(desc, 'opVr', control: 2, jitterPercent: 0);
  desc.key('useScatter');
  desc.asciiChars('bool');
  desc.u8(1);
  desc.key('Cnt ');
  desc.asciiChars('doub');
  desc.f64(3);
  desc.key('bothAxes');
  desc.asciiChars('bool');
  desc.u8(1);
  _writeBrVr(desc, 'scatterDynamics', control: 0, jitterPercent: 200);
  desc.key('Brsh');
  desc.asciiChars('Objc');
  desc.unicode('');
  desc.key('sampledBrush');
  desc.i32(6);
  desc.key('sampledData');
  desc.text(sampledUuid);
  desc.key('Dmtr');
  desc.untf('#Pxl', 44);
  desc.key('Spcn');
  desc.untf('#Prc', 25);
  desc.key('Angl');
  desc.untf('#Ang', -60);
  desc.key('Rndn');
  desc.untf('#Prc', 40);
  desc.key('Intr');
  desc.asciiChars('bool');
  desc.u8(1);

  // Brush 2: computed round brush, carrying a paper texture.
  desc.asciiChars('Objc');
  desc.unicode('');
  desc.key('null');
  desc.i32(6);
  desc.key('Nm  ');
  desc.text('Soft Round 16');
  desc.key('useTexture');
  desc.asciiChars('bool');
  desc.u8(1);
  desc.key('Txtr');
  desc.asciiChars('Objc');
  desc.unicode('');
  desc.key('Ptrn');
  desc.i32(2);
  desc.key('Nm  ');
  desc.text('packed paper');
  desc.key('Idnt');
  desc.text('pattern-rle-uuid');
  desc.key('textureScale');
  desc.untf('#Prc', 150);
  desc.key('textureDepth');
  desc.untf('#Prc', 40);
  desc.key('Brsh');
  desc.asciiChars('Objc');
  desc.unicode('');
  desc.key('computedBrush');
  desc.i32(5);
  desc.key('Dmtr');
  desc.untf('#Pxl', 16);
  desc.key('Hrdn');
  desc.untf('#Prc', 80);
  desc.key('Spcn');
  desc.untf('#Prc', 30);
  desc.key('Angl');
  desc.untf('#Ang', 0);
  desc.key('Rndn');
  desc.untf('#Prc', 100);

  return desc.bytes;
}

/// A 6x4 gradient tip (non-square, to exercise padding).
final List<int> _tipOnePixels = [
  for (var index = 0; index < 24; index += 1) (index * 10 + 5) % 256,
];

/// A 4x4 uniform tip.
final List<int> _tipTwoPixels = List<int>.filled(16, 200);

/// Writes one `patt` pattern record: header, name, uuid, then a virtual
/// memory array per channel. [rle] packs the planes the way Photoshop does
/// once a pattern gets large.
void _writePatternRecord(
  _AbrBytes patt, {
  required String name,
  required String id,
  required int width,
  required int height,
  required List<int> Function(int channel) plane,
  int channels = 3,
  bool rle = false,
}) {
  final record = _AbrBytes();
  record.i32(1); // record version
  record.i32(3); // image mode: RGB
  record.i16(height);
  record.i16(width);
  record.unicode(name);
  record.pascal(id);

  record.i32(3); // array list version
  record.i32(0); // array list length (unread)
  record.i32(0); // top
  record.i32(0); // left
  record.i32(height);
  record.i32(width);
  record.i32(24); // declared channel slots, as Photoshop writes them

  for (var channel = 0; channel < 24; channel += 1) {
    if (channel >= channels) {
      record.i32(0); // written = false
      record.i32(0); // length
      continue;
    }
    final body = _AbrBytes();
    body.i32(8); // pixel depth
    body.i32(0);
    body.i32(0);
    body.i32(height);
    body.i32(width);
    body.i16(8); // pixel depth, repeated
    body.u8(rle ? 1 : 0);
    final pixels = plane(channel);
    if (rle) {
      // One literal run per scanline: a 1-byte count then the row.
      for (var y = 0; y < height; y += 1) {
        body.i16(width + 1);
      }
      for (var y = 0; y < height; y += 1) {
        body.u8(width - 1); // literal run of `width` bytes
        body.raw(pixels.sublist(y * width, (y + 1) * width));
      }
    } else {
      body.raw(pixels);
    }
    final bytes = body.bytes;
    record.i32(1); // written
    record.i32(bytes.length);
    record.raw(bytes);
  }

  final recordBytes = record.bytes;
  patt.i32(recordBytes.length);
  patt.raw(recordBytes);
  while (patt.bytes.length % 4 != 0) {
    patt.u8(0);
  }
}

Uint8List _fixtureAbr({
  bool includeDesc = true,
  bool corruptDesc = false,
  bool patternsMissing = false,
}) {
  final samp = _AbrBytes();
  _writeSampEntry(
    samp,
    uuid: 'tip-one-uuid',
    width: 6,
    height: 4,
    pixels: _tipOnePixels,
    rle: true,
  );
  _writeSampEntry(
    samp,
    uuid: 'tip-two-uuid',
    width: 4,
    height: 4,
    pixels: _tipTwoPixels,
  );

  // Two patterns: a raw one that nothing references, and the RLE one the
  // computed brush asks for by uuid.
  final patt = _AbrBytes();
  _writePatternRecord(
    patt,
    name: 'plain paper',
    id: 'pattern-raw-uuid',
    width: 4,
    height: 4,
    plane: (_) => List<int>.filled(16, 90),
  );
  _writePatternRecord(
    patt,
    name: 'packed paper',
    id: 'pattern-rle-uuid',
    width: 4,
    height: 4,
    rle: true,
    // Channel 0 is the only one that differs, so a decoder that ignored the
    // green/blue planes would produce a different luminance.
    plane: (channel) =>
        List<int>.generate(16, (i) => channel == 0 ? (i * 16) % 256 : 0),
  );

  final file = _AbrBytes();
  file.i16(6); // version
  file.i16(2); // subversion
  _write8bimSection(file, 'samp', samp.bytes);
  if (!patternsMissing) {
    _write8bimSection(file, 'patt', patt.bytes);
  }
  if (includeDesc) {
    final payload = corruptDesc
        ? Uint8List.fromList([0, 0, 0, 99, 1, 2, 3])
        : _descPayload(sampledUuid: 'tip-one-uuid');
    _write8bimSection(file, 'desc', payload);
  }
  return file.bytes;
}

void main() {
  group('decodeAbrBrushFile', () {
    test('imports sampled and computed brushes with their parameters', () {
      final result = decodeAbrBrushFile(_fixtureAbr(), sourceName: 'fixture');

      expect(result.warnings, isEmpty);
      // Two desc brushes; the second samp tip is consumed as the dual
      // texture, so no orphan preset is created for it.
      expect(result.presets, hasLength(2));

      final chalk = result.presets.firstWhere((p) => p.name == 'Fancy Chalk');
      expect(chalk.id.value, 'abr-tip-one-uuid');
      expect(chalk.settings.size, 44.0);
      expect(chalk.settings.spacing, 0.25);
      expect(chalk.settings.angleDegrees, 120.0); // -60 normalized into 0-180
      expect(chalk.settings.roundness, 0.4);
      expect(chalk.settings.tipMask, isNotNull);
      // Preset-level dynamics: szVr control 2 = pen pressure, minimum
      // diameter, jitters, direction-following angle, scatter block.
      // BB-3: szVr pen pressure + minimum diameter 65% = the size curve
      // (0, 0.65)-(1, 1); opVr pen pressure = the identity opacity curve
      // (prVr is absent, so the flow channel stays pressure-free).
      expect(
        chalk.settings.sizePressureCurve,
        BrushPressureCurve.linearFrom(0.65),
      );
      expect(chalk.settings.sizeJitter, closeTo(0.3, 1e-9));
      expect(
        chalk.settings.opacityPressureCurve,
        BrushPressureCurve.identity(),
      );
      expect(chalk.settings.flowPressureCurve, isNull);
      expect(chalk.settings.rotationMode, BrushTipRotationMode.direction);
      expect(chalk.settings.angleJitter, closeTo(0.1, 1e-9));
      expect(chalk.settings.scatterRadiusRatio, closeTo(2.0, 1e-9));
      expect(chalk.settings.scatterCount, 3);
      expect(chalk.settings.scatterBothAxes, isTrue);
      // Dual brush: the second tip joins by uuid and scales relative to
      // the primary diameter (22 / 44).
      expect(chalk.settings.dualMask, isNotNull);
      expect(chalk.settings.dualMask!.id, 'abr-tip-two-uuid');
      expect(chalk.settings.dualMaskScale, closeTo(0.5, 1e-9));

      // Photoshop keeps opacity and flow in the `toolOptions` bundle; both
      // are preset fields on this engine, so both import.
      expect(chalk.settings.opacity, closeTo(0.7, 1e-9));
      expect(chalk.settings.flow, closeTo(0.6, 1e-9));

      final round = result.presets.firstWhere((p) => p.name == 'Soft Round 16');
      expect(round.settings.tipMask, isNull);
      expect(round.settings.size, 16.0);
      expect(round.settings.hardness, closeTo(0.8, 1e-9));
      expect(round.settings.spacing, closeTo(0.3, 1e-9));
      // No toolOptions on this one: opacity and flow fall back to full.
      expect(round.settings.opacity, 1.0);
      expect(round.settings.flow, 1.0);
      // Paper texture joins the `patt` section by uuid; the referenced
      // pattern is RLE-packed, which is what Photoshop writes once a
      // pattern gets large.
      expect(round.settings.textureMask, isNotNull);
      expect(round.settings.textureMask!.id, 'abr-pattern-pattern-rle-uuid');
      expect(round.settings.textureMask!.size, 4);
      expect(round.settings.textureScale, closeTo(1.5, 1e-9));
      // Photoshop's texture depth is Clip Studio's density.
      expect(round.settings.textureDensity, closeTo(0.4, 1e-9));
      // Coverage reads dark-means-paint, over the luminance of all three
      // channels: pixel 0 is black -> full, and the ramp darkens coverage.
      final paper = round.settings.textureMask!;
      expect(paper.alpha[0], 255);
      expect(paper.alpha[1], lessThan(255));
      expect(paper.alpha[15], lessThan(paper.alpha[1]));
      // The brush that asked for no texture keeps none.
      expect(chalk.settings.textureMask, isNull);
    });

    test('a texture reference with no embedded pattern warns', () {
      // Real packs ship brushes whose paper was never embedded.
      final result = decodeAbrBrushFile(
        _fixtureAbr(patternsMissing: true),
        sourceName: 'fixture',
      );
      final round = result.presets.firstWhere((p) => p.name == 'Soft Round 16');

      expect(round.settings.textureMask, isNull);
      expect(
        result.warnings.any((w) => w.contains('not embedded in this file')),
        isTrue,
      );
    });

    test('pads non-square tips to a centered square mask', () {
      final result = decodeAbrBrushFile(_fixtureAbr(), sourceName: 'fixture');
      final mask = result.presets
          .firstWhere((p) => p.name == 'Fancy Chalk')
          .settings
          .tipMask!;

      // 6x4 source -> 6x6 mask with one empty row above and below.
      expect(mask.size, 6);
      for (var x = 0; x < 6; x += 1) {
        expect(mask.alpha[x], 0); // padded top row
        expect(mask.alpha[5 * 6 + x], 0); // padded bottom row
      }
      for (var y = 0; y < 4; y += 1) {
        for (var x = 0; x < 6; x += 1) {
          expect(mask.alpha[(y + 1) * 6 + x], _tipOnePixels[y * 6 + x]);
        }
      }
    });

    test('RLE and raw tips decode to the exact pixel bytes', () {
      final result = decodeAbrBrushFile(_fixtureAbr(), sourceName: 'fixture');
      // The raw (uniform) tip is consumed as the chalk brush's dual mask.
      final uniform = result.presets
          .firstWhere((p) => p.name == 'Fancy Chalk')
          .settings
          .dualMask!;
      expect(uniform.alpha, everyElement(200));
    });

    test('imports tips with default settings when desc is corrupt', () {
      final result = decodeAbrBrushFile(
        _fixtureAbr(corruptDesc: true),
        sourceName: 'fixture',
      );

      expect(result.warnings, isNotEmpty);
      expect(result.presets, hasLength(2));
      expect(result.presets.first.name, 'fixture tip 1');
      expect(result.presets.first.settings.tipMask, isNotNull);
    });

    test('imports tips when there is no desc section at all', () {
      final result = decodeAbrBrushFile(
        _fixtureAbr(includeDesc: false),
        sourceName: 'fixture',
      );
      expect(result.presets, hasLength(2));
      expect(result.presets.every((p) => p.settings.tipMask != null), isTrue);
    });

    test('rejects legacy and non-ABR files with clear errors', () {
      final legacy = _AbrBytes()
        ..i16(1)
        ..i16(0);
      expect(
        () => decodeAbrBrushFile(legacy.bytes, sourceName: 'old'),
        throwsA(isA<AbrDecodeException>()),
      );
      expect(
        () => decodeAbrBrushFile(
          Uint8List.fromList([0x50, 0x4B, 3, 4, 0, 0, 0, 0]),
          sourceName: 'zip',
        ),
        throwsA(isA<AbrDecodeException>()),
      );
      expect(
        () => decodeAbrBrushFile(Uint8List(2), sourceName: 'tiny'),
        throwsA(isA<AbrDecodeException>()),
      );
    });

    test('brushes sharing one sampled tip get unique preset ids', () {
      // Real packs commonly define several brushes as variants of the SAME
      // tip bitmap. Duplicate preset ids crashed the preset chips (duplicate
      // widget keys), so the decoder must de-collide them deterministically.
      final desc = _AbrBytes();
      desc.i32(16);
      desc.unicode('');
      desc.key('null');
      desc.i32(1);
      desc.key('Brsh');
      desc.asciiChars('VlLs');
      desc.i32(2);
      for (final name in ['Variant A', 'Variant B']) {
        desc.asciiChars('Objc');
        desc.unicode('');
        desc.key('null');
        desc.i32(2);
        desc.key('Nm  ');
        desc.text(name);
        desc.key('Brsh');
        desc.asciiChars('Objc');
        desc.unicode('');
        desc.key('sampledBrush');
        desc.i32(2);
        desc.key('sampledData');
        desc.text('shared-tip');
        desc.key('Dmtr');
        desc.untf('#Pxl', 20);
      }

      final samp = _AbrBytes();
      _writeSampEntry(
        samp,
        uuid: 'shared-tip',
        width: 2,
        height: 2,
        pixels: List<int>.filled(4, 7),
      );
      final file = _AbrBytes()
        ..i16(6)
        ..i16(2);
      _write8bimSection(file, 'samp', samp.bytes);
      _write8bimSection(file, 'desc', desc.bytes);

      final result = decodeAbrBrushFile(file.bytes, sourceName: 'fixture');
      expect(result.presets, hasLength(2));
      expect(result.presets[0].id.value, 'abr-shared-tip');
      expect(result.presets[1].id.value, 'abr-shared-tip-2');
      expect(result.presets[0].name, 'Variant A');
      expect(result.presets[1].name, 'Variant B');
      // Both variants carry the shared tip bitmap.
      expect(result.presets[0].settings.tipMask, isNotNull);
      expect(
        result.presets[1].settings.tipMask,
        result.presets[0].settings.tipMask,
      );

      // Decoding the same file again yields the same ids (re-import
      // replaces instead of duplicating).
      final again = decodeAbrBrushFile(file.bytes, sourceName: 'fixture');
      expect(
        again.presets.map((p) => p.id.value),
        result.presets.map((p) => p.id.value),
      );
    });

    test('skips unsupported 16-bit tips with a warning', () {
      final samp = _AbrBytes();
      _writeSampEntry(
        samp,
        uuid: 'deep-tip',
        width: 2,
        height: 2,
        pixels: List<int>.filled(8, 1),
        depth: 16,
      );
      _writeSampEntry(
        samp,
        uuid: 'ok-tip',
        width: 2,
        height: 2,
        pixels: List<int>.filled(4, 9),
      );
      final file = _AbrBytes()
        ..i16(6)
        ..i16(2);
      _write8bimSection(file, 'samp', samp.bytes);

      final result = decodeAbrBrushFile(file.bytes, sourceName: 'fixture');
      expect(result.warnings.single, contains('16-bit'));
      expect(result.presets.single.id.value, 'abr-ok-tip');
    });
  });

  group('photoshop descriptor parser', () {
    test('round-trips the fixture descriptor structure', () {
      final reader = PhotoshopByteReader(_descPayload(sampledUuid: 'u'));
      final descriptor = readVersionedDescriptor(reader);

      final brushes = descriptor['Brsh'] as List;
      expect(brushes, hasLength(2));
      final sampled = (brushes.first as PsDescriptor);
      expect(sampled.textValue('Nm  '), 'Fancy Chalk');
      final tip = sampled.childDescriptor('Brsh')!;
      expect(tip.classId, 'sampledBrush');
      expect(tip.textValue('sampledData'), 'u');
      expect(tip.numberValue('Dmtr'), 44.0);
      expect(tip['Intr'], isTrue);
    });

    test('fails cleanly on unknown value types', () {
      final bytes = _AbrBytes()
        ..i32(16)
        ..unicode('')
        ..key('null')
        ..i32(1)
        ..key('Wht?')
        ..asciiChars('XXXX');
      expect(
        () => readVersionedDescriptor(PhotoshopByteReader(bytes.bytes)),
        throwsFormatException,
      );
    });
  });
}
