import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';

/// The multitrack display path's canvas content: every track's covered cut
/// stacks as one camera projection per track (bottom letterboxes + paper,
/// the rest composite transparently), and uncovered frames stay the void.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const cameraFrameSize = CanvasSize(width: 4, height: 2);

  Cut cutOf(
    String id,
    int duration, {
    int leadingGap = 0,
    TransformTrack? transformTrack,
  }) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    leadingGapFrames: leadingGap,
    canvasSize: canvasSize,
    transformTrack: transformTrack,
  );

  /// track-1: cut-a [0,4) — track-2: cut-c [2,12). Frame 3 is covered by
  /// both; frame 5 by track-2 alone; frame 12+ by nobody.
  Project project({
    TransformTrack? cutATransformTrack,
    TransformTrack? cutCTransformTrack,
  }) => Project(
    id: const ProjectId('project'),
    name: 'Project',
    cameraSize: cameraFrameSize,
    tracks: [
      Track(
        id: const TrackId('track-1'),
        name: 'One',
        cuts: [cutOf('cut-a', 4, transformTrack: cutATransformTrack)],
      ),
      Track(
        id: const TrackId('track-2'),
        name: 'Two',
        cuts: [
          cutOf('cut-c', 10, leadingGap: 2, transformTrack: cutCTransformTrack),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  BrushFrameKey frameKey(Cut cut, LayerId layerId, FrameId frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('project'),
        trackId: const TrackId('track-1'),
        cutId: cut.id,
        layerId: layerId,
        frameId: frameId,
      );

  ({
    CutFrameCompositeCache composites,
    ValueNotifier<int?> frame,
    List<StoryboardTimelineLayoutEntry> layout,
  })
  fixture({
    TransformTrack? cutATransformTrack,
    TransformTrack? cutCTransformTrack,
  }) {
    final store = BrushFrameStore();
    final composites = CutFrameCompositeCache(
      layerImages: LayerFrameImageCache(frameStore: store),
      frameStore: store,
      frameKeyOf: frameKey,
    );
    return (
      composites: composites,
      frame: ValueNotifier<int?>(null),
      layout: buildStoryboardTimelineLayout(
        project(
          cutATransformTrack: cutATransformTrack,
          cutCTransformTrack: cutCTransformTrack,
        ),
      ),
    );
  }

  Future<void> pumpView(
    WidgetTester tester, {
    required CutFrameCompositeCache composites,
    required ValueNotifier<int?> frame,
    required List<StoryboardTimelineLayoutEntry> layout,
    bool Function(CutId cutId)? cutFxEnabledOf,
    bool Function(CutId cutId)? cutPictureVisibleOf,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasTrackStackView(
            globalFrame: frame,
            positionsOf: (globalFrame) => resolveTrackStackPositions(
              layout: layout,
              globalFrameIndex: globalFrame,
            ),
            compositeCache: composites,
            qualityOf: () => PlaybackQuality.full,
            cameraFrameSize: cameraFrameSize,
            cameraPoseOf: (cut, frameIndex) =>
                CameraPose(center: CanvasPoint(x: 4, y: 4)),
            cutFxEnabledOf: cutFxEnabledOf,
            cutPictureVisibleOf: cutPictureVisibleOf,
          ),
        ),
      ),
    );
  }

  List<PlaybackFramePainter> paintersOf(WidgetTester tester) {
    return [
      for (final paint in tester.widgetList<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('canvas-track-stack-frames')),
          matching: find.byType(CustomPaint),
        ),
      ))
        paint.painter! as PlaybackFramePainter,
    ];
  }

  Future<void> warm(
    WidgetTester tester,
    CutFrameCompositeCache composites,
    List<StoryboardTimelineLayoutEntry> layout,
    List<(String, int)> frames,
  ) async {
    await tester.runAsync(() async {
      for (final (cutId, frameIndex) in frames) {
        final cut = layout
            .firstWhere((entry) => entry.cutId == CutId(cutId))
            .cut;
        await composites.prepareComposite(
          cut: cut,
          frameIndex: frameIndex,
          quality: PlaybackQuality.full,
        );
      }
    });
  }

  testWidgets('a frame covered by both tracks stacks one camera projection '
      'per track — the bottom letterboxes and papers, the one above '
      'composites transparently', (tester) async {
    final f = fixture();
    await warm(tester, f.composites, f.layout, [('cut-a', 3), ('cut-c', 1)]);

    f.frame.value = 3;
    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
    );

    final painters = paintersOf(tester);
    expect(painters, hasLength(2));
    expect(painters[0].image, isNotNull);
    expect(painters[0].cameraPose, isNotNull, reason: 'camera framing');
    expect(painters[0].cameraFrameSize, cameraFrameSize);
    expect(painters[0].paintPaper, isTrue);
    expect(painters[0].paintLetterbox, isTrue);
    expect(painters[1].image, isNotNull);
    expect(painters[1].cameraPose, isNotNull);
    expect(painters[1].paintPaper, isFalse, reason: 'stacks over the bottom');
    expect(painters[1].paintLetterbox, isFalse);

    f.composites.dispose();
  });

  testWidgets('a frame covered on one track alone paints just that track '
      '(the gap on the other contributes nothing)', (tester) async {
    final f = fixture();
    await warm(tester, f.composites, f.layout, [('cut-c', 3)]);

    f.frame.value = 5; // track-1 has no cut here
    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
    );

    final painters = paintersOf(tester);
    expect(painters, hasLength(1));
    expect(painters.single.paintPaper, isTrue);
    expect(painters.single.paintLetterbox, isTrue);

    f.composites.dispose();
  });

  testWidgets('a frame no track covers (and the null no-parking state) '
      'keeps the void', (tester) async {
    final f = fixture();

    f.frame.value = 20;
    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-track-stack-void')),
      findsOneWidget,
    );

    f.frame.value = null;
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('canvas-track-stack-void')),
      findsOneWidget,
    );

    f.composites.dispose();
  });

  testWidgets('moving the parking repaints the stack to the new frame\'s '
      'coverage', (tester) async {
    final f = fixture();
    f.frame.value = 3;
    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
    );
    expect(paintersOf(tester), hasLength(2));

    f.frame.value = 5;
    await tester.pump();
    expect(paintersOf(tester), hasLength(1), reason: 'track-1 gapped away');

    f.frame.value = 20;
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('canvas-track-stack-void')),
      findsOneWidget,
    );

    f.composites.dispose();
  });

  testWidgets('cache misses show no picture yet; a later warm shows on the '
      'next build, and moving to an unwarmed frame keeps the stale held '
      'frame (the playback stale policy)', (tester) async {
    final f = fixture();
    f.frame.value = 3;
    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
    );
    expect(paintersOf(tester)[0].image, isNull, reason: 'nothing warmed yet');

    await warm(tester, f.composites, f.layout, [('cut-a', 3), ('cut-c', 1)]);
    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
    );
    expect(paintersOf(tester)[0].image, isNotNull);
    expect(paintersOf(tester)[1].image, isNotNull);

    // Frame 2 is covered by both tracks but only warmed for neither: the
    // held clones stand in (no flicker to blank).
    f.frame.value = 2;
    await tester.pump();
    expect(paintersOf(tester)[0].image, isNotNull, reason: 'stale held');
    expect(paintersOf(tester)[1].image, isNotNull, reason: 'stale held');

    f.composites.dispose();
  });

  testWidgets('the V-row display gates apply per track: fx off bypasses '
      'the cut pose AND fade, the eye off drops that track\'s picture '
      'alone', (tester) async {
    // cut-a carries a geometric key + an opacity key: posed and fading.
    final posed = fixture(
      cutATransformTrack: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 6, y: 4),
        ),
        opacity: PropertyTrack<double>.empty().withKey(0, 0.5),
      ),
    );
    await warm(tester, posed.composites, posed.layout, [
      ('cut-a', 3),
      ('cut-c', 1),
    ]);
    posed.frame.value = 3;
    await pumpView(
      tester,
      composites: posed.composites,
      frame: posed.frame,
      layout: posed.layout,
    );
    expect(paintersOf(tester)[0].cutPose, isNotNull);
    expect(paintersOf(tester)[0].fadeOpacity, 0.5);

    await pumpView(
      tester,
      composites: posed.composites,
      frame: posed.frame,
      layout: posed.layout,
      cutFxEnabledOf: (cutId) => cutId != const CutId('cut-a'),
    );
    expect(paintersOf(tester)[0].cutPose, isNull, reason: 'pose bypassed');
    expect(paintersOf(tester)[0].fadeOpacity, 1, reason: 'fade bypassed');

    await pumpView(
      tester,
      composites: posed.composites,
      frame: posed.frame,
      layout: posed.layout,
      cutPictureVisibleOf: (cutId) => cutId != const CutId('cut-a'),
    );
    expect(paintersOf(tester)[0].image, isNull, reason: 'eye off');
    expect(paintersOf(tester)[1].image, isNotNull, reason: 'per track');

    posed.composites.dispose();
  });

  testWidgets('fades split by stack position: the bottom track washes the '
      'frame (playback parity), an upper track thins its own contribution '
      'instead of blanking the stage below', (tester) async {
    // Both cuts mid-fade at the parked frame.
    final fading = fixture(
      cutATransformTrack: TransformTrack.empty().copyWith(
        opacity: PropertyTrack<double>.empty().withKey(0, 0.5),
      ),
      cutCTransformTrack: TransformTrack.empty().copyWith(
        opacity: PropertyTrack<double>.empty().withKey(0, 0.25),
      ),
    );
    await warm(tester, fading.composites, fading.layout, [
      ('cut-a', 3),
      ('cut-c', 1),
    ]);
    fading.frame.value = 3;
    await pumpView(
      tester,
      composites: fading.composites,
      frame: fading.frame,
      layout: fading.layout,
    );

    final painters = paintersOf(tester);
    expect(painters[0].fadeOpacity, 0.5, reason: 'bottom = the wash');
    expect(painters[0].imageOpacity, 1);
    expect(
      painters[1].fadeOpacity,
      1,
      reason: 'an upper wash would cover the whole frame below',
    );
    expect(painters[1].imageOpacity, 0.25, reason: 'its own picture thins');

    fading.composites.dispose();
  });
}
