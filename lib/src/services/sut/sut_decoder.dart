import '../brush_preset_id_mint.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../models/brush_anti_alias.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/brush_input_source.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_settings.dart';
import '../../models/brush_shape.dart';
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

  final mint = BrushPresetIdMint();

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
    final presetId = mint.next(idBase);

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
    var textureInvert = false;
    var textureBrightness = 0.0;
    var textureContrast = 0.0;
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
        // ⛔CARRIED, not baked in here — see the same change in the ABR
        // importer. The levels are three brush settings now, so baking them
        // into the mask on the way in would be the one thing that could
        // make them unreachable.
        //
        // 濃度反転 — the same switch the Photoshop importer honours as
        // `InvT`, and it was going unread on this side.
        textureInvert = _intOf(variant['TextureReverseDensity']) == 1;
        textureBrightness = _signedPercent(variant['TextureBrightness']);
        textureContrast = _signedPercent(variant['TextureContrast']);
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
          textureMaskSource: textureMask,
          textureInvert: textureInvert,
          textureBrightness: textureBrightness,
          textureContrast: textureContrast,
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
  BrushTipMask? textureMaskSource,
  bool textureInvert = false,
  double textureBrightness = 0.0,
  double textureContrast = 0.0,
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
  // ⛔EVERY enabled source, not just pressure. A Clip Studio brush can drive
  // one setting from several inputs at once, and each has its own curve block
  // in the effector's tail; reading only the first one imported a tilt brush
  // as a plain one.
  final curves = <BrushDynamicsKey, BrushPressureCurve>{
    for (final entry in _effectorCurves(variant['BrushSizeEffector']).entries)
      (BrushPressureTarget.size, entry.key): entry.value,
    for (final entry
        in _effectorCurves(variant['BrushOpacityEffector']).entries)
      (BrushPressureTarget.opacity, entry.key): entry.value,
    for (final entry in _effectorCurves(variant['BrushFlowEffector']).entries)
      (BrushPressureTarget.flow, entry.key): entry.value,
  };

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
    curves: curves,
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
    textureMaskSource: textureMaskSource,
    textureInvert: textureInvert,
    textureBrightness: textureBrightness,
    textureContrast: textureContrast,
    textureScale: _textureScaleOf(variant),
    textureDensity: _textureDensityOf(variant),
    mixesGroundColor: mixesGroundColor,
    paintAmount: paintAmount,
    paintDensity: paintDensity,
    colorStretch: colorStretch,
    blendMode: _blendModeOf(
      variant['CompositeMode'],
      brushName: brushName,
      warnings: warnings,
    ),
    antiAlias: _antiAliasOf(
      variant['AntiAlias'],
      brushName: brushName,
      warnings: warnings,
    ),
  );
}

/// How hard Clip Studio draws this brush's edge.
///
/// `AntiAlias` is the INDEX of the アンチエイリアス control, a row of four
/// buttons in the order なし・弱・中・強 — the same order and the same count
/// as [BrushAntiAlias]. Verified against four real brushes, one per level
/// (2026-09-09): G펜 3, 質感が残るように混ぜる 2, 鉛筆R 1, 水筆 0.
///
/// 🚨WHAT IS AND IS NOT VERIFIED. That the column exists, that it varies, and
/// that 3 is 強 are measured — G펜 ships from Clip Studio at 強 and stores 3.
/// Which of 1 and 2 is 弱 and which is 中 follows from the control's ORDER,
/// not from a reading, and the cheapest check is opening one file in Clip
/// Studio and looking at the panel. The two are adjacent steps of one ramp,
/// so a swap would be a subtle edge difference rather than a wrong brush.
///
/// ⛔Not `BrushAntiAlias.values[index]`: that would make Clip Studio's
/// encoding depend on our declaration order, so reordering the enum would
/// silently re-map every imported brush. The table says the mapping out loud.
///
/// ⚠️`DualAntiAlias` is a SEPARATE column for the dual tip and is not this.
/// Every one of the four files parks it at 2 while their own `AntiAlias`
/// spans 0..3, which is exactly the shape of a value nobody set.
BrushAntiAlias _antiAliasOf(
  Object? value, {
  required String brushName,
  required List<String> warnings,
}) {
  final index = _intOf(value);
  final mapped = switch (index) {
    0 => BrushAntiAlias.none, // なし
    1 => BrushAntiAlias.low, // 弱
    2 => BrushAntiAlias.medium, // 中
    3 => BrushAntiAlias.high, // 強
    _ => null,
  };
  if (mapped != null) {
    return mapped;
  }
  if (index != null) {
    warnings.add(
      'Brush "$brushName": anti-aliasing level $index is not one of Clip '
      'Studio\'s four; imported as 強.',
    );
  }
  // An absent column is an older file, and 強 is both Clip Studio's common
  // setting and our identity — the edge the engine already drew.
  return BrushAntiAlias.high;
}

/// The blend a Clip Studio sub tool composites with.
///
/// `CompositeMode` is the INDEX of Clip Studio's 合成モード menu, read off
/// the brush menu itself. Two entries had already been pinned by real files
/// — 0 通常 across nine brushes, 2 乗算 on ウェット水彩 — and the menu's order
/// puts 乗算 third, which is what confirmed the encoding rather than a
/// coincidence of two numbers.
///
/// Note the LAYER menu is a different, shorter list: it has no 消去, 背景,
/// 透明度置換 or the (黒)/(白) burn and dodge variants, so its indices do not
/// line up. This table is the brush menu's.
///
/// ⛔This used to answer "does this brush PIN a blend?", and index 0 meant
/// "no". It does not any more (유저 2026-09-08): a brush simply HAS a blend,
/// 通常 included, so 0 is a value like every other index and an unreadable
/// column falls back to it rather than to an absence.
BrushBlendMode _blendModeOf(
  Object? value, {
  required String brushName,
  required List<String> warnings,
}) {
  final mode = _intOf(value);
  if (mode == null || mode == 0) {
    return BrushBlendMode.color; // 通常
  }
  final mapped = switch (mode) {
    1 => BrushBlendMode.darken, // 比較(暗)
    2 => BrushBlendMode.multiply, // 乗算
    3 => BrushBlendMode.colorBurn, // 焼き込みカラー
    7 => BrushBlendMode.lighten, // 比較(明)
    8 => BrushBlendMode.screen, // スクリーン
    9 => BrushBlendMode.colorDodge, // 覆い焼きカラー
    12 => BrushBlendMode.add, // 加算
    14 => BrushBlendMode.overlay, // オーバーレイ
    15 => BrushBlendMode.softLight, // ソフトライト
    16 => BrushBlendMode.hardLight, // ハードライト
    17 => BrushBlendMode.difference, // 差の絶対値
    18 => BrushBlendMode.erase, // 消去
    19 => BrushBlendMode.behind, // 背景
    27 => BrushBlendMode.exclusion, // 除外
    _ => null,
  };
  if (mapped != null) {
    return mapped;
  }
  // The rest of the menu exists, it just has no kernel on this engine yet.
  // Naming it beats a bare number: it says what a brush would need.
  warnings.add(
    'Brush "$brushName": blend mode ${_clipStudioBlendName(mode)} has no '
    'equivalent yet; imported as 通常.',
  );
  return BrushBlendMode.color;
}

/// The 合成モード menu entry at [index], for warnings.
String _clipStudioBlendName(int index) => switch (index) {
  4 => '焼き込み(リニア)',
  5 => '焼き込み(黒)',
  6 => '減算',
  10 => '覆い焼き(発光)',
  11 => '覆い焼き(白)',
  13 => '加算(発光)',
  20 => '透明度置換',
  21 => '比較(濃度)',
  22 => '消去(比較)',
  23 => 'ビビッドライト',
  24 => 'リニアライト',
  25 => 'ピンライト',
  26 => 'ハードミックス',
  28 => 'カラー比較(暗)',
  29 => 'カラー比較(明)',
  30 => '除算',
  31 => '色相',
  32 => '彩度',
  33 => 'カラー',
  34 => '輝度',
  _ => '#$index',
};

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
double _dualMaskScaleOf(
  Map<String, Object?> variant, {
  required double brushSize,
}) {
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
/// Bit 0x10 selects pen pressure, 0x20 velocity, **0x40 pen TILT** and 0x80
/// random. ⛔They are no longer "read and dropped": every one of the three
/// curve sources gets its own curve and its own minimum (see
/// [_effectorCurves]), and random drives the jitters. ⛔Nor is 速度's curve
/// "stored but not yet applied" any more: the dab HAS a clock — the pen
/// door normalizes px/s against `AppInputSettings
/// .speedReferencePixelsPerSecond` and `BrushDab.speed` carries the ratio,
/// which `brushInputValue` reads like any other source.
///
/// ↩️0x40 was guessed here as "most likely stroke direction", on the evidence
/// that it only ever appeared on the rotation effector. 🚨THE GUESS WAS
/// WRONG, and a brush settled it (`물붓.sut`, 2026-09-08): every one of its
/// four inputs is ticked and its SIZE effector reads 0xF0, so the fourth bit
/// belongs to 傾き. ⛔Stroke direction is therefore still unmapped — do not
/// reach for 0x40 when it comes up.
int? _effectorFlags(Object? effector) {
  if (effector is int) {
    return effector;
  }
  if (effector is Uint8List && effector.length >= 12) {
    return ByteData.sublistView(effector).getInt32(8);
  }
  return null;
}

/// Whether the effector answers to the RANDOM input (0x80).
bool _usesRandom(int? flags) => flags != null && (flags & 0x80) != 0;

/// Every input source's curve on one effector, keyed by source.
///
/// 🚨**THE BLOCKS RUN IN ASCENDING FLAG-BIT ORDER** — 筆圧 0x10, 速度 0x20,
/// 傾き 0x40, ランダム 0x80 — so a source's block index is its rank among the
/// ENABLED sources below it, and randomness (the highest bit) can never shift
/// the others. ⚠️That is NOT the order the four minimums sit in; those run in
/// panel order. See [BrushInputSource.effectorMinimumIndex].
///
/// ⛔Everything but pressure used to be dropped on the floor here, which is
/// what made a tilt-driven Clip Studio brush import as a plain one.
Map<BrushInputSource, BrushPressureCurve> _effectorCurves(Object? effector) {
  final flags = _effectorFlags(effector);
  if (flags == null) {
    return const {};
  }
  final curves = <BrushInputSource, BrushPressureCurve>{};
  var block = 0;
  for (final source in _sourcesInBlockOrder) {
    if (flags & source.effectorFlagBit == 0) {
      continue;
    }
    final curve = _effectorSourceCurve(effector, source, block);
    if (curve != null) {
      curves[source] = curve;
    }
    block += 1;
  }
  return curves;
}

/// The sources in the order their curve blocks are written.
const _sourcesInBlockOrder = <BrushInputSource>[
  BrushInputSource.pressure,
  BrushInputSource.speed,
  BrushInputSource.tilt,
];

BrushPressureCurve? _effectorSourceCurve(
  Object? effector,
  BrushInputSource source,
  int blockIndex,
) {
  final minimum = _effectorMinimumRatio(
    effector,
    source.effectorMinimumIndex,
  );
  final maximum = source == BrushInputSource.tilt
      ? _effectorTiltMaximum(effector)
      : 1.0;
  // 🚨THE FLOOR IS DIVIDED BY THE CEILING, and getting this wrong is silent.
  //
  // The panel says the response runs from 최소치% to 최대치%. Our curve stores
  // a SHAPE in [0, 1] and `evaluate` returns `shape * maximum`, so for the
  // output to land on 최소치 at no input the shape has to start at
  // `minimum / maximum` — not at `minimum`, which would come out
  // maximum-times too high. With no maximum (every source but 傾き) the
  // division is by 1.0 and this is exactly what it always was.
  final floor = (minimum / maximum).clamp(0.0, 1.0).toDouble();
  final stored = effector is Uint8List
      ? _effectorCurvePoints(effector, blockIndex)
      : null;
  if (stored == null || stored.isEmpty) {
    return BrushPressureCurve.linearFrom(floor, maximum: maximum);
  }
  final points = <BrushCurvePoint>[BrushCurvePoint(0.0, floor)];
  for (final point in stored) {
    // The engine wants strictly increasing x inside the unit square; Clip
    // Studio pads unused slots by repeating the last point.
    if (point.x <= points.last.x || point.x > 1.0) {
      continue;
    }
    points.add(
      BrushCurvePoint(
        point.x,
        (floor + (1.0 - floor) * point.y).clamp(0.0, 1.0).toDouble(),
      ),
    );
  }
  if (points.last.x < 1.0) {
    points.add(const BrushCurvePoint(1.0, 1.0));
  }
  if (points.length < 2) {
    return BrushPressureCurve.linearFrom(floor, maximum: maximum);
  }
  try {
    return BrushPressureCurve(points, maximum: maximum);
  } on ArgumentError {
    // Never fail an import over a curve; the straight line is the honest
    // fallback the file already implies through its minimum.
    return BrushPressureCurve.linearFrom(floor, maximum: maximum);
  }
}

/// 傾き's 最大値 as a multiplier.
///
/// Clip Studio offers a maximum on tilt and on nothing else (100–1000%), and
/// it sits at int[10] — measured 2026-09-08 beside the four minimums, against
/// two brushes and their panel screenshots. Absent, short, or at-or-below
/// 100% all mean 1.0: "never exceeds the base", which is what every curve
/// meant before maximums existed.
double _effectorTiltMaximum(Object? blob) {
  if (blob is! Uint8List || blob.length < 44) {
    return 1.0;
  }
  final percent = ByteData.sublistView(blob).getInt32(40);
  if (percent <= 100) {
    return 1.0;
  }
  return (percent / 100.0).clamp(1.0, 10.0).toDouble();
}

/// The [blockIndex]-th curve block's stored points, origin excluded.
List<BrushCurvePoint>? _effectorCurvePoints(Uint8List blob, int blockIndex) {
  var seen = 0;
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
      // ⛔NOT `return null`. That was safe while only the FIRST block was
      // ever read; now a nonsense count in an early source's block would
      // abandon the scan and cost every LATER source its curve. A header
      // whose count makes no sense is not a block, so it does not count as
      // one either — `seen` stays put.
      continue;
    }
    // Blocks are written one per enabled source, so walk past the ones that
    // belong to sources ahead of this one in flag-bit order.
    if (seen != blockIndex) {
      seen += 1;
      continue;
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
  return (1.0 -
          _effectorMinimumRatio(
            effector,
            BrushInputSource.randomEffectorMinimumIndex,
          ))
      .clamp(0.0, 1.0)
      .toDouble();
}

/// One source's 최소치 percentage — the floor that source's curve lifts to.
///
/// 🚨**THERE ARE FOUR OF THESE, NOT ONE.** The blob stores a minimum per
/// input source at `int[3 + index]` in PANEL order (筆圧 · 傾き · 速度 ·
/// ランダム), and Clip Studio's own manual says so: TIPS #563 「各入力項目が
/// 最小値の時、設定してある数値を100としたときの何%で描画するかを設定します」
/// — 各入力項目, per input.
///
/// ⛔This used to read `int[3]` for everybody and call it "the pressure
/// floor". That was harmless for pressure and WRONG for random, which took
/// pressure's number as its jitter amplitude (see [_effectorRandomJitter]).
/// The fixtures could not catch it: `sut_decoder_test`'s `effector()` wrote
/// only `setInt32(12, …)`, so every synthetic blob had its four slots
/// collapsed into one and any index read the same value.
double _effectorMinimumRatio(Object? blob, int sourceIndex) {
  final offset = 12 + sourceIndex * 4;
  if (blob is! Uint8List || blob.length < offset + 4) {
    return 0.0;
  }
  final minimum = ByteData.sublistView(blob).getInt32(offset);
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
  } on Object catch (error) {
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
