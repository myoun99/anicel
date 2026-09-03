import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';

/// 🚨★★★ONE COMPOSITE PAINT — the half #1304 left hand-written.
///
/// #1304 ("Every route composites a group the same way") unified the WALK:
/// the editing stack, the playback cache and the camera all call
/// `drawSubtreeAsImage`. It did NOT unify the PAINT that walk composites
/// with, and three hand-written copies promptly disagreed — the editing
/// stack clamped the opacity, the camera and the playback cache did not.
///
/// ⛔`Color.fromRGBO` DOES NOT CLAMP. Its constructor is `a = opacity`,
/// stored raw: 1.5 stays 1.5 and −0.2 stays −0.2, and what a backend does
/// with an alpha outside the unit range is its own business. `opacity` is a
/// bare `double` off the JSON with no model guard, so the same document
/// could composite one way on the canvas and another in playback — against
/// the standing law that the two are byte-identical.
///
/// ⛔A BEHAVIOUR TEST CANNOT CLOSE THIS. Three copies that agree today pass
/// every pixel comparison; what fails is the fourth route someone adds next
/// year. So the ratchet is a source scan (사본 금지: 전임자 삭제 + 스캔).
void main() {
  test('an opacity outside the unit range cannot leave this function', () {
    const blend = LayerBlendMode.normal;
    final over = layerCompositePaint(
      opacity: 1.5,
      blendMode: blend,
      effects: CompositeEffectPaint.none,
    );
    final under = layerCompositePaint(
      opacity: -0.2,
      blendMode: blend,
      effects: CompositeEffectPaint.none,
    );
    final opaque = layerCompositePaint(
      opacity: 1,
      blendMode: blend,
      effects: CompositeEffectPaint.none,
    );
    final clear = layerCompositePaint(
      opacity: 0,
      blendMode: blend,
      effects: CompositeEffectPaint.none,
    );
    expect(over.color.a, opaque.color.a);
    expect(under.color.a, clear.color.a);
    // ⛔Prove the fixture is not vacuous: the RAW constructor keeps 1.5.
    expect(const ui.Color.fromRGBO(0, 0, 0, 1.5).a, 1.5);
  });

  test('the blend and the CHAIN both land on it', () {
    // ⛔A `CompositeEffectPaint.none` FIXTURE CANNOT TEST THIS, and this
    // test used one: `applyTo` returns immediately on an empty chain, so
    // deleting the call outright left the assertion green. 🧪Caught by
    // mutation, not by reading. Ask for a chain that has something to say.
    final chain = resolveCompositeEffectPaint([
      ResolvedLayerEffect(
        kind: EffectKind.brightnessContrast,
        values: const [-0.5, 0],
      ),
    ]);
    expect(chain.isEmpty, isFalse, reason: 'fixture: the chain resolved');

    final paint = layerCompositePaint(
      opacity: 0.5,
      blendMode: LayerBlendMode.multiply,
      effects: chain,
    );
    expect(paint.blendMode, LayerBlendMode.multiply.paintBlendMode);
    expect(paint.color.a, closeTo(0.5, 1e-9));
    expect(
      paint.colorFilter,
      chain.colorFilter,
      reason: 'a folder whose own effects never reach the picture it '
          'composed is the failure this function exists to prevent',
    );
  });

  test('nothing in lib/ spells the alpha-only colour by hand', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      if (path.endsWith('lib/src/services/composite_effect_paint.dart')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Prose may NAME the idiom; only code may not spell it.
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (line.contains('Color.fromRGBO(0, 0, 0,')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'an alpha-only paint is built by `alphaOnly` — a hand-spelled '
          'one is a copy, and the copies already disagreed about the clamp',
    );
  });

  test('the three group routes build their paint with the one function', () {
    const routes = [
      'lib/src/ui/canvas/canvas_layer_stack_view.dart',
      'lib/src/ui/playback/cut_frame_composite_cache.dart',
      'lib/src/ui/camera/camera_frame_render_service.dart',
    ];
    for (final route in routes) {
      final source = File(route).readAsStringSync();
      expect(
        source.contains('layerCompositePaint('),
        isTrue,
        reason: '$route composites a group and must build its paint with '
            'the shared function',
      );
    }
  });
}
