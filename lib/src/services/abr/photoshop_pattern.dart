import 'dart:typed_data';

import '../../models/brush_tip_mask.dart';
import 'abr_byte_reader.dart';

/// A pattern lifted from an ABR `patt` section — Photoshop's paper textures.
class PsPattern {
  const PsPattern({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.luminance,
  });

  /// The `Idnt` uuid a brush's `Txtr` descriptor joins on.
  final String id;
  final String name;
  final int width;
  final int height;

  /// Row-major 0-255 luminance, one byte per pixel.
  final Uint8List luminance;
}

/// Reads the pattern records of a `patt` section payload.
///
/// Each record is a length-prefixed block padded to a 4-byte boundary:
/// version, image mode, height/width shorts, a unicode name, a pascal uuid,
/// then a "virtual memory array list" holding one array per channel.
/// Channels are written independently and an unwritten one contributes
/// nothing, so a record is usable as soon as its first channel lands.
///
/// A record that cannot be read stops the scan rather than failing the
/// import: the tips and parameters are worth keeping without the paper.
List<PsPattern> readPatternSection(Uint8List payload) {
  final reader = AbrByteReader(payload);
  final patterns = <PsPattern>[];
  while (reader.remaining > 16) {
    final recordLength = reader.readInt32();
    if (recordLength <= 0 || recordLength > reader.remaining) {
      break;
    }
    final record = AbrByteReader(reader.readBytes(recordLength));
    try {
      final pattern = _readPatternRecord(record);
      if (pattern != null) {
        patterns.add(pattern);
      }
    } on FormatException {
      break;
    }
    // Records are padded out to a 4-byte boundary.
    while (reader.remaining > 0 && (reader.offset % 4) != 0) {
      reader.skip(1);
    }
  }
  return patterns;
}

PsPattern? _readPatternRecord(AbrByteReader record) {
  record.readInt32(); // record version
  final imageMode = record.readInt32();
  final height = record.readInt16();
  final width = record.readInt16();
  final name = record.readUnicodeString();
  final id = record.readPascalString();
  if (width <= 0 || height <= 0) {
    return null;
  }
  // Indexed-colour patterns carry a 768-byte palette before the arrays.
  if (imageMode == 2) {
    record.skip(768);
  }

  record.readInt32(); // array list version (3)
  record.readInt32(); // array list length
  record.readInt32(); // top
  record.readInt32(); // left
  record.readInt32(); // bottom
  record.readInt32(); // right
  final channelCount = record.readInt32();
  if (channelCount <= 0 || channelCount > 64) {
    return null;
  }

  // Photoshop declares a generous channel-slot count and writes only the
  // ones the image mode uses, so collect whatever actually arrives.
  final channels = <Uint8List>[];
  for (var index = 0; index < channelCount; index += 1) {
    if (record.remaining < 8) {
      break;
    }
    final written = record.readInt32();
    final length = record.readInt32();
    if (written == 0 || length <= 0) {
      continue;
    }
    if (length > record.remaining) {
      break;
    }
    final channel = AbrByteReader(record.readBytes(length));
    final depth = channel.readInt32();
    channel.skip(16); // the channel's own rectangle
    channel.readInt16(); // depth, repeated
    final compression = channel.readUint8();
    if (depth != 8) {
      // 16-bit arrays would need their own narrowing rule; skip rather than
      // guess at the payload.
      continue;
    }
    final expected = width * height;
    final Uint8List plane;
    if (compression == 0) {
      if (channel.remaining < expected) {
        continue;
      }
      plane = Uint8List.fromList(channel.readBytes(expected));
    } else if (compression == 1) {
      // Photoshop switches a pattern to RLE once it gets big — the small
      // tiles in real packs are raw and the 2048px noise one is packed, so
      // a raw-only reader silently drops exactly the heavy paper.
      try {
        plane = decodePackBitsScanlines(
          channel,
          width: width,
          height: height,
        );
      } on FormatException {
        continue;
      }
    } else {
      // 2/3 are the ZIP variants; no pattern in the wild has needed them.
      continue;
    }
    channels.add(plane);
    if (channels.length == 3) {
      break;
    }
  }
  if (channels.isEmpty) {
    return null;
  }

  final luminance = Uint8List(width * height);
  if (channels.length >= 3) {
    for (var i = 0; i < luminance.length; i += 1) {
      luminance[i] =
          ((channels[0][i] * 77 + channels[1][i] * 150 + channels[2][i] * 29) >>
                  8)
              .clamp(0, 255);
    }
  } else {
    luminance.setAll(0, channels.first);
  }
  return PsPattern(
    id: id,
    name: name,
    width: width,
    height: height,
    luminance: luminance,
  );
}

/// Builds a brush tip mask from [pattern]'s luminance.
///
/// Coverage reads the SAME way the shared tip codec reads an opaque image —
/// dark means paint — so a Photoshop paper and a Clip Studio one behave
/// alike. [invert] is the descriptor's `InvT` switch. Patterns larger than
/// [maxBrushTipMaskSide] are box-downscaled; paper tiles at that size, and a
/// 2048px pattern would otherwise cost megabytes in every saved preset.
BrushTipMask brushTipMaskFromPattern(
  PsPattern pattern, {
  required String id,
  bool invert = false,
}) {
  final side = pattern.width > pattern.height ? pattern.width : pattern.height;
  final scale = side > maxBrushTipMaskSide ? side / maxBrushTipMaskSide : 1.0;
  final maskSide = (side / scale).round().clamp(1, maxBrushTipMaskSide);
  final alpha = Uint8List(maskSide * maskSide);
  final offsetX = ((maskSide - pattern.width / scale) / 2).round();
  final offsetY = ((maskSide - pattern.height / scale) / 2).round();

  for (var y = 0; y < maskSide; y += 1) {
    final sourceTop = ((y - offsetY) * scale).floor();
    final sourceBottom = (((y - offsetY) + 1) * scale).ceil();
    if (sourceBottom <= 0 || sourceTop >= pattern.height) {
      continue;
    }
    for (var x = 0; x < maskSide; x += 1) {
      final sourceLeft = ((x - offsetX) * scale).floor();
      final sourceRight = (((x - offsetX) + 1) * scale).ceil();
      if (sourceRight <= 0 || sourceLeft >= pattern.width) {
        continue;
      }
      var total = 0;
      var count = 0;
      for (var sy = sourceTop < 0 ? 0 : sourceTop;
          sy < sourceBottom && sy < pattern.height;
          sy += 1) {
        for (var sx = sourceLeft < 0 ? 0 : sourceLeft;
            sx < sourceRight && sx < pattern.width;
            sx += 1) {
          total += pattern.luminance[sy * pattern.width + sx];
          count += 1;
        }
      }
      if (count == 0) {
        continue;
      }
      final mean = total ~/ count;
      alpha[y * maskSide + x] = invert ? mean : 255 - mean;
    }
  }
  return BrushTipMask(id: id, size: maskSide, alpha: alpha);
}
