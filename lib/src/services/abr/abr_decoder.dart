import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/brush_blend_mode.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_settings.dart';
import '../../models/brush_tip_mask.dart';
import '../../models/brush_tip_rotation_mode.dart';
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
class AbrDecodeException implements Exception {
  const AbrDecodeException(this.message);

  final String message;

  @override
  String toString() => 'AbrDecodeException: $message';
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
    throw const AbrDecodeException('File is too short to be an ABR file.');
  }
  final version = reader.readInt16();
  if (version == 1 || version == 2) {
    throw AbrDecodeException(
      'ABR version $version (Photoshop 6 era) is not supported yet; '
      're-save the brushes with a modern Photoshop.',
    );
  }
  if (version != 6 && version != 7 && version != 10) {
    throw AbrDecodeException('Not a supported ABR file (version $version).');
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
      throw const AbrDecodeException('Corrupt ABR section length.');
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
    throw const AbrDecodeException('No brushes found in the ABR file.');
  }

  final presets = <BrushPreset>[];
  final usedTipKeys = <String>{};
  // Multiple brushes may share one sampled tip (variants of the same
  // bitmap with different settings — common in artist packs), so preset
  // ids must be de-collided; the suffixes are order-deterministic, keeping
  // re-imports of the same file replacing instead of duplicating.
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
        uniquePresetId: uniquePresetId,
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
        id: uniquePresetId('abr-$key'),
        name: '$sourceName tip $unnamedIndex',
        settings: _settingsForTip(
          tipsByKey[key]!,
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
      'The ABR file contained no importable brushes.',
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
      final mask = _squareMaskFromTipPixels(
        key: key,
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

/// Pads a tip bitmap to a centered square, matching the engine's
/// square-mask requirement.
BrushTipMask _squareMaskFromTipPixels({
  required String key,
  required Uint8List pixels,
  required int width,
  required int height,
}) {
  final side = math.max(width, height);
  final alpha = Uint8List(side * side);
  final offsetX = (side - width) ~/ 2;
  final offsetY = (side - height) ~/ 2;
  for (var y = 0; y < height; y += 1) {
    alpha.setRange(
      (offsetY + y) * side + offsetX,
      (offsetY + y) * side + offsetX + width,
      pixels,
      y * width,
    );
  }
  return BrushTipMask(id: 'abr-$key', size: side, alpha: alpha);
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
  final spacingPercent = tip.numberValue('Spcn') ?? 25.0;
  final angle = tip.numberValue('Angl') ?? 0.0;
  final roundnessPercent = tip.numberValue('Rndn') ?? 100.0;
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
  final blendLock = _blendLockOf(toolOptions?['Md  ']);

  // Dynamics live at the preset level (sibling of 'Brsh'), gated by the
  // useTipDynamics / usePaintDynamics switches. Control type ('bVTy')
  // 2 = pen pressure; 6/7 = initial direction / direction.
  BrushPressureCurve? sizePressureCurve;
  var sizeJitter = 0.0;
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
    sizeJitter = _jitterOf(sizeVariance, cap: 1.0);
    final angleVariance = entry.childDescriptor('angleDynamics');
    final angleControl = _controlOf(angleVariance);
    if (angleControl == 6 || angleControl == 7) {
      rotationMode = BrushTipRotationMode.direction;
    }
    angleJitter = _jitterOf(angleVariance, cap: 1.0);
  }
  BrushPressureCurve? opacityPressureCurve;
  BrushPressureCurve? flowPressureCurve;
  var opacityJitter = 0.0;
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
    opacityJitter = math.max(
      _jitterOf(opacityVariance, cap: 1.0),
      _jitterOf(flowVariance, cap: 1.0),
    );
  }
  // Dual brush: the nested second tip multiplies the primary coverage.
  // Photoshop's per-blend-mode combine is approximated as multiply, and
  // the dual tip's own spacing/scatter is approximated by the per-dab
  // random tile phase.
  BrushTipMask? dualMask;
  var dualMaskScale = 1.0;
  final dualBrush = entry.childDescriptor('dualBrush');
  if (dualBrush != null && dualBrush['useDualBrush'] == true) {
    final dualTip = dualBrush.childDescriptor('Brsh');
    final dualKey = dualTip?.textValue('sampledData');
    if (dualKey != null) {
      dualMask = tipsByKey[dualKey];
      if (dualMask != null) {
        usedTipKeys.add(dualKey);
        final dualDiameter = dualTip?.numberValue('Dmtr');
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
  }

  // Paper texture: the descriptor names a pattern from the `patt` section by
  // uuid, and the engine anchors it to the canvas exactly like the Clip
  // Studio one.
  BrushTipMask? textureMask;
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
      textureMask = brushTipMaskWithLevels(
        brushTipMaskFromPattern(pattern, id: 'abr-pattern-${pattern.id}'),
        invert: entry['InvT'] == true,
        brightness: ((entry.numberValue('textureBrightness') ?? 0.0) / 100.0)
            .clamp(-1.0, 1.0)
            .toDouble(),
        contrast: ((entry.numberValue('textureContrast') ?? 0.0) / 100.0)
            .clamp(-1.0, 1.0)
            .toDouble(),
      );
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

  var scatterRadiusRatio = 0.0;
  var scatterCount = 1;
  var scatterBothAxes = true;
  if (entry['useScatter'] == true) {
    scatterRadiusRatio = _jitterOf(
      entry.childDescriptor('scatterDynamics'),
      cap: 10.0,
    );
    scatterCount = (entry.numberValue('Cnt ') ?? 1.0).round().clamp(1, 16);
    scatterBothAxes = entry['bothAxes'] == true;
  }

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
      spacingRatio: spacingPercent / 100.0,
      angleDegrees: angle,
      roundness: roundnessPercent / 100.0,
      hardness: hardnessPercent / 100.0,
      opacity: opacityPercent / 100.0,
      flow: flowPercent / 100.0,
      sizePressureCurve: sizePressureCurve,
      opacityPressureCurve: opacityPressureCurve,
      flowPressureCurve: flowPressureCurve,
      sizeJitter: sizeJitter,
      opacityJitter: opacityJitter,
      angleJitter: angleJitter,
      rotationMode: rotationMode,
      scatterRadiusRatio: scatterRadiusRatio,
      scatterCount: scatterCount,
      scatterBothAxes: scatterBothAxes,
      dualMask: dualMask,
      dualMaskScale: dualMaskScale,
      textureMask: textureMask,
      textureScale: textureScale,
      textureDensity: textureDensity,
      lockedBlendMode: blendLock,
    ),
  );
}

/// The blend a Photoshop brush pins, or null to leave the hand setting be.
///
/// Photoshop names its blends with the PSD format's four-character keys.
/// Only a non-normal one locks — see the Clip Studio importer for why the
/// rule is shared. An unrecognised key simply does not lock, which is why
/// Photoshop's "Clear" is deliberately absent: guessing its key wrong would
/// turn a paint brush into an eraser.
BrushBlendMode? _blendLockOf(Object? value) {
  if (value is! PsEnum) {
    return null;
  }
  return switch (value.value) {
    'Nrml' => null,
    'Mltp' => BrushBlendMode.multiply,
    'Drkn' => BrushBlendMode.darken,
    'CBrn' => BrushBlendMode.colorBurn,
    'Lghn' => BrushBlendMode.lighten,
    'Scrn' => BrushBlendMode.screen,
    'CDdg' => BrushBlendMode.colorDodge,
    'linearDodge' => BrushBlendMode.add,
    'Ovrl' => BrushBlendMode.overlay,
    'SftL' => BrushBlendMode.softLight,
    'HrdL' => BrushBlendMode.hardLight,
    'Dfrn' => BrushBlendMode.difference,
    'Xclu' => BrushBlendMode.exclusion,
    'Bhnd' => BrushBlendMode.behind,
    _ => null,
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
  double sizeJitter = 0.0,
  double opacityJitter = 0.0,
  double angleJitter = 0.0,
  BrushTipRotationMode rotationMode = BrushTipRotationMode.fixed,
  double scatterRadiusRatio = 0.0,
  int scatterCount = 1,
  bool scatterBothAxes = true,
  BrushTipMask? dualMask,
  double dualMaskScale = 1.0,
  BrushTipMask? textureMask,
  double textureScale = 1.0,
  double textureDensity = 1.0,
  BrushBlendMode? lockedBlendMode,
}) {
  // Photoshop angles span -180..180; the ellipse repeats every 180.
  final normalizedAngle = ((angleDegrees % 180.0) + 180.0) % 180.0;
  return BrushSettings(
    size: diameterPixels.isFinite && diameterPixels > 0 ? diameterPixels : 24,
    spacing: spacingRatio.isFinite && spacingRatio > 0
        ? spacingRatio.clamp(0.01, 10.0).toDouble()
        : 0.25,
    angleDegrees: normalizedAngle.isFinite ? normalizedAngle : 0.0,
    roundness: roundness.isFinite ? roundness.clamp(0.01, 1.0).toDouble() : 1.0,
    hardness: hardness.isFinite ? hardness.clamp(0.0, 1.0).toDouble() : 1.0,
    opacity: opacity.isFinite ? opacity.clamp(0.0, 1.0).toDouble() : 1.0,
    flow: flow.isFinite ? flow.clamp(0.0, 1.0).toDouble() : 1.0,
    tipMask: mask,
    sizePressureCurve: sizePressureCurve,
    opacityPressureCurve: opacityPressureCurve,
    flowPressureCurve: flowPressureCurve,
    sizeJitter: sizeJitter,
    opacityJitter: opacityJitter,
    angleJitter: angleJitter,
    rotationMode: rotationMode,
    scatterRadiusRatio: scatterRadiusRatio,
    scatterCount: scatterCount,
    scatterBothAxes: scatterBothAxes,
    dualMask: dualMask,
    dualMaskScale: dualMaskScale,
    textureMask: textureMask,
    textureScale: textureScale,
    textureDensity: textureDensity,
    lockedBlendMode: lockedBlendMode,
  );
}
