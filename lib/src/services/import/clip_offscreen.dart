import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'clip_container.dart' show ClipFormatException;

/// What a CLIP STUDIO PAINT picture is made of before its pixels: its size,
/// the grid of 256-pixel blocks it is stored in, and how many channels a
/// pixel has.
///
/// ## Format (memory `csp-clip-format-notes` §4 — `Offscreen.Attribute`)
///
/// Big-endian: `u32 16 · u32 size of 「Parameter」 · u32 size of 「InitColor」
/// · u32 size of 「BlockSize」`, then those sections in that order, each
/// opening with `u32 character count + UTF-16BE name`.
///
///   Parameter  u32 width · u32 height · u32 grid columns · u32 grid rows ·
///              sixteen u32 — the second and third are the channel bundles
///              (1 alpha + 4 colour = a picture, 5 bytes a pixel; a sum of
///              1 = one channel: a mask)
///   InitColor  u32 · u32 fill (not 0 = where no block is, it is filled)
final class ClipOffscreenShape {
  const ClipOffscreenShape({
    required this.width,
    required this.height,
    required this.columns,
    required this.rows,
    required this.alphaChannels,
    required this.colourChannels,
    required this.fill,
  });

  /// The stored picture's size — it can be larger than the canvas: it is
  /// the blocks' grid.
  final int width;
  final int height;
  final int columns;
  final int rows;
  final int alphaChannels;
  final int colourChannels;

  /// What stands where no block was stored: 0 = nothing.
  final int fill;

  /// A picture: an alpha plane and four colour bytes a pixel (B · G · R ·
  /// unused). Every raster layer of the measured files is one.
  bool get isColour => alphaChannels == 1 && colourChannels == 4;

  /// One byte a pixel — a mask.
  bool get isSingleChannel => alphaChannels + colourChannels == 1;
}

/// The side of the square blocks a picture is stored in.
const clipBlockSide = 256;

/// [attribute] (`Offscreen.Attribute`) as the picture's shape.
ClipOffscreenShape parseClipOffscreenAttribute(Uint8List attribute) {
  final data = ByteData.sublistView(attribute);
  int u32(int at) {
    if (at + 4 > attribute.length) {
      throw const ClipFormatException('a picture\'s attribute ends early');
    }
    return data.getUint32(at);
  }

  final headerSize = u32(0);
  final parameterSize = u32(4);
  // Past a section's name: its character count, then two bytes a character.
  int pastName(int section) => section + 4 + u32(section) * 2;
  final parameter = pastName(headerSize);
  final initColour = headerSize + parameterSize;
  final fillAt = pastName(initColour) + 4;
  return ClipOffscreenShape(
    width: u32(parameter),
    height: u32(parameter + 4),
    columns: u32(parameter + 8),
    rows: u32(parameter + 12),
    alphaChannels: u32(parameter + 16 + 4),
    colourChannels: u32(parameter + 16 + 8),
    fill: u32(fillAt),
  );
}

/// The blocks an offscreen's external data holds, by block number — each
/// inflated, or null for a block stored empty.
///
/// A block record: `u32 record size · u32 19 · "BlockDataBeginChunk"
/// (UTF-16BE) · u32 block number · u32 inflated size · u32 256 · u32 256 ·
/// u32 has data · [u32 data length · u32 LE zlib length · zlib] · u32 17 ·
/// "BlockDataEndChunk"`. The records end where a section of another name
/// begins (「BlockStatus」, 「BlockCheckSum」).
Map<int, Uint8List?> clipBlocksOf(Uint8List data) {
  final view = ByteData.sublistView(data);
  final blocks = <int, Uint8List?>{};
  var at = 0;
  while (at + 8 <= data.length) {
    final recordSize = view.getUint32(at);
    final nameLength = view.getUint32(at + 4);
    if (nameLength != 19) {
      break;
    }
    if (recordSize == 0 || at + recordSize > data.length) {
      throw ClipFormatException('a block record at $at runs past its data');
    }
    final fields = at + 8 + nameLength * 2;
    final number = view.getUint32(fields);
    final hasData = view.getUint32(fields + 16);
    if (hasData == 0) {
      blocks[number] = null;
    } else {
      final zlibLength = view.getUint32(fields + 24, Endian.little);
      final zlibAt = fields + 28;
      if (zlibAt + zlibLength > at + recordSize) {
        throw ClipFormatException('block $number runs past its record');
      }
      blocks[number] = Uint8List.fromList(
        ZLibDecoder().convert(
          Uint8List.sublistView(data, zlibAt, zlibAt + zlibLength),
        ),
      );
    }
    at += recordSize;
  }
  return blocks;
}

/// A colour picture ([ClipOffscreenShape.isColour]) as straight RGBA,
/// [ClipOffscreenShape.width] × [ClipOffscreenShape.height] — or null for a
/// picture of another channel bundle, which this reader does not turn into
/// colour.
///
/// A block inflates to an alpha plane (one byte a pixel, not premultiplied)
/// followed by the colour (B · G · R · unused). Block n stands at column
/// `n mod columns`, row `n ÷ columns`. A block that is not there, or holds
/// another size than a whole block, is transparent.
Uint8List? clipColourRgba(
  ClipOffscreenShape shape,
  Map<int, Uint8List?> blocks,
) {
  if (!shape.isColour) {
    return null;
  }
  const side = clipBlockSide;
  const plane = side * side;
  final width = shape.width;
  final height = shape.height;
  final rgba = Uint8List(width * height * 4);
  blocks.forEach((number, block) {
    if (block == null || block.length != plane * 5) {
      return;
    }
    final left = (number % shape.columns) * side;
    final top = (number ~/ shape.columns) * side;
    for (var y = 0; y < side && top + y < height; y += 1) {
      for (var x = 0; x < side && left + x < width; x += 1) {
        final pixel = y * side + x;
        final colour = plane + pixel * 4;
        final out = ((top + y) * width + left + x) * 4;
        rgba[out] = block[colour + 2];
        rgba[out + 1] = block[colour + 1];
        rgba[out + 2] = block[colour];
        rgba[out + 3] = block[pixel];
      }
    }
  });
  return rgba;
}
