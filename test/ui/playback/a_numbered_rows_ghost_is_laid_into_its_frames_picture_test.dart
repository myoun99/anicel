@Tags(['gpu'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart' show defaultCelTileSize;
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/draw_on_current_frame.dart';

/// a-numbered-rows-ghost-resolves-its-chain-unsplit: a row with a cel
/// number and its onion on had no picture of its frame made — its ghosts
/// carried the number unsplit to the paint, and the debug build asserted
/// (`paintedEffectsOf`) on the walk, the canvas's screen and the making
/// alike (🔬S5_BA cut 352, row D, 11-15 · 11-16). A ghost is laid as its
/// row is now (`celNumberedRow`, 🗣️Q1 a 유저 2026-11-17 「그린다」), in
/// place and over the frame, tinted or not.
void main() {
  opensTheEnginesScreens();

  const canvasSize = CanvasSize(width: 128, height: 64);
  const pen = LayerId('pen');
  final cels = ['pen-0', 'pen-1', 'pen-2'];

  /// A session on one numbered row of three drawings, the onion on it at
  /// frame 1 and laid as [settings] says.
  EditorSessionManager numberedWithItsOnion(OnionSkinSettings settings) {
    final app = EditorAppSettings();
    addTearDown(app.dispose);
    app.onionSkinSettings.value = settings;
    final row = Layer(
      id: pen,
      name: 'D',
      frames: [
        for (var at = 0; at < cels.length; at += 1)
          Frame(
            id: FrameId(cels[at]),
            duration: 1,
            strokes: const [],
            name: '${at + 1}',
          ),
      ],
      timeline: {
        for (var at = 0; at < cels.length; at += 1)
          at: TimelineExposure.drawing(FrameId(cels[at]), length: 1),
      },
      effects: [
        LayerEffect(id: const EffectId('number'), kind: EffectKind.celNumber),
      ],
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'T',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'cut',
                duration: 3,
                canvasSize: canvasSize,
                layers: [row],
              ),
            ],
          ),
        ],
      ),
      appSettings: app,
    );
    addTearDown(session.dispose);
    final cut = session.requireActiveCut;
    for (var at = 0; at < cels.length; at += 1) {
      inkCelIn(
        session.renderCaches.brushFrameStore,
        session.brushFrameKeyForCut(cut, pen, FrameId(cels[at])),
        canvasSize: canvasSize,
        at: CanvasPoint(x: 20.0 + 30 * at, y: 30),
        size: 9,
        color: 0xFF000000,
        tileSize: defaultCelTileSize,
      );
    }
    session.selectFrameIndex(1);
    session.onionSkin.toggleLayerOnionSkin(pen);
    return session;
  }

  final ways = {
    'in place': OnionSkinPlacement.inPlace,
    'over the frame': OnionSkinPlacement.onTop,
  };
  for (final MapEntry(key: way, value: placement) in ways.entries) {
    for (final colours in [false, true]) {
      final named = colours ? '$way, in the sides\' colours' : way;
      test('the frame of a numbered row with its ghosts $named is laid',
          () async {
        final defaults = const OnionSkinSettings();
        final session = numberedWithItsOnion(
          defaults.copyWith(
            placement: placement,
            mode: colours ? OnionSkinMode.colors : OnionSkinMode.images,
          ),
        );
        final pictures = session.playbackRig.framePictures;
        final frame = standingPicturesOf(
          session.requireActiveCut,
          1,
          placement,
          paintPaper: true,
        ).frame;

        expect(
          await pictures.make(frame, shouldAbort: () => false),
          isTrue,
        );
        expect(pictures.store.peek(pictures.keyOf(frame)), isNotNull);
      });
    }
  }
}
