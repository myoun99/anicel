import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/services/export/ae_effects.dart';
import 'package:anicel/src/services/export/ae_script.dart';

/// The app's effects as After Effects' nearest, by the table measured in
/// After Effects 2025 (ae-script-export-Q5, 유저 2026-10-16 「앱 계산은 앱
/// 것 — AE 탭은 가장 가까운 AE 이펙트로」). How each is said to After
/// Effects is `ae_script_test.dart`'s; that After Effects draws them so,
/// checked there (2026-10-30).
void main() {
  const paper = CanvasSize(width: 40, height: 20);

  LayerEffect effectOf(EffectKind kind, Map<String, double> values) =>
      LayerEffect(
        id: const EffectId('e'),
        kind: kind,
        parameters: {
          for (final MapEntry(:key, :value) in values.entries)
            key: EffectParameter(value: value),
        },
      );

  AeEffect aeOf(LayerEffect effect, {int frames = 1}) =>
      aeEffectOf(effect, frames: frames, paper: paper)!;

  List<double> still(AeEffect effect, String number) =>
      effect.values['${effect.matchName}-$number']!.value!;

  test('Brightness & Contrast is AE\'s legacy one: brightness in 0…255, '
      'positive contrast as steep as the app\'s', () {
    final ae = aeOf(
      effectOf(EffectKind.brightnessContrast, {
        'brightness': 20,
        'contrast': 50,
      }),
    );
    expect(ae.matchName, 'ADBE Brightness & Contrast 2');
    expect(still(ae, '0001'), [51]);
    // The app steepens by 1.5; AE's 100 / (100 − c) is 1.5 at 33.3.
    expect(still(ae, '0002').single, closeTo(100 / 3, 1e-9));
    expect(still(ae, '0003'), [1]);
    expect(
      still(
        aeOf(effectOf(EffectKind.brightnessContrast, {'contrast': -40})),
        '0002',
      ),
      [-40],
      reason: 'below 0 the two steepen alike',
    );
  });

  test('a Gaussian\'s Blurriness is turned to AE\'s sigma, its menu to AE\'s '
      'count from 1', () {
    final ae = aeOf(
      effectOf(EffectKind.blur, {
        'blurriness': 30,
        'blurDimensions': 2,
        'repeatEdgePixels': 1,
      }),
    );
    expect(ae.matchName, 'ADBE Gaussian Blur 2');
    expect(still(ae, '0001').single, closeTo(30 * 1.17, 1e-9));
    expect(still(ae, '0002'), [3], reason: 'the app\'s third word, Vertical');
    expect(still(ae, '0003'), [1]);
  });

  test('a Directional Blur\'s length is turned to AE\'s tent', () {
    final ae = aeOf(
      effectOf(EffectKind.directionalBlur, {'direction': 90, 'blurLength': 40}),
    );
    expect(ae.matchName, 'ADBE Motion Blur');
    expect(still(ae, '0001'), [90]);
    expect(still(ae, '0002').single, closeTo(40 * 0.93, 1e-9));
  });

  test('a colour key is AE\'s Linear Color Key: its colour, its tolerance '
      'a percent, its Amount the effect\'s opacity', () {
    final ae = aeOf(
      LayerEffect(
        id: const EffectId('e'),
        kind: EffectKind.colorKey,
        parameters: {
          'tolerance': EffectParameter(value: 51),
          'amount': EffectParameter(value: 60),
          'keyOperation': EffectParameter(value: 1),
        },
        colors: {
          'keyColor': PropertyTrack<int>(
            keys: {0: const PropertyKey<int>(0xFF336699)},
          ),
        },
      ),
    );
    expect(ae.matchName, 'ADBE Linear Color Key2');
    expect(still(ae, '0003'), [0x33 / 255, 0x66 / 255, 0x99 / 255, 1]);
    expect(still(ae, '0005').single, closeTo(20, 1e-9));
    expect(still(ae, '0006'), [0], reason: 'the app\'s key is hard');
    expect(still(ae, '0007'), [2], reason: 'Keep Colors, AE\'s second word');
    expect(ae.opacity!.value, [60]);
  });

  test('Radial Blur takes the app\'s values as they are, its centre at '
      'rest the paper\'s middle, Best AE\'s High', () {
    final ae = aeOf(
      effectOf(EffectKind.radialBlur, {'amount': 25, 'type': 1}),
    );
    expect(ae.matchName, 'ADBE Radial Blur');
    expect(still(ae, '0001'), [25]);
    expect(still(ae, '0002'), [20, 10]);
    expect(still(ae, '0003'), [2], reason: 'Zoom');
    expect(still(ae, '0004'), [2], reason: 'Best is High');
  });

  test('Camera Lens Blur divides what the app holds in 0…255 down to AE\'s '
      '0…1', () {
    final ae = aeOf(
      effectOf(EffectKind.cameraLensBlur, {
        'blurRadius': 12,
        'highlightThreshold': 204,
        'blurFocalDistance': 51,
      }),
    );
    expect(ae.matchName, 'ADBE Camera Lens Blur');
    expect(still(ae, '0001'), [12]);
    expect(still(ae, '0018').single, closeTo(0.8, 1e-9));
    expect(still(ae, '0013').single, closeTo(0.2, 1e-9));
  });

  test('Hue/Saturation is AE\'s master three', () {
    final ae = aeOf(
      effectOf(EffectKind.hueSaturation, {
        'hue': -30,
        'saturation': 40,
        'lightness': 10,
      }),
    );
    expect(ae.matchName, 'ADBE HUE SATURATION');
    expect(
      [still(ae, '0004'), still(ae, '0005'), still(ae, '0006')],
      [
        [-30],
        [40],
        [10],
      ],
    );
  });

  test('a keyed value is AE\'s at every frame; a switched-off effect is '
      'carried switched off', () {
    final ae = aeOf(
      LayerEffect(
        id: const EffectId('e'),
        kind: EffectKind.blur,
        enabled: false,
        parameters: {
          'blurriness': EffectParameter(
            track: PropertyTrack<double>(
              keys: {
                0: const PropertyKey<double>(0),
                2: const PropertyKey<double>(20),
              },
            ),
          ),
        },
      ),
      frames: 3,
    );
    expect(ae.enabled, isFalse);
    final frames = ae.values['ADBE Gaussian Blur 2-0001']!.frames!;
    expect(frames.map((value) => value.single), [0, 10 * 1.17, 20 * 1.17]);
  });

  test('a kind After Effects has none of is not carried', () {
    expect(
      aeEffectOf(
        LayerEffect(id: const EffectId('e'), kind: EffectKind.celNumber),
        frames: 1,
        paper: paper,
      ),
      isNull,
    );
  });
}
