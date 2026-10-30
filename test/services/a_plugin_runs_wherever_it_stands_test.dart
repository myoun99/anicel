import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/fx_plugins/device_fx_plugin_binding.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/a_plugin_that_shifts.dart';

/// 🗣️I-132-Q34 a (유저 2026-10-30): 「머문다 — 어디에 걸어도 돌고 …」 — a
/// plugin's effect runs wherever it stands: every one switched on, in every
/// chain the plan lays — a row's, a folder's, an adjustment's, the V row's
/// over the cut.
void main() {
  const paper = CanvasSize(width: 8, height: 8);
  final other = FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'test.other',
    'name': 'Other',
    'vendor': 'Test',
    'version': '1',
    'can': ['cpu'],
    'params': <Object?>[],
  })!;
  final reading = FxPluginDescription.fromJson({
    ...shiftingFxPluginDescription.toJson(),
    'params': [
      {'id': 'map', 'kind': 'layer', 'label': 'Map'},
    ],
  })!;
  const p = EffectId('p');
  final plugin = LayerEffect.defaults(
    id: p,
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
  );
  LayerEffect blur(EffectParameter amount, {bool enabled = true}) =>
      LayerEffect.defaults(id: const EffectId('b'), kind: EffectKind.blur)
          .withParameter('blurriness', amount)
          .copyWith(enabled: enabled);
  final chains = <String, List<LayerEffect>>{
    'alone': [plugin],
    'after a key': [
      LayerEffect.defaults(id: const EffectId('k'), kind: EffectKind.colorKey),
      plugin,
    ],
    'after a blur': [blur(EffectParameter(value: 3)), plugin],
    'after a blur switched off': [
      blur(EffectParameter(value: 3), enabled: false),
      plugin,
    ],
    // Nothing at frame 0, a blur from frame 1.
    'after a blur keyed up from nothing': [
      blur(
        EffectParameter(
          track: PropertyTrack<double>().withKey(0, 0).withKey(1, 10),
        ),
      ),
      plugin,
    ],
    'after another plugin': [
      LayerEffect.defaults(
        id: const EffectId('q'),
        kind: EffectKind.plugin,
        plugin: other,
      ),
      plugin,
    ],
    'switched off': [plugin.copyWith(enabled: false)],
  };

  final cels = <FrameId, BitmapSurface>{
    const FrameId('m0'): BitmapSurface(canvasSize: paper),
    const FrameId('m2'): BitmapSurface(canvasSize: paper),
  };
  final binding = deviceFxPluginBinding(
    runnerFor: (_) => ShiftingFxPlugin(by: 1),
    frameRate: ProjectFrameRate.fps24,
    surfaceOf: (_, frame) => cels[frame.id],
  );
  Layer drawing(String id, {String? folder}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 4)},
    folderId: folder == null ? null : LayerId(folder),
  );
  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 4,
    canvasSize: paper,
    layers: layers,
  );
  List<ResolvedLayerEffect> bound(List<LayerEffect> chain, int frame) =>
      binding(
        resolveLayerEffectsAt(effects: chain, frameIndex: frame),
        cut: cutOf(const []),
        frameIndex: frame,
      );

  test('🎯every plugin of a chain runs, wherever it stands, switched on', () {
    for (final MapEntry(key: name, value: chain) in chains.entries) {
      final on = chain.singleWhere((effect) => effect.id == p).enabled;
      for (final frame in [0, 1]) {
        final plugins = bound(
          chain,
          frame,
        ).where((effect) => effect.kind == EffectKind.plugin).toList();
        expect(
          plugins.map((effect) => effect.plugin),
          [
            for (final effect in chain)
              if (effect.kind == EffectKind.plugin && effect.enabled)
                effect.plugin,
          ],
          reason: '⛔premise: $name · frame $frame',
        );
        expect(
          plugins.every((effect) => effect.run != null),
          isTrue,
          reason: '$name · frame $frame',
        );
        expect(plugins, on ? isNotEmpty : isEmpty, reason: name);
      }
    }
  });

  test('the plan runs one on a folder\'s chain and on an adjustment\'s', () {
    List<CompositeNode<CutFrameCompositeLayer>> planOf(
      List<Layer> layers, {
      required bool binds,
    }) => planCutFrameCompositeTree(
      cut: cutOf(layers),
      frameIndex: 0,
      reading: (
        surfaces: (_, _) => BitmapSurface(canvasSize: paper),
        plugins: binds ? binding : null,
      ),
    );
    final folder = [
      drawing('a', folder: 'f'),
      createFolderLayer(id: const LayerId('f'), name: 'f').copyWith(
        effects: [plugin],
      ),
    ];
    final adjustment = [
      drawing('a'),
      createAdjustmentLayer(id: const LayerId('fx'), name: 'fx').copyWith(
        effects: [plugin],
      ),
    ];
    List<ResolvedLayerEffect> chainOf(
      List<CompositeNode<CutFrameCompositeLayer>> nodes,
    ) => switch (nodes.single) {
      CompositeGroup(:final effects) || CompositeAdjustment(:final effects) =>
        effects,
      final node => fail('⛔premise: one buffer, not $node'),
    };
    for (final (name, layers) in [
      ('a folder', folder),
      ('an adjustment', adjustment),
    ]) {
      expect(
        chainOf(planOf(layers, binds: false)).single.run,
        isNull,
        reason: '⛔CONTROL: $name\'s chain where nothing binds it',
      );
      expect(
        chainOf(planOf(layers, binds: true)).single.run,
        isNotNull,
        reason: name,
      );
    }
  });

  test('the V row\'s is told the frame its sample is of — the track\'s axis '
      '— and reads the cut\'s rows at the cut\'s', () {
    final map = LayerEffect.defaults(
      id: p,
      kind: EffectKind.plugin,
      plugin: reading,
    ).withLayer('map', const LayerId('m'));
    final m = Layer(
      id: const LayerId('m'),
      name: 'm',
      frames: [
        Frame(id: const FrameId('m0'), duration: 1, strokes: const []),
        Frame(id: const FrameId('m2'), duration: 1, strokes: const []),
      ],
      timeline: const {
        0: TimelineExposure.drawing(FrameId('m0'), length: 2),
        2: TimelineExposure.drawing(FrameId('m2'), length: 2),
      },
    );
    final run = binding(
      resolveLayerEffectsAt(effects: [map], frameIndex: 7),
      cut: cutOf([m]),
      frameIndex: 2,
    ).single.run!;

    expect(run.moment.frameIndex, 7);
    expect(run.moment.time, ProjectFrameRate.fps24.frameStartSeconds(7));
    expect(
      identical(run.rows[const LayerId('m')], cels[const FrameId('m2')]),
      isTrue,
    );
  });
}
