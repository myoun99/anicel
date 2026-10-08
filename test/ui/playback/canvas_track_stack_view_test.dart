import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transition_geometry.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';

/// The multitrack display path's canvas content: every track's covered cut
/// stacks as one camera projection per track (bottom letterboxes + paper,
/// the rest composite transparently), and uncovered frames stay the void.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const cameraFrameSize = CanvasSize(width: 4, height: 2);

  Cut cutOf(String id, int duration, {int leadingGap = 0}) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    leadingGapFrames: leadingGap,
    canvasSize: canvasSize,
  );

  /// track-1: cut-a [0,4) — track-2: cut-c [2,12). Frame 3 is covered by
  /// both; frame 5 by track-2 alone; frame 12+ by nobody. The V effects
  /// live on each TRACK now (R4) and reach the view via [pumpView]'s
  /// `transformTrackOf` callback, keyed on the GLOBAL frame axis.
  Project project() => Project(
    id: const ProjectId('project'),
    name: 'Project',
    cameraSize: cameraFrameSize,
    tracks: [
      Track(
        id: const TrackId('track-1'),
        name: 'One',
        cuts: [cutOf('cut-a', 4)],
      ),
      Track(
        id: const TrackId('track-2'),
        name: 'Two',
        cuts: [cutOf('cut-c', 10, leadingGap: 2)],
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
  fixture() {
    final store = BrushFrameStore();
    final composites = CutFrameCompositeCache(
      layerImages: LayerFrameImageCache(frameStore: store),
      frameStore: store,
      frameKeyOf: frameKey,
    );
    return (
      composites: composites,
      frame: ValueNotifier<int?>(null),
      layout: buildStoryboardTimelineLayout(project()),
    );
  }

  Future<void> pumpView(
    WidgetTester tester, {
    required CutFrameCompositeCache composites,
    required ValueNotifier<int?> frame,
    required List<StoryboardTimelineLayoutEntry> layout,
    bool Function(CutId cutId)? cutFxEnabledOf,
    List<TransitionSpan> Function(TrackId trackId)? spansOf,
    List<ResolvedSeNameTag> Function(Cut cut, int frameIndex)? seNameTagsOf,
    bool cameraViewEnabled = true,
    bool backdropNone = false,
    bool pasteboardNone = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasTrackStackView(
            globalFrame: frame,
            positionsOf: (globalFrame) => resolveTrackStackContributions(
              layout: layout,
              spansOf: spansOf ?? (_) => const [],
              globalFrameIndex: globalFrame,
            ),
            compositeCache: composites,
            cameraFrameSize: cameraFrameSize,
            cameraViewEnabled: cameraViewEnabled,
            cameraPoseOf: (cut, frameIndex) =>
                CameraPose(center: CanvasPoint(x: 4, y: 4)),
            cutFxEnabledOf: cutFxEnabledOf,
            seNameTagsOf: seNameTagsOf,
            pasteboardArgb: 0xff123456,
            backdropNone: backdropNone,
            pasteboardNone: pasteboardNone,
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
        // An absent backdrop's checkerboard floor rides the same stack
        // (F-114); only the frames are asked about here.
        if (paint.painter case final PlaybackFramePainter painter) painter,
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

  testWidgets('each unit carries the names its OWN cut speaks, at its own '
      'frame', (tester) async {
    final f = fixture();
    await warm(tester, f.composites, f.layout, [('cut-a', 3), ('cut-c', 1)]);
    ResolvedSeNameTag tagOf(Cut cut, int frame) => ResolvedSeNameTag(
      layerId: '${cut.id.value}@$frame',
      widthBudget: 100,
      content: TextCelContent(
        text: cut.id.value,
        style: SeNameTag.defaultStyle,
        position: Offset.zero,
      ),
    );

    f.frame.value = 3;
    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
      seNameTagsOf: (cut, frame) => [tagOf(cut, frame)],
    );

    expect(
      [
        for (final painter in paintersOf(tester))
          [for (final tag in painter.seNameTags) tag.layerId],
      ],
      [
        ['cut-a@3'],
        ['cut-c@1'],
      ],
      reason: 'resolved PER CUT (R5b): each covered track its own speakers',
    );

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

  // ↩️Two pins stood here for the V row's own gates, which left its head on
  // 2026-10-08 (I-73): the EYE dropped one track's picture alone, and the
  // track's STATIC opacity (0.5 on the bottom track, 0.25 on the one above)
  // drove the split below. What thins a contribution now is a transition,
  // and the split by stack position is unchanged — the bottom track's half
  // is pinned in the O.L group under this, the upper track's here.
  testWidgets('an O.L on an UPPER track thins its own pictures instead of '
      'washing the stage below', (tester) async {
    // track-1: cut-a [0,10) — the stage. track-2: cut-c [0,4) then cut-d
    // [4,10), with the O.L over [2,6).
    final store = BrushFrameStore();
    final composites = CutFrameCompositeCache(
      layerImages: LayerFrameImageCache(frameStore: store),
      frameStore: store,
      frameKeyOf: frameKey,
    );
    final frame = ValueNotifier<int?>(3);
    addTearDown(frame.dispose);
    await pumpView(
      tester,
      composites: composites,
      frame: frame,
      layout: buildStoryboardTimelineLayout(
        Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: cameraFrameSize,
          tracks: [
            Track(
              id: const TrackId('track-1'),
              name: 'One',
              cuts: [cutOf('cut-a', 10)],
            ),
            Track(
              id: const TrackId('track-2'),
              name: 'Two',
              cuts: [cutOf('cut-c', 4), cutOf('cut-d', 6)],
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      ),
      spansOf: (trackId) => trackId == const TrackId('track-2')
          ? const [(start: 2, length: 4, mark: CameraInstructionMarkType.ol)]
          : const [],
    );

    final painters = paintersOf(tester);
    expect(painters, hasLength(3), reason: 'the stage, and the O.L\'s two');
    expect(painters[0].fadeOpacity, 1);
    expect(painters[0].imageOpacity, 1);
    for (final upper in painters.skip(1)) {
      expect(
        upper.fadeOpacity,
        1,
        reason: 'an upper wash would cover the whole frame below',
      );
    }
    // Frame 3 = offset 1 of 4: the leaving cut opaque, the arriving one at
    // the ramp's 1/3 — the bottom track's own two weights, on the picture.
    expect(painters[1].imageOpacity, 1);
    expect(
      painters[2].imageOpacity,
      closeTo(1 / 3, 1e-9),
      reason: 'its own picture thins',
    );

    composites.dispose();
  });

  group('a cut-crossing O.L', () {
    /// ONE track, cut-a [0,4) then cut-b [4,10), with a 4-frame transition
    /// spanning [2,6) — dead centre on the boundary, so frames 2..5 have two
    /// pictures and the ramp runs 0, 1/3, 2/3, 1.
    Project olProject() => Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: cameraFrameSize,
      tracks: [
        Track(
          id: const TrackId('track-1'),
          name: 'One',
          cuts: [cutOf('cut-a', 4), cutOf('cut-b', 6)],
        ),
      ],
      createdAt: DateTime.utc(2026),
    );

    List<TransitionSpan> spans(TrackId _) => const [(start: 2, length: 4, mark: CameraInstructionMarkType.ol)];

    testWidgets('puts BOTH cuts on screen, leaving one first, and both paint '
        'the stage — a 場面転換 cross-fades the paper too, so keying it to the '
        'bottom CONTRIBUTION would superimpose line art over the old paper', (
      tester,
    ) async {
      final store = BrushFrameStore();
      final composites = CutFrameCompositeCache(
        layerImages: LayerFrameImageCache(frameStore: store),
        frameStore: store,
        frameKeyOf: frameKey,
      );
      final layout = buildStoryboardTimelineLayout(olProject());
      final frame = ValueNotifier<int?>(3);
      await pumpView(
        tester,
        composites: composites,
        frame: frame,
        layout: layout,
        spansOf: spans,
      );

      final painters = paintersOf(tester);
      expect(painters, hasLength(2));
      expect(painters[0].paintPaper, isTrue);
      expect(painters[1].paintPaper, isTrue, reason: 'the arriving cut too');
      expect(painters[0].paintLetterbox, isTrue);
      expect(painters[1].paintLetterbox, isTrue);

      composites.dispose();
    });

    testWidgets('lays the leaving cut down OPAQUE and the arriving one at the '
        'ramp — painting both at their own share leaves t(1-t) of the floor '
        'showing, which is a dip to black mid-dissolve', (tester) async {
      final store = BrushFrameStore();
      final composites = CutFrameCompositeCache(
        layerImages: LayerFrameImageCache(frameStore: store),
        frameStore: store,
        frameKeyOf: frameKey,
      );
      final layout = buildStoryboardTimelineLayout(olProject());
      final frame = ValueNotifier<int?>(3);
      await pumpView(
        tester,
        composites: composites,
        frame: frame,
        layout: layout,
        spansOf: spans,
      );

      // Frame 3 = offset 1 of 4 → the canonical ramp bottoms out ON the last
      // frame, so t = 1/3 and the leaving cut owns 2/3.
      final painters = paintersOf(tester);
      expect(painters[0].fadeOpacity, 1, reason: 'no floor may show through');
      expect(painters[1].fadeOpacity, closeTo(1 / 3, 1e-9));
      // The mix the two weights actually produce IS the ramp: source-over of
      // 1 then 1/3 gives 2/3 of the leaving picture and 1/3 of the arriving.
      expect((1 - 1 / 3) * 1, closeTo(2 / 3, 1e-9));

      composites.dispose();
    });

    testWidgets('outside the span nothing changes — one contribution, its own '
        'share, exactly as a project with no transition', (tester) async {
      final store = BrushFrameStore();
      final composites = CutFrameCompositeCache(
        layerImages: LayerFrameImageCache(frameStore: store),
        frameStore: store,
        frameKeyOf: frameKey,
      );
      final layout = buildStoryboardTimelineLayout(olProject());
      final frame = ValueNotifier<int?>(8);
      await pumpView(
        tester,
        composites: composites,
        frame: frame,
        layout: layout,
        spansOf: spans,
      );

      final painters = paintersOf(tester);
      expect(painters, hasLength(1));
      expect(painters.single.fadeOpacity, 1);
      expect(painters.single.paintPaper, isTrue);

      composites.dispose();
    });
  });

  testWidgets('CAMERA VIEW OFF leaves the stack in canvas space — no crop, no '
      'letterbox, no apron. A storyboard ruler drag parks per move, so this '
      'stack is what shows while scrubbing, and it used to reframe into the '
      'camera whatever the toggle said', (tester) async {
    final f = fixture();
    await warm(tester, f.composites, f.layout, [('cut-a', 3), ('cut-c', 1)]);
    f.frame.value = 3;

    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
      cameraViewEnabled: false,
    );
    var painters = paintersOf(tester);
    expect(painters[0].cameraFrameSize, isNull);
    expect(painters[0].cameraPose, isNull);
    expect(painters[0].paintLetterbox, isFalse);
    expect(painters[0].pasteboardColor, isNull);
    expect(painters[0].paintPaper, isTrue, reason: 'the paper is not the crop');
    expect(painters[0].image, isNotNull);

    // Toggle on: the crop is back, so framing stays available while scrubbing
    // rather than being reserved for playback.
    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
    );
    painters = paintersOf(tester);
    expect(painters[0].cameraFrameSize, cameraFrameSize);
    expect(painters[0].cameraPose, isNotNull);
    expect(painters[0].paintLetterbox, isTrue);
    expect(painters[0].pasteboardColor, isNotNull);

    f.composites.dispose();
  });

  testWidgets('🚨F-114: an ABSENT backdrop is the checkerboard floor, and an '
      'absent pasteboard rides the painter as a checkerboard on screen', (
    tester,
  ) async {
    // 유저 2026-09-15: 「없음버튼 누르면 없는상태. 즉 해당 용지부분이
    // 체크무늬되도록. 페이스트보드도 백그라운드도 동일하게」 — the law the
    // editing canvas keeps, so a scrub into playback does not trade the
    // checkerboard for a colour.
    final f = fixture();
    await warm(tester, f.composites, f.layout, [('cut-a', 3), ('cut-c', 1)]);
    f.frame.value = 3;
    Widget floor() => tester.widget(
      find.byKey(const ValueKey<String>('canvas-track-stack-floor')),
    );

    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
    );
    expect(floor(), isA<ColoredBox>(), reason: 'control: a backdrop that is there');

    await pumpView(
      tester,
      composites: f.composites,
      frame: f.frame,
      layout: f.layout,
      backdropNone: true,
      pasteboardNone: true,
    );
    expect(floor(), isA<CustomPaint>(), reason: 'the checkerboard floor');
    final bottom = paintersOf(tester).first;
    expect(bottom.pasteboardNone, isTrue);
    expect(
      bottom.checkersAbsentPlanes,
      isTrue,
      reason: 'on screen the absent apron checkers — the export never sets it',
    );

    f.composites.dispose();
  });
}
