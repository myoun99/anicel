import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show TimelineRowDragHooks;

/// The V row's fx chain ON SCREEN: its lane rows show up under the Transform
/// group, and grabbing a group header re-orders the chain — the layer rail's
/// gesture, one level up (user 2026-08-08).

const _track = TrackId('fx-track');
const _cut = CutId('fx-cut');

LayerEffect _effect(String id, EffectKind kind) =>
    LayerEffect.defaults(id: EffectId(id), kind: kind);

Project _project(List<LayerEffect> effects) => Project(
  id: const ProjectId('fx-project'),
  name: 'Project',
  createdAt: DateTime.utc(2026, 8, 8),
  tracks: [
    Track(
      id: _track,
      name: 'Video',
      effects: effects,
      cuts: [
        Cut(
          id: _cut,
          name: '1',
          duration: 12,
          canvasSize: const CanvasSize(width: 1280, height: 720),
          layers: [
            Layer(id: const LayerId('layer-1'), name: 'A', frames: const []),
          ],
        ),
      ],
    ),
  ],
);

/// The panel with the SESSION's own drag hooks — the host's wiring, so the
/// gesture runs the real command path.
Future<EditorSessionManager> _pumpPanel(
  WidgetTester tester,
  List<LayerEffect> effects,
) async {
  final session = EditorSessionManager(initialProject: _project(effects));
  final expandedTracks = <String>{};
  final expandedGroups = <String>{};
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => StoryboardPanel(
            project: session.repository.requireProject(),
            activeCutId: _cut,
            pixelsPerFrame: 12,
            projectFrameRate: const ProjectFrameRate.integer(24),
            audioPeaksFor: (_) => null,
            expandedSeAudioRows: const <String>{},
            expandedTransformTracks: expandedTracks,
            onToggleTrackLane: (track) => setState(() {
              if (!expandedTracks.add(track.id.value)) {
                expandedTracks.remove(track.id.value);
              }
            }),
            expandedTransformGroups: expandedGroups,
            onToggleTransformGroup: (groupKey) => setState(() {
              if (!expandedGroups.add(groupKey)) {
                expandedGroups.remove(groupKey);
              }
            }),
            poseDisplaySize: const CanvasSize(width: 640, height: 360),
            onToggleTrackEffectEnabled: (track, effectId) =>
                session.toggleTrackEffectEnabled(track.id, effectId),
            rowDragHooks: TimelineRowDragHooks(
              drag: session.layerRowDrag,
              onBegin: session.beginLayerRowDrag,
              onUpdate: session.updateLayerRowDrag,
              onRowTarget: session.updateLayerRowDropOnRow,
              onEffectUpdate: session.updateEffectRowDrag,
              onEnd: session.endLayerRowDrag,
              onCancel: session.cancelLayerRowDrag,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      const ValueKey<String>('storyboard-track-lane-toggle-fx-track'),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

List<EffectKind> _chain(EditorSessionManager session) => [
  for (final effect in session.repository.requireProject().tracks.single.effects)
    effect.kind,
];

Finder _fxHeaderLabel(String effectId) => find.byKey(
  ValueKey<String>(
    'storyboard-lane-label-v-track:${_track.value}-fx-group:$effectId',
  ),
);

void main() {
  testWidgets('the V row shows one lane row per effect, label and strip', (
    tester,
  ) async {
    await _pumpPanel(tester, [
      _effect('fx-a', EffectKind.blur),
      _effect('fx-b', EffectKind.hueSaturation),
    ]);

    expect(_fxHeaderLabel('fx-a'), findsOneWidget);
    expect(_fxHeaderLabel('fx-b'), findsOneWidget);
    // The two columns are built from the SAME lane list, so the strip row
    // exists for every label row (their heights must stay in lockstep).
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-row-0-fx-group:fx-a'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-row-0-fx-group:fx-b'),
      ),
      findsOneWidget,
    );
    // LOCKSTEP: the rail and the strips share no scaffolding, so the only
    // thing keeping them aligned is that both are built from that one list.
    // The row-to-row step must be the same in each column.
    double stepOf(Finder a, Finder b) =>
        tester.getTopLeft(b).dy - tester.getTopLeft(a).dy;
    final labelStep = stepOf(_fxHeaderLabel('fx-a'), _fxHeaderLabel('fx-b'));
    final stripStep = stepOf(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-row-0-fx-group:fx-a'),
      ),
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-row-0-fx-group:fx-b'),
      ),
    );
    expect(labelStep, 26);
    expect(stripStep, labelStep);
  });

  testWidgets('dragging an fx header re-orders the V row\'s chain', (
    tester,
  ) async {
    final session = await _pumpPanel(tester, [
      _effect('fx-a', EffectKind.blur),
      _effect('fx-b', EffectKind.hueSaturation),
    ]);
    expect(_chain(session), [EffectKind.blur, EffectKind.hueSaturation]);

    // One lane row of downward travel takes the first header past the
    // second — the same half-row step the layer rail commits on.
    final header = _fxHeaderLabel('fx-a');
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.drag(header, const Offset(0, 26));
    await tester.pumpAndSettle();

    expect(_chain(session), [EffectKind.hueSaturation, EffectKind.blur]);

    session.undo();
    expect(_chain(session), [EffectKind.blur, EffectKind.hueSaturation]);

    // Drain the prerender scheduler's debounced warming (the established
    // idiom for a test that commits through the session).
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('a PARAMETER lane is not a handle — twirling one open and '
      'dragging it moves nothing', (tester) async {
    final session = await _pumpPanel(tester, [
      _effect('fx-a', EffectKind.blur),
      _effect('fx-b', EffectKind.hueSaturation),
    ]);
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-group-toggle-v-track:fx-track-fx-group:fx-a',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final parameter = find.byKey(
      const ValueKey<String>(
        'storyboard-lane-label-v-track:fx-track-fx:fx-a:blurX',
      ),
    );
    expect(parameter, findsOneWidget);

    await tester.drag(parameter, const Offset(0, 52));
    await tester.pumpAndSettle();

    expect(_chain(session), [EffectKind.blur, EffectKind.hueSaturation]);
  });
}
