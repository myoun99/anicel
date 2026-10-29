import '../brush_preset_id_mint.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/brush_blend_mode.dart';
import '../../models/separable_blend_mode.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../../models/brush_input_source.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_settings.dart';
import '../../models/brush_tip_mask.dart';
import '../../models/brush_tip_rotation_mode.dart';
import '../../models/import/import_warning.dart';
import '../photoshop/photoshop_byte_reader.dart';
import 'photoshop_descriptor.dart';
import 'photoshop_pattern.dart';

/// Result of decoding a Photoshop `.abr` brush file.
class AbrImportResult {
  const AbrImportResult({required this.presets, required this.warnings});

  /// One preset per usable brush, ready for the preset library.
  final List<BrushPreset> presets;

  /// Human-readable notes about entries that could not be fully imported.
  final List<String> warnings;
}

/// Thrown when the file cannot be read as a supported ABR at all.
class AbrDecodeException extends ImportRefusal {
  const AbrDecodeException(super.reason);
}

/// Decodes a Photoshop `.abr` brush file (version 6/7/10 — the format every
/// modern Photoshop writes) into brush presets.
///
/// The `samp` section provides the sampled tip bitmaps (grayscale, raw or
/// PackBits RLE); the `desc` section provides names and tip parameters
/// (diameter, spacing, angle, roundness, hardness) for sampled AND computed
/// brushes, joined to their bitmaps by the sampled-data UUID. When the
/// descriptor cannot be parsed, the tip bitmaps still import with default
/// settings and a warning.
AbrImportResult decodeAbrBrushFile(
  Uint8List bytes, {
  required String sourceName,
}) {
  final reader = PhotoshopByteReader(bytes);
  if (bytes.length < 4) {
    throw const AbrDecodeException(
      ImportWarning('abrTooShort', 'File is too short to be an ABR file.'),
    );
  }
  final version = reader.readInt16();
  if (version == 1 || version == 2) {
    throw AbrDecodeException(
      ImportWarning(
        'abrOldVersion',
        'ABR version {version} (Photoshop 6 era) is not supported yet; '
            're-save the brushes with a modern Photoshop.',
        {'version': '$version'},
      ),
    );
  }
  if (version != 6 && version != 7 && version != 10) {
    throw AbrDecodeException(
      ImportWarning(
        'abrUnknownVersion',
        'Not a supported ABR file (version {version}).',
        {'version': '$version'},
      ),
    );
  }
  final subversion = reader.readInt16();

  final warnings = <String>[];
  final tipsByKey = <String, BrushTipMask>{};
  final tipOrder = <String>[];
  final patternsById = <String, PsPattern>{};
  PsDescriptor? descriptor;

  while (_seekTo8bimSection(reader)) {
    final tag = reader.readAscii(4);
    final sectionLength = reader.readInt32();
    final sectionEnd = reader.offset + sectionLength;
    if (sectionLength < 0 || sectionEnd > reader.length) {
      throw const AbrDecodeException(
        ImportWarning('abrCorruptSection', 'Corrupt ABR section length.'),
      );
    }
    switch (tag) {
      case 'samp':
        _readSampledTips(
          reader,
          sectionEnd: sectionEnd,
          subversion: subversion,
          tipsByKey: tipsByKey,
          tipOrder: tipOrder,
          warnings: warnings,
        );
      case 'patt':
        for (final pattern in readPatternSection(
          reader.readBytes(sectionLength),
        )) {
          patternsById[pattern.id] = pattern;
        }
      case 'desc':
        try {
          descriptor = readVersionedDescriptor(
            PhotoshopByteReader(reader.readBytes(sectionLength)),
          );
        } on FormatException catch (error) {
          warnings.add(
            'Brush parameters could not be read (${error.message}); '
            'imported tips with default settings.',
          );
        }
      default:
        break;
    }
    reader.offset = sectionEnd;
  }

  if (tipsByKey.isEmpty && descriptor == null) {
    throw const AbrDecodeException(
      ImportWarning('abrNoBrushes', 'No brushes found in the ABR file.'),
    );
  }

  final presets = <BrushPreset>[];
  final usedTipKeys = <String>{};
  // Multiple brushes may share one sampled tip (variants of the same
  // bitmap with different settings — common in artist packs), so preset
  // ids must be de-collided — by the one mint. ↩️Its suffixes being
  // order-deterministic used to make a re-import REPLACE the file's brushes;
  // an import only adds now (F-433), so they just have to be free.
  final mint = BrushPresetIdMint();

  final brushList = _brushListOf(descriptor);
  if (brushList != null) {
    var computedIndex = 0;
    for (final entry in brushList) {
      if (entry is! PsDescriptor) {
        continue;
      }
      final preset = _presetFromBrushDescriptor(
        entry,
        tipsByKey: tipsByKey,
        patternsById: patternsById,
        usedTipKeys: usedTipKeys,
        sourceName: sourceName,
        computedIndex: () => ++computedIndex,
        uniquePresetId: mint.next,
        warnings: warnings,
      );
      if (preset != null) {
        presets.add(preset);
      }
    }
  }

  // Tips the descriptor did not claim (or no descriptor at all): import
  // them with default settings so no artwork data is silently dropped.
  var unnamedIndex = 0;
  for (final key in tipOrder) {
    if (usedTipKeys.contains(key)) {
      continue;
    }
    unnamedIndex += 1;
    presets.add(
      BrushPreset(
        id: mint.next('abr-$key'),
        name: '$sourceName tip $unnamedIndex',
        settings: _settingsForTip(
          tipsByKey[key],
          diameterPixels: tipsByKey[key]!.size.toDouble(),
          spacingRatio: 0.25,
          angleDegrees: 0,
          roundness: 1,
        ),
      ),
    );
  }

  if (presets.isEmpty) {
    throw const AbrDecodeException(
      ImportWarning(
        'abrNothingImportable',
        'The ABR file contained no importable brushes.',
      ),
    );
  }
  return AbrImportResult(presets: presets, warnings: warnings);
}

/// Positions the reader at the start of the next `8BIM` signature; returns
/// false at end of data. Robust against writer padding differences.
bool _seekTo8bimSection(PhotoshopByteReader reader) {
  while (reader.remaining >= 12) {
    final bytes = reader.readBytes(4);
    if (bytes[0] == 0x38 && // 8
        bytes[1] == 0x42 && // B
        bytes[2] == 0x49 && // I
        bytes[3] == 0x4D) {
      return true;
    }
    reader.offset -= 3;
  }
  return false;
}

void _readSampledTips(
  PhotoshopByteReader reader, {
  required int sectionEnd,
  required int subversion,
  required Map<String, BrushTipMask> tipsByKey,
  required List<String> tipOrder,
  required List<String> warnings,
}) {
  while (reader.offset < sectionEnd - 4) {
    final entryLength = reader.readInt32();
    if (entryLength <= 0) {
      break;
    }
    final entryStart = reader.offset;
    final nextEntry = math.min(
      entryStart + ((entryLength + 3) & ~3),
      sectionEnd,
    );
    try {
      final key = reader.readPascalString();
      // The fixed preamble (key + short coordinates, plus unknown bytes in
      // subversion >= 2) measured from the entry start.
      final preamble = subversion == 1 ? 47 : 301;
      final consumed = reader.offset - entryStart;
      if (preamble > consumed) {
        reader.skip(preamble - consumed);
      }

      final top = reader.readInt32();
      final left = reader.readInt32();
      final bottom = reader.readInt32();
      final right = reader.readInt32();
      final depth = reader.readInt16();
      final compressed = reader.readUint8() != 0;
      final width = right - left;
      final height = bottom - top;
      if (width <= 0 || height <= 0) {
        throw const FormatException('Empty tip bitmap.');
      }
      if (depth != 8) {
        warnings.add('Skipped tip "$key": $depth-bit tips are not supported.');
        continue;
      }

      final pixels = compressed
          ? decodePackBitsScanlines(reader, bytesPerRow: width, height: height)
          : Uint8List.fromList(reader.readBytes(width * height));
      final mask = BrushTipMask.square(
        id: 'abr-$key',
        pixels: pixels,
        width: width,
        height: height,
      );
      tipsByKey[key] = mask;
      tipOrder.add(key);
    } on FormatException catch (error) {
      warnings.add('Skipped a corrupt sampled tip (${error.message}).');
    } finally {
      reader.offset = nextEntry;
    }
  }
}

List<Object?>? _brushListOf(PsDescriptor? descriptor) {
  if (descriptor == null) {
    return null;
  }
  final direct = descriptor['Brsh'];
  if (direct is List) {
    return direct;
  }
  // Defensive: some writers nest the list one level down.
  for (final value in descriptor.items.values) {
    if (value is List) {
      return value;
    }
  }
  return null;
}

/// One Photoshop brush descriptor read into a preset, key by key.
///
/// ⛔NOT SPLIT (2026-09-05): forty-nine branches at cognitive 45 is a
/// FLAT mapping — read a key, fall back to Photoshop's default — and the
/// sections it is already divided into by comment (tip shape, tool
/// options, dynamics, scatter, texture) are the file's own order. Pulling
/// them into functions would move the defaults away from the keys they
/// belong to, and a default that drifts from its key is how an imported
/// brush stops matching the one in Photoshop.
BrushPreset? _presetFromBrushDescriptor(
  PsDescriptor entry, {
  required Map<String, BrushTipMask> tipsByKey,
  required Map<String, PsPattern> patternsById,
  required Set<String> usedTipKeys,
  required String sourceName,
  required int Function() computedIndex,
  required BrushPresetId Function(String base) uniquePresetId,
  required List<String> warnings,
}) {
  final tip = entry.childDescriptor('Brsh') ?? entry;
  final name = entry.textValue('Nm  ') ?? tip.textValue('Nm  ');

  final sampledKey = tip.textValue('sampledData');
  BrushTipMask? mask;
  if (sampledKey != null) {
    mask = tipsByKey[sampledKey];
    if (mask == null) {
      warnings.add(
        'Brush "${name ?? sampledKey}" references a missing tip bitmap; '
        'skipped.',
      );
      return null;
    }
    usedTipKeys.add(sampledKey);
  }

  final diameter = tip.numberValue('Dmtr') ?? mask?.size.toDouble() ?? 24.0;
  final placement = _tipPlacementOf(tip);
  final hardnessPercent = tip.numberValue('Hrdn') ?? 100.0;

  // Photoshop keeps opacity, flow, blend mode and smoothing together in a
  // `toolOptions` sub-descriptor — the settings its "Include Tool Settings"
  // checkbox bundles into a preset. Opacity and flow import outright,
  // because this engine already carries both as preset fields.
  //
  // Blend mode locks the brush only when it is something OTHER than normal,
  // the same rule the Clip Studio importer follows: a file that never left
  // the default has nothing to pin, so R26 #10 still holds for it. Every
  // brush in the packs to hand says `Nrml`, so nothing locks today.
  //
  // Smoothing stays unread — that one really is a hand setting.
  final toolOptions = entry.childDescriptor('toolOptions');
  final opacityPercent = toolOptions?.numberValue('Opct') ?? 100.0;
  final flowPercent = toolOptions?.numberValue('flow') ?? 100.0;
  final blendMode = _blendModeOf(toolOptions?['Md  ']);

  // Dynamics live at the preset level (sibling of 'Brsh'), gated by the
  // useTipDynamics / usePaintDynamics switches. Control type ('bVTy')
  // 2 = pen pressure; 6/7 = initial direction / direction.
  BrushPressureCurve? sizePressureCurve;
  var sizeRandom = 0.0;
  var rotationMode = BrushTipRotationMode.fixed;
  var angleJitter = 0.0;
  if (entry['useTipDynamics'] == true) {
    final sizeVariance = entry.childDescriptor('szVr');
    if (_controlOf(sizeVariance) == 2) {
      // BB-3: Photoshop's minimum diameter is the size curve's left
      // endpoint (the old minimumSizeRatio floor).
      sizePressureCurve = BrushPressureCurve.linearFrom(
        ((entry.numberValue('minimumDiameter') ?? 0.0) / 100.0)
            .clamp(0.0, 1.0)
            .toDouble(),
      );
    }
    sizeRandom = _jitterOf(sizeVariance, cap: 1.0);
    final angleVariance = entry.childDescriptor('angleDynamics');
    final angleControl = _controlOf(angleVariance);
    // Photoshop's control list runs Off · Fade · Pen Pressure · Pen Tilt ·
    // Stylus Wheel · Rotation · Initial Direction · Direction, so 3 is the
    // pen's lean — Clip Studio's ペンの方向 (F-176-Q1) — and 5 its turn
    // about the barrel, ペン軸の回転 (F-176-Q9).
    if (angleControl == 3) {
      rotationMode = BrushTipRotationMode.penTilt;
    }
    if (angleControl == 5) {
      rotationMode = BrushTipRotationMode.penTwist;
    }
    if (angleControl == 6 || angleControl == 7) {
      rotationMode = BrushTipRotationMode.direction;
    }
    angleJitter = _jitterOf(angleVariance, cap: 1.0);
  }
  BrushPressureCurve? opacityPressureCurve;
  BrushPressureCurve? flowPressureCurve;
  var opacityRandom = 0.0;
  var flowRandom = 0.0;
  if (entry['usePaintDynamics'] == true) {
    final opacityVariance = entry.childDescriptor('opVr');
    final flowVariance = entry.childDescriptor('prVr');
    // BB-3: opacity (opVr) and flow (prVr) import as their own pressure
    // channels — they used to be OR-merged into one opacity bool.
    if (_controlOf(opacityVariance) == 2) {
      opacityPressureCurve = BrushPressureCurve.identity();
    }
    if (_controlOf(flowVariance) == 2) {
      flowPressureCurve = BrushPressureCurve.identity();
    }
    // Each jitter is its own setting's ランダム row now (F-176-Q2) — flow
    // used to fold into opacity's for want of a row of its own.
    opacityRandom = _jitterOf(opacityVariance, cap: 1.0);
    flowRandom = _jitterOf(flowVariance, cap: 1.0);
  }
  // Dual brush: the nested second tip, a second stroke along the path — its
  // own spacing, angle, roundness and scatter written with the keys the
  // main tip's are, so they are read by the same readers.
  //
  // ✏️ITS BLEND MODE ARRIVES NOW (v33). `dualBrush.BlnM` was measured across
  // the user's seven .abr packs — 765 brushes — and EIGHT codes are in
  // actual use (Mltp·Drkn·Ovrl·CBrn·CDdg and more), all of which the table
  // below already reads for the main brush. Until the engine had a field
  // for it every one of them arrived as a plain multiply.
  //
  // ↩️Not all of them: 🔬counted again 2026-10-17 over the user's nine packs
  // (brush-fidelity) — Mltp 52 · Ovrl 50 · CBrn 46 · linearHeight 37 · Drkn
  // 12 · linearBurn 11 · hardMix 10 · CDdg 2. linearBurn and hardMix read
  // since the brush learned them; linearHeight, a mode Photoshop offers a
  // dual tip and a texture and nothing else, still arrives as multiply.
  BrushTipMask? dualMask;
  var dualMaskScale = 1.0;
  var dualCompositeMode = SeparableBlendMode.multiply;
  ({
    ({double spacingRatio, double angleDegrees, double roundness}) tip,
    ({double radiusRatio, int count, bool bothAxes}) scatter,
  })?
  dualWay;
  final dualBrush = entry.childDescriptor('dualBrush');
  if (dualBrush != null && dualBrush['useDualBrush'] == true) {
    final dualTip = dualBrush.childDescriptor('Brsh');
    final dualKey = dualTip?.textValue('sampledData');
    if (dualKey != null) {
      dualMask = tipsByKey[dualKey];
      if (dualMask != null) {
        usedTipKeys.add(dualKey);
        dualWay = (
          tip: _tipPlacementOf(dualTip!),
          scatter: _scatterOf(dualBrush),
        );
        final dualDiameter = dualTip.numberValue('Dmtr');
        if (dualDiameter != null && dualDiameter > 0 && diameter > 0) {
          dualMaskScale = (dualDiameter / diameter)
              .clamp(0.05, 10.0)
              .toDouble();
        }
      } else {
        warnings.add(
          'Brush "${name ?? sampledKey ?? ''}": dual-brush tip bitmap '
          'missing; imported without the dual texture.',
        );
      }
    }
    // ⛔Read through the SAME table the main brush reads, then narrowed to
    // the separable half — a dual tip combines two COVERAGES, and the
    // porter-duff heads answer a question about pixels and alpha that a
    // mask pair does not ask.
    //
    // 🚨SAYING NOTHING IS NOT SAYING SOMETHING UNREADABLE. A brush with no
    // `BlnM` at all keeps the multiply in silence; only a file that NAMES a
    // mode this app cannot combine two tips with is worth a line. The
    // fixture caught the difference: `Fancy Chalk` states no dual blend and
    // was being warned about.
    final dualBlendValue = dualBrush['BlnM'];
    if (dualBlendValue != null) {
      final dualBlend = _blendModeOf(dualBlendValue).separable;
      if (dualBlend != null) {
        dualCompositeMode = dualBlend;
      } else if (dualMask != null) {
        warnings.add(
          'Brush "${name ?? sampledKey ?? ''}": dual-brush blend mode is not '
          'one this app can combine two tips with; imported as multiply.',
        );
      }
    }
  }

  // Paper texture: the descriptor names a pattern from the `patt` section by
  // uuid, and the engine anchors it to the canvas exactly like the Clip
  // Studio one.
  BrushTipMask? textureMask;
  var textureInvert = false;
  var textureBrightness = 0.0;
  var textureContrast = 0.0;
  var textureScale = 1.0;
  var textureDensity = 1.0;
  if (entry['useTexture'] == true) {
    final label = name ?? sampledKey ?? '';
    final reference = entry.childDescriptor('Txtr');
    final patternId = reference?.textValue('Idnt');
    final pattern = patternId == null ? null : patternsById[patternId];
    if (pattern == null) {
      warnings.add(
        'Brush "$label": paper texture '
        '"${reference?.textValue('Nm  ') ?? patternId ?? 'unknown'}" is not '
        'embedded in this file; imported without it.',
      );
    } else {
      // ⛔The levels are CARRIED, not baked in here any more. Baking made
      // them unreachable forever: nothing kept the original to re-bake from,
      // so the panel could never offer the three controls Photoshop and Clip
      // Studio both put on a texture.
      textureMask = brushTipMaskFromPattern(
        pattern,
        id: 'abr-pattern-${pattern.id}',
      );
      textureInvert = entry['InvT'] == true;
      textureBrightness = ((entry.numberValue('textureBrightness') ?? 0.0) /
              100.0)
          .clamp(-1.0, 1.0)
          .toDouble();
      textureContrast =
          ((entry.numberValue('textureContrast') ?? 0.0) / 100.0)
              .clamp(-1.0, 1.0)
              .toDouble();
      final scalePercent = entry.numberValue('textureScale');
      if (scalePercent != null && scalePercent > 0) {
        textureScale = (scalePercent / 100.0).clamp(0.05, 10.0).toDouble();
      }
      // Photoshop's texture "depth" is the same knob as Clip Studio's
      // density: how far the paper is allowed to eat into the coverage.
      final depthPercent = entry.numberValue('textureDepth');
      if (depthPercent != null) {
        textureDensity = (depthPercent / 100.0).clamp(0.0, 1.0).toDouble();
      }
    }
  }

  final scatter = _scatterOf(entry);

  final id = uniquePresetId(
    sampledKey != null
        ? 'abr-$sampledKey'
        : 'abr-$sourceName-computed-${computedIndex()}',
  );
  final fallbackName = sampledKey != null
      ? '$sourceName brush'
      : '$sourceName round';

  return BrushPreset(
    id: id,
    name: (name == null || name.isEmpty) ? fallbackName : name,
    settings: _settingsForTip(
      mask,
      diameterPixels: diameter,
      spacingRatio: placement.spacingRatio,
      angleDegrees: placement.angleDegrees,
      roundness: placement.roundness,
      hardness: hardnessPercent / 100.0,
      opacity: opacityPercent / 100.0,
      flow: flowPercent / 100.0,
      sizePressureCurve: sizePressureCurve,
      opacityPressureCurve: opacityPressureCurve,
      flowPressureCurve: flowPressureCurve,
      sizeRandom: sizeRandom,
      opacityRandom: opacityRandom,
      flowRandom: flowRandom,
      angleJitter: angleJitter,
      rotationMode: rotationMode,
      scatterRadiusRatio: scatter.radiusRatio,
      scatterCount: scatter.count,
      scatterBothAxes: scatter.bothAxes,
      dualMask: dualMask,
      dualMaskScale: dualMaskScale,
      dualCompositeMode: dualCompositeMode,
      dualWay: dualWay,
      textureMaskSource: textureMask,
      textureInvert: textureInvert,
      textureBrightness: textureBrightness,
      textureContrast: textureContrast,
      textureScale: textureScale,
      textureDensity: textureDensity,
      blendMode: blendMode,
    ),
  );
}

/// The blend a Photoshop brush composites with.
///
/// Photoshop names its blends with the PSD format's four-character keys,
/// and the modes newer than the format's first with string ids
/// (`linearBurn`, `blendSubtraction` …) — the `BlnM` enumeration's own
/// terms. An unrecognised key falls back to [BrushBlendMode.color] — which
/// is why Photoshop's "Clear" is deliberately absent: guessing its key
/// wrong would turn a paint brush into an eraser.
///
/// ⚠️Only `Nrml` and `Mltp` occur as a MAIN blend in the user's nine packs
/// (🔬2026-10-17); `linearBurn` and `hardMix` are measured there as DUAL
/// blends, read through this same table. The rest are the enumeration's
/// documented terms, unmeasured.
///
/// ⛔This used to answer "does this brush PIN a blend?" and returned null for
/// 'Nrml'. It does not any more (유저 2026-09-08) — see the Clip Studio
/// importer's twin for why the rule is shared.
BrushBlendMode _blendModeOf(Object? value) {
  if (value is! PsEnum) {
    return BrushBlendMode.color;
  }
  return switch (value.value) {
    'Nrml' => BrushBlendMode.color,
    'Mltp' => BrushBlendMode.multiply,
    'Drkn' => BrushBlendMode.darken,
    'CBrn' => BrushBlendMode.colorBurn,
    'linearBurn' => BrushBlendMode.linearBurn,
    'blendSubtraction' => BrushBlendMode.subtract,
    'Lghn' => BrushBlendMode.lighten,
    'Scrn' => BrushBlendMode.screen,
    'CDdg' => BrushBlendMode.colorDodge,
    'linearDodge' => BrushBlendMode.add,
    'Ovrl' => BrushBlendMode.overlay,
    'SftL' => BrushBlendMode.softLight,
    'HrdL' => BrushBlendMode.hardLight,
    'Dfrn' => BrushBlendMode.difference,
    'vividLight' => BrushBlendMode.vividLight,
    'linearLight' => BrushBlendMode.linearLight,
    'pinLight' => BrushBlendMode.pinLight,
    'hardMix' => BrushBlendMode.hardMix,
    'Xclu' => BrushBlendMode.exclusion,
    'darkerColor' => BrushBlendMode.darkerColor,
    'lighterColor' => BrushBlendMode.lighterColor,
    'blendDivide' => BrushBlendMode.divide,
    'H   ' => BrushBlendMode.hue,
    'Strt' => BrushBlendMode.saturation,
    'Clr ' => BrushBlendMode.chroma,
    'Lmns' => BrushBlendMode.luminosity,
    'Bhnd' => BrushBlendMode.behind,
    _ => BrushBlendMode.color,
  };
}

/// Control type of a `brVr` dynamics descriptor (0 = off, 2 = pen
/// pressure, 6/7 = direction).
int _controlOf(PsDescriptor? variance) {
  if (variance == null) {
    return 0;
  }
  final value = variance['bVTy'];
  return value is int ? value : 0;
}

/// Jitter ratio of a `brVr` dynamics descriptor (percent -> ratio).
double _jitterOf(PsDescriptor? variance, {required double cap}) {
  if (variance == null) {
    return 0.0;
  }
  return ((variance.numberValue('jitter') ?? 0.0) / 100.0)
      .clamp(0.0, cap)
      .toDouble();
}

BrushSettings _settingsForTip(
  BrushTipMask? mask, {
  required double diameterPixels,
  required double spacingRatio,
  required double angleDegrees,
  required double roundness,
  double hardness = 1.0,
  double opacity = 1.0,
  double flow = 1.0,
  BrushPressureCurve? sizePressureCurve,
  BrushPressureCurve? opacityPressureCurve,
  BrushPressureCurve? flowPressureCurve,
  double sizeRandom = 0.0,
  double opacityRandom = 0.0,
  double flowRandom = 0.0,
  double angleJitter = 0.0,
  BrushTipRotationMode rotationMode = BrushTipRotationMode.fixed,
  double scatterRadiusRatio = 0.0,
  int scatterCount = 1,
  bool scatterBothAxes = true,
  BrushTipMask? dualMask,
  double dualMaskScale = 1.0,
  SeparableBlendMode dualCompositeMode = SeparableBlendMode.multiply,
  ({
    ({double spacingRatio, double angleDegrees, double roundness}) tip,
    ({double radiusRatio, int count, bool bothAxes}) scatter,
  })?
  dualWay,
  BrushTipMask? textureMaskSource,
  bool textureInvert = false,
  double textureBrightness = 0.0,
  double textureContrast = 0.0,
  double textureScale = 1.0,
  double textureDensity = 1.0,
  BrushBlendMode blendMode = BrushBlendMode.color,
}) {
  final settings = BrushSettings(
    size: diameterPixels.isFinite && diameterPixels > 0 ? diameterPixels : 24,
    spacing: _spacingFrom(spacingRatio),
    angleDegrees: _angleFrom(angleDegrees),
    roundness: _roundnessFrom(roundness),
    hardness: hardness.isFinite ? hardness.clamp(0.0, 1.0).toDouble() : 1.0,
    opacity: opacity.isFinite ? opacity.clamp(0.0, 1.0).toDouble() : 1.0,
    flow: flow.isFinite ? flow.clamp(0.0, 1.0).toDouble() : 1.0,
    tips: [?mask],
    sizePressureCurve: sizePressureCurve,
    opacityPressureCurve: opacityPressureCurve,
    flowPressureCurve: flowPressureCurve,
    curves: {
      for (final (target, amount) in [
        (BrushPressureTarget.size, sizeRandom),
        (BrushPressureTarget.opacity, opacityRandom),
        (BrushPressureTarget.flow, flowRandom),
      ])
        if (amount > 0.0)
          (target, BrushInputSource.random): BrushPressureCurve.linearFrom(
            1.0 - amount,
          ),
    },
    angleJitter: angleJitter,
    rotationMode: rotationMode,
    scatterRadiusRatio: scatterRadiusRatio,
    scatterCount: scatterCount,
    scatterBothAxes: scatterBothAxes,
    dualMask: dualMask,
    dualMaskScale: dualMaskScale,
    dualCompositeMode: dualCompositeMode,
    textureMaskSource: textureMaskSource,
    textureInvert: textureInvert,
    textureBrightness: textureBrightness,
    textureContrast: textureContrast,
    textureScale: textureScale,
    textureDensity: textureDensity,
    blendMode: blendMode,
  );
  if (dualWay == null) {
    return settings;
  }
  final (:tip, :scatter) = dualWay;
  return settings.copyWith(
    dualSpacing: _spacingFrom(tip.spacingRatio),
    dualAngleDegrees: _angleFrom(tip.angleDegrees),
    dualRoundness: _roundnessFrom(tip.roundness),
    dualScatterRadiusRatio: scatter.radiusRatio,
    dualScatterCount: scatter.count,
    dualScatterBothAxes: scatter.bothAxes,
  );
}

/// A tip's spacing, angle and roundness as a brush descriptor writes them —
/// the main tip's `Brsh`, or the dual brush's, which has the same keys.
({double spacingRatio, double angleDegrees, double roundness})
_tipPlacementOf(PsDescriptor tip) => (
  spacingRatio: (tip.numberValue('Spcn') ?? 25.0) / 100.0,
  angleDegrees: tip.numberValue('Angl') ?? 0.0,
  roundness: (tip.numberValue('Rndn') ?? 100.0) / 100.0,
);

/// The scatter [brush] writes — the brush entry's, or its dual brush's,
/// which carries `useScatter`, `Cnt `, `bothAxes` and `scatterDynamics`
/// under the same keys.
({double radiusRatio, int count, bool bothAxes}) _scatterOf(
  PsDescriptor brush,
) {
  if (brush['useScatter'] != true) {
    return (radiusRatio: 0.0, count: 1, bothAxes: true);
  }
  return (
    radiusRatio: _jitterOf(
      brush.childDescriptor('scatterDynamics'),
      cap: 10.0,
    ),
    count: (brush.numberValue('Cnt ') ?? 1.0).round().clamp(1, 16),
    bothAxes: brush['bothAxes'] == true,
  );
}

double _spacingFrom(double ratio) => ratio.isFinite && ratio > 0
    ? ratio.clamp(0.01, 10.0).toDouble()
    : 0.25;

/// Photoshop angles span -180..180; the ellipse repeats every 180.
double _angleFrom(double degrees) {
  final normalized = ((degrees % 180.0) + 180.0) % 180.0;
  return normalized.isFinite ? normalized : 0.0;
}

double _roundnessFrom(double roundness) =>
    roundness.isFinite ? roundness.clamp(0.01, 1.0).toDouble() : 1.0;
