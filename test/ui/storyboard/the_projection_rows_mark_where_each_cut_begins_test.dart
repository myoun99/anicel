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
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show TimelineGridSheet, timelineFrameBoundaryLinePosition;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show CutTrimDragPreview;

/// 🗣️I-73 ④ — the drawn proposal: 「투영 행은 컷이 시작하는 자리마다 세로
/// 점선(2 3)」, and 유저 2026-10-08: 「컷 클리핑하는거 사이 점선으로
/// 만드는거 좋네. 굉장히 알기쉬워」.
///
/// Every projection row — the camera row, the conte row, a row riding the
/// conte — draws the one dashed line where each cut begins, from one
/// painter. Cuts a [0, 10) and b [10, 20), four frames of gap, then c
/// [24, 30) — a and b with a conte and a row riding it, c with neither.
///
/// 🗣️F-347 (유저 2026-10-12): 「기존 세로선 위에 점선 얹는거같은데 그
/// 부분의 세로선을 그냥 점선으로 교체할수있나?」 — the dash stands on the
/// grid's own line, and the sheet leaves that line to it across exactly the
/// rows that stroke it.
void main() {
  const trackId = TrackId('t1');
  const sheetKey = ValueKey<String>('storyboard-grid-sheet');

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

  /// The conte tab over the three cuts; the session, to steer a drag.
  Future<EditorSessionManager> pumpDashes(WidgetTester tester) async {
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
    return session;
  }

  double pixelsPerFrame(WidgetTester tester) => tester
      .widget<StoryboardPanel>(find.byType(StoryboardPanel))
      .pixelsPerFrame;

  /// Each stretch of the screen that dashes, top to bottom, with the frames
  /// it dashes — as the rows' painters stroke them, and as the sheet yields
  /// them.
  ({_Dashed painted, _Dashed yielded}) dashes(WidgetTester tester) {
    final painted = <(double, double), Set<int>>{};
    for (final element in find.byType(CustomPaint).evaluate()) {
      if ((element.widget as CustomPaint).painter
          case final StoryboardCutStartsPainter painter) {
        final rect = tester.getRect(find.byWidget(element.widget));
        (painted[(rect.top, rect.bottom)] ??= {}).addAll(painter.starts);
      }
    }
    final top = tester.getTopLeft(find.byKey(sheetKey)).dy;
    final rows = tester.widget<TimelineGridSheet>(find.byKey(sheetKey)).rows;
    final yielded = <(double, double), Set<int>>{};
    for (final (:frame, :from, :to) in rows.dashes) {
      (yielded[(top + from, top + to)] ??= {}).add(frame);
    }
    return (painted: painted, yielded: yielded);
  }

  testWidgets('🎯the camera row, the conte row and the row riding it dash '
      'where each cut begins — its place, every cut, on the grid\'s own '
      'line', (tester) async {
    await pumpDashes(tester);
    final ppf = pixelsPerFrame(tester);

    /// Where the row keyed [key] dashes, as its painter lays them down.
    List<double> startsOn(String key) =>
        (tester.widget<CustomPaint>(find.byKey(ValueKey<String>(key))).painter!
                as StoryboardCutStartsPainter)
            .cutStarts();

    final everyCut = [
      for (final frame in [0, 10, 24])
        timelineFrameBoundaryLinePosition(frame, ppf),
    ];
    expect(startsOn('storyboard-camera-cut-starts-t1'), everyCut);
    expect(startsOn('storyboard-conte-cut-starts-t1'), everyCut);
    expect(
      startsOn('storyboard-conte-cut-starts-t1-conte+1'),
      everyCut,
      reason: 'the row riding the conte, a seat above it',
    );
    const cameraDashes = ValueKey<String>('storyboard-camera-cut-starts-t1');
    expect(
      tester.getTopLeft(find.byKey(sheetKey)).dx,
      tester.getTopLeft(find.byKey(cameraDashes)).dx,
      reason: 'the row and the sheet share an origin, so the same x is the '
          'same pixel',
    );
  });

  testWidgets('🎯the sheet leaves each cut start to the dash across exactly '
      'the rows that stroke it (F-347)', (tester) async {
    await pumpDashes(tester);
    final (:painted, :yielded) = dashes(tester);
    expect(
      painted.length,
      3,
      reason: 'fixture premise: the camera row, the conte row and the row '
          'riding it',
    );
    expect(yielded, painted);
  });

  testWidgets('a drag in flight moves the yield with the dash, and letting '
      'go puts it back', (tester) async {
    final session = await pumpDashes(tester);
    session.dragPreview.value = CutTrimDragPreview(
      previewDurations: {const CutId('a'): 14},
    );
    await tester.pump();
    final during = dashes(tester);
    expect(during.painted, hasLength(3));
    expect(
      during.painted.values,
      everyElement({0, 14, 28}),
      reason: 'fixture premise: the rows follow the drag',
    );
    expect(during.yielded, during.painted);

    session.dragPreview.value = null;
    await tester.pump();
    final after = dashes(tester);
    expect(after.yielded.values, everyElement({0, 10, 24}));
    expect(after.yielded, after.painted);
  });
}

/// Frames dashed, by the stretch of the screen they are dashed across —
/// its top and its bottom.
typedef _Dashed = Map<(double, double), Set<int>>;
