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
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_drop_verdict.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

import '../../helpers/placed_sound_conform.dart';

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

  /// The same track with its SE row where the storyboard draws SE rows: on
  /// the TRACK. [project]'s S1 sits in the cut's own layers, which only the
  /// timeline shows.
  EditorSessionManager trackSeProject({AudioConformStore? conform}) {
    final session = EditorSessionManager(
      audioConformStore: conform,
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
                ],
              ),
            ],
            seLayers: [
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
    );
    addTearDown(session.dispose);
    return session;
  }

  testWidgets('an SE row\'s empty cell on the storyboard says no to a picture, '
      'and a sound let go there stands on that cell and is a new block there', (
    tester,
  ) async {
    final s = trackSeProject();
    final placed = <ImportLayerSpot>[];
    final gap = find.byKey(
      const ValueKey<String>('storyboard-se-cell-drop-verdict-se-6'),
    );
    // Two frames into the gap that starts after the block at 2..5: frame 8.
    const intoTheGap = Offset(2 * 8 + 4, 12);
    var verdict = await pumpStoryboard(tester, s, r'C:\art\bg.png', placed);
    var gesture = await hover(tester, tester.getTopLeft(gap) + intoTheGap);
    expect(verdict.value, isFalse, reason: 'an SE row holds sounds');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(placed, isEmpty);

    verdict = await pumpStoryboard(tester, s, r'C:\snd\door.wav', placed);
    gesture = await hover(tester, tester.getTopLeft(gap) + intoTheGap);
    expect(verdict.value, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();

    expect(placed, [
      const SeCellSpot(layerId: seId, trackFrame: 8, shownCell: 8),
    ]);
    expect(
      s.selectedRow,
      const LayerRowAddress(seId),
      reason: 'landing is standing: the drop stood on the row it named',
    );
  });

  testWidgets('the storyboard\'s rail says no to a picture — no row of the '
      'cut\'s stack is on it — and a sound let go there takes the SE rows\' '
      'rule, as on the timeline\'s rail', (tester) async {
    final s = project();
    final placed = <ImportLayerSpot>[];
    final rail = find.byKey(
      const ValueKey<String>('storyboard-rail-placement-entrance'),
    );
    var verdict = await pumpStoryboard(tester, s, r'C:\art\bg.png', placed);
    var gesture = await hover(tester, tester.getCenter(rail));
    expect(verdict.value, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(placed, isEmpty);

    verdict = await pumpStoryboard(tester, s, r'C:\snd\door.wav', placed);
    gesture = await hover(tester, tester.getCenter(rail));
    expect(verdict.value, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(placed, [const AboveActiveLayerSpot()]);
  });

  /// 🚨F-155 (유저 2026-09-17): 「그림 존재하는데 블록이 회색임」 — the row
  /// kept showing the drag's stand-in cels after the file was let go.
  testWidgets('whatever an entrance draws while a file stands over it goes '
      'when the file is let go, as when it leaves — a row\'s frames, an SE '
      'row\'s empty cell and the layer area, on the timeline and the sheet', (
    tester,
  ) async {
    const picture = r'C:\art\bg.png';
    const sound = r'C:\snd\door.wav';
    // A quarter second — six frames — so a sound over an SE gap has a
    // length to draw.
    final s = trackSeProject(conform: soundConformStore(seconds: 0.25));
    await tester.runAsync(() => s.audioConformStore.ensurePeaksFor(sound));

    Offset into(String key, Offset by) =>
        tester.getTopLeft(find.byKey(ValueKey<String>(key))) + by;
    // Each entrance the hover draws on, the file it draws for, and a point
    // inside it: a row's frames and the layer area take a picture, an SE
    // row's gap (the one before the block at 2..5 — the sheet runs the
    // later one off the bottom of the window) a sound.
    final entrances = <(String, TimelineOrientation, String, Offset Function())>[
      (
        'the timeline\'s row frames',
        TimelineOrientation.horizontal,
        picture,
        () => into('timeline-layer-asset-drop-$drawingId', const Offset(72, 8)),
      ),
      (
        'the sheet\'s row frames',
        TimelineOrientation.vertical,
        picture,
        () => into('xsheet-layer-asset-drop-$drawingId', const Offset(8, 72)),
      ),
      (
        'the timeline\'s SE gap',
        TimelineOrientation.horizontal,
        sound,
        () => into('timeline-se-cell-drop-$seId-0', const Offset(24, 8)),
      ),
      (
        'the sheet\'s SE gap',
        TimelineOrientation.vertical,
        sound,
        () => into('xsheet-se-cell-drop-$seId-0', const Offset(8, 24)),
      ),
      (
        'the timeline\'s layer area',
        TimelineOrientation.horizontal,
        picture,
        () => into('timeline-rail-row-$drawingId-row', const Offset(24, 3)),
      ),
      (
        'the sheet\'s layer area',
        TimelineOrientation.vertical,
        picture,
        () => into('xsheet-layer-placement-entrance', const Offset(3, 8)),
      ),
    ];

    for (final (name, orientation, path, at) in entrances) {
      final verdict = await pumpTimeline(
        tester,
        s,
        path,
        orientation: orientation,
      );
      final gesture = await hover(tester, at());
      expect(
        s.dragPreview.value,
        isNotNull,
        reason: '$name: premise — the file standing there is drawn',
      );

      await gesture.up();
      await tester.pump();

      expect(
        s.dragPreview.value,
        isNull,
        reason: '$name: let go, what it would make is no longer drawn',
      );
      expect(
        s.layerRowDragVerbs.inFlight.value,
        isNull,
        reason: '$name: nor the caret that marked its gap',
      );
      expect(verdict.value, isNull, reason: '$name: nor the chip\'s answer');
      await tester.pumpAndSettle();
    }
    s.playbackRig.prerenderScheduler.cancel();
  });
}
