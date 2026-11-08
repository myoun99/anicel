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
import 'package:anicel/src/models/string_id.dart';
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
    final place = (owner: row.id, effect: effect.id);
    BitmapSurface blank(int side) => BitmapSurface(
      canvasSize: CanvasSize(width: side, height: side),
      pasteboardReach: PasteboardReach.none,
      tileSize: 64,
      tiles: const {},
    );
    BitmapSurface shown(BitmapSurface cel, int frame) => celSurfaceAsShown(
      cel,
      binding(
        resolveLayerEffectsAt(
          effects: [effect],
          frameIndex: frame,
          blocks: null,
          worn: (owner: row.id, wearer: row.id),
        ),
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
    expect(outcomes.failedAt(place, 3), isTrue);
    expect(outcomes.failedAt(place, 4), isFalse,
        reason: 'the frame it failed at, and no other');

    expect(identical(shown(small, 3), small), isFalse, reason: 'it drew');
    expect(outcomes.failedAt(place, 3), isFalse,
        reason: 'drawn at that frame, the mark goes');

    shown(big, 3);
    expect(outcomes.failedAt(place, 3), isTrue,
        reason: 'a picture kept from before is told as a made one is');
  });

  testWidgets('an installed plugin that will not open fails as a run does — '
      'told, not drawn as if off with nothing to say — and is let go of '
      'with the plugin', (tester) async {
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
        resolveLayerEffectsAt(
          effects: [effect],
          frameIndex: 2,
          blocks: null,
          worn: (owner: row.id, wearer: row.id),
        ),
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
    final place = (owner: row.id, effect: effect.id);

    expect(identical(shown, cel), isTrue);
    expect(plugins.outcomes.failedAt(place, 2), isTrue);

    var heard = 0;
    plugins.outcomes.addListener(() => heard += 1);
    await tester.runAsync(
      () => plugins.uninstall(shiftingFxPluginDescription.id),
    );
    expect(plugins.outcomes.failedAt(place, 2), isFalse,
        reason: 'taken off, its build tells nothing of the next');
    expect(heard, 1);
  });

  const a = LayerId('a');
  const fx = EffectId('fx');
  const place = (owner: a, effect: fx);
  const cut = CutId('c');
  ResolvedLayerEffect sample(double value) => ResolvedLayerEffect(
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
    values: [value],
    frame: 1,
  );

  test('a run is heard once the picture is made, once for the tells before '
      'it, and only where the outcome changed', () async {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    final ran = sample(0);
    void tell(int frame, {required bool failed}) => outcomes.toldFor(
      (owner: a, effect: fx, wearer: a),
      ran,
      cut: cut,
      frame: frame,
    )(failed: failed);
    var heard = 0;
    outcomes.addListener(() => heard += 1);

    tell(1, failed: true);
    tell(2, failed: true);
    tell(1, failed: true);
    expect(heard, 0, reason: 'not while the picture is being made');
    await Future<void>.delayed(Duration.zero);
    expect(heard, 1);

    tell(2, failed: true);
    await Future<void>.delayed(Duration.zero);
    expect(heard, 1, reason: 'no change, nothing to hear');

    tell(2, failed: false);
    await Future<void>.delayed(Duration.zero);
    expect(heard, 2);
    expect(outcomes.failedAt(place, 2), isFalse);
    expect(outcomes.failedAt(place, 1), isTrue);
  });

  test('a run bound where its sample ran before is told at once how it went '
      'there — a picture served from a cache runs nothing to tell it', () {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    const worn = (owner: a, effect: fx, wearer: a);
    final failing = sample(1);
    final drawing = sample(2);

    outcomes.toldFor(worn, failing, cut: cut, frame: 1)(failed: true);
    outcomes.toldFor(worn, drawing, cut: cut, frame: 1)(failed: false);
    expect(outcomes.failedAt(place, 1), isFalse);

    outcomes.toldFor(worn, failing, cut: cut, frame: 1);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'the value it failed at given back, as an undo gives it');

    outcomes.toldFor(worn, sample(3), cut: cut, frame: 1);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'a sample never run there says nothing until it runs');

    outcomes.toldFor(worn, failing, cut: cut, frame: 2);
    expect(outcomes.failedAt(place, 2), isFalse,
        reason: 'recalled at the frame it ran at, and no other');
    outcomes.toldFor(worn, drawing, cut: cut, frame: 1);
    expect(outcomes.failedAt(place, 1), isFalse);
    outcomes.toldFor(
      (owner: a, effect: fx, wearer: const LayerId('b')),
      failing,
      cut: cut,
      frame: 1,
    );
    expect(outcomes.failedAt(place, 1), isFalse,
        reason: 'recalled for the row it ran over, and no other');
  });

  test('a run walks back through the samples an undo is likely to, and lets '
      'go of the oldest past them', () {
    const worn = (owner: a, effect: fx, wearer: a);
    bool recalledAfter(int others) {
      final outcomes = FxPluginOutcomes();
      addTearDown(outcomes.dispose);
      final oldest = sample(-1);
      outcomes.toldFor(worn, oldest, cut: cut, frame: 1)(failed: true);
      for (var value = 0; value < others; value++) {
        outcomes.toldFor(worn, sample(value.toDouble()), cut: cut, frame: 1)(
          failed: false,
        );
      }
      outcomes.toldFor(worn, oldest, cut: cut, frame: 1);
      return outcomes.failedAt(place, 1);
    }

    expect(recalledAfter(15), isTrue, reason: 'sixteen back, it is kept');
    expect(recalledAfter(16), isFalse, reason: 'seventeen back, it is not');
  });

  test('an effect fails where any row that wears it fails — an attach row '
      'runs its base\'s chain over its own picture, a copied row keeps its '
      'chain\'s effects', () {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    final ran = sample(0);
    void Function({required bool failed}) wornBy(StringId row, CutId cut) =>
        outcomes.toldFor(
          (owner: a, effect: fx, wearer: row),
          ran,
          cut: cut,
          frame: 1,
        );
    const attach = LayerId('attach');

    wornBy(a, cut)(failed: false);
    wornBy(attach, cut)(failed: true);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'the base draws, the attach row does not');
    wornBy(a, cut)(failed: false);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'the base drawing again leaves the attach row\'s mark');
    wornBy(attach, cut)(failed: false);
    expect(outcomes.failedAt(place, 1), isFalse);

    wornBy(a, const CutId('other'))(failed: true);
    wornBy(a, cut)(failed: false);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'the same row of another cut is another wearer');

    expect(outcomes.failedAt((owner: attach, effect: fx), 1), isFalse,
        reason: 'the attach row\'s header is of its own chain');
    expect(
      outcomes.failedAt((owner: a, effect: const EffectId('other')), 1),
      isFalse,
    );
  });

  test('forgetting a plugin lets go of its runs alone, and is heard where a '
      'mark goes', () async {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    const other = EffectId('other');
    final otherPlugin = ResolvedLayerEffect(
      kind: EffectKind.plugin,
      plugin: FxPluginDescription.fromJson({
        ...shiftingFxPluginDescription.toJson(),
        'id': 'test.other',
      }),
      values: const [],
      frame: 1,
    );
    const worn = (owner: a, effect: fx, wearer: a);
    outcomes.toldFor(worn, sample(0), cut: cut, frame: 1)(failed: true);
    outcomes.toldFor(
      (owner: a, effect: other, wearer: a),
      otherPlugin,
      cut: cut,
      frame: 1,
    )(failed: true);
    await Future<void>.delayed(Duration.zero);
    var heard = 0;
    outcomes.addListener(() => heard += 1);

    outcomes.forget('test.other');
    await Future<void>.delayed(Duration.zero);
    expect(outcomes.failedAt((owner: a, effect: other), 1), isFalse);
    expect(outcomes.failedAt(place, 1), isTrue);
    expect(heard, 1);

    outcomes.forget('test.nobody');
    await Future<void>.delayed(Duration.zero);
    expect(heard, 1, reason: 'no mark gone, nothing to hear');
  });
}
