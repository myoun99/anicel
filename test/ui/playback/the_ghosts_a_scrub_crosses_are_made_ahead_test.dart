import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/debug/device_grid_probe.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 🚨THE GHOSTS A SCRUB CROSSES ARE MADE AHEAD, AS ITS FRAMES ARE (card
/// onion-scrub-rebuilds-the-ghost-each-step). The ghosts are in a picture —
/// their own over the frame, or the frame's with them in place
/// (onion-ghosts-in-place) — and a picture is made ahead only where the
/// warmer's demand names it: named by none, every frame a scrub crossed
/// laid its ghosts on the spot — 🔬11520×7680 on a 3840² scene, asked→back
/// p50 131ms (10-28).
///
/// What the canvas stands on is what the warmer made: both stack the ghosts
/// through one function (`FramePictures.stackOf`), so here the ghosts of
/// every frame are asked of it, and found made — wherever they lie.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const row = LayerId('row');

  // Three frames, each its own cel: every frame has a neighbour to ghost,
  // whichever side the pegs look.
  Cut threeCels() => Cut(
    id: const CutId('cut'),
    name: 'cut',
    duration: 3,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: row,
        name: 'A',
        frames: [
          for (var cel = 0; cel < 3; cel += 1)
            Frame(id: FrameId('f$cel'), duration: 1, strokes: const []),
        ],
        timeline: {
          for (var cel = 0; cel < 3; cel += 1)
            cel: TimelineExposure.drawing(FrameId('f$cel'), length: 1),
        },
      ),
    ],
  );

  EditorSessionManager inked(OnionSkinPlacement placement) {
    final app = EditorAppSettings();
    addTearDown(app.dispose);
    app.onionSkinSettings.value = app.onionSkinSettings.value.copyWith(
      placement: placement,
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(id: const TrackId('track'), name: 'T', cuts: [threeCels()]),
        ],
      ),
      appSettings: app,
    );
    addTearDown(session.dispose);
    for (var cel = 0; cel < 3; cel += 1) {
      inkCel(
        session,
        session.brushFrameKeyForCut(
          session.requireActiveCut,
          row,
          FrameId('f$cel'),
        ),
        canvasSize: canvasSize,
        at: CanvasPoint(x: 2.0 + cel, y: 4),
        size: 3,
      );
    }
    return session;
  }

  /// The picture a canvas standing on [frame] shows its ghosts in: the
  /// ghosts' own over the frame, or the frame's with them in place.
  DemandedPicture onionAt(EditorSessionManager session, int frame) {
    final shown = standingPicturesOf(
      session.requireActiveCut,
      frame,
      session.onionSkin.settings.value.placement,
    );
    return shown.over ?? shown.frame;
  }

  /// Each row of a stack as a ghost reads: its cel, tint and opacity.
  List<(String, int?, double)> asGhosts(
    List<CompositeNode<CanvasStackRow>> nodes,
  ) => [
    for (final node in nodes)
      switch (node) {
        CompositeLeaf(payload: final CanvasLayerImageRequest ghost) => (
          ghost.frameKey.frameId.value,
          ghost.tint,
          ghost.opacity,
        ),
        _ => ('not a ghost: $node', null, -1),
      },
  ];

  /// [frame]'s ghosts as the onion plans them, as [asGhosts] reads them.
  List<(String, int?, double)> plannedAt(
    EditorSessionManager session,
    int frame,
  ) => [
    for (final ghosts in session.onionSkin
        .ghostsAt(session.requireActiveCut, frame, null)
        .values)
      for (final ghost in ghosts)
        (ghost.frameId.value, ghost.tint, ghost.opacity),
  ];

  Future<void> warmed(EditorSessionManager session) async {
    await Future<void>.delayed(Duration.zero);
    await session.playbackRig.prerenderScheduler.idle;
  }

  /// Every frame's ghosts stacked as the onion plans them — over the frame,
  /// or under its row's own cel — and made.
  void expectEveryFramesGhostsMade(EditorSessionManager session) {
    final pictures = session.playbackRig.framePictures;
    final inPlace =
        session.onionSkin.settings.value.placement ==
        OnionSkinPlacement.inPlace;
    for (var frame = 0; frame < 3; frame += 1) {
      final onion = onionAt(session, frame);
      final planned = plannedAt(session, frame);
      expect(planned, isNotEmpty, reason: '⛔premise: frame $frame ghosts');
      expect(
        asGhosts(pictures.stackOf(onion)),
        [...planned, if (inPlace) ('f$frame', null, 1.0)],
        reason: 'frame $frame: the ghosts are the onion\'s',
      );
      expect(
        pictures.has(onion),
        isTrue,
        reason: 'frame $frame: its ghosts are made ahead of the scrub',
      );
    }
  }

  for (final placement in OnionSkinPlacement.values) {
    group('laid ${placement.name}', () {
      // A widget test, run for real: the pictures are images the engine
      // makes.
      testWidgets('the onion turned on, every frame\'s ghosts are made ahead '
          '— stacked as the canvas stacks them', (tester) async {
        await tester.runAsync(() async {
          final session = inked(placement);
          await warmed(session);

          session.onionSkin.toggleLayerOnionSkin(row);
          await warmed(session);

          expectEveryFramesGhostsMade(session);
        });
      });

      testWidgets('the pegs changed, the ghosts they plan are made ahead '
          'again', (tester) async {
        await tester.runAsync(() async {
          final session = inked(placement);
          session.onionSkin.toggleLayerOnionSkin(row);
          await warmed(session);
          final pictures = session.playbackRig.framePictures;
          final tinted = pictures.keyOf(onionAt(session, 1));

          session.onionSkin.settings.value = session.onionSkin.settings.value
              .copyWith(mode: OnionSkinMode.images);
          expect(
            pictures.keyOf(onionAt(session, 1)),
            isNot(tinted),
            reason: '⛔premise: untinted, the ghosts are another picture',
          );
          await warmed(session);

          expectEveryFramesGhostsMade(session);
        });
      });

      testWidgets('the canvas shows the very ghosts the warmer makes — one '
          'picture, one key', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(home: HomePage(initialProject: createDefaultProject())),
        );
        await tester.pumpAndSettle();
        final session = tester
            .widget<EditorWorkspace>(find.byType(EditorWorkspace))
            .session;
        session.onionSkin.settings.value = session.onionSkin.settings.value
            .copyWith(placement: placement);
        session.createDrawingAtCurrentFrame();
        session.selectFrameIndex(1);
        session.createDrawingAtCurrentFrame();
        session.onionSkin.toggleOnionSkin();
        await tester.pumpAndSettle();

        final views = tester
            .widgetList<FramePictureView>(
              find.descendant(
                of: find.byType(DeviceGridProbe),
                matching: find.byType(FramePictureView),
              ),
            )
            .toList();
        expect(
          views,
          hasLength(placement == OnionSkinPlacement.onTop ? 2 : 1),
          reason: 'over the frame a view of their own; in place, none',
        );
        final onion = onionAt(session, 1);
        final shown = views.singleWhere((view) => view.picture == onion);
        final planned = plannedAt(session, 1);
        expect(planned, isNotEmpty, reason: '⛔premise: frame 1 ghosts');
        expect(
          [
            for (final ghost in asGhosts(shown.nodes))
              if (ghost.$2 != null) ghost,
          ],
          planned,
          reason: 'the tinted rows it shows are the onion\'s ghosts',
        );
        final pictures = session.playbackRig.framePictures;
        expect(
          pictures.keyOfStack(shown.nodes, shown.picture),
          pictures.keyOf(onion),
          reason: 'the picture the warmer lays ahead is the one the canvas '
              'asks',
        );
      });
    });
  }

  test('a session let go of hears the app\'s pegs no more — they are one '
      'value for every open project', () {
    final app = EditorAppSettings();
    addTearDown(app.dispose);
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      appSettings: app,
    );
    session.onionSkin.toggleOnionSkin();
    session.dispose();
    final warmer = session.playbackRig.prerenderScheduler;
    expect(warmer.demand, isNull, reason: '⛔premise: let go, it follows none');

    app.onionSkinSettings.value = app.onionSkinSettings.value.copyWith(
      mode: OnionSkinMode.images,
    );
    expect(
      warmer.demand,
      isNull,
      reason: 'a pegs change asked the warmer of a session already gone — '
          'the app\'s settings held on to the whole of it',
    );
  });
}
