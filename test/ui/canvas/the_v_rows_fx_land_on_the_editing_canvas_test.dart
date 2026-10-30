import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/track_effect_paint_policy.dart';

import '../../helpers/a_plugin_that_shifts.dart';

/// playback-plays-the-screen-material ④ (10-09): the V row's fx filter the
/// cut's picture on the canvas you stand on, as they do in playback, on the
/// parked track stack and in both exports — a group round the cut's rows,
/// composed by the folder's own buffer law, so the paper is untouched.
///
/// 🚨The canvas was the one route that drew the cut without them, so the
/// same frame read two ways the moment a run began (유저 절대규칙 「보이는
/// 중이랑 결과랑 절대로 다르면 안 되」).
void main() {
  final brightness = LayerEffect(
    id: const EffectId('fx'),
    kind: EffectKind.brightnessContrast,
    parameters: {'brightness': EffectParameter(value: 0.5)},
  );

  /// The V row wearing [effects] — [brightness] where none are named — on
  /// a device whose installed plugins are [plugins].
  EditorSessionManager session({
    bool fxEnabled = true,
    List<LayerEffect>? effects,
    InstalledFxPlugins? plugins,
  }) =>
      EditorSessionManager(
        fxPlugins: plugins,
        initialProject: Project(
          id: const ProjectId('p'),
          name: 'P',
          createdAt: DateTime.utc(2026, 10, 9),
          tracks: [
            Track(
              id: const TrackId('t'),
              name: 'V1',
              effects: effects ?? [brightness],
              fxEnabled: fxEnabled,
              cuts: [
                Cut(
                  id: const CutId('c'),
                  name: '1',
                  duration: 4,
                  canvasSize: const CanvasSize(width: 8, height: 8),
                  layers: [
                    Layer(
                      id: const LayerId('l'),
                      name: 'A',
                      frames: [
                        Frame(id: const FrameId('f'), duration: 1, strokes: const []),
                      ],
                      timeline: const {
                        0: TimelineExposure.drawing(FrameId('f'), length: 4),
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

  /// The one group a stack's cut rows stand under, or null when they stand
  /// at the top.
  CompositeGroup<CanvasStackRow>? groupOf(
    List<CompositeNode<CanvasStackRow>> nodes,
  ) => nodes.whereType<CompositeGroup<CanvasStackRow>>().singleOrNull;

  test('🚨the cut\'s rows stand under the V row\'s fx — the chain at the '
      'frame stood on, on the track\'s axis — the run\'s tree too', () {
    final s = session();
    addTearDown(s.dispose);

    for (final nodes in [
      s.editingCanvas.stack.nodes,
      s.editingCanvas.playingStack.nodes,
    ]) {
      final group = groupOf(nodes);
      expect(group, isNotNull, reason: 'the cut is filtered as a whole');
      expect(group!.effects, trackEffectsAt([brightness], 0));
      expect(group.opacity, 1);
      expect(group.children, isNotEmpty, reason: 'the cut\'s row is inside');
    }
  });

  testWidgets('🗣️I-132-Q34 a 「어디에 걸어도 돌고」: a plugin on the V row '
      'runs on the canvas, at the playhead and ahead of it', (tester) async {
    final plugins = await installedShiftingFxPlugin(tester);
    final s = session(
      effects: [shiftingFxPluginLayerEffect()],
      plugins: plugins,
    );
    addTearDown(s.dispose);

    for (final nodes in [
      s.editingCanvas.stack.nodes,
      s.editingCanvas.playedStackAt(s.requireActiveCut, 0),
    ]) {
      final chain = groupOf(nodes)!.effects;
      expect(chain.map((effect) => effect.kind), [EffectKind.plugin]);
      expect(chain.single.run, isNotNull, reason: 'bound to its run');
    }
  });

  test('the V row\'s fx switch takes the chain off the canvas as it takes it '
      'off playback', () {
    final s = session(fxEnabled: false);
    addTearDown(s.dispose);

    expect(groupOf(s.editingCanvas.stack.nodes), isNull);
    expect(groupOf(s.editingCanvas.playingStack.nodes), isNull);
  });

  test('🚨the chain is sampled on the TRACK\'s axis: a cut that stands four '
      'frames on reads its frame 0 where the track says 4', () {
    final keyed = LayerEffect(
      id: const EffectId('fx'),
      kind: EffectKind.brightnessContrast,
      parameters: {
        'brightness': EffectParameter(
          value: 0.1,
          track: PropertyTrack<double>(
            keys: const {
              0: PropertyKey<double>(0.1),
              4: PropertyKey<double>(0.9),
            },
          ),
        ),
      },
    );
    Cut cut(String id) => Cut(
      id: CutId(id),
      name: id,
      duration: 4,
      canvasSize: const CanvasSize(width: 8, height: 8),
      layers: [
        Layer(
          id: LayerId('l-$id'),
          name: 'A',
          frames: [
            Frame(id: FrameId('f-$id'), duration: 1, strokes: const []),
          ],
          timeline: {0: TimelineExposure.drawing(FrameId('f-$id'), length: 4)},
        ),
      ],
    );
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V1',
            effects: [keyed],
            cuts: [cut('first'), cut('second')],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    s.selectCut(const CutId('second'));

    final group = groupOf(s.editingCanvas.stack.nodes)!;
    expect(group.effects, trackEffectsAt([keyed], 4));
    expect(
      group.effects,
      isNot(trackEffectsAt([keyed], 0)),
      reason: '⛔the cut\'s own frame 0 is not the track\'s',
    );
  });

  test('the cels the warmer makes a frame of are the cut\'s own — the V '
      'row\'s group wraps them, it is no row of its own', () {
    final s = session();
    addTearDown(s.dispose);

    expect(
      stackedCelsOf(
        s.editingCanvas.playedStackAt(s.requireActiveCut, 0),
      ).map((cel) => cel.frameId),
      [const FrameId('f')],
    );
  });
}
