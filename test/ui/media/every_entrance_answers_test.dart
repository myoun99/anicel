import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_drop_verdict.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// 🚨EVERY ENTRANCE ANSWERS FOR THE FILE STANDING OVER IT, and the chip wears
/// the answer (유저 2026-09-11, 미디어 배치 라운드: 「불가능 = 칩의 금지
/// 표시(커서는 그대로)」). A no is a no everywhere: nothing lands.
void main() {
  const seId = LayerId('verdict-se');
  const drawingId = LayerId('verdict-drawing');

  EditorSessionManager project() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('verdict-project'),
        name: 'Verdict Project',
        createdAt: DateTime.utc(2026, 9, 12),
        tracks: [
          Track(
            id: const TrackId('verdict-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('verdict-cut'),
                name: 'Verdict Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: drawingId,
                    name: 'A',
                    frames: const [],
                    timeline: const {},
                  ),
                  Layer(
                    id: seId,
                    name: 'S1',
                    kind: LayerKind.se,
                    frames: [
                      Frame(
                        id: const FrameId('verdict-f1'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: {
                      2: const TimelineExposure.drawing(
                        FrameId('verdict-f1'),
                        length: 4,
                      ),
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
    return session;
  }

  /// A pool row carrying [path], [panel] beside it, both under one verdict
  /// channel — as the workspace holds them.
  Future<ValueNotifier<bool?>> pumpBeside(
    WidgetTester tester,
    EditorSessionManager s,
    String path,
    Widget Function() panel,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final verdict = ValueNotifier<bool?>(null);
    addTearDown(verdict.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaDropVerdictScope(
            verdict: verdict,
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Draggable<MediaAssetDragData>(
                    data: MediaAssetDragData(path: path, name: path),
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    feedback: const SizedBox(width: 8, height: 8),
                    child: Container(
                      key: const ValueKey<String>('source'),
                      width: 40,
                      height: 40,
                      color: const Color(0xFF888888),
                    ),
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: s,
                    builder: (context, _) => panel(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return verdict;
  }

  /// The timeline beside the pool row.
  Future<ValueNotifier<bool?>> pumpTimeline(
    WidgetTester tester,
    EditorSessionManager s,
    String path, {
    TimelineOrientation orientation = TimelineOrientation.horizontal,
  }) => pumpBeside(
    tester,
    s,
    path,
    () => TimelineTabHost(
      session: s,
      orientation: orientation,
      onOrientationChanged: (_) {},
      pixelsPerFrame: 48,
      onPixelsPerFrameChanged: (_) {},
      showSeconds: false,
      onShowSecondsChanged: (_) {},
      onPlaceMediaAsset: (_, _, _) {},
      onPlaceMediaAssetBetweenLayers: (_, _, _) {},
    ),
  );

  /// The storyboard beside the pool row; each place its host would open the
  /// window for is written to [placed].
  Future<ValueNotifier<bool?>> pumpStoryboard(
    WidgetTester tester,
    EditorSessionManager s,
    String path,
    List<ImportLayerSpot> placed,
  ) => pumpBeside(
    tester,
    s,
    path,
    () => StoryboardTabHost(
      session: s,
      pixelsPerFrame: 8,
      onPixelsPerFrameChanged: (_) {},
      showSeconds: false,
      onShowSecondsChanged: (_) {},
      thumbnailFor: null,
      onPlaceMediaAsset: (_, spot) => placed.add(spot),
    ),
  );

  Future<TestGesture> hover(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('source'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(at);
    await tester.pump();
    return gesture;
  }

  testWidgets('an SE block takes a sound and says no to a picture — which '
      'then links nothing', (tester) async {
    final s = project();
    final verdict = await pumpTimeline(tester, s, r'C:\art\bg.png');
    final block = find.byKey(
      const ValueKey<String>('timeline-se-asset-drop-verdict-se-2'),
    );

    final gesture = await hover(tester, tester.getCenter(block));
    expect(verdict.value, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();

    final se = s.layers.firstWhere((layer) => layer.id == seId);
    expect(se.audioClips, isEmpty, reason: 'a picture is no sound to link');
  });

  testWidgets('the verb itself refuses a picture on an SE block', (
    tester,
  ) async {
    final s = project();

    s.mediaPool.linkMediaAssetToSeBlock(
      layerId: seId,
      blockStartFrame: 2,
      path: r'C:\art\bg.png',
    );

    expect(
      s.layers.firstWhere((layer) => layer.id == seId).audioClips,
      isEmpty,
    );
  });

  testWidgets('a drawing row\'s frames say no to a sound, yes to a picture', (
    tester,
  ) async {
    final s = project();
    final row = find.byKey(
      ValueKey<String>('timeline-layer-asset-drop-$drawingId'),
    );
    var verdict = await pumpTimeline(tester, s, r'C:\snd\door.wav');
    var gesture = await hover(
      tester,
      tester.getTopLeft(row) + const Offset(24 + 48, 8),
    );
    expect(verdict.value, isFalse, reason: '「그림 행 → 받지 않는다」');
    await gesture.up();
    await tester.pumpAndSettle();

    verdict = await pumpTimeline(tester, s, r'C:\art\bg.png');
    gesture = await hover(
      tester,
      tester.getTopLeft(row) + const Offset(24 + 48, 8),
    );
    expect(verdict.value, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('an SE row\'s empty cell says no to a picture', (tester) async {
    final s = project();
    final verdict = await pumpTimeline(tester, s, r'C:\art\bg.png');
    final gap = find.byKey(
      ValueKey<String>('timeline-se-cell-drop-$seId-6'),
    );

    final gesture = await hover(
      tester,
      tester.getTopLeft(gap) + const Offset(24, 8),
    );
    expect(verdict.value, isFalse, reason: 'an SE row holds sounds');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the layer area says yes at a gap a new row may take, and no '
      'where it may not — above the SE rows', (tester) async {
    final s = project();
    final verdict = await pumpTimeline(tester, s, r'C:\art\bg.png');
    final drawingRail = find.byKey(
      ValueKey<String>('timeline-rail-row-$drawingId-row'),
    );
    final seRail = find.byKey(ValueKey<String>('timeline-rail-row-$seId-row'));

    var gesture = await hover(
      tester,
      tester.getTopLeft(drawingRail) + const Offset(24, 3),
    );
    expect(verdict.value, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();

    gesture = await hover(
      tester,
      tester.getTopLeft(seRail) + const Offset(24, 3),
    );
    expect(verdict.value, isFalse, reason: 'a picture row does not go there');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the sheet answers the same — a drawing column says no to a '
      'sound, the header strip no past the SE column', (tester) async {
    final s = project();
    var verdict = await pumpTimeline(
      tester,
      s,
      r'C:\snd\door.wav',
      orientation: TimelineOrientation.vertical,
    );
    final column = find.byKey(
      ValueKey<String>('xsheet-layer-asset-drop-$drawingId'),
    );
    var gesture = await hover(
      tester,
      tester.getTopLeft(column) + const Offset(8, 24 + 48),
    );
    expect(verdict.value, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();

    verdict = await pumpTimeline(
      tester,
      s,
      r'C:\art\bg.png',
      orientation: TimelineOrientation.vertical,
    );
    // The sheet lists the stack raw — A, then S1 — so its far end is past
    // the SE column, where a picture row does not go.
    final strip = tester.getRect(
      find.byKey(const ValueKey<String>('xsheet-layer-placement-entrance')),
    );
    gesture = await hover(
      tester,
      Offset(strip.left + 2 * timelineLayerRowHeight - 2, strip.center.dy),
    );
    expect(verdict.value, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a track\'s frames on the storyboard say no to a sound, and a '
      'picture let go there stands on that frame and is a NEW cut there', (
    tester,
  ) async {
    final s = project();
    final placed = <ImportLayerSpot>[];
    final lane = find.byKey(
      const ValueKey<String>('storyboard-track-asset-drop-verdict-track'),
    );
    // Past the 12-frame cut: frame 16 of the track, 4 frames into the gap.
    const pastTheCut = Offset(16 * 8 + 4, 12);
    var verdict = await pumpStoryboard(tester, s, r'C:\snd\door.wav', placed);
    var gesture = await hover(tester, tester.getTopLeft(lane) + pastTheCut);
    expect(verdict.value, isFalse, reason: 'a sound\'s place is the SE rows');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(placed, isEmpty);

    verdict = await pumpStoryboard(tester, s, r'C:\art\bg.png', placed);
    gesture = await hover(tester, tester.getTopLeft(lane) + pastTheCut);
    expect(verdict.value, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    // The warm scheduler arms an idle timer whenever the playhead moves.
    s.playbackRig.prerenderScheduler.cancel();

    expect(placed, [const NewCutSpot(index: 1, leadingGapFrames: 4)]);
    expect(
      s.activeCutOrNull,
      isNull,
      reason: 'landing is standing: the drop stood on frame 16, in the gap',
    );
  });
}
