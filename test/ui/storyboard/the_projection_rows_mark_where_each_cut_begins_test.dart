import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_panel.dart'
    show StoryboardCutStartsPainter, StoryboardPanel;
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// 🗣️I-73 ④ — the drawn proposal: 「투영 행은 컷이 시작하는 자리마다 세로
/// 점선(2 3)」, and 유저 2026-10-08: 「컷 클리핑하는거 사이 점선으로
/// 만드는거 좋네. 굉장히 알기쉬워」.
///
/// Every projection row — the camera row, the conte row, a row riding the
/// conte — draws the one dashed line where each cut begins, from one
/// painter. Cuts a [0, 10) and b [10, 20), four frames of gap, then c
/// [24, 30) — a and b with a conte and a row riding it, c with neither.
void main() {
  const trackId = TrackId('t1');

  Layer storyboardRow(String id, {String? ridesOn}) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.storyboard,
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
    attachedPlacement: AttachedPlacement.above,
    attachedMode: AttachedMode.free,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 10)},
  );

  Cut cutOf(String id, int duration, {int gap = 0, bool conte = true}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      if (conte) ...[
        storyboardRow('$id-conte'),
        storyboardRow('$id-over', ridesOn: '$id-conte'),
      ],
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  testWidgets('🎯the camera row, the conte row and the row riding it dash '
      'where each cut begins — its place, every cut', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('dashes'),
        name: 'Dashes',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: trackId,
            name: 'V1',
            cuts: [
              cutOf('a', 10),
              cutOf('b', 10),
              cutOf('c', 6, gap: 4, conte: false),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ppf = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .pixelsPerFrame;

    /// Where the row keyed [key] dashes, as its painter lays them down.
    List<double> startsOn(String key) =>
        (tester.widget<CustomPaint>(find.byKey(ValueKey<String>(key))).painter!
                as StoryboardCutStartsPainter)
            .cutStarts();

    final everyCut = [0.0, 10 * ppf, 24 * ppf];
    expect(startsOn('storyboard-camera-cut-starts-t1'), everyCut);
    expect(startsOn('storyboard-conte-cut-starts-t1'), everyCut);
    expect(
      startsOn('storyboard-conte-cut-starts-t1-conte+1'),
      everyCut,
      reason: 'the row riding the conte, a seat above it',
    );
  });
}
