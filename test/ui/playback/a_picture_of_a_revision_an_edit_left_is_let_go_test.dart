import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show DemandedPicture, FrameGhosts;
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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🗣️F-569 (유저 2026-11-05: 「최신 FU로 작업중 메모리가 7000까지 상승해있음.
/// 채우기툴로 연속채우기 여러번했기에 채우기툴이 원인인가」) — A PICTURE MADE
/// OF A REVISION AN EDIT LEFT IS LET GO OF AT THAT EDIT.
///
/// 🔬S5_BA cut 352 (2026-11-06, Windows, profile): the cel a fill lands on
/// shows on two frames whose other rows differ — two pictures. The canvas
/// moved the one it stood on, and the warmer laid the other again at every
/// fill under the cel's new revision; the one it laid before stayed, under
/// a revision no cel holds, until the playback budget (6 GB there) was
/// full: 30 fills, 2757 → 3390 MB, none let go at rest.
///
/// The cut: row A one cel over both frames, row B a cel a frame.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  final cut = Cut(
    id: const CutId('cut'),
    name: 'cut',
    duration: 2,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('a'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('a'), duration: 2, strokes: const []),
        ],
        timeline: {0: const TimelineExposure.drawing(FrameId('a'), length: 2)},
      ),
      Layer(
        id: const LayerId('b'),
        name: 'B',
        frames: [
          Frame(id: const FrameId('b0'), duration: 1, strokes: const []),
          Frame(id: const FrameId('b1'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('b0'), length: 1),
          1: const TimelineExposure.drawing(FrameId('b1'), length: 1),
        },
      ),
    ],
  );

  /// A dab of [color] inside the canvas on [layer]'s cel [frame].
  void draw(
    EditorSessionManager s,
    String layer,
    String frame, {
    int color = 0xFF000000,
  }) {
    BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        cut,
        LayerId(layer),
        FrameId(frame),
      ),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 4, y: 4),
          color: color,
          size: 6,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.square,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
  }

  /// An edit of [layer]'s cel [frame]: other pixels than it had — the same
  /// dab again changes nothing, and nothing is edited.
  void edit(EditorSessionManager s, String layer, String frame) =>
      draw(s, layer, frame, color: 0xFFFF0000);

  /// A session with every cel of the cut inked — an empty cel is no part of
  /// a picture.
  EditorSessionManager inked() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('left'),
        name: 'Left',
        createdAt: DateTime.utc(2026, 11, 6),
        tracks: [
          Track(id: const TrackId('track'), name: 'Video', cuts: [cut]),
        ],
      ),
    );
    addTearDown(s.dispose);
    for (final (layer, frame) in [('a', 'a'), ('b', 'b0'), ('b', 'b1')]) {
      draw(s, layer, frame);
    }
    return s;
  }

  DemandedPicture at(int frame) =>
      (cut: cut, frameIndex: frame, paintPaper: true, ghosts: FrameGhosts.none);

  /// Frame [frame]'s picture made as the warmer makes it, and its key.
  Future<FramePictureKey> make(EditorSessionManager s, int frame) async {
    final pictures = s.playbackRig.framePictures;
    expect(
      await pictures.make(at(frame), shouldAbort: () => false),
      isTrue,
      reason: 'LIVENESS: frame $frame is made',
    );
    return pictures.keyOf(at(frame));
  }

  testWidgets('both frames\' pictures of the cel an edit left are let go of',
      (tester) async {
    await tester.runAsync(() async {
      final s = inked();
      final store = s.renderCaches.framePictureStore;
      final first = await make(s, 0);
      final second = await make(s, 1);
      expect(first, isNot(second), reason: '⛔premise: two pictures');
      expect(store.holds(first) && store.holds(second), isTrue);

      edit(s, 'a', 'a');

      expect(store.holds(first), isFalse);
      expect(store.holds(second), isFalse);
      expect(store.estimatedBytes, 0);
    });
  });

  testWidgets('a picture the edit left alone stays', (tester) async {
    await tester.runAsync(() async {
      final s = inked();
      final store = s.renderCaches.framePictureStore;
      final first = await make(s, 0);
      final second = await make(s, 1);

      edit(s, 'b', 'b1');

      expect(store.holds(first), isTrue, reason: 'b0 is no b1');
      expect(store.holds(second), isFalse);
    });
  });

  testWidgets('a picture a screen holds stays, to go as the screen leaves it',
      (tester) async {
    await tester.runAsync(() async {
      final s = inked();
      final store = s.renderCaches.framePictureStore;
      final shown = await make(s, 0);
      final other = await make(s, 1);
      store.retainPin(shown);
      addTearDown(() => store.releasePin(shown));

      edit(s, 'a', 'a');

      expect(store.holds(shown), isTrue);
      expect(store.holds(other), isFalse);
    });
  });
}
