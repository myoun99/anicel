import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_settings.dart';
import '../../models/brush_tip_mask.dart';
import '../brush_tip_image_codec.dart';

/// Result of decoding a Clip Studio Paint `.sut`/`.sutg` brush file.
class SutImportResult {
  const SutImportResult({required this.presets, required this.warnings});

  final List<BrushPreset> presets;
  final List<String> warnings;
}

/// Thrown when the file cannot be read as a Clip Studio brush at all.
class SutDecodeException implements Exception {
  const SutDecodeException(this.message);

  final String message;

  @override
  String toString() => 'SutDecodeException: $message';
}

/// Decodes a Clip Studio Paint brush file — a SQLite database holding tool
/// nodes (`Node`), their parameters (`Variant`), and, when the brush was
/// exported with its materials, embedded tip bitmaps (`MaterialFile`).
///
/// Mapping (verified against real CSP 1.x/3.x exports): `BrushSize` px when
/// `BrushSizeUnit` is 0 (other units warn rather than mis-scale),
/// `Opacity`/`BrushFlow`/`BrushHardness`/`BrushThickness` percent,
/// `BrushInterval` percent -> spacing ratio, `BrushRotation` degrees,
/// `*Effector` values carry the input-source flags (0x10 pen pressure,
/// 0x80 random -> the jitters). The dual tip rides `UseDualBrush` +
/// `DualPatternImageArray`. Tip bitmaps live in `MaterialFile.FileData` (a CSP
/// material archive containing PNGs; the largest PNG is the tip image,
/// smaller ones are thumbnails), joined through the UTF-16 catalog path in
/// `BrushPatternImageArray`. The Variant schema varies across CSP versions,
/// so every column read tolerates absence.
Future<SutImportResult> decodeSutBrushFile({
  required String filePath,
  required String sourceName,
}) async {
  final Database database;
  try {
    database = sqlite3.open(filePath, mode: OpenMode.readOnly);
  } on SqliteException catch (error) {
    throw SutDecodeException('Could not open the file: ${error.message}');
  }
  try {
    return await _decode(database, sourceName: sourceName);
  } on SqliteException catch (error) {
    throw SutDecodeException(
      'This file is not a readable Clip Studio brush (${error.message}).',
    );
  } finally {
    database.close();
  }
}

Future<SutImportResult> _decode(
  Database database, {
  required String sourceName,
}) async {
  final tables = database
      .select("SELECT name FROM sqlite_master WHERE type='table'")
      .map((row) => row['name'] as String)
      .toSet();
  if (!tables.contains('Node') || !tables.contains('Variant')) {
    throw const SutDecodeException(
      'No Clip Studio brush data found in this file.',
    );
  }

  final warnings = <String>[];
  final variantsById = <int, Map<String, Object?>>{};
  for (final row in database.select('SELECT * FROM Variant')) {
    final id = row['VariantID'];
    if (id is int) {
      variantsById[id] = Map<String, Object?>.from(row);
    }
  }

  final materials = <({String path, Uint8List data})>[];
  if (tables.contains('MaterialFile')) {
    for (final row in database.select('SELECT * FROM MaterialFile')) {
      final data = row['FileData'];
      final catalogPath = row['CatalogPath'] ?? row['OriginalPath'];
      if (data is Uint8List &&
          catalogPath is String &&
          catalogPath.isNotEmpty) {
        materials.add((path: _stripLayerSuffix(catalogPath), data: data));
      }
    }
  }

  final usedPresetIds = <String>{};
  BrushPresetId uniquePresetId(String base) {
    if (usedPresetIds.add(base)) {
      return BrushPresetId(base);
    }
    var suffix = 2;
    while (!usedPresetIds.add('$base-$suffix')) {
      suffix += 1;
    }
    return BrushPresetId('$base-$suffix');
  }

  final presets = <BrushPreset>[];
  var nodeIndex = 0;
  for (final row in database.select('SELECT * FROM Node')) {
    final node = Map<String, Object?>.from(row);
    nodeIndex += 1;
    final variantId = node['NodeVariantID'];
    final variant = variantId is int ? variantsById[variantId] : null;
    // Group/root nodes have no usable parameter set.
    if (variant == null || variant['BrushSize'] == null) {
      continue;
    }

    final nodeName = node['NodeName'];
    final name = nodeName is String && nodeName.isNotEmpty
        ? nodeName
        : '$sourceName brush $nodeIndex';
    final uuid = node['NodeUuid'];
    final idBase = uuid is Uint8List && uuid.length >= 16
        ? 'sut-${_hex(uuid)}'
        : 'sut-$sourceName-$nodeIndex';
    final presetId = uniquePresetId(idBase);

    BrushTipMask? mask;
    if (_intOf(variant['BrushUsePatternImage']) == 1) {
      mask = await _tipMaskFromPatternArray(
        variant['BrushPatternImageArray'],
        materials: materials,
        maskId: '$idBase-tip',
        brushName: name,
        describe: 'tip bitmap',
        warnings: warnings,
      );
    }
    // Paper texture material (canvas-anchored overlay), referenced the same
    // way as the pattern array.
    BrushTipMask? textureMask;
    if (variant['TextureImage'] != null) {
      textureMask = await _tipMaskFromPatternArray(
        variant['TextureImage'],
        materials: materials,
        maskId: '$idBase-texture',
        brushName: name,
        describe: 'paper texture',
        warnings: warnings,
      );
      if (textureMask != null) {
        textureMask = brushTipMaskWithLevels(
          textureMask,
          // 濃度反転 — the same switch the Photoshop importer honours as
          // `InvT`, and it was going unread on this side.
          invert: _intOf(variant['TextureReverseDensity']) == 1,
          brightness: _signedPercent(variant['TextureBrightness']),
          contrast: _signedPercent(variant['TextureContrast']),
        );
        // Rotation stays unmapped on purpose: the tiled samplers run off a
        // separable per-axis lattice that exists precisely BECAUSE textures
        // never rotate, so honouring one brush's angle would cost every
        // textured brush its fast path.
        final rotation = _doubleOf(variant['TextureRotate']) ?? 0.0;
        if (rotation != 0.0) {
          warnings.add(
            'Brush "$name": paper texture rotation '
            '(${rotation.round()}°) is not applied.',
          );
        }
      }
    }
    // Dual brush: a second tip whose coverage multiplies the primary's,
    // referenced through its own pattern array.
    BrushTipMask? dualMask;
    if (_intOf(variant['UseDualBrush']) == 1 &&
        _intOf(variant['DualUsePatternImage']) == 1) {
      dualMask = await _tipMaskFromPatternArray(
        variant['DualPatternImageArray'],
        materials: materials,
        maskId: '$idBase-dual',
        brushName: name,
        describe: 'dual brush tip',
        warnings: warnings,
      );
    }

    presets.add(
      BrushPreset(
        id: presetId,
        name: name,
        settings: _settingsFromVariant(
          variant,
          mask: mask,
          textureMask: textureMask,
          dualMask: dualMask,
          brushName: name,
          warnings: warnings,
        ),
      ),
    );
  }

  if (presets.isEmpty) {
    throw const SutDecodeException('The file contained no importable brushes.');
  }
  return SutImportResult(presets: presets, warnings: warnings);
}

BrushSettings _settingsFromVariant(
  Map<String, Object?> variant, {
  required BrushTipMask? mask,
  required String brushName,
  required List<String> warnings,
  BrushTipMask? textureMask,
  BrushTipMask? dualMask,
}) {
  // `BrushSizeUnit` scales the stored number: 0 stores pixels outright, 2
  // stores tenths of one. Confirmed against Clip Studio itself — 小さな雲
  // stores 15 and reads 150, 水彩うろこ雲 stores 30 and reads 300, while
  // every unit-0 brush matches its stored number exactly.
  final sizeUnit = _intOf(variant['BrushSizeUnit']) ?? 0;
  final rawSize = _doubleOf(variant['BrushSize']) ?? 24.0;
  final size = sizeUnit == 2 ? rawSize * 10.0 : rawSize;
  if (sizeUnit != 0 && sizeUnit != 2) {
    warnings.add(
      'Brush "$brushName": size is stored in an unrecognised unit '
      '(BrushSizeUnit $sizeUnit); imported as $rawSize px, which may not '
      'match Clip Studio.',
    );
  }
  final opacityPercent = _doubleOf(variant['Opacity']) ?? 100.0;
  final flowPercent = _doubleOf(variant['BrushFlow']) ?? 100.0;
  final hardnessPercent = _doubleOf(variant['BrushHardness']) ?? 100.0;
  final intervalPercent = _doubleOf(variant['BrushInterval']) ?? 25.0;
  final thicknessPercent = _doubleOf(variant['BrushThickness']) ?? 100.0;
  final rotation = _doubleOf(variant['BrushRotation']) ?? 0.0;

  // BB-3: effectors map to pressure CURVES — the CSP minimum value is the
  // size curve's left endpoint. Opacity and flow effectors now import as
  // their own channels (they used to be OR-merged into one opacity bool).
  final sizePressureCurve = _effectorPressureCurve(
    variant['BrushSizeEffector'],
  );
  final opacityPressureCurve = _effectorPressureCurve(
    variant['BrushOpacityEffector'],
  );
  final flowPressureCurve = _effectorPressureCurve(
    variant['BrushFlowEffector'],
  );

  // Random input source (flag 0x80) drives the jitters. The engine shakes a
  // value DOWNWARD from its full setting (`v *= 1 - jitter * random`), which
  // is exactly Clip Studio's effector minimum: the value wanders between
  // 최소치% and 100%, so the amplitude is the complement of that floor.
  final sizeJitter = _effectorRandomJitter(variant['BrushSizeEffector']);
  // No flow jitter exists on the engine; flow randomness folds into opacity,
  // the same approximation the ABR importer makes.
  final opacityJitter = math.max(
    _effectorRandomJitter(variant['BrushOpacityEffector']),
    _effectorRandomJitter(variant['BrushFlowEffector']),
  );
  // `BrushRotationEffector` is a bare int rather than a blob, but carries the
  // SAME input-source bits. `BrushRotationRandomScale` is a percentage of a
  // full turn and sits at its default 100 on brushes that never randomise,
  // so it only means anything once the random bit is actually set.
  // Thickness IS roundness here, so its random source squashes the tip per
  // dab — what stops a textured stamp brush from looking stamped.
  final roundnessJitter = _effectorRandomJitter(
    variant['BrushThicknessEffector'],
  );
  // The interval effector's random source breaks up the even beat of a
  // stamped brush.
  final spacingJitter = _effectorRandomJitter(
    variant['BrushIntervalEffector'],
  );
  final angleJitter = _usesRandom(_effectorFlags(variant['BrushRotationEffector']))
      ? ((_doubleOf(variant['BrushRotationRandomScale']) ?? 0.0) / 100.0)
            .clamp(0.0, 1.0)
            .toDouble()
      : 0.0;

  // Ground-colour mixing (밑바탕 혼색). `BrushUseWaterColor` is the gate and
  // it matters: brushes that never enabled mixing still carry stored knob
  // values (鉛筆R sits at 물감량 50 with the gate off). The three knobs are
  // percentages; 불투명 수채 reading 색 늘이기 0 while the wet brushes read
  // 10-50 is the tell that this column is the smear, not the pickup.
  final mixesGroundColor = _intOf(variant['BrushUseWaterColor']) == 1;
  final paintAmount = _percentRatio(variant['BrushMixColor'], fallback: 1.0);
  final paintDensity = _percentRatio(variant['BrushMixAlpha'], fallback: 1.0);
  final colorStretch = _percentRatio(
    variant['BrushMixColorExtension'],
    fallback: 0.0,
  );

  // Spray mode scatters dabs around the stroke; the spray size is a
  // percentage of the brush size (its diameter), so the radius is half.
  var scatterRadiusRatio = 0.0;
  var scatterCount = 1;
  if (_intOf(variant['BrushUseSpray']) == 1) {
    final spraySize = _doubleOf(variant['BrushSpraySize']) ?? 0.0;
    scatterRadiusRatio = spraySize.isFinite
        ? (spraySize / 100.0 / 2.0).clamp(0.0, 10.0).toDouble()
        : 0.0;
    scatterCount = (_intOf(variant['BrushSprayDensity']) ?? 1).clamp(1, 16);
  }

  return BrushSettings(
    size: size.isFinite && size > 0 ? size : 24,
    opacity: (opacityPercent / 100.0).clamp(0.0, 1.0).toDouble(),
    flow: (flowPercent / 100.0).clamp(0.0, 1.0).toDouble(),
    hardness: (hardnessPercent / 100.0).clamp(0.0, 1.0).toDouble(),
    spacing: intervalPercent.isFinite && intervalPercent > 0
        ? (intervalPercent / 100.0).clamp(0.01, 10.0).toDouble()
        : 0.25,
    roundness: (thicknessPercent / 100.0).clamp(0.01, 1.0).toDouble(),
    angleDegrees: rotation.isFinite ? ((rotation % 180.0) + 180.0) % 180.0 : 0,
    sizePressureCurve: sizePressureCurve,
    opacityPressureCurve: opacityPressureCurve,
    flowPressureCurve: flowPressureCurve,
    tipMask: mask,
    sizeJitter: sizeJitter,
    opacityJitter: opacityJitter,
    angleJitter: angleJitter,
    roundnessJitter: roundnessJitter,
    spacingJitter: spacingJitter,
    scatterRadiusRatio: scatterRadiusRatio,
    scatterCount: scatterCount,
    dualMask: dualMask,
    // Inactive dual settings keep their stored defaults (`DualSize` 30 sits
    // on brushes that never enabled a dual tip), so the ratio only means
    // anything once a tip actually arrived.
    dualMaskScale: dualMask == null
        ? 1.0
        : _dualMaskScaleOf(variant, brushSize: size),
    textureMask: textureMask,
    textureScale: _textureScaleOf(variant),
    textureDensity: _textureDensityOf(variant),
    mixesGroundColor: mixesGroundColor,
    paintAmount: paintAmount,
    paintDensity: paintDensity,
    colorStretch: colorStretch,
  );
}

/// Reads a -100..100 percentage column as a -1..1 ratio, 0 neutral.
///
/// Real files pin the neutral point: brushes that never touched their paper
/// controls store 0, not 100.
double _signedPercent(Object? value) {
  final percent = _doubleOf(value);
  if (percent == null || !percent.isFinite) {
    return 0.0;
  }
  return (percent / 100.0).clamp(-1.0, 1.0).toDouble();
}

/// Reads a 0-100 percentage column as a 0..1 ratio.
double _percentRatio(Object? value, {required double fallback}) {
  final percent = _doubleOf(value);
  if (percent == null || !percent.isFinite) {
    return fallback;
  }
  return (percent / 100.0).clamp(0.0, 1.0).toDouble();
}

/// The dual tip's size relative to the primary tip.
///
/// `SyncDualBrushSize` decides how `DualSize` reads: synced, it is a
/// percentage of the brush size (Clip Studio's own default presentation);
/// unsynced, it is an absolute size in the same unit as `BrushSize`, so the
/// ratio comes from dividing. Either way the engine wants a multiplier.
double _dualMaskScaleOf(Map<String, Object?> variant, {required double brushSize}) {
  final dualSize = _doubleOf(variant['DualSize']);
  if (dualSize == null || !dualSize.isFinite || dualSize <= 0.0) {
    return 1.0;
  }
  final synced = _intOf(variant['SyncDualBrushSize']) == 1;
  final scale = synced
      ? dualSize / 100.0
      : (brushSize > 0 ? dualSize / brushSize : 1.0);
  if (!scale.isFinite || scale <= 0.0) {
    return 1.0;
  }
  return scale.clamp(0.05, 10.0).toDouble();
}

/// `TextureScale2` is a percentage of the texture's native size.
double _textureScaleOf(Map<String, Object?> variant) {
  final scale = _doubleOf(variant['TextureScale2']);
  if (scale == null || !scale.isFinite || scale <= 0.0) {
    return 1.0;
  }
  return (scale / 100.0).clamp(0.05, 10.0).toDouble();
}

/// `TextureDensity` is the overlay strength in percent.
double _textureDensityOf(Map<String, Object?> variant) {
  final density = _doubleOf(variant['TextureDensity']);
  if (density == null || !density.isFinite) {
    return 1.0;
  }
  return (density / 100.0).clamp(0.0, 1.0).toDouble();
}

/// The input-source flags of an effector, or `null` when it carries none.
///
/// Most effectors are blobs: two header ints, then the flags. The rotation
/// effector is a bare int that IS the flags, with the same bit layout —
/// real files show 0x13 on a brush whose rotation follows pressure and 0xC3
/// on the one brush carrying a non-default random scale.
///
/// Bit 0x10 selects pen pressure and 0x80 random. 0x20 (velocity) and 0x40
/// (seen only on the rotation effector, most likely stroke direction) have
/// no engine target yet and stay unmapped.
int? _effectorFlags(Object? effector) {
  if (effector is int) {
    return effector;
  }
  if (effector is Uint8List && effector.length >= 12) {
    return ByteData.sublistView(effector).getInt32(8);
  }
  return null;
}

bool _usesRandom(int? flags) => flags != null && (flags & 0x80) != 0;

bool _effectorUsesPressure(Object? effector) {
  final flags = _effectorFlags(effector);
  return flags != null && (flags & 0x10) != 0;
}

/// The pen-pressure response curve an effector carries, or `null` when it
/// does not answer to pressure.
///
/// Clip Studio stores the 筆압설정 graph in the effector's tail, and the
/// engine's curve is the same shape of object — control points read by a
/// monotone spline — so the graph imports as itself instead of being
/// flattened to a line.
///
/// Layout: a `12, <point count>, 16, 0, 0, 0, 0` marker, then `count - 1`
/// (x, y) float64 pairs; the origin (0, 0) is implied rather than stored.
/// One block per input source, in ascending flag-bit order, so the pressure
/// curve is the FIRST block whenever pressure (0x10) is set — it is the
/// lowest source bit there is.
///
/// The 최소치 slider is a SEPARATE control: the stored curve spans the full
/// 0..1 output and the minimum lifts its floor, which is why a brush that
/// never touched the graph still lands on exactly the straight
/// `min + (1 - min) * p` line this importer used to assume for everyone.
BrushPressureCurve? _effectorPressureCurve(Object? effector) {
  if (!_effectorUsesPressure(effector)) {
    return null;
  }
  final minimum = _effectorMinimumRatio(effector);
  final stored = effector is Uint8List ? _effectorCurvePoints(effector) : null;
  if (stored == null || stored.isEmpty) {
    return BrushPressureCurve.linearFrom(minimum);
  }
  final points = <BrushCurvePoint>[BrushCurvePoint(0.0, minimum)];
  for (final point in stored) {
    // The engine wants strictly increasing x inside the unit square; Clip
    // Studio pads unused slots by repeating the last point.
    if (point.x <= points.last.x || point.x > 1.0) {
      continue;
    }
    points.add(
      BrushCurvePoint(point.x, (minimum + (1.0 - minimum) * point.y).clamp(0.0, 1.0).toDouble()),
    );
  }
  if (points.last.x < 1.0) {
    points.add(const BrushCurvePoint(1.0, 1.0));
  }
  if (points.length < 2) {
    return BrushPressureCurve.linearFrom(minimum);
  }
  try {
    return BrushPressureCurve(points);
  } on ArgumentError {
    // Never fail an import over a curve; the straight line is the honest
    // fallback the file already implies through its minimum.
    return BrushPressureCurve.linearFrom(minimum);
  }
}

/// The first curve block's stored points, origin excluded.
List<BrushCurvePoint>? _effectorCurvePoints(Uint8List blob) {
  final data = ByteData.sublistView(blob);
  final intCount = blob.length ~/ 4;
  for (var i = 0; i + 7 <= intCount; i += 1) {
    if (data.getInt32(i * 4) != 12 || data.getInt32((i + 2) * 4) != 16) {
      continue;
    }
    var padded = true;
    for (var k = 3; k < 7; k += 1) {
      padded &= data.getInt32((i + k) * 4) == 0;
    }
    if (!padded) {
      continue;
    }
    final count = data.getInt32((i + 1) * 4);
    if (count < 2 || count > 64) {
      return null;
    }
    final start = (i + 7) * 4;
    final points = <BrushCurvePoint>[];
    for (var k = 0; k < count - 1; k += 1) {
      final offset = start + k * 16;
      if (offset + 16 > blob.length) {
        break;
      }
      final x = data.getFloat64(offset);
      final y = data.getFloat64(offset + 8);
      if (!x.isFinite || !y.isFinite || x < 0.0 || y < 0.0) {
        break;
      }
      points.add(BrushCurvePoint(x, y.clamp(0.0, 1.0).toDouble()));
    }
    return points;
  }
  return null;
}

/// Jitter amplitude for an effector driven by the random input source.
///
/// Clip Studio wanders the value between its 최소치% and 100%; the engine
/// shakes downward by `jitter * random`, so the amplitude is the complement
/// of the minimum. An effector without the random bit contributes nothing.
double _effectorRandomJitter(Object? effector) {
  if (!_usesRandom(_effectorFlags(effector))) {
    return 0.0;
  }
  return (1.0 - _effectorMinimumRatio(effector)).clamp(0.0, 1.0).toDouble();
}

/// The effector's minimum-output percentage (byte offset 12) — Clip
/// Studio's 최소치 slider, the pressure floor for the affected value.
double _effectorMinimumRatio(Object? blob) {
  if (blob is! Uint8List || blob.length < 16) {
    return 0.0;
  }
  final minimum = ByteData.sublistView(blob).getInt32(12);
  return (minimum / 100.0).clamp(0.0, 1.0).toDouble();
}

Future<BrushTipMask?> _tipMaskFromPatternArray(
  Object? patternArray, {
  required List<({String path, Uint8List data})> materials,
  required String maskId,
  required String brushName,
  required String describe,
  required List<String> warnings,
}) async {
  if (patternArray is! Uint8List || materials.isEmpty) {
    if (patternArray != null) {
      warnings.add(
        'Brush "$brushName": $describe is not embedded; '
        'imported without it.',
      );
    }
    return null;
  }
  // The array blob carries UTF-16BE catalog paths; match them against the
  // embedded material files. The earliest referenced material is the
  // primary tip (pattern brushes with several tips use only the first).
  final text = _utf16Runs(patternArray);
  ({String path, Uint8List data})? tipMaterial;
  var bestIndex = -1;
  for (final material in materials) {
    final index = text.indexOf(material.path);
    if (index >= 0 && (bestIndex == -1 || index < bestIndex)) {
      bestIndex = index;
      tipMaterial = material;
    }
  }
  if (tipMaterial == null) {
    warnings.add(
      'Brush "$brushName": $describe reference not found; '
      'imported without it.',
    );
    return null;
  }

  final png = _largestPng(tipMaterial.data);
  if (png == null) {
    warnings.add(
      'Brush "$brushName": $describe material holds no readable '
      'image; imported without it.',
    );
    return null;
  }
  try {
    return await decodeBrushTipImage(png, id: maskId);
  } catch (error) {
    warnings.add(
      'Brush "$brushName": $describe image could not be decoded '
      '($error); imported without it.',
    );
    return null;
  }
}

String _stripLayerSuffix(String path) {
  final index = path.indexOf(':data:');
  return index > 0 ? path.substring(0, index) : path;
}

/// Extracts the printable UTF-16 characters of [bytes] in both byte orders
/// (CSP writes the catalog paths little-endian, but be permissive).
String _utf16Runs(Uint8List bytes) {
  final buffer = StringBuffer();
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final littleEndian = bytes[i] | (bytes[i + 1] << 8);
    if (littleEndian >= 0x20 && littleEndian < 0x7F) {
      buffer.writeCharCode(littleEndian);
    }
  }
  buffer.write('\n');
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final bigEndian = (bytes[i] << 8) | bytes[i + 1];
    if (bigEndian >= 0x20 && bigEndian < 0x7F) {
      buffer.writeCharCode(bigEndian);
    }
  }
  return buffer.toString();
}

/// Finds the largest embedded PNG in a CSP material archive blob — the tip
/// image itself; smaller PNGs are thumbnails.
Uint8List? _largestPng(Uint8List data) {
  Uint8List? best;
  var bestArea = 0;
  for (var i = 0; i + 26 < data.length; i += 1) {
    if (data[i] != 0x89 ||
        data[i + 1] != 0x50 ||
        data[i + 2] != 0x4E ||
        data[i + 3] != 0x47) {
      continue;
    }
    final view = ByteData.sublistView(data, i);
    final width = view.getUint32(16);
    final height = view.getUint32(20);
    final end = _pngEnd(data, i);
    if (end == null) {
      continue;
    }
    final area = width * height;
    if (area > bestArea) {
      bestArea = area;
      best = Uint8List.sublistView(data, i, end);
    }
    i = end - 1;
  }
  return best;
}

/// Walks PNG chunks from [start] to the end of IEND; `null` when corrupt.
int? _pngEnd(Uint8List data, int start) {
  var offset = start + 8;
  final view = ByteData.sublistView(data);
  while (offset + 8 <= data.length) {
    final length = view.getUint32(offset);
    final type = String.fromCharCodes(data, offset + 4, offset + 8);
    offset += 8 + length + 4;
    if (offset > data.length) {
      return null;
    }
    if (type == 'IEND') {
      return offset;
    }
  }
  return null;
}

// The PNG -> mask read (coverage from alpha and darkness, the >256px
// downscale, the centered-square padding) moved to
// `../brush_tip_image_codec.dart`, so a tip the user registers by hand and
// one that arrives inside a .sut are read by exactly the same rules.

String _hex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final value in bytes) {
    buffer.write(value.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

int? _intOf(Object? value) => value is int ? value : null;

double? _doubleOf(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  return null;
}
