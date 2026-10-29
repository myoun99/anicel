import '../brush_preset_id_mint.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../models/brush_anti_alias.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/brush_correction.dart';
import '../../models/separable_blend_mode.dart';
import '../../models/brush_input_source.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_settings.dart';
import '../../models/brush_shape.dart';
import '../../models/brush_tip_mask.dart';
import '../../models/brush_tip_order.dart';
import '../../models/import/import_warning.dart';
import '../brush_tip_image_codec.dart';

/// Result of decoding a Clip Studio Paint `.sut`/`.sutg` brush file.
class SutImportResult {
  const SutImportResult({required this.presets, required this.warnings});

  final List<BrushPreset> presets;
  final List<String> warnings;
}

/// Thrown when the file cannot be read as a Clip Studio brush at all.
class SutDecodeException extends ImportRefusal {
  const SutDecodeException(super.reason);
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
    throw SutDecodeException(
      ImportWarning('sutCannotOpen', 'Could not open the file: {error}', {
        'error': error.message,
      }),
    );
  }
  try {
    return await _decode(database, sourceName: sourceName);
  } on SqliteException catch (error) {
    throw SutDecodeException(
      ImportWarning(
        'sutUnreadable',
        'This file is not a readable Clip Studio brush ({error}).',
        {'error': error.message},
      ),
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
      ImportWarning(
        'sutNoBrushData',
        'No Clip Studio brush data found in this file.',
      ),
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
      // An EMPTY catalog path falls back too, not only a missing one: the
      // user's 색연필 (F-456) stores '' there and names its tip by the
      // original path — read as absent, its tip came in as a plain circle.
      final catalog = row['CatalogPath'];
      final catalogPath = catalog is String && catalog.isNotEmpty
          ? catalog
          : row['OriginalPath'];
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

    var tips = const <BrushTipMask>[];
    if (_intOf(variant['BrushUsePatternImage']) == 1) {
      tips = await _tipMasksFromPatternArray(
        variant['BrushPatternImageArray'],
        materials: materials,
        maskId: '$idBase-tip',
        part: (brushName: name, describe: 'tip bitmap', warnings: warnings),
      );
    }
    // Paper texture material (canvas-anchored overlay), referenced the same
    // way as the pattern array.
    BrushTipMask? textureMask;
    var textureInvert = false;
    var textureBrightness = 0.0;
    var textureContrast = 0.0;
    if (variant['TextureImage'] != null) {
      final part = (
        brushName: name,
        describe: 'paper texture',
        warnings: warnings,
      );
      textureMask = _theOneOf(
        await _tipMasksFromPatternArray(
          variant['TextureImage'],
          materials: materials,
          maskId: '$idBase-texture',
          part: part,
        ),
        part,
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
    //
    // 📏A DUAL TIP AT 通常 COMES IN WITHOUT IT (유저 2026-10-25, board
    // an-imported-pencil-drops-its-second-brush Q2 「「通常」과 두 번째 종이
    // 결까지 맞춘다」): the user drew 鉛筆 in Clip Studio with its dual tip at
    // 通常 and with it off, and the two lines measure alike — 3.64 and 3.60
    // ink a column, the same width, the same grain. At 乗算 the line drew
    // nothing. ↩️It came in as multiply — a mask that thinned every line
    // the pencil drew. ⚠️One brush measured; what 通常 does with a second
    // tip wider than the first is not.
    BrushTipMask? dualMask;
    final dualAtNormal =
        _intOf(variant['UseDualBrush']) == 1 &&
        _intOf(variant['DualBrushCompositeMode']) == 0;
    if (dualAtNormal) {
      warnings.add(
        'Brush "$name": dual brush tip at 通常 draws as no dual tip; '
        'imported without it.',
      );
    }
    if (!dualAtNormal &&
        _intOf(variant['UseDualBrush']) == 1 &&
        _intOf(variant['DualUsePatternImage']) == 1) {
      final part = (
        brushName: name,
        describe: 'dual brush tip',
        warnings: warnings,
      );
      dualMask = _theOneOf(
        await _tipMasksFromPatternArray(
          variant['DualPatternImageArray'],
          materials: materials,
          maskId: '$idBase-dual',
          part: part,
        ),
        part,
      );
    }

    presets.add(
      BrushPreset(
        id: presetId,
        name: name,
        settings: _settingsFromVariant(
          variant,
          tips: tips,
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
    throw const SutDecodeException(
      ImportWarning(
        'sutNothingImportable',
        'The file contained no importable brushes.',
      ),
    );
  }
  return SutImportResult(presets: presets, warnings: warnings);
}

BrushSettings _settingsFromVariant(
  Map<String, Object?> variant, {
  required List<BrushTipMask> tips,
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
  final placement = _placementOf(variant, 'Brush');

  // BB-3: effectors map to response CURVES — each source's 最小値 is its
  // curve's own minimum. Opacity and flow effectors import as their own
  // channels (they used to be OR-merged into one opacity bool).
  // ⛔EVERY enabled source, not just pressure. A Clip Studio brush can drive
  // one setting from several inputs at once, each with its own curve;
  // reading only the first one imported a tilt brush as a plain one.
  // ★Thickness IS roundness here and Interval IS spacing, so their effectors
  // land on those settings' rows (F-176-Q2) — ランダム included, which is what
  // stops a textured stamp brush looking stamped and breaks up the even beat
  // of its dabs.
  final curves = <BrushDynamicsKey, BrushPressureCurve>{
    for (final (target, column) in const [
      (BrushPressureTarget.size, 'BrushSizeEffector'),
      (BrushPressureTarget.opacity, 'BrushOpacityEffector'),
      (BrushPressureTarget.flow, 'BrushFlowEffector'),
      (BrushPressureTarget.roundness, 'BrushThicknessEffector'),
      (BrushPressureTarget.spacing, 'BrushIntervalEffector'),
    ])
      for (final entry in _effectorCurves(variant[column]).entries)
        (target, entry.key): entry.value,
  };

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

  final settings = BrushSettings(
    size: size.isFinite && size > 0 ? size : 24,
    opacity: (opacityPercent / 100.0).clamp(0.0, 1.0).toDouble(),
    flow: (flowPercent / 100.0).clamp(0.0, 1.0).toDouble(),
    hardness: (hardnessPercent / 100.0).clamp(0.0, 1.0).toDouble(),
    spacing: placement.spacing,
    roundness: placement.roundness,
    angleDegrees: placement.angleDegrees,
    curves: curves,
    tips: tips,
    tipOrder: _tipOrderOf(variant, brushName: brushName, warnings: warnings),
    angleJitter: placement.angleJitter,
    scatterRadiusRatio: placement.scatterRadiusRatio,
    scatterCount: placement.scatterCount,
    dualMask: dualMask,
    // Inactive dual settings keep their stored defaults (`DualSize` 30 sits
    // on brushes that never enabled a dual tip), so the ratio only means
    // anything once a tip actually arrived.
    dualMaskScale: dualMask == null
        ? 1.0
        : _dualMaskScaleOf(variant, brushSize: size),
    // 🚨AND ITS DENSITY, which nobody was reading — from EITHER importer.
    // `dualDensity`'s own declaration says 1.0 is the pre-density behaviour
    // (an unconditional multiply), and 1.0 is what every dual brush landed
    // at however faint its file said the second tip should be.
    //
    // 📏Measured 2026-09-10 on the user's files: one brush of twenty enables
    // a dual tip (`ウェット水彩`) and it stores `DualFlow = 30`, so it was
    // arriving three times as strong as it was authored.
    //
    // ⚠️A SAMPLE OF ONE, and the reading is positional: `DualFlow` sits where
    // `BrushFlow` sits on the main tip, and `BrushFlow` is our `flow`.
    dualDensity: dualMask == null
        ? 1.0
        : _percentRatio(variant['DualFlow'], fallback: 1.0),
    // ✏️`DualBrushCompositeMode` READS NOW (v33). It was the next thing that
    // brush wanted and it wanted an engine field; the field exists.
    //
    // ⛔It is the SAME 合成モード menu index the main tip's `CompositeMode`
    // uses, so it goes through the same [_blendModeOf] — a second table
    // would be a second chance to get 加算 wrong. Narrowed to the separable
    // half afterwards: a dual tip combines two COVERAGES, and 背景/消去
    // answer a question about pixels and alpha that a mask pair does not
    // ask (a tip at 通常 never gets here — the decode leaves it out).
    // ウェット水彩 stores 12, which is 加算.
    dualCompositeMode: dualMask == null
        ? SeparableBlendMode.multiply
        : _dualCompositeModeOf(
            variant['DualBrushCompositeMode'],
            brushName: brushName,
            warnings: warnings,
          ),
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
    correction: _correctionOf(variant),
  );
  // The second tip's own way along the path, read by the first tip's
  // reader under its `Dual` prefix — once a tip arrived, for the reason
  // the scale above gives.
  if (dualMask == null) {
    return settings;
  }
  final second = _placementOf(variant, 'Dual');
  return settings.copyWith(
    dualSpacing: second.spacing,
    dualRoundness: second.roundness,
    dualAngleDegrees: second.angleDegrees,
    dualAngleJitter: second.angleJitter,
    dualScatterRadiusRatio: second.scatterRadiusRatio,
    dualScatterCount: second.scatterCount,
  );
}

/// The brush's 補正, every column of it the user's five files carry
/// (F-418): its 手ブレ補正 (`FlickerReduction`, Clip Studio's 0..100) on
/// our scale, the speed's say in it, the 後補正 and the corners.
///
/// 🗣️A file without the 手ブレ補正 reads as Clip Studio's 0 (유저
/// 2026-10-20, F-418-Q6: 「없으면 클튜 0인거랑 동일한 우리의 값으로
/// 기본값으로」). A 後補正 that is off is 0 whatever strength it keeps
/// ([BrushCorrection.postStrength]); a part the file leaves out keeps our
/// default.
BrushCorrection _correctionOf(Map<String, Object?> variant) {
  const fallback = BrushCorrection();
  double finite(String column, double otherwise) {
    final value = _doubleOf(variant[column]);
    return value == null || !value.isFinite ? otherwise : value;
  }

  bool flag(String column, bool otherwise) => switch (_intOf(
    variant[column],
  )) {
    null => otherwise,
    final value => value != 0,
  };
  return BrushCorrection(
    sharpenCorners: flag('BrushSharpenCorner', fallback.sharpenCorners),
    stabilization: finite(
      'FlickerReduction',
      0,
    ).clamp(0.0, BrushCorrection.maxStabilization),
    steadyingBySpeed: BrushSteadyingBySpeed.fromClipStudio(
      bySpeed: _intOf(variant['FlickerReductionBySpeed']),
      type: _intOf(variant['FlickerReductionBySpeedType']),
    ),
    postStrength: flag('BrushUseRevision', false)
        ? finite('BrushRevision', 0).clamp(0.0, BrushCorrection.maxPostStrength)
        : 0,
    postBySpeed: flag('BrushRevisionBySpeed', fallback.postBySpeed),
    postByViewScale: flag('BrushRevisionByViewScale', fallback.postByViewScale),
    postBezier: flag('BrushRevisionBezier', fallback.postBezier),
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
    4 => BrushBlendMode.linearBurn, // 焼き込み(リニア)
    6 => BrushBlendMode.subtract, // 減算
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
    23 => BrushBlendMode.vividLight, // ビビッドライト
    24 => BrushBlendMode.linearLight, // リニアライト
    25 => BrushBlendMode.pinLight, // ピンライト
    26 => BrushBlendMode.hardMix, // ハードミックス
    27 => BrushBlendMode.exclusion, // 除外
    28 => BrushBlendMode.darkerColor, // カラー比較(暗)
    29 => BrushBlendMode.lighterColor, // カラー比較(明)
    30 => BrushBlendMode.divide, // 除算
    31 => BrushBlendMode.hue, // 色相
    32 => BrushBlendMode.saturation, // 彩度
    33 => BrushBlendMode.chroma, // カラー
    34 => BrushBlendMode.luminosity, // 輝度
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
  5 => '焼き込み(黒)',
  10 => '覆い焼き(発光)',
  11 => '覆い焼き(白)',
  13 => '加算(発光)',
  20 => '透明度置換',
  21 => '比較(濃度)',
  22 => '消去(比較)',
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
/// Bit 0x10 selects pen pressure, 0x20 pen tilt, 0x40 speed and 0x80
/// random — [BrushInputSource.effectorFlagBit] holds the table and how it
/// was settled. ⛔They are no longer "read and dropped": every source gets
/// its own curve and its own minimum (see [_effectorCurves]), and random
/// drives the jitters. ⛔Nor is 速度's curve "stored but not yet applied"
/// any more: the dab HAS a clock — the pen door normalizes px/s against
/// `AppInputSettings.speedReferencePixelsPerSecond` and `BrushDab.speed`
/// carries the ratio, which `brushInputValue` reads like any other source.
///
/// ↩️0x40 was first guessed here as "most likely stroke direction", on the
/// evidence that it only ever appeared on the rotation effector, then read
/// as 傾き off `물붓.sut` (2026-09-08), and is 速度 (F-456). ⛔Stroke
/// direction is still unmapped — do not reach for a bit when it comes up.
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

/// A percentage column read as a 0..1 amplitude, but ONLY when its effector
/// says the random input is switched on.
///
/// 🚨THE GATE IS THE WHOLE POINT (「값이 있다 ≠ 켜져 있다」). Clip Studio parks
/// these scales at their defaults — 100 is the usual one — on brushes that
/// never randomise anything, so reading a scale without its effector turns
/// every tip in the library. Two pairs are shaped this way (the plain
/// rotation and the in-spray one), which is why the law is written once.
double _randomScaleRatio(
  Map<String, Object?> variant, {
  required String effector,
  required String scale,
}) {
  if (!_usesRandom(_effectorFlags(variant[effector]))) {
    return 0.0;
  }
  return ((_doubleOf(variant[scale]) ?? 0.0) / 100.0).clamp(0.0, 1.0).toDouble();
}

/// Every input source's curve on one effector, keyed by source.
///
/// ⛔Everything but pressure used to be dropped on the floor here, which is
/// what made a tilt-driven Clip Studio brush import as a plain one.
Map<BrushInputSource, BrushPressureCurve> _effectorCurves(Object? effector) {
  final flags = _effectorFlags(effector);
  if (flags == null) {
    return const {};
  }
  return {
    for (final source in BrushInputSource.values)
      if (flags & source.effectorFlagBit != 0)
        source: _effectorSourceCurve(effector, source),
  };
}

/// Which of the effector's two graph blocks is [source]'s, or null when
/// it has none and runs straight from its 最小値 (to its 最大値).
///
/// 🚨**TWO GRAPHS, 筆圧設定 AND 傾き設定, IN FIXED PLACES, ticked or not**
/// (📏F-456, 2026-10-23 — the user's screenshot of Clip Studio's
/// 影響元設定 window, and their five pencils): `int[8]` and `int[9]` are
/// the two blocks' byte lengths, the blocks follow the header in that
/// order, and a length of 0 is a graph the file left out. 鉛筆's 不透明度
/// ticks 筆圧 alone and still carries both. 速度 and ランダム have a
/// 最小値 and no graph — ランダム's is all it is read as (F-176-Q2).
/// ↩️A source's block was its rank among the TICKED sources, so a brush
/// that ticked 傾き alone read 筆圧's graph as its own.
int? _graphBlockOf(BrushInputSource source) => switch (source) {
  BrushInputSource.pressure => 0,
  BrushInputSource.tilt => 1,
  BrushInputSource.speed || BrushInputSource.random => null,
};

BrushPressureCurve _effectorSourceCurve(
  Object? effector,
  BrushInputSource source,
) {
  final minimum = _effectorMinimumRatio(
    effector,
    source.effectorMinimumIndex,
  ).clamp(0.0, 1.0).toDouble();
  final maximum = source == BrushInputSource.tilt
      ? _effectorTiltMaximum(effector)
      : 1.0;
  // The panel says the response runs from 最小値% to 最大値% as the graph
  // runs from 0 to 1 — which is what a curve's own [BrushPressureCurve.minimum]
  // and [BrushPressureCurve.maximum] mean, so the graph comes in as it is.
  // ↩️The floor used to be folded into the points (divided by the ceiling
  // first — 「THE FLOOR IS DIVIDED BY THE CEILING」), from before a curve
  // could hold one apart; the popup now shows it as its own slider.
  final block = _graphBlockOf(source);
  final stored = effector is Uint8List && block != null
      ? _effectorGraphPoints(effector, block)
      : null;
  if (stored == null) {
    return BrushPressureCurve.linearFrom(minimum, maximum: maximum);
  }
  // 傾き設定 runs 水平 → 垂直 left to right (the window's own axis labels),
  // and a 傾き input is how far the pen LEANS ([brushInputValue]), so its
  // graph comes in mirrored.
  final points = source == BrushInputSource.tilt
      ? [
          for (final point in stored.reversed)
            BrushCurvePoint(1.0 - point.x, point.y),
        ]
      : stored;
  // 📏Every graph in the eleven reference files runs from x 0 to x 1,
  // rising, inside the unit square (119 of them, 2026-10-23) — what a curve
  // asks of its points — so one that does not is not read: it comes in
  // straight, below. ↩️Its ends were padded — to (1, 1), then flat — and
  // its points sifted for a repeat 「Clip Studio pads unused slots」 with,
  // on no file's word: that reader scanned the tail for the block.
  try {
    return BrushPressureCurve(points, minimum: minimum, maximum: maximum);
  } on ArgumentError {
    // Never fail an import over a curve; the straight line is the honest
    // fallback the file already implies through its minimum.
    return BrushPressureCurve.linearFrom(minimum, maximum: maximum);
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

/// The points of graph [block] (0 = 筆圧設定, 1 = 傾き設定 — see
/// [_graphBlockOf]) as stored, every one of them, or null when the file
/// left that graph out or it does not read.
///
/// A block is `12 · count · 16` and then `count` (x, y) float64 pairs,
/// big-endian. ↩️Its FIRST point is stored like the rest: it was taken
/// for padding that had to be (0, 0), so a graph that starts anywhere
/// else — every falling one — was not seen as a graph at all (F-456).
List<BrushCurvePoint>? _effectorGraphPoints(Uint8List blob, int block) {
  if (blob.length < 44) {
    return null;
  }
  final data = ByteData.sublistView(blob);
  var start = data.getInt32(0);
  for (var before = 0; before < block; before += 1) {
    start += data.getInt32(32 + before * 4);
  }
  final length = data.getInt32(32 + block * 4);
  if (length < 12 || start < 44 || start + length > blob.length) {
    return null;
  }
  final count = data.getInt32(start + 4);
  if (data.getInt32(start) != 12 ||
      data.getInt32(start + 8) != 16 ||
      count < 2 ||
      12 + count * 16 > length) {
    return null;
  }
  final points = <BrushCurvePoint>[];
  for (var k = 0; k < count; k += 1) {
    final offset = start + 12 + k * 16;
    final x = data.getFloat64(offset);
    final y = data.getFloat64(offset + 8);
    if (!x.isFinite || !y.isFinite) {
      return null;
    }
    points.add(BrushCurvePoint(x, y));
  }
  return points;
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
/// pressure's number as its own 最小値 (see [_effectorCurves]).
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

/// Every mask [patternArray] names, in its order — the first under [maskId],
/// each further material under `[maskId]-2`, `-3`, … (a material named twice
/// is one mask, taken twice).
///
/// ↩️Only the earliest material was read, so a brush of several tips came
/// in with its first alone (F-176-Q3).
Future<List<BrushTipMask>> _tipMasksFromPatternArray(
  Object? patternArray, {
  required List<({String path, Uint8List data})> materials,
  required String maskId,
  required _BrushPart part,
}) async {
  if (patternArray is! Uint8List || materials.isEmpty) {
    if (patternArray != null) {
      _leftOut(part, 'is not embedded');
    }
    return const [];
  }
  final named = _materialsNamedBy(patternArray, materials);
  if (named.isEmpty) {
    _leftOut(part, 'reference not found');
    return const [];
  }
  final masks = <({String path, Uint8List data}), BrushTipMask?>{};
  final tips = <BrushTipMask>[];
  for (final material in named) {
    if (!masks.containsKey(material)) {
      masks[material] = await _tipMaskOf(
        material,
        id: masks.isEmpty ? maskId : '$maskId-${masks.length + 1}',
        part: part,
      );
    }
    if (masks[material] case final mask?) {
      tips.add(mask);
    }
  }
  return tips;
}

/// What a one-mask slot — the paper texture, the dual tip — keeps of
/// [masks]: the first, said aloud when the file names more (Clip Studio
/// lets a dual tip take turns too).
BrushTipMask? _theOneOf(List<BrushTipMask> masks, _BrushPart part) {
  if (masks.length > 1) {
    part.warnings.add(
      'Brush "${part.brushName}": ${part.describe} has ${masks.length} '
      'images; only the first is used.',
    );
  }
  return masks.firstOrNull;
}

/// One part of a brush being read — the brush, the part as a warning
/// words it, and where its warnings go.
typedef _BrushPart = ({
  String brushName,
  String describe,
  List<String> warnings,
});

/// Says [part] came in without it, for [why].
void _leftOut(_BrushPart part, String why) => part.warnings.add(
  'Brush "${part.brushName}": ${part.describe} $why; imported without it.',
);

/// 繰り返し方法, from `BrushPatternOrderType`.
///
/// 📏ALL SIX NUMBERS ARE MEASURED (2026-10-21, board F-176-Q5): the user
/// saved one brush six times in Clip Studio, the method alone changed —
/// 繰り返し 0 · 折り返し 1 · 繰り返さない 2 · ランダム 3 · 一巡のみ 4 ·
/// ランダムに一巡 5, the order Clip Studio lists them in.
/// ↩️Before, two facts bore that order out without pinning it: each
/// one-tip brush of the user's stores 0, and all six of their Cloud
/// brushes, which scatter their tips at random, store 3 (2026-10-18, ten
/// brushes). `BrushPatternOrderType2` beside it holds the same number in
/// all sixteen and is left unread.
BrushTipOrder _tipOrderOf(
  Map<String, Object?> variant, {
  required String brushName,
  required List<String> warnings,
}) {
  final stored = _intOf(variant['BrushPatternOrderType']) ?? 0;
  final order = switch (stored) {
    0 => BrushTipOrder.repeat,
    1 => BrushTipOrder.pingPong,
    2 => BrushTipOrder.holdLast,
    3 => BrushTipOrder.random,
    4 => BrushTipOrder.oneLap,
    5 => BrushTipOrder.shuffledLap,
    _ => null,
  };
  if (order == null) {
    warnings.add(
      'Brush "$brushName": its tips take turns in an unrecognised order '
      '(BrushPatternOrderType $stored); imported taking them in order.',
    );
  }
  return order ?? BrushTipOrder.repeat;
}

/// The material each entry of a Clip Studio material array names, in the
/// array's order.
///
/// The array is a big-endian u32 saying where its entries start, a u32
/// count, and the entries, each led by a u32 of its own length in bytes
/// that counts those four; an entry spells its material's paths in
/// UTF-16. 📏Read 2026-10-18 off the user's five brush files, tips,
/// textures and dual tips alike — 遠くの雲's array counts thirteen entries
/// and names thirteen materials.
///
/// ⚠️AN ENTRY IS MATCHED BY THE CATALOG PATH IT SPELLS, not by its layer
/// path: an installed material's layer path drops the `Install:` its
/// catalog path carries (ウェット水彩: `.:Paint110:…:data:material_0.layer`
/// beside `.:Install:Paint110:…`), so only the catalog path finds it.
List<({String path, Uint8List data})> _materialsNamedBy(
  Uint8List array,
  List<({String path, Uint8List data})> materials,
) {
  if (array.length < 8) {
    return const [];
  }
  final view = ByteData.sublistView(array);
  final count = view.getUint32(4);
  final named = <({String path, Uint8List data})>[];
  var offset = view.getUint32(0);
  for (var entry = 0; entry < count && offset + 4 <= array.length; entry += 1) {
    final length = view.getUint32(offset);
    if (length < 4 || offset + length > array.length) {
      break;
    }
    final text = _utf16Runs(
      Uint8List.sublistView(array, offset, offset + length),
    );
    ({String path, Uint8List data})? material;
    var earliest = -1;
    for (final candidate in materials) {
      final index = text.indexOf(candidate.path);
      if (index >= 0 && (earliest == -1 || index < earliest)) {
        earliest = index;
        material = candidate;
      }
    }
    if (material != null) {
      named.add(material);
    }
    offset += length;
  }
  return named;
}

/// [material]'s image as a mask, or `null` — with a warning — when it holds
/// none that reads.
///
/// 🚨THE TIP IS THE LARGEST IMAGE THAT HOLDS ANYTHING. Clip Studio's own
/// 鉛筆 · デッサン鉛筆 · ガッシュ carry each tip twice at one size, a blank
/// one first (measured 2026-10-25, board
/// an-imported-pencil-drops-its-second-brush). ↩️The first of two equal
/// areas came in, so those brushes came in drawing nothing at all.
Future<BrushTipMask?> _tipMaskOf(
  ({String path, Uint8List data}) material, {
  required String id,
  required _BrushPart part,
}) async {
  final pngs = _largestPngs(material.data);
  if (pngs.isEmpty) {
    _leftOut(part, 'material holds no readable image');
    return null;
  }
  for (final png in pngs) {
    final BrushTipMask mask;
    try {
      mask = await decodeBrushTipImage(png, id: id);
    } on Object catch (error) {
      _leftOut(part, 'image could not be decoded ($error)');
      return null;
    }
    if (mask.alpha.any((alpha) => alpha != 0)) {
      return mask;
    }
  }
  _leftOut(part, 'material holds a blank image alone');
  return null;
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

/// The largest embedded PNGs in a CSP material archive blob, in the order
/// they lie — the tip image itself and any twin of its size; smaller PNGs
/// are thumbnails.
List<Uint8List> _largestPngs(Uint8List data) {
  final best = <Uint8List>[];
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
      best.clear();
    }
    if (area > 0 && area == bestArea) {
      best.add(Uint8List.sublistView(data, i, end));
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

/// The blend a Clip Studio DUAL tip combines with — the same 合成モード menu
/// index the main tip's `CompositeMode` uses, narrowed to the separable
/// half.
///
/// ⛔It reads through [_blendModeOf] rather than carrying its own table. The
/// menu is one menu; two transcriptions of it would be two chances to get
/// 加算 (index 12) wrong, and 12 is one of the two values actually found in
/// the user's files.
///
/// A mode with no separable form (通常/背景/消去, and the six from カラー比較
/// on that mix three colour channels) keeps the multiply and says so:
/// combining two COVERAGES has no question about pixels, alpha or a colour
/// of three for those to answer, and silently reinterpreting one would be
/// inventing a rule nobody asked for.
SeparableBlendMode _dualCompositeModeOf(
  Object? value, {
  required String brushName,
  required List<String> warnings,
}) {
  if (_intOf(value) == null) {
    return SeparableBlendMode.multiply;
  }
  final mode = _blendModeOf(value, brushName: brushName, warnings: warnings);
  final separable = mode.separable;
  if (separable != null) {
    return separable;
  }
  warnings.add(
    'Brush "$brushName": the dual tip\'s composite mode (${mode.label}) is '
    'not one two tips can be combined with; imported as multiply.',
  );
  return SeparableBlendMode.multiply;
}

/// A tip's way along the path as Clip Studio stores it: the first tip's
/// `Brush*` columns, or — under [prefix] `Dual` — the second tip's, which
/// are the same columns over again (`DualInterval` ↔ `BrushInterval`,
/// `DualThickness`, `DualRotation`, `DualUseSpray` …). One reader for both,
/// so the second tip's columns mean what the first tip's do.
({
  double spacing,
  double roundness,
  double angleDegrees,
  double angleJitter,
  double scatterRadiusRatio,
  int scatterCount,
})
_placementOf(Map<String, Object?> variant, String prefix) {
  final intervalPercent = _doubleOf(variant['${prefix}Interval']) ?? 25.0;
  final thicknessPercent = _doubleOf(variant['${prefix}Thickness']) ?? 100.0;
  final rotation = _doubleOf(variant['${prefix}Rotation']) ?? 0.0;

  // Spray mode scatters dabs around the stroke — and it is also the gate on
  // WHICH pair of rotation columns describes the tip's spin, so it is read
  // before either of them.
  final sprays = _intOf(variant['${prefix}UseSpray']) == 1;
  final angleJitter = _spinOf(variant, prefix, sprays: sprays);
  // The spray size is a percentage of the brush size (its diameter), so the
  // radius is half.
  var scatterRadiusRatio = 0.0;
  var scatterCount = 1;
  if (sprays) {
    final spraySize = _doubleOf(variant['${prefix}SpraySize']) ?? 0.0;
    scatterRadiusRatio = spraySize.isFinite
        ? (spraySize / 100.0 / 2.0).clamp(0.0, 10.0).toDouble()
        : 0.0;
    scatterCount = (_intOf(variant['${prefix}SprayDensity']) ?? 1).clamp(1, 16);
  }

  return (
    spacing: intervalPercent.isFinite && intervalPercent > 0
        ? (intervalPercent / 100.0).clamp(0.01, 10.0).toDouble()
        : 0.25,
    roundness: (thicknessPercent / 100.0).clamp(0.01, 1.0).toDouble(),
    angleDegrees: rotation.isFinite ? ((rotation % 180.0) + 180.0) % 180.0 : 0,
    angleJitter: angleJitter,
    scatterRadiusRatio: scatterRadiusRatio,
    scatterCount: scatterCount,
  );
}

/// How far a tip's turn is thrown at random, read from the pair of rotation
/// columns that describes it — which pair, whether it [sprays] decides.
double _spinOf(
  Map<String, Object?> variant,
  String prefix, {
  required bool sprays,
}) {
  // 🚨A SPRAY BRUSH'S PARTICLES SPIN BY THEIR OWN PAIR OF COLUMNS. Measured
  // on the user's real files (2026-09-10): the only two brushes of twenty
  // with `BrushUseSpray = 1` — `Sampled Brush 4 3` and `ウェット水彩` — PARK
  // the plain pair (`BrushRotationEffector = 3`, no random bit) and put the
  // real setting in `BrushRotationEffectorInSpray = 129`, the same 0x80.
  // Reading only the plain pair imported `Sampled Brush 4 3`'s 69% particle
  // spin as ZERO, which is a scatter brush whose stamps all face one way.
  //
  // ⚠️THE GATE IS `BrushUseSpray`, not the presence of the in-spray columns:
  // every non-spray brush in the sample parks them at 3 / 100, and a brush
  // that really does spin its tip without spray says so in the plain pair
  // (鉛筆R at 45%).
  // ⛔What a brush that sets BOTH should do is NOT measured — no file in the
  // sample has one — so the in-spray pair simply WINS where spray is on,
  // which is the narrowest reading the evidence supports.
  //
  // ⚠️Both effectors are bare ints rather than blobs, and both carry the same
  // input-source bits; both scales are percentages of a full turn.
  return sprays
      ? _randomScaleRatio(
          variant,
          effector: '${prefix}RotationEffectorInSpray',
          scale: '${prefix}RotationRandomInSpray',
        )
      : _randomScaleRatio(
          variant,
          effector: '${prefix}RotationEffector',
          scale: '${prefix}RotationRandomScale',
        );
}
