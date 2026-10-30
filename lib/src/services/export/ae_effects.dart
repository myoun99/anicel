import '../../models/canvas_size.dart';
import '../../models/layer_effect.dart';
import 'ae_script.dart';

/// [effect] as the After Effects effect nearest it, over a comp [frames]
/// long on [paper] — null for a kind After Effects has none of: a cel
/// number, a plugin's. Those are not carried (Q2 「날것으로 — 이펙트 없이」).
///
/// 🗣️ae-script-export-Q5 (유저 2026-10-16): 「앱 계산은 앱 것 — AE 탭은
/// 가장 가까운 AE 이펙트로」 — 「환산표는 AE 에서 한 번 재서 만든다」. The
/// table, measured in After Effects 2025 (2026-10-30, its renders sampled
/// where a known picture went through each effect):
/// - Brightness & Contrast is AE's legacy one, the app's sum to the pixel's
///   half: AE adds Brightness to 0…255 where the app adds 2.55 of it, and
///   AE's positive Contrast steepens by 100 / (100 − c) where the app's does
///   by (100 + c) / 100 (its negative is the app's). AE stops at ±150.
/// - A Gaussian's sigma is [aeBlurrinessPerBlurriness] of AE's Blurriness
///   to the app's (`blurSigmaPerRadius`).
/// - Directional Blur is a tent in AE, a box in the app: lengths matched by
///   how wide an edge goes from a quarter to three quarters
///   ([aeBlurLengthPerBlurLength]).
/// - Linear Color Key cuts at Matching Tolerance × 2.55 off the key, one
///   channel off or all three — the app's tolerance; two channels off, AE
///   lets about 15 % more through. The app's Amount is the effect's
///   opacity.
/// - Hue/Saturation, Radial Blur and Camera Lens Blur take the app's
///   values as they are: their names and ranges are AE's (I-132-Q4, their
///   forms the app's). Their menus are AE's words in AE's order, counted
///   from 1; a 0…255 the app holds where AE holds 0…1 is divided down. A
///   Camera Lens Blur's map layer is not named.
AeEffect? aeEffectOf(
  LayerEffect effect, {
  required int frames,
  required CanvasSize paper,
}) {
  final kin = _AeKin(effect, frames: frames, paper: paper);
  return switch (effect.kind) {
    EffectKind.brightnessContrast => kin.brightnessContrast(),
    EffectKind.hueSaturation => kin.hueSaturation(),
    EffectKind.blur => kin.gaussianBlur(),
    EffectKind.directionalBlur => kin.directionalBlur(),
    EffectKind.radialBlur => kin.radialBlur(),
    EffectKind.cameraLensBlur => kin.cameraLensBlur(),
    EffectKind.colorKey => kin.linearColorKey(),
    EffectKind.celNumber || EffectKind.plugin => null,
  };
}

/// After Effects' Gaussian Blurriness for the app's: AE's sigma is 0.284
/// of its Blurriness (10, 30, 60 and 100 alike), the app's a third.
const double aeBlurrinessPerBlurriness = 1.17;

/// After Effects' Directional Blur length for the app's: an edge a quarter
/// to three quarters across 0.54 of AE's length, half of the app's.
const double aeBlurLengthPerBlurLength = 0.93;

/// After Effects' legacy Contrast that steepens as the app's [contrast]
/// does: the app's (100 + c) / 100 both ways; AE's that below 0 and
/// 100 / (100 − c) above.
double aeLegacyContrastOf(double contrast) =>
    contrast <= 0 ? contrast : 100 * contrast / (100 + contrast);

/// One effect's kin in After Effects ([aeEffectOf]): the effect sampled at
/// each of the comp's frames, and a property of the kin per lane.
class _AeKin {
  _AeKin(this.effect, {required this.frames, required this.paper})
    : samples = [
        for (var frame = 0; frame < frames; frame += 1)
          sampleLayerEffectAt(effect, frame),
      ];

  final LayerEffect effect;
  final int frames;
  final CanvasSize paper;
  final List<ResolvedLayerEffect> samples;

  AeEffect brightnessContrast() => _ae('ADBE Brightness & Contrast 2', {
    '0001': _number((at) => at.parameter('brightness') * 2.55),
    '0002': _number((at) => aeLegacyContrastOf(at.parameter('contrast'))),
    '0003': const AeChannel.still([1]),
  });

  AeEffect hueSaturation() => _ae('ADBE HUE SATURATION', {
    '0004': _same('hue'),
    '0005': _same('saturation'),
    '0006': _same('lightness'),
  });

  AeEffect gaussianBlur() => _ae('ADBE Gaussian Blur 2', {
    '0001': _number(
      (at) => at.parameter('blurriness') * aeBlurrinessPerBlurriness,
    ),
    '0002': _menu('blurDimensions'),
    '0003': _flag('repeatEdgePixels'),
  });

  AeEffect directionalBlur() => _ae('ADBE Motion Blur', {
    '0001': _same('direction'),
    '0002': _number(
      (at) => at.parameter('blurLength') * aeBlurLengthPerBlurLength,
    ),
  });

  AeEffect radialBlur() => _ae('ADBE Radial Blur', {
    '0001': _same('amount'),
    '0002': _channel((at) {
      final center = effectPointOnPaper(at.points['center'], paper);
      return [center.x, center.y];
    }),
    '0003': _menu('type'),
    // The app's Best is AE's High, its second word; Draft its Low.
    '0004': _number((at) => at.parameter('antialiasing').round() == 0 ? 2 : 1),
  });

  AeEffect cameraLensBlur() => _ae('ADBE Camera Lens Blur', {
    '0001': _same('blurRadius'),
    '0003': _menu('irisShape'),
    '0004': _same('irisRoundness'),
    '0005': _same('irisAspectRatio'),
    '0006': _same('irisRotation'),
    '0007': _same('irisDiffractionFringe'),
    '0011': _menu('blurMapChannel'),
    '0013': _byte('blurFocalDistance'),
    '0014': _flag('invertBlurMap'),
    '0017': _same('highlightGain'),
    '0018': _byte('highlightThreshold'),
    '0019': _same('highlightSaturation'),
    '0021': _flag('repeatEdgePixels'),
    '0022': _flag('useLinearWorkingSpace'),
  });

  AeEffect linearColorKey() => _ae(
    'ADBE Linear Color Key2',
    {
      '0003': _channel((at) {
        final argb = at.color('keyColor');
        return [
          ((argb >> 16) & 0xFF) / 255,
          ((argb >> 8) & 0xFF) / 255,
          (argb & 0xFF) / 255,
          1,
        ];
      }),
      '0005': _number((at) => at.parameter('tolerance') / 2.55),
      '0006': const AeChannel.still([0]),
      '0007': _menu('keyOperation'),
    },
    opacity: _same('amount'),
  );

  /// [matchName] with [values] by its properties' numbers.
  AeEffect _ae(
    String matchName,
    Map<String, AeChannel> values, {
    AeChannel? opacity,
  }) => AeEffect(
    matchName: matchName,
    enabled: effect.enabled,
    opacity: opacity,
    values: {
      for (final MapEntry(key: number, value: value) in values.entries)
        '$matchName-$number': value,
    },
  );

  AeChannel _channel(List<double> Function(ResolvedLayerEffect at) value) =>
      AeChannel.sampled(frames, (frame) => value(samples[frame]));

  AeChannel _number(double Function(ResolvedLayerEffect at) value) =>
      _channel((at) => [value(at)]);

  AeChannel _same(String id) => _number((at) => at.parameter(id));

  AeChannel _menu(String id) =>
      _number((at) => at.parameter(id).roundToDouble() + 1);

  AeChannel _flag(String id) => _number((at) => at.flag(id) ? 1 : 0);

  AeChannel _byte(String id) => _number((at) => at.parameter(id) / 255);
}
