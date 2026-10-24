import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/camera_instruction.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transition_geometry.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart' show LayerPlacement;
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';

/// One covered cut's share of the frame as the stack lays it: the unit's
/// fade, the painter under its picture (the apron, an absent paper's
/// checkerboard), the thinning on its picture, the picture — parked, its
/// own stack, its paper with it; under a run, the frame's one picture —
/// and the painter over it (names, veils).
typedef _Unit = ({
  double fade,
  PlaybackFramePainter under,
  double thinning,
  Widget picture,
  PlaybackFramePainter over,
});

extension on _Unit {
  /// The picture parked: the cut's own stack.
  CanvasLayerStackView get stack => picture as CanvasLayerStackView;

  /// The picture under a run: the frame's one picture.
  FramePictureView get played => picture as FramePictureView;
}

/// What a run on the stack hands it: the signal its pictures landed, and
/// whether a frame goes up when asked for.
typedef _Run = ({
  ValueNotifier<int> landings,
  bool Function(int frame) frameIsThere,
});

/// The multitrack display path's canvas content: every track's covered cut
/// stacks as one camera projection per track (the bottom's paper under it,
/// the rest composite transparently), drawn from its rows' images as the
/// canvas draws them, and uncovered frames stay the void.
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
  /// both; frame 5 by track-2 alone; frame 12+ by nobody.
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

  /// A cut's frame as the stack is told it — one row naming the cut and the
  /// frame, so a unit says which frame of which cut it was handed.
  List<CompositeNode<CanvasStackRow>> stackOf(Cut cut, int frameIndex) => [
    CompositeLeaf(
      CanvasLayerImageRequest(
        frameKey: BrushFrameKey(
          projectId: const ProjectId('project'),
          trackId: const TrackId('track-1'),
          cutId: cut.id,
          layerId: const LayerId('layer'),
          frameId: FrameId('${cut.id.value}@$frameIndex'),
        ),
        opacity: 1,
      ),
    ),
  ];

  String? toldFrame(Widget picture) => switch (picture) {
    CanvasLayerStackView(:final layers) => layers.single.frameKey.frameId.value,
    FramePictureView(:final nodes) => stackedCelsOf(nodes).single.frameId.value,
    _ => throw StateError('not a cut\'s picture: $picture'),
  };

  ({ValueNotifier<int?> frame, List<StoryboardTimelineLayoutEntry> layout})
  fixture() => (
    frame: ValueNotifier<int?>(null),
    layout: buildStoryboardTimelineLayout(project()),
  );

  Future<void> pumpView(
    WidgetTester tester, {
    required ValueNotifier<int?> frame,
    required List<StoryboardTimelineLayoutEntry> layout,
    List<TransitionSpan> Function(TrackId trackId)? spansOf,
    List<ResolvedSeNameTag> Function(Cut cut, int frameIndex)? seNameTagsOf,
    _Run? run,
    void Function(Object cut, int bytes)? onBufferBytes,
    bool cameraViewEnabled = true,
    bool backdropNone = false,
    bool pasteboardNone = false,
  }) async {
    final images = LayerFrameImageCache(frameStore: BrushFrameStore());
    addTearDown(images.dispose);
    final pictures = FramePictureStore<FramePictureKey>();
    addTearDown(pictures.dispose);
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
            stackOf: stackOf,
            imageCache: images,
            cameraFrameSize: cameraFrameSize,
            cameraViewEnabled: cameraViewEnabled,
            cameraPoseOf: (cut, frameIndex) =>
                CameraPose(center: CanvasPoint(x: 4, y: 4)),
            seNameTagsOf: seNameTagsOf,
            run: switch (run) {
              (:final landings, :final frameIsThere) => (
                cuts: (
                  landings: landings,
                  pictures: FramePictures(
                    store: pictures,
                    layerImages: images,
                    stackOf: (picture) =>
                        stackOf(picture.cut, picture.frameIndex),
                    pageOf: (picture) => (
                      canvasSize: picture.cut.canvasSize,
                      pasteboardReach: PasteboardReach.none,
                      paintPaper: picture.paintPaper,
                      paperBackground: ProjectBackground.defaultBackground,
                    ),
                  ),
                ),
                frameIsThere: frameIsThere,
              ),
              null => null,
            },
            onBufferBytes: onBufferBytes,
            pasteboardArgb: 0xff123456,
            backdropNone: backdropNone,
            pasteboardNone: pasteboardNone,
          ),
        ),
      ),
    );
  }

  List<_Unit> unitsOf(WidgetTester tester) => [
    for (final unit in find
        .byWidgetPredicate(
          (widget) => switch (widget.key) {
            ValueKey<Object>(value: ('track-stack-unit', _)) => true,
            _ => false,
          },
        )
        .evaluate())
      () {
        final inUnit = find.byElementPredicate(
          (element) => identical(element, unit),
        );
        final painters = [
          for (final paint in tester.widgetList<CustomPaint>(
            find.descendant(of: inUnit, matching: find.byType(CustomPaint)),
          ))
            if (paint.painter case final PlaybackFramePainter painter) painter,
        ];
        return (
          fade: (unit.widget as Opacity).opacity,
          under: painters.first,
          thinning: tester
              .widget<Opacity>(
                find.descendant(of: inUnit, matching: find.byType(Opacity)),
              )
              .opacity,
          picture: tester.widget(
            find.descendant(
              of: inUnit,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is CanvasLayerStackView ||
                    widget is FramePictureView,
              ),
            ),
          ),
          over: painters.last,
        );
      }(),
  ];

  const backdrop = 0xFF2040C0;
  final screen = GlobalKey();

  /// The stack at [frame] seen through the camera, twenty screen pixels a
  /// canvas pixel — the camera's frame is the screen's top left 80×40 — and
  /// what it put on screen, as the colour at a pixel. [cameraViewEnabled]
  /// false sees it through none.
  Future<int Function(int x, int y)> seenAt(
    WidgetTester tester,
    int frame, {
    required List<StoryboardTimelineLayoutEntry> layout,
    List<TransitionSpan> Function(TrackId trackId)? spansOf,
    bool backdropNone = false,
    bool cameraViewEnabled = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = LayerFrameImageCache(frameStore: BrushFrameStore());
    addTearDown(images.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: screen,
            child: SizedBox(
              width: 100,
              height: 60,
              child: CanvasTrackStackView(
                globalFrame: ValueNotifier<int?>(frame),
                positionsOf: (globalFrame) => resolveTrackStackContributions(
                  layout: layout,
                  spansOf: spansOf ?? (_) => const [],
                  globalFrameIndex: globalFrame,
                ),
                // Nothing drawn: what shows is the stage alone.
                stackOf: (_, _) => const [],
                imageCache: images,
                cameraFrameSize: cameraFrameSize,
                cameraViewEnabled: cameraViewEnabled,
                cameraPoseOf: (cut, frameIndex) =>
                    CameraPose(center: CanvasPoint(x: 4, y: 4)),
                viewport: CanvasViewport(zoom: 20),
                backdropArgb: backdrop,
                backdropNone: backdropNone,
                pasteboardArgb: 0xff123456,
              ),
            ),
          ),
        ),
      ),
    );
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final rgba = (await tester.runAsync<Uint8List>(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    return (int x, int y) {
      final o = (y * 100 + x) * 4;
      return (rgba[o + 3] << 24) |
          (rgba[o] << 16) |
          (rgba[o + 1] << 8) |
          rgba[o + 2];
    };
  }

  testWidgets('a frame covered by both tracks stacks one camera projection '
      'per track — the bottom papers, the one above composites '
      'transparently', (tester) async {
    final f = fixture();
    f.frame.value = 3;
    await pumpView(tester, frame: f.frame, layout: f.layout);

    final units = unitsOf(tester);
    expect(units, hasLength(2));
    expect(units[0].under.cameraPose, isNotNull, reason: 'camera framing');
    expect(units[0].under.cameraFrameSize, cameraFrameSize);
    expect(units[0].stack.paintPaper, isTrue);
    expect(units[1].under.cameraPose, isNotNull);
    expect(units[1].stack.paintPaper, isFalse, reason: 'stacks over the bottom');
    expect(
      [
        for (final unit in units) ...[
          unit.under.paintLetterbox,
          unit.over.paintLetterbox,
        ],
      ],
      everyElement(isFalse),
      reason: 'the letterbox is the floor\'s, under every track',
    );
  });

  testWidgets('🚨each unit is its OWN cut\'s tree at its own frame, drawn '
      'through the camera from the canvas\'s images', (tester) async {
    final f = fixture();
    f.frame.value = 3;
    await pumpView(tester, frame: f.frame, layout: f.layout);

    final units = unitsOf(tester);
    expect(
      [for (final unit in units) toldFrame(unit.stack)],
      ['cut-a@3', 'cut-c@1'],
      reason: 'cut-a at its frame 3, cut-c — two frames in — at its frame 1',
    );
    expect(
      units.first.stack.viewport,
      isNot(CanvasViewport()),
      reason: 'seen through the camera: the panel\'s view with the '
          'projection under it',
    );
  });

  testWidgets('each unit carries the names its OWN cut speaks, at its own '
      'frame', (tester) async {
    final f = fixture();
    ResolvedSeNameTag tagOf(Cut cut, int frame) => ResolvedSeNameTag(
      layerId: '${cut.id.value}@$frame',
      widthBudget: 100,
      shot: const LayerPlacement.identity(),
      content: TextCelContent(
        text: cut.id.value,
        style: SeNameTag.defaultStyle,
        position: Offset.zero,
      ),
    );

    f.frame.value = 3;
    await pumpView(
      tester,
      frame: f.frame,
      layout: f.layout,
      seNameTagsOf: (cut, frame) => [tagOf(cut, frame)],
    );

    expect(
      [
        for (final unit in unitsOf(tester))
          [for (final tag in unit.over.seNameTags) tag.layerId],
      ],
      [
        ['cut-a@3'],
        ['cut-c@1'],
      ],
      reason: 'resolved PER CUT (R5b): each covered track its own speakers',
    );
    expect(
      [for (final unit in unitsOf(tester)) unit.under.seNameTags],
      everyElement(isEmpty),
      reason: 'the names lie over the picture, never under it',
    );
  });

  testWidgets('a frame covered on one track alone paints just that track '
      '(the gap on the other contributes nothing)', (tester) async {
    final f = fixture();
    f.frame.value = 5; // track-1 has no cut here
    await pumpView(tester, frame: f.frame, layout: f.layout);

    final units = unitsOf(tester);
    expect(units, hasLength(1));
    expect(units.single.stack.paintPaper, isTrue);
    expect(
      units.single.under.paintPaper,
      isFalse,
      reason: 'the paper is the canvas\'s own, drawn with its rows',
    );
    expect(units.single.under.paintLetterbox, isFalse, reason: 'the floor\'s');
  });

  testWidgets('seen through the camera, the floor is the letterbox past its '
      'frame and the backdrop in it — or the checkerboard, where there is '
      'none (F-114)', (tester) async {
    final layout = buildStoryboardTimelineLayout(project());
    var at = await seenAt(tester, 20, layout: layout);
    expect(at(40, 20), backdrop, reason: 'in the frame, no track covers it');
    expect(at(90, 50), PlaybackFramePainter.letterboxColor.toARGB32());

    at = await seenAt(tester, 20, layout: layout, backdropNone: true);
    expect(
      at(40, 20),
      isNot(anyOf(backdrop, PlaybackFramePainter.letterboxColor.toARGB32())),
      reason: 'the checkerboard',
    );
  });

  testWidgets('a frame no track covers (and the null no-parking state) '
      'keeps the void', (tester) async {
    final f = fixture();

    f.frame.value = 20;
    await pumpView(tester, frame: f.frame, layout: f.layout);
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
  });

  testWidgets('moving the parking repaints the stack to the new frame\'s '
      'coverage', (tester) async {
    final f = fixture();
    f.frame.value = 3;
    await pumpView(tester, frame: f.frame, layout: f.layout);
    expect(unitsOf(tester), hasLength(2));

    f.frame.value = 5;
    await tester.pump();
    expect(unitsOf(tester), hasLength(1), reason: 'track-1 gapped away');
    expect(toldFrame(unitsOf(tester).single.stack), 'cut-c@3');

    f.frame.value = 20;
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('canvas-track-stack-void')),
      findsOneWidget,
    );
  });

  testWidgets('a run\'s pictures are the warmer\'s; a parked frame\'s, each '
      'cut makes its own', (tester) async {
    final f = fixture();
    f.frame.value = 3;
    await pumpView(tester, frame: f.frame, layout: f.layout);
    expect(
      [for (final unit in unitsOf(tester)) unit.picture],
      everyElement(isA<CanvasLayerStackView>()),
      reason: 'parked: 「스크럽하던 뭐던 존재하는게 보여야함」 (F-206)',
    );
    expect(
      [for (final unit in unitsOf(tester)) unit.stack.wholeFrames],
      [true, true],
      reason: 'and a drag that parks frame after frame shows each cut\'s last '
          'whole frame until the next is made, never its bare paper',
    );

    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    await pumpView(
      tester,
      frame: f.frame,
      layout: f.layout,
      run: (landings: landings, frameIsThere: (_) => true),
    );
    final played = [for (final unit in unitsOf(tester)) unit.played];
    expect(
      [for (final view in played) view.run.landings],
      [same(landings), same(landings)],
      reason: 'a run: every cut it shows waits on the one maker',
    );
    expect(
      played.last.run.pictures,
      same(played.first.run.pictures),
      reason: 'and shows the one maker\'s pictures',
    );
    expect(
      [for (final view in played) view.picture.paintPaper],
      [true, false],
      reason: 'the stage\'s picture is on its paper, the track over it on '
          'none — two pictures of one frame',
    );
  });

  /// F-365-Q2 (유저 2026-10-15: 「컷을 넘을 때도 직전 그림을 남기고」): a cut
  /// coming in is a view of its own, with no last whole frame to leave
  /// standing — it showed its bare paper wherever the clock went on without
  /// its picture (skipping frames).
  testWidgets('🚨a run crossing into a cut whose picture is not there yet '
      'shows the last whole frame, and the new one once it is whole', (
    tester,
  ) async {
    final f = fixture();
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    var made = false;
    f.frame.value = 1;
    await pumpView(
      tester,
      frame: f.frame,
      layout: f.layout,
      run: (landings: landings, frameIsThere: (frame) => frame != 2 || made),
    );
    List<String?> told() => [
      for (final unit in unitsOf(tester)) toldFrame(unit.picture),
    ];
    expect(told(), ['cut-a@1']);

    // cut-c comes in at its frame 0.
    f.frame.value = 2;
    await tester.pump();
    expect(
      told(),
      ['cut-a@1'],
      reason: 'the last whole frame stands — never cut-c\'s bare paper',
    );

    made = true;
    landings.value += 1;
    await tester.pump();
    expect(told(), ['cut-a@2', 'cut-c@0'], reason: 'whole, it goes up');

    f.frame.value = 3;
    await tester.pump();
    expect(
      told(),
      ['cut-a@3', 'cut-c@1'],
      reason: 'a frame already whole goes up as it is asked for',
    );
  });

  testWidgets('a run that takes over a parked stack leaves its frame '
      'standing until the run\'s is whole — and parked again, the frame '
      'asked for goes up at once', (tester) async {
    final f = fixture();
    List<String?> told() => [
      for (final unit in unitsOf(tester)) toldFrame(unit.picture),
    ];
    f.frame.value = 1;
    await pumpView(tester, frame: f.frame, layout: f.layout);
    expect(told(), ['cut-a@1']);

    final clock = ValueNotifier<int?>(2);
    addTearDown(clock.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    var made = false;
    await pumpView(
      tester,
      frame: clock,
      layout: f.layout,
      run: (landings: landings, frameIsThere: (_) => made),
    );
    expect(told(), ['cut-a@1'], reason: 'the run\'s frame is not whole yet');

    made = true;
    landings.value += 1;
    await tester.pump();
    expect(told(), ['cut-a@2', 'cut-c@0']);

    f.frame.value = 3;
    await pumpView(tester, frame: f.frame, layout: f.layout);
    expect(told(), ['cut-a@3', 'cut-c@1']);
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
    final frame = ValueNotifier<int?>(3);
    addTearDown(frame.dispose);
    await pumpView(
      tester,
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

    final units = unitsOf(tester);
    expect(units, hasLength(3), reason: 'the stage, and the O.L\'s two');
    expect(units[0].fade, 1);
    expect(units[0].thinning, 1);
    for (final upper in units.skip(1)) {
      expect(
        upper.fade,
        1,
        reason: 'an upper wash would cover the whole frame below',
      );
    }
    // Frame 3 = offset 1 of 4: the leaving cut opaque, the arriving one at
    // the ramp's 1/3 — the bottom track's own two weights, on the picture.
    expect(units[1].thinning, 1);
    expect(
      units[2].thinning,
      closeTo(1 / 3, 1e-9),
      reason: 'its own picture thins',
    );
    expect(
      units[2].over.imageOpacity,
      closeTo(1 / 3, 1e-9),
      reason: 'and its names and veils with it',
    );
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

    List<TransitionSpan> spans(TrackId _) =>
        const [(start: 2, length: 4, mark: CameraInstructionMarkType.ol)];

    testWidgets('puts BOTH cuts on screen, leaving one first, and both paint '
        'the stage — a 場面転換 cross-fades the paper too, so keying it to the '
        'bottom CONTRIBUTION would superimpose line art over the old paper', (
      tester,
    ) async {
      final frame = ValueNotifier<int?>(3);
      await pumpView(
        tester,
        frame: frame,
        layout: buildStoryboardTimelineLayout(olProject()),
        spansOf: spans,
      );

      final units = unitsOf(tester);
      expect(units, hasLength(2));
      expect(units[0].stack.paintPaper, isTrue);
      expect(units[1].stack.paintPaper, isTrue, reason: 'the arriving cut too');
      expect(
        [toldFrame(units[0].stack), toldFrame(units[1].stack)],
        ['cut-a@3', 'cut-b@1'],
        reason: 'the leaving cut first, each at its own frame — the '
            'arriving cut\'s own frames begin at its head のりしろ, two '
            'before its place on the track (cutMediaRange)',
      );
      expect(
        [units[0].under.paintLetterbox, units[1].under.paintLetterbox],
        [false, false],
        reason: 'neither lays a letterbox over the other — the floor holds '
            'it, under both',
      );
    });

    /// A stack holds its last whole frame until the next one is: a cut's
    /// stack that went to the other cut would show the other's picture
    /// until its own is made.
    testWidgets('🚨each cut keeps its own stack as the other comes and goes '
        '— the cut left alone does not take over the one that left', (
      tester,
    ) async {
      final frame = ValueNotifier<int?>(1);
      await pumpView(
        tester,
        frame: frame,
        layout: buildStoryboardTimelineLayout(olProject()),
        spansOf: spans,
      );
      State stackOf(String cut) => tester.state(
        find.descendant(
          of: find.byKey(ValueKey<Object>(('track-stack-unit', CutId(cut)))),
          matching: find.byType(CanvasLayerStackView),
        ),
      );
      final a = stackOf('cut-a');

      frame.value = 3;
      await tester.pump();
      expect(unitsOf(tester), hasLength(2), reason: '⛔premise: the O.L');
      expect(stackOf('cut-a'), same(a), reason: 'the leaving cut keeps its own');
      final b = stackOf('cut-b');
      expect(b, isNot(same(a)));

      frame.value = 6;
      await tester.pump();
      expect(unitsOf(tester), hasLength(1), reason: '⛔premise: past the O.L');
      expect(
        stackOf('cut-b'),
        same(b),
        reason: 'the arriving cut, alone now in the first slot, keeps its own '
            '— not the stack the leaving cut held its pictures in',
      );
    });

    /// The census adds the buffers up by name: two cuts telling under one
    /// would count whichever told last, and the one that went first would
    /// take the other's bytes off with it.
    testWidgets('each cut tells its own buffer\'s bytes under its own name', (
      tester,
    ) async {
      final told = <Object, int>{};
      await pumpView(
        tester,
        frame: ValueNotifier<int?>(3),
        layout: buildStoryboardTimelineLayout(olProject()),
        spansOf: spans,
        onBufferBytes: (cut, bytes) => told[cut] = bytes,
      );
      final stacks = tester
          .widgetList<CanvasLayerStackView>(find.byType(CanvasLayerStackView))
          .toList();
      expect(stacks, hasLength(2), reason: '⛔premise: the O.L');
      for (final (i, stack) in stacks.indexed) {
        stack.onBufferBytes!(100 + i);
      }
      expect(told, {const CutId('cut-a'): 100, const CutId('cut-b'): 101});
    });

    testWidgets('lays the leaving cut down OPAQUE and the arriving one at the '
        'ramp — painting both at their own share leaves t(1-t) of the floor '
        'showing, which is a dip to black mid-dissolve', (tester) async {
      final frame = ValueNotifier<int?>(3);
      await pumpView(
        tester,
        frame: frame,
        layout: buildStoryboardTimelineLayout(olProject()),
        spansOf: spans,
      );

      // Frame 3 = offset 1 of 4 → the canonical ramp bottoms out ON the last
      // frame, so t = 1/3 and the leaving cut owns 2/3.
      final units = unitsOf(tester);
      expect(units[0].fade, 1, reason: 'no floor may show through');
      expect(units[1].fade, closeTo(1 / 3, 1e-9));
      expect(
        [units[0].thinning, units[1].thinning],
        [1, 1],
        reason: 'the stage thins as one unit — paper, picture, names — never '
            'its picture alone',
      );
      // The mix the two weights actually produce IS the ramp: source-over of
      // 1 then 1/3 gives 2/3 of the leaving picture and 1/3 of the arriving.
      expect((1 - 1 / 3) * 1, closeTo(2 / 3, 1e-9));
    });

    /// 10-10: each stage contribution laid its own letterbox over the whole
    /// screen, under its fade, so the arriving cut covered the leaving one
    /// with it — two white papers met at (99,102,104).
    testWidgets('🚨seen through the camera, it dissolves one paper into the '
        'other — no letterbox shows through', (tester) async {
      final at = await seenAt(
        tester,
        3,
        layout: buildStoryboardTimelineLayout(olProject()),
        spansOf: spans,
      );
      expect(at(40, 20), 0xFFFFFFFF, reason: 'paper into paper is paper');
      expect(at(90, 50), PlaybackFramePainter.letterboxColor.toARGB32());
    });

    testWidgets('outside the span nothing changes — one contribution, its own '
        'share, exactly as a project with no transition', (tester) async {
      final frame = ValueNotifier<int?>(8);
      await pumpView(
        tester,
        frame: frame,
        layout: buildStoryboardTimelineLayout(olProject()),
        spansOf: spans,
      );

      final units = unitsOf(tester);
      expect(units, hasLength(1));
      expect(units.single.fade, 1);
      expect(units.single.stack.paintPaper, isTrue);
    });
  });

  testWidgets('CAMERA VIEW OFF leaves the stack in canvas space — no crop, no '
      'letterbox, no apron. A storyboard ruler drag parks per move, so this '
      'stack is what shows while scrubbing, and it used to reframe into the '
      'camera whatever the toggle said', (tester) async {
    final f = fixture();
    f.frame.value = 3;

    await pumpView(
      tester,
      frame: f.frame,
      layout: f.layout,
      cameraViewEnabled: false,
    );
    var units = unitsOf(tester);
    expect(units[0].under.cameraFrameSize, isNull);
    expect(units[0].under.cameraPose, isNull);
    expect(units[0].under.paintLetterbox, isFalse);
    expect(units[0].under.pasteboardColor, isNull);
    expect(
      units[0].stack.paintPaper,
      isTrue,
      reason: 'the paper is not the crop',
    );
    expect(
      units[0].stack.viewport,
      CanvasViewport(),
      reason: 'the cut in its own canvas space, the panel\'s view',
    );

    // Toggle on: the crop is back, so framing stays available while scrubbing
    // rather than being reserved for playback.
    await pumpView(tester, frame: f.frame, layout: f.layout);
    units = unitsOf(tester);
    expect(units[0].under.cameraFrameSize, cameraFrameSize);
    expect(units[0].under.cameraPose, isNotNull);
    expect(units[0].under.pasteboardColor, isNotNull);
  });

  testWidgets('🚨F-114: an ABSENT backdrop is the checkerboard floor, and an '
      'absent pasteboard rides the painter as a checkerboard on screen', (
    tester,
  ) async {
    // 유저 2026-09-15: 「없음버튼 누르면 없는상태. 즉 해당 용지부분이
    // 체크무늬되도록. 페이스트보드도 백그라운드도 동일하게」 — the law the
    // editing canvas keeps, so a scrub into playback does not trade the
    // checkerboard for a colour.
    // Seen through no camera the floor is the box: a frame no track covers
    // shows it alone.
    final layout = buildStoryboardTimelineLayout(project());
    var at = await seenAt(
      tester,
      20,
      layout: layout,
      cameraViewEnabled: false,
    );
    expect(
      at(90, 50),
      backdrop,
      reason: 'control: a backdrop that is there — past where a camera\'s '
          'frame would end, the box is the floor',
    );

    at = await seenAt(
      tester,
      20,
      layout: layout,
      cameraViewEnabled: false,
      backdropNone: true,
    );
    expect(
      [at(4, 4), at(12, 4)],
      everyElement(isNot(backdrop)),
      reason: 'the checkerboard floor',
    );
    expect(
      (at(4, 4), at(12, 4)),
      (at(12, 12), at(4, 12)),
      reason: 'its cells the box\'s, eight pixels from its corner — the '
          'editing canvas\'s',
    );
    expect(at(4, 4), isNot(at(12, 4)), reason: 'two cells, not one colour');

    // Seen through the camera, the floor is in the frame (pinned by pixels
    // in the camera floor group).
    final f = fixture();
    f.frame.value = 3;
    await pumpView(
      tester,
      frame: f.frame,
      layout: f.layout,
      backdropNone: true,
      pasteboardNone: true,
    );
    final bottom = unitsOf(tester).first.under;
    expect(bottom.pasteboardNone, isTrue);
    expect(
      bottom.checkersAbsentPlanes,
      isTrue,
      reason: 'on screen the absent apron checkers — the export never sets it',
    );
  });
}
