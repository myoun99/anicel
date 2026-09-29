import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';

/// A conte cell whose camera moves shows the canvas that camera sweeps
/// (유저 2026-09-29: 「일단 카메라 팬대로 해당 코마에서 보여주고」): its
/// picture is rendered over that region of the canvas, square to it, not
/// through the camera at the picture's frame.
void main() {
  testWidgets('a picture over a region is that region of the canvas; without '
      'one it is the camera\'s view', (tester) async {
    await tester.runAsync(() async {
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('region'),
          name: 'Region',
          cameraSize: const CanvasSize(width: 32, height: 18),
          createdAt: DateTime.utc(2026, 9, 30),
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Video',
              cuts: [
                Cut(
                  id: const CutId('c'),
                  name: '1',
                  duration: 6,
                  canvasSize: const CanvasSize(width: 64, height: 36),
                  layers: [
                    Layer(
                      id: const LayerId('a'),
                      name: 'A',
                      kind: LayerKind.animation,
                      frames: [
                        Frame(
                          id: const FrameId('f'),
                          duration: 1,
                          strokes: const [],
                        ),
                      ],
                      timeline: const {
                        0: TimelineExposure.drawing(FrameId('f'), length: 6),
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(session.dispose);
      final cut = session.requireActiveCut;
      final layer = cut.layers.firstWhere((layer) => layer.id.value == 'a');
      // A black dab near the canvas's top-left corner — far outside the
      // camera's view, which stands centred on the canvas.
      BrushFrameEditingCoordinator(
        initialFrameKey: session.brushFrameKeyForCut(
          cut,
          layer.id,
          const FrameId('f'),
        ),
        frameStore: session.renderCaches.brushFrameStore,
        sessionStore: BrushFrameEditSessionStore(canvasSize: cut.canvasSize),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: 4, y: 4),
            color: 0xFF000000,
            size: 4,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ],
      );

      Future<(int, int, ByteData)> picture({ui.Rect? region}) async {
        final image = await ExportFrameRenderer(
          session: session,
          background: const ui.Color(0x00000000),
        ).renderPicture(cut, 0, width: 32, region: region);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final size = (image.width, image.height);
        image.dispose();
        return (size.$1, size.$2, bytes!);
      }

      int alphaAt((int, int, ByteData) picture, int x, int y) =>
          picture.$3.getUint8((y * picture.$1 + x) * 4 + 3);

      final corner = await picture(
        region: const ui.Rect.fromLTWH(0, 0, 32, 18),
      );
      expect((corner.$1, corner.$2), (32, 18));
      expect(
        alphaAt(corner, 4, 4),
        greaterThan(200),
        reason: 'the dab, a pixel a pixel',
      );
      expect(alphaAt(corner, 20, 12), 0);

      final wide = await picture(region: const ui.Rect.fromLTWH(0, 0, 64, 18));
      expect(
        (wide.$1, wide.$2),
        (32, 9),
        reason: 'the region\'s shape, 32 wide',
      );
      expect(
        alphaAt(wide, 2, 2),
        greaterThan(100),
        reason: 'the dab, at half the size',
      );

      final beside = await picture(
        region: const ui.Rect.fromLTWH(32, 0, 32, 18),
      );
      expect(alphaAt(beside, 4, 4), 0, reason: 'another region, no dab');

      final camera = await picture();
      expect((camera.$1, camera.$2), (32, 18));
      for (var y = 0; y < 18; y += 1) {
        for (var x = 0; x < 32; x += 1) {
          expect(
            alphaAt(camera, x, y),
            0,
            reason: 'the camera\'s view holds no dab ($x, $y)',
          );
        }
      }
    });
  });
}
