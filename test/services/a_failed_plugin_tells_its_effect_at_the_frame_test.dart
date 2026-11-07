@TestOn('vm')
library;

import 'dart:io';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_fx_plugin_host.dart';
import 'package:anicel/src/services/cel_surface_as_shown.dart';
import 'package:anicel/src/services/fx_plugins/device_fx_plugin_binding.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_outcomes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/a_plugin_that_shifts.dart';

/// 🗣️a-failed-plugin-shows-the-cel-silently-Q1 (유저 2026-11-08): 「원래 셀
/// + 머리를 회색으로, 이름 뒤 ⚠ 칸은 늘 잡아 둔다」 — a plugin that cannot
/// draw a cel leaves the cel as it is, and its effect is told it failed at
/// that frame, which its fx row's header reads.
///
/// The plugin is the sample's WebAssembly twin through the engine's host,
/// failing for real: its memory is two pages (128 KB), and a paper of
/// 256 × 256 does not fit in it — the room the host asks for the frame is
/// refused (native/fx_plugin `wasm.rs`, NO_ROOM).
void main() {
  test('a plugin that cannot draw tells its effect so at that frame, each '
      'time the cel is shown — and one that draws clears it', () {
    final host = QaFxPluginHost.instance!;
    final twin = host
        .openWasm(File('test/fixtures/fx/sample_twin.wasm').readAsBytesSync())
        .plugin!;
    addTearDown(twin.close);
    final effect = LayerEffect.defaults(
      id: const EffectId('fx'),
      kind: EffectKind.plugin,
      plugin: FxPluginDescription.read(twin.describe()!),
    );
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    final binding = deviceFxPluginBinding(
      runnerFor: (_) => twin,
      frameRate: ProjectFrameRate.fps24,
      surfaceOf: (_, _) => null,
      outcomes: outcomes,
    );
    final row = Layer(
      id: const LayerId('a'),
      name: 'a',
      kind: LayerKind.animation,
      frames: const [],
      effects: [effect],
    );
    BitmapSurface blank(int side) => BitmapSurface(
      canvasSize: CanvasSize(width: side, height: side),
      pasteboardReach: PasteboardReach.none,
      tileSize: 64,
      tiles: const {},
    );
    BitmapSurface shown(BitmapSurface cel, int frame) => celSurfaceAsShown(
      cel,
      binding(
        resolveLayerEffectsAt(effects: [effect], frameIndex: frame, blocks: null),
        cut: Cut(
          id: const CutId('c'),
          name: 'c',
          duration: 8,
          canvasSize: cel.canvasSize,
          layers: [row],
        ),
        frameIndex: frame,
      ),
    );
    final big = blank(256);
    final small = blank(8);

    expect(identical(shown(big, 3), big), isTrue,
        reason: 'the cel as it is, as if the effect were off');
    expect(outcomes.failedAt(effect, 3), isTrue);
    expect(outcomes.failedAt(effect, 4), isFalse,
        reason: 'the frame it failed at, and no other');

    expect(identical(shown(small, 3), small), isFalse, reason: 'it drew');
    expect(outcomes.failedAt(effect, 3), isFalse,
        reason: 'drawn at that frame, the mark goes');

    shown(big, 3);
    expect(outcomes.failedAt(effect, 3), isTrue,
        reason: 'a picture kept from before is told as a made one is');
  });

  testWidgets('an installed plugin that will not open fails as a run does — '
      'told, not drawn as if off with nothing to say', (tester) async {
    final plugins = await installedShiftingFxPlugin(tester, opens: false);
    final runner = plugins.runnerFor(shiftingFxPluginDescription);
    expect(runner, isNotNull);
    expect(
      identical(plugins.runnerFor(shiftingFxPluginDescription), runner),
      isTrue,
      reason: 'kept, not opened again each frame',
    );
    final effect = shiftingFxPluginLayerEffect();
    final binding = deviceFxPluginBinding(
      runnerFor: plugins.runnerFor,
      frameRate: ProjectFrameRate.fps24,
      surfaceOf: (_, _) => null,
      outcomes: plugins.outcomes,
    );
    const paper = CanvasSize(width: 8, height: 8);
    final cel = BitmapSurface(
      canvasSize: paper,
      pasteboardReach: PasteboardReach.none,
      tileSize: 8,
      tiles: const {},
    );
    final row = Layer(
      id: const LayerId('a'),
      name: 'a',
      kind: LayerKind.animation,
      frames: const [],
      effects: [effect],
    );
    final shown = celSurfaceAsShown(
      cel,
      binding(
        resolveLayerEffectsAt(effects: [effect], frameIndex: 2, blocks: null),
        cut: Cut(
          id: const CutId('c'),
          name: 'c',
          duration: 4,
          canvasSize: paper,
          layers: [row],
        ),
        frameIndex: 2,
      ),
    );

    expect(identical(shown, cel), isTrue);
    expect(plugins.outcomes.failedAt(effect, 2), isTrue);
  });

  test('a run is heard once the picture is made, once for the tells before '
      'it, and only where the outcome changed', () async {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    final effect = LayerEffect.defaults(
      id: const EffectId('fx'),
      kind: EffectKind.blur,
    );
    var heard = 0;
    outcomes.addListener(() => heard += 1);

    outcomes
      ..tell(effect, 1, failed: true)
      ..tell(effect, 2, failed: true)
      ..tell(effect, 1, failed: true);
    expect(heard, 0, reason: 'not while the picture is being made');
    await Future<void>.delayed(Duration.zero);
    expect(heard, 1);

    outcomes.tell(effect, 2, failed: true);
    await Future<void>.delayed(Duration.zero);
    expect(heard, 1, reason: 'no change, nothing to hear');

    outcomes.tell(effect, 2, failed: false);
    await Future<void>.delayed(Duration.zero);
    expect(heard, 2);
    expect(outcomes.failedAt(effect, 2), isFalse);
    expect(outcomes.failedAt(effect, 1), isTrue);
  });
}
