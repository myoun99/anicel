import 'dart:typed_data';

import 'photoshop_byte_reader.dart';
import 'psd_pixels.dart';

/// Reads Photoshop documents — `.psd` and its large sibling `.psb`.
///
/// WHY THIS EXISTS. Nothing in the app could open a PSD. The extension was
/// not in the kind table, so a dropped file went down the still-image path
/// and died in `instantiateImageCodec`; the one platform where it seemed to
/// work was iPadOS, where Apple's picker let `com.adobe.photoshop-image`
/// through the `public.image` umbrella and Apple's decoder answered with the
/// file's COMPATIBILITY COMPOSITE — which is why the layers arrived merged.
/// A format that opens on one platform by accident is worse than one that
/// does not open at all, so the document is read here, the same way, on
/// every platform.
///
/// Two ways in, matching the two things a PSD can be to this app:
///   - MERGE — [PsdDocument.composite], the flattened picture Photoshop
///     stores for compatibility. It carries adjustment layers and layer
///     effects already applied, so it is the ACCURATE reading.
///   - EXPAND — [PsdDocument.layers], the stack itself, which trades those
///     effects for structure.
///
/// The reader is deliberately unaware of our layer model: it reports what
/// the file says (bottom-first, with the group rows the file uses) and the
/// import planner decides what that becomes.

/// What a record is: a picture, or one of the two rows Photoshop uses to
/// bracket a group.
enum PsdLayerRole {
  /// An ordinary layer — pixels, text, shape, smart object; all of them
  /// arrive as their rendered pixels, which is all we can keep.
  raster,

  /// The folder row itself. It sits ABOVE its members in the file's
  /// bottom-first order and carries the group's name, blend and opacity.
  groupOpen,

  /// The hidden `</Layer group>` record that marks where a group's members
  /// begin. Photoshop writes it; nobody sees it.
  groupClose,
}

/// One record from the layer section.
class PsdLayer {
  const PsdLayer({
    required this.name,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.opacity,
    required this.visible,
    required this.clipping,
    required this.blendKey,
    required this.role,
    required this.pixels,
    required this.adjustmentKey,
  });

  final String name;
  final int left;
  final int top;
  final int right;
  final int bottom;

  /// 0–255, as the file stores it.
  final int opacity;
  final bool visible;

  /// Clipped to the layer below. We do not map this yet — the flag is
  /// carried so the importer can say so rather than silently flattening the
  /// distinction.
  final bool clipping;

  /// Photoshop's four-character blend code (`norm`, `mul `, `pass`…).
  final String blendKey;
  final PsdLayerRole role;

  /// Straight RGBA8 covering [width]×[height], mask already multiplied into
  /// alpha. Null when the record has no picture (an empty layer, a group
  /// row, an adjustment).
  final Uint8List? pixels;

  /// The additional-info key that makes this an adjustment or fill layer
  /// (`levl`, `curv`, `SoCo`…), or null for an ordinary layer. We cannot
  /// reproduce these, so the importer names them and moves on.
  final String? adjustmentKey;

  int get width => right - left;
  int get height => bottom - top;
  bool get hasPixels => pixels != null && width > 0 && height > 0;
  bool get isGroupRow => role != PsdLayerRole.raster;
  bool get isPassThrough => blendKey == 'pass';
}

/// A document, read.
class PsdDocument {
  const PsdDocument({
    required this.width,
    required this.height,
    required this.depth,
    required this.colorMode,
    required this.isPsb,
    required this.composite,
    required this.layers,
    required this.warnings,
  });

  final int width;
  final int height;
  final int depth;
  final PsdColorMode colorMode;
  final bool isPsb;

  /// Straight RGBA8 of [width]×[height], or null when the file carries no
  /// composite (Photoshop can be told not to write one) or the caller did
  /// not ask for it.
  final Uint8List? composite;

  /// Bottom-first, exactly as the file orders them.
  final List<PsdLayer> layers;

  /// Everything the import window should say out loud: colour conversions,
  /// blend modes we do not have, adjustments dropped.
  final List<String> warnings;
}

/// The four bytes every Photoshop document starts with.
const List<int> _psdSignature = [0x38, 0x42, 0x50, 0x53]; // '8BPS'

/// Whether [bytes] begins like a Photoshop document. Cheap enough to run on
/// every file the image decoder is handed.
bool looksLikePsdBytes(Uint8List bytes) {
  if (bytes.length < 4) {
    return false;
  }
  for (var i = 0; i < 4; i += 1) {
    if (bytes[i] != _psdSignature[i]) {
      return false;
    }
  }
  return true;
}

/// Additional-info keys that mean "this layer is an instruction, not a
/// picture" — adjustments and fills. Photoshop renders them into the
/// composite; expanding the stack leaves them behind.
const Set<String> _adjustmentKeys = {
  'levl', 'curv', 'brit', 'blnc', 'hue ', 'hue2', 'selc', 'thrs', 'nvrt',
  'post', 'mixr', 'clrL', 'vibA', 'blwh', 'phfl', 'grdm', 'expA', 'SoCo',
  'GdFl', 'PtFl', 'brst',
};

/// Additional-info keys whose length field is 8 bytes wide in a `.psb`.
const Set<String> _psbLongKeys = {
  'LMsk', 'Lr16', 'Lr32', 'Layr', 'Mt16', 'Mt32', 'Mtrn', 'Alph', 'FMsk',
  'lnk2', 'FEid', 'FXid', 'PxSD', 'cinf',
};

/// Reads [bytes] as a Photoshop document.
///
/// [withLayers] and [withComposite] exist because the two readings cost
/// wildly different amounts: a thumbnail wants the composite of a 200MB file
/// and has no use for its 80 layers.
PsdDocument readPsdDocument(
  Uint8List bytes, {
  bool withLayers = true,
  bool withComposite = true,
}) {
  final reader = PhotoshopByteReader(bytes);
  if (!looksLikePsdBytes(bytes)) {
    throw const FormatException('Not a Photoshop document.');
  }
  reader.skip(4);
  final version = reader.readUint16();
  if (version != 1 && version != 2) {
    throw FormatException('Unknown Photoshop document version $version.');
  }
  final psb = version == 2;
  reader.skip(6); // Reserved, always zero.
  final channelCount = reader.readUint16();
  final height = reader.readUint32();
  final width = reader.readUint32();
  final depth = reader.readUint16();
  final colorMode = PsdColorMode.fromCode(reader.readUint16());
  final warnings = <String>[];
  if (depth == 16 || depth == 32) {
    warnings.add('$depth-bit document stepped down to 8-bit.');
  }

  // Colour mode data — the palette lives here and nothing else we want.
  final colorDataLength = reader.readUint32();
  Uint8List? palette;
  if (colorMode == PsdColorMode.indexed && colorDataLength >= 768) {
    palette = Uint8List.fromList(reader.readBytes(colorDataLength));
  } else {
    reader.skip(colorDataLength);
  }

  // Image resources — thumbnails, guides, print settings. None of it ours.
  reader.skip(reader.readUint32());

  final layerMaskLength = psb ? reader.readUint64() : reader.readUint32();
  final layerMaskEnd = reader.offset + layerMaskLength;
  var layers = const <PsdLayer>[];
  var mergedAlpha = false;
  if (layerMaskLength > 0) {
    final layerInfoLength = psb ? reader.readUint64() : reader.readUint32();
    final layerInfoEnd = reader.offset + layerInfoLength;
    if (layerInfoLength > 0) {
      final declaredCount = reader.readInt16();
      mergedAlpha = declaredCount < 0;
      final count = declaredCount.abs();
      if (withLayers) {
        layers = _readLayers(
          reader,
          count: count,
          psb: psb,
          depth: depth,
          colorMode: colorMode,
          palette: palette,
          warnings: warnings,
        );
      }
    }
    reader.offset = layerInfoEnd < bytes.length ? layerInfoEnd : bytes.length;
  }
  reader.offset = layerMaskEnd < bytes.length ? layerMaskEnd : bytes.length;

  Uint8List? composite;
  if (withComposite && !reader.isAtEnd) {
    composite = _readComposite(
      reader,
      width: width,
      height: height,
      depth: depth,
      psb: psb,
      channelCount: channelCount,
      colorMode: colorMode,
      palette: palette,
      mergedAlpha: mergedAlpha,
      warnings: warnings,
    );
  }

  return PsdDocument(
    width: width,
    height: height,
    depth: depth,
    colorMode: colorMode,
    isPsb: psb,
    composite: composite,
    layers: layers,
    warnings: warnings,
  );
}

/// One layer's record, before its pixels are read.
class _LayerRecord {
  _LayerRecord({
    required this.name,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.opacity,
    required this.visible,
    required this.clipping,
    required this.blendKey,
    required this.role,
    required this.channels,
    required this.adjustmentKey,
    required this.mask,
  });

  final String name;
  final int left;
  final int top;
  final int right;
  final int bottom;
  final int opacity;
  final bool visible;
  final bool clipping;
  final String blendKey;
  final PsdLayerRole role;

  /// (channel id, declared byte length) in the order the file stores them.
  final List<(int, int)> channels;
  final String? adjustmentKey;
  final _MaskRecord? mask;

  int get width => right - left;
  int get height => bottom - top;
}

class _MaskRecord {
  _MaskRecord({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.defaultColor,
    required this.disabled,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;
  final int defaultColor;

  /// Photoshop keeps a mask it is not applying. Baking a disabled mask would
  /// erase pixels the user can still see in Photoshop.
  final bool disabled;

  int get width => right - left;
  int get height => bottom - top;
}

List<PsdLayer> _readLayers(
  PhotoshopByteReader reader, {
  required int count,
  required bool psb,
  required int depth,
  required PsdColorMode colorMode,
  required Uint8List? palette,
  required List<String> warnings,
}) {
  final records = <_LayerRecord>[
    for (var i = 0; i < count; i += 1) _readLayerRecord(reader, psb: psb),
  ];
  final layers = <PsdLayer>[];
  for (final record in records) {
    layers.add(
      _readLayerPixels(
        reader,
        record: record,
        psb: psb,
        depth: depth,
        colorMode: colorMode,
        palette: palette,
        warnings: warnings,
      ),
    );
  }
  return layers;
}

_LayerRecord _readLayerRecord(
  PhotoshopByteReader reader, {
  required bool psb,
}) {
  final top = reader.readInt32();
  final left = reader.readInt32();
  final bottom = reader.readInt32();
  final right = reader.readInt32();
  final channelCount = reader.readUint16();
  final channels = <(int, int)>[
    for (var i = 0; i < channelCount; i += 1)
      (reader.readInt16(), psb ? reader.readUint64() : reader.readUint32()),
  ];
  reader.skip(4); // '8BIM'
  final blendKey = reader.readAscii(4);
  final opacity = reader.readUint8();
  final clipping = reader.readUint8() != 0;
  final flags = reader.readUint8();
  reader.skip(1); // Filler.
  final extraLength = reader.readUint32();
  final extraEnd = reader.offset + extraLength;

  _MaskRecord? mask;
  final maskLength = reader.readUint32();
  if (maskLength > 0) {
    final maskEnd = reader.offset + maskLength;
    final maskTop = reader.readInt32();
    final maskLeft = reader.readInt32();
    final maskBottom = reader.readInt32();
    final maskRight = reader.readInt32();
    final defaultColor = reader.readUint8();
    final maskFlags = reader.readUint8();
    mask = _MaskRecord(
      left: maskLeft,
      top: maskTop,
      right: maskRight,
      bottom: maskBottom,
      defaultColor: defaultColor,
      disabled: (maskFlags & 0x02) != 0,
    );
    reader.offset = maskEnd;
  }
  reader.skip(reader.readUint32()); // Blending ranges.

  // The Pascal name is padded so the whole field is a multiple of four.
  final nameStart = reader.offset;
  var name = reader.readPascalString();
  final nameLength = reader.offset - nameStart;
  final namePadding = (4 - (nameLength % 4)) % 4;
  reader.skip(namePadding);

  String? adjustmentKey;
  var role = PsdLayerRole.raster;
  while (reader.offset + 12 <= extraEnd) {
    final signature = reader.readAscii(4);
    if (signature != '8BIM' && signature != '8B64') {
      // Not an additional-info block: the rest is padding or something this
      // reader does not know. Stopping beats walking off the record.
      break;
    }
    final key = reader.readAscii(4);
    final blockLength = psb && _psbLongKeys.contains(key)
        ? reader.readUint64()
        : reader.readUint32();
    final blockStart = reader.offset;
    final blockEnd = blockStart + blockLength;
    if (_adjustmentKeys.contains(key)) {
      adjustmentKey = key;
    } else if (key == 'luni') {
      // The unicode name is the real one; the Pascal name above is a
      // MacRoman truncation Photoshop keeps for very old readers.
      name = reader.readUnicodeString();
    } else if (key == 'lsct' && blockLength >= 4) {
      final type = reader.readUint32();
      role = switch (type) {
        1 || 2 => PsdLayerRole.groupOpen,
        3 => PsdLayerRole.groupClose,
        _ => PsdLayerRole.raster,
      };
    }
    reader.offset = blockEnd <= extraEnd ? blockEnd : extraEnd;
    // Blocks are padded to an even length in practice; a stray odd byte
    // would otherwise desynchronise the walk.
    if (reader.offset < extraEnd && (blockLength & 1) == 1) {
      reader.skip(1);
    }
  }
  reader.offset = extraEnd;

  return _LayerRecord(
    name: name,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    opacity: opacity,
    // Flag bit 1 means HIDDEN. Reading it as "visible" hides every layer
    // that is showing, which is the kind of inversion that looks like a
    // decode bug.
    visible: (flags & 0x02) == 0,
    clipping: clipping,
    blendKey: blendKey,
    role: role,
    channels: channels,
    adjustmentKey: adjustmentKey,
    mask: mask,
  );
}

PsdLayer _readLayerPixels(
  PhotoshopByteReader reader, {
  required _LayerRecord record,
  required bool psb,
  required int depth,
  required PsdColorMode colorMode,
  required Uint8List? palette,
  required List<String> warnings,
}) {
  final colorPlanes = <int, Uint8List>{};
  Uint8List? alpha;
  Uint8List? maskPlane;
  for (final (id, byteLength) in record.channels) {
    final planeStart = reader.offset;
    final isMask = id == -2;
    final planeWidth = isMask ? (record.mask?.width ?? 0) : record.width;
    final planeHeight = isMask ? (record.mask?.height ?? 0) : record.height;
    if (byteLength < 2 || planeWidth <= 0 || planeHeight <= 0) {
      reader.offset = planeStart + byteLength;
      continue;
    }
    if (id == -3) {
      // A vector mask is a path, not a plane. Rasterising one needs a path
      // filler we do not have; the merged reading is the answer when it
      // matters.
      reader.offset = planeStart + byteLength;
      warnings.add('${record.name}: vector mask ignored.');
      continue;
    }
    final plane = readPsdChannelPlane(
      reader,
      width: planeWidth,
      height: planeHeight,
      depth: depth,
      psb: psb,
      payloadLength: byteLength,
      warnings: warnings,
    );
    if (id >= 0) {
      colorPlanes[id] = plane;
    } else if (id == -1) {
      alpha = plane;
    } else if (isMask) {
      maskPlane = plane;
    }
    reader.offset = planeStart + byteLength;
  }

  Uint8List? pixels;
  if (record.width > 0 && record.height > 0 && colorPlanes.isNotEmpty) {
    pixels = psdPlanesToRgba(
      mode: colorMode,
      colorPlanes: [
        for (var i = 0; i < colorMode.colorPlaneCount; i += 1)
          colorPlanes[i] ?? Uint8List(record.width * record.height),
      ],
      alphaPlane: alpha,
      width: record.width,
      height: record.height,
      palette: palette,
      warnings: warnings,
    );
    final mask = record.mask;
    if (mask != null && maskPlane != null && !mask.disabled) {
      applyPsdMaskToAlpha(
        pixels,
        layerLeft: record.left,
        layerTop: record.top,
        layerWidth: record.width,
        layerHeight: record.height,
        mask: maskPlane,
        maskLeft: mask.left,
        maskTop: mask.top,
        maskWidth: mask.width,
        maskHeight: mask.height,
        defaultColor: mask.defaultColor,
      );
    }
  }

  return PsdLayer(
    name: record.name,
    left: record.left,
    top: record.top,
    right: record.right,
    bottom: record.bottom,
    opacity: record.opacity,
    visible: record.visible,
    clipping: record.clipping,
    blendKey: record.blendKey,
    role: record.role,
    pixels: pixels,
    adjustmentKey: record.adjustmentKey,
  );
}

Uint8List? _readComposite(
  PhotoshopByteReader reader, {
  required int width,
  required int height,
  required int depth,
  required bool psb,
  required int channelCount,
  required PsdColorMode colorMode,
  required Uint8List? palette,
  required bool mergedAlpha,
  required List<String> warnings,
}) {
  if (width <= 0 || height <= 0 || channelCount <= 0) {
    return null;
  }
  final compression = reader.readUint16();
  final bytesPerRow = psdBytesPerRow(width: width, depth: depth);
  final planes = <Uint8List>[];
  switch (compression) {
    case 0:
      for (var c = 0; c < channelCount; c += 1) {
        planes.add(
          _normalise(
            Uint8List.fromList(reader.readBytes(bytesPerRow * height)),
            width: width,
            height: height,
            depth: depth,
            bytesPerRow: bytesPerRow,
          ),
        );
      }
    case 1:
      // ONE length table in front of every channel's rows, not one per
      // channel — the composite is the odd one out in this format.
      final counts = <int>[
        for (var i = 0; i < channelCount * height; i += 1)
          psb ? reader.readUint32() : reader.readUint16(),
      ];
      for (var c = 0; c < channelCount; c += 1) {
        final rows = counts.sublist(c * height, (c + 1) * height);
        planes.add(
          _normalise(
            decodePackBitsRows(
              reader,
              rowLengths: rows,
              bytesPerRow: bytesPerRow,
            ),
            width: width,
            height: height,
            depth: depth,
            bytesPerRow: bytesPerRow,
          ),
        );
      }
    default:
      warnings.add('Composite image uses compression $compression — skipped.');
      return null;
  }

  final colorPlaneCount = colorMode.colorPlaneCount;
  if (planes.length < colorPlaneCount) {
    return null;
  }
  final hasAlpha = planes.length > colorPlaneCount;
  if (planes.length > colorPlaneCount + 1) {
    warnings.add('Extra document channels ignored.');
  }
  final rgba = psdPlanesToRgba(
    mode: colorMode,
    colorPlanes: planes.sublist(0, colorPlaneCount),
    alphaPlane: hasAlpha ? planes[colorPlaneCount] : null,
    width: width,
    height: height,
    palette: palette,
    warnings: warnings,
  );
  if (hasAlpha && !mergedAlpha) {
    // A fourth channel with no merged-transparency flag is a spot or saved
    // selection channel as often as it is transparency. Photoshop shows the
    // composite opaque in that case, so we do too.
    for (var i = 0; i < width * height; i += 1) {
      rgba[i * 4 + 3] = 255;
    }
  }
  return rgba;
}

Uint8List _normalise(
  Uint8List raw, {
  required int width,
  required int height,
  required int depth,
  required int bytesPerRow,
}) => depth == 8 && bytesPerRow == width
    ? raw
    : psdPlaneToEightBit(
        raw,
        width: width,
        height: height,
        depth: depth,
        bytesPerRow: bytesPerRow,
      );
