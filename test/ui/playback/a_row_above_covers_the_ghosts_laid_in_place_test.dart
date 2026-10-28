import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 🗣️onion-ghosts-in-place (유저 2026-10-26: 「TVPaint · 클립 스튜디오처럼
/// 위 레이어가 고스트를 가리게」, Q1 = a 「바로 밑」): laid in place, a row's
/// ghosts are in the frame's own picture, under its drawing — a row above
/// covers them, and where none does they show.
///
/// Read off the pictures the warmer makes ahead of the canvas, as the
/// engine makes them: the frame with its ghosts in place against the frame
/// a run plays.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);
  const low = LayerId('low');
  const cover = LayerId('cover');
  // Where the low row's drawing before the playhead stands: once under the
  // cover, once in the open.
  final underTheCover = CanvasPoint(x: 4, y: 8);
  final inTheOpen = CanvasPoint(x: 11, y: 8);

  Cut twoRows() => Cut(
    id: const CutId('cut'),
    name: 'cut',
    duration: 2,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: low,
        name: 'LOW',
        frames: [
          for (final cel in ['l0', 'l1'])
            Frame(id: FrameId(cel), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('l0'), length: 1),
          1: const TimelineExposure.drawing(FrameId('l1'), length: 1),
        },
      ),
      Layer(
        id: cover,
        name: 'COVER',
        frames: [Frame(id: const FrameId('c'), duration: 1, strokes: const [])],
        timeline: {0: const TimelineExposure.drawing(FrameId('c'), length: 2)},
      ),
    ],
  );

  EditorSessionManager inked() {
    final app = EditorAppSettings();
    addTearDown(app.dispose);
    app.onionSkinSettings.value = app.onionSkinSettings.value.copyWith(
      placement: OnionSkinPlacement.inPlace,
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(id: const TrackId('track'), name: 'T', cuts: [twoRows()]),
        ],
      ),
      appSettings: app,
    );
    addTearDown(session.dispose);
    void ink(LayerId row, String cel, CanvasPoint at, double size) => inkCel(
      session,
      session.brushFrameKeyForCut(session.requireActiveCut, row, FrameId(cel)),
      canvasSize: canvasSize,
      at: at,
      size: size,
    );
    ink(low, 'l0', underTheCover, 3);
    ink(low, 'l0', inTheOpen, 3);
    ink(low, 'l1', CanvasPoint(x: 8, y: 2), 3);
    ink(cover, 'c', underTheCover, 9);
    return session;
  }

  /// [picture]'s pixel at [at], as the warmer made it.
  Future<Uint8List> pixelOf(
    EditorSessionManager session,
    DemandedPicture picture,
    CanvasPoint at,
  ) async {
    final pictures = session.playbackRig.framePictures;
    final made = pictures.store.peek(pictures.keyOf(picture));
    expect(made, isNotNull, reason: '⛔premise: $picture is made');
    final x = at.x.floor() - made!.extent.left.round();
    final y = at.y.floor() - made.extent.top.round();
    final bytes = (await made.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final at4 = (y * made.image.width + x) * 4;
    return bytes.buffer.asUint8List(at4, 4);
  }

  testWidgets('a row above covers the ghosts in place, and where none does '
      'they show', (tester) async {
    await tester.runAsync(() async {
      final session = inked();
      session.selectFrameIndex(1);
      session.onionSkin.toggleLayerOnionSkin(low);
      await Future<void>.delayed(Duration.zero);
      await session.playbackRig.prerenderScheduler.idle;

      final cut = session.requireActiveCut;
      final played = (
        cut: cut,
        frameIndex: 1,
        paintPaper: true,
        ghosts: FrameGhosts.none,
      );
      final inPlace = standingPicturesOf(
        cut,
        1,
        OnionSkinPlacement.inPlace,
      ).frame;
      expect(
        await pixelOf(session, inPlace, underTheCover),
        await pixelOf(session, played, underTheCover),
        reason: 'the cover lies over the ghost — the frame as it plays',
      );
      expect(
        await pixelOf(session, inPlace, inTheOpen),
        isNot(await pixelOf(session, played, inTheOpen)),
        reason: 'in the open the ghost shows',
      );
    });
  });
}
