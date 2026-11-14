import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackTransitionLayer;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart'
    show trackCameraRowId;
import 'package:anicel/src/models/track_conte_row.dart' show trackConteRowId;
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart'
    show trackTransformLaneCarrierId;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart'
    show TimelineBlockEdgeGrip;
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart'
    show timelineFrameWindowSpanFor;
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../../helpers/storyboard_host.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q8 (유저 2026-11-07, 「한다 — 행
/// 그림 영역을 창 상자로」): the conte's rows are laid as the timeline's
/// are — each row's image is its window, not the axis — so the runway a
/// drag past the end grows under them takes none of their images.
void main() {
  const cell = 8.0;
  const frames = 200;

  /// [count] blocks of [length] frames from [from] on, each its own cel.
  ({List<Frame> frames, Map<int, TimelineExposure> timeline}) blocks(
    String prefix, {
    required int from,
    required int count,
    required int length,
  }) => (
    frames: [
      for (var b = 0; b < count; b += 1)
        Frame(
          id: FrameId('$prefix-$b'),
          duration: length,
          strokes: const [],
        ),
    ],
    timeline: {
      for (var b = 0; b < count; b += 1)
        from + b * length: TimelineExposure.drawing(
          FrameId('$prefix-$b'),
          length: length,
        ),
    },
  );

  // Each row draws what it holds where the view stands at the end: the
  // conte's panels, a sound on S1 with its grips, and a span on the
  // transition row with its own.
  Track track(int t) {
    final panels = blocks('t$t-p', from: 0, count: 4, length: frames ~/ 4);
    final sound = blocks('t$t-s', from: 150, count: 1, length: 40);
    return Track(
      id: TrackId('t$t'),
      name: 'T$t',
      // An fx chain on the track, its lanes open: the lane rows stand too.
      effects: [
        LayerEffect(
          id: const EffectId('fx'),
          kind: EffectKind.brightnessContrast,
          parameters: {'brightness': EffectParameter(value: 0.4)},
        ),
      ],
      lanesExpanded: true,
      transitionLayer: createTrackTransitionLayer(TrackId('t$t')).copyWith(
        instructions: const {
          180: InstructionEvent(instructionId: 'ol', length: 8),
        },
      ),
      cuts: [
        Cut(
          id: CutId('t$t-cut'),
          name: 't$t cut',
          duration: frames,
          canvasSize: const CanvasSize(width: 1280, height: 720),
          camera: CutCamera.empty(),
          // The camera row and the conte row twirled open: every family
          // of lane rows the conte keeps stands.
          layers: [
            Layer(
              id: LayerId('t$t-conte'),
              name: 't$t conte',
              kind: LayerKind.storyboard,
              frames: panels.frames,
              timeline: panels.timeline,
              lanesExpanded: true,
            ),
            Layer(
              id: LayerId('t$t-camera'),
              name: 'Camera',
              kind: LayerKind.camera,
              frames: const [],
              lanesExpanded: true,
            ),
          ],
        ),
      ],
      seLayers: [
        for (final s in ['S1', 'S2'])
          Layer(
            id: LayerId('t$t-$s'),
            name: 't$t $s',
            kind: LayerKind.se,
            frames: s == 'S1' ? sound.frames : const [],
            timeline: s == 'S1' ? sound.timeline : const {},
            lanesExpanded: true,
          ),
      ],
    );
  }

  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    StaticRaster.debugCapturePaysOverride = false;
  });
  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
  });

  Future<void> frame(WidgetTester tester) async {
    tester.binding.scheduleFrame();
    await tester.pump();
  }

  /// Every row's still region the conte built, the rail's and the strips',
  /// named by the first key under it.
  List<({String name, RenderStillRaster region})> rowsOf(WidgetTester tester) {
    String nameUnder(Element still) {
      String? name;
      void visit(Element element) {
        if (name != null) {
          return;
        }
        if (element.widget.key case ValueKey<String>(:final value)) {
          name = value;
          return;
        }
        element.visitChildElements(visit);
      }

      still.visitChildElements(visit);
      return name ?? '(unkeyed)';
    }

    return [
      for (final element in find.byType(StillRaster).evaluate())
        if (element.renderObject case final RenderStillRaster region
            when region.debugLabel == 'row')
          (name: nameUnder(element), region: region),
    ];
  }

  Future<List<({String name, RenderStillRaster region})>>
  untilEveryRowIsAnImage(WidgetTester tester) async {
    for (var i = 0; i < 600; i += 1) {
      final rows = rowsOf(tester);
      if (rows.isNotEmpty &&
          rows.every((row) => row.region.debugDrawnFromImage)) {
        return rows;
      }
      await frame(tester);
    }
    fail('rows still drawn live after 600 frames');
  }

  /// The rows each family of lane labels is carried by on the conte: the
  /// V row's fx chain, an S row's, the camera row's and the conte row's.
  List<String> laneCarriersOf(int t) => [
    trackTransformLaneCarrierId(TrackId('t$t')).value,
    't$t-S1',
    't$t-S2',
    trackCameraRowId(TrackId('t$t')).value,
    trackConteRowId(TrackId('t$t')).value,
  ];

  /// Each family's lane labels stand among [rows] as images of their own.
  void expectEveryLaneFamily(
    List<({String name, RenderStillRaster region})> rows,
  ) {
    for (var t = 0; t < 2; t += 1) {
      for (final carrier in laneCarriersOf(t)) {
        expect(
          rows.where(
            (row) => row.name.startsWith(
              'storyboard-lane-stand-cell-$carrier-',
            ),
          ),
          isNotEmpty,
          reason: '⛔premise: $carrier\'s lane labels stand as images',
        );
      }
    }
  }

  /// Both tracks on the conte, [cell] a frame.
  Future<EditorSessionManager> pumpConte(WidgetTester tester) =>
      pumpStoryboardHost(
    tester,
    Project(
      id: const ProjectId('conte-runway'),
      name: 'Conte runway',
      createdAt: DateTime.utc(2026, 11, 7),
      tracks: [track(0), track(1)],
      // Past the cuts, so the press on the ruler below stands on no cut
      // wherever the drag takes it.
      trailingFrames: 60,
    ),
    // Tall enough that both tracks stand whole, every lane open.
    surface: const Size(1400, 2600),
    pixelsPerFrame: cell,
  );

  testWidgets('the conte\'s rows keep their images through a growth of the '
      'runway', (tester) async {
    await pumpConte(tester);
    final position = tester
        .widget<SingleChildScrollView>(
          find.byKey(
            const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
          ),
        )
        .controller!
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    final spanPx = timelineFrameWindowSpanFor(cell) * cell;
    int bucket() => (position.pixels / spanPx).floor();
    final area = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-ruler')),
    );
    Offset at(double x) => Offset(area.left + x, area.center.dy);
    // A scrub first takes the playhead off the cut it stood on, which the
    // V row's standing wash draws: the rows are counted after it.
    final scrub = await tester.startGesture(
      at(area.width - 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await scrub.moveTo(at(area.width - 30));
    await tester.pump();
    await scrub.up();
    await tester.pumpAndSettle();
    final hand = await tester.startGesture(
      at(area.width - 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final before = await untilEveryRowIsAnImage(tester);
    // A row that lost its still region would drop off the list above, not
    // fail it: each kind is looked for under its own key.
    for (var t = 0; t < 2; t += 1) {
      for (final row in [
        'storyboard-camera-row-t$t',
        'storyboard-transition-row-t$t',
        'storyboard-se-row-$t-1',
        'storyboard-se-row-$t-2',
        'storyboard-track-timeline-area-t$t',
        'storyboard-conte-row-t$t',
        'storyboard-track-lane-row-$t-',
      ]) {
        expect(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) => switch (widget.key) {
                ValueKey<String>(:final value) =>
                  row.endsWith('-') ? value.startsWith(row) : value == row,
                _ => false,
              },
            ),
            matching: find.byWidgetPredicate(
              (widget) => widget is StillRaster && widget.debugLabel == 'row',
            ),
          ),
          findsAtLeastNWidgets(1),
          reason: '⛔premise: $row stands as an image of its own',
        );
      }
    }
    expect(
      find.byType(TimelineBlockEdgeGrip),
      findsAtLeastNWidgets(8),
      reason: '⛔premise: each track\'s sound and span wear their grips',
    );
    expectEveryLaneFamily(before);
    final taken = [for (final row in before) row.region.debugCaptureCount];
    final built = position.maxScrollExtent;
    var stood = bucket();
    var past = area.width + 4;
    for (var move = 0; position.maxScrollExtent <= built; move += 1) {
      expect(move, lessThan(400), reason: '⛔premise: the runway grew');
      stood = bucket();
      past += 0.5;
      await hand.moveTo(at(past));
      await tester.pump();
    }
    expect(bucket(), stood, reason: '⛔premise: the growth crossed no span');

    final live = [
      for (final (index, (:name, :region)) in before.indexed)
        if (region.attached &&
            (!region.debugDrawnFromImage ||
                region.debugCaptureCount != taken[index]))
          '$name (${region.standDown.name}, took '
              '${region.debugCaptureCount - taken[index]})',
    ];
    expect(
      before.where((row) => row.region.attached),
      hasLength(greaterThan(4)),
      reason: '⛔premise: the rows stayed',
    );
    expect(live, isEmpty, reason: 'the runway grew under them');
    await hand.up();
    await tester.pumpAndSettle();
  });

  // 🔬Card the-conte-rails-lane-rows-are-built-again-with-the-rail (11-08):
  // a pick of an S row moves the current row, which only the rows it
  // leaves and lands on show — and the lane rows of both tracks' fx drew
  // themselves again and let their images go, built anew with the rail.
  testWidgets('the conte\'s rows keep their images through a pick of an S '
      'row, but the rows it moves between', (tester) async {
    await pumpConte(tester);
    final before = await untilEveryRowIsAnImage(tester);
    final taken = [for (final row in before) row.region.debugCaptureCount];
    expectEveryLaneFamily(before);

    await tester.tap(
      find.byKey(const ValueKey<String>('storyboard-se-label-t0-1')),
      warnIfMissed: false,
    );
    await tester.pump();
    await frame(tester);

    final drawnAgain = [
      for (final (index, (:name, :region)) in before.indexed)
        if (!region.debugDrawnFromImage ||
            region.debugCaptureCount != taken[index])
          name,
    ];
    expect(
      drawnAgain,
      unorderedEquals([
        'storyboard-se-label-t0-1',
        'storyboard-track-select-t0',
        'storyboard-cut-blocks-t0',
      ]),
      reason: 'the current row moved from the V row of t0 to its S1, and '
          'no other row shows it',
    );
    await tester.pumpAndSettle();
  });

  // 🔬Card a-track-copy-wraps-its-unchanged-lists-anew (11-11): a stroke in
  // one cut copies its track, and the copy handed every collection it did
  // not change back anew — the S rows', the fx chain's, the twirls' — so
  // the conte read their lane lists again and drew their labels again
  // (seven of them, measured). A copy keeps what it did not change.
  testWidgets('🚨one stroke in a cut leaves the lane labels of its track\'s '
      'S rows and fx chain standing as they were', (tester) async {
    final session = await pumpConte(tester);
    final before = await untilEveryRowIsAnImage(tester);
    final taken = [for (final row in before) row.region.debugCaptureCount];
    expectEveryLaneFamily(before);

    session.repository.addStroke(
      frameId: const FrameId('t0-p-1'),
      stroke: Stroke(
        id: const StrokeId('one'),
        points: const [StrokePoint(x: 10, y: 10), StrokePoint(x: 40, y: 30)],
        brushSettings: BrushSettings(),
      ),
    );
    session.notifyChanged();
    await tester.pump();
    await frame(tester);

    final drawnAgain = [
      for (final (index, (:name, :region)) in before.indexed)
        if (region.attached &&
            (!region.debugDrawnFromImage ||
                region.debugCaptureCount != taken[index]))
          name,
    ];
    expect(
      drawnAgain,
      contains('storyboard-conte-cells-t0'),
      reason: '⛔premise: the stroke landed, and the panels show it',
    );
    final carriers = laneCarriersOf(0).take(3);
    expect(
      [
        for (final name in drawnAgain)
          for (final carrier in carriers)
            if (name.startsWith('storyboard-lane-stand-cell-$carrier-')) name,
      ],
      isEmpty,
      reason: 'nothing those labels show changed — the track was copied '
          'with its S rows, fx chain and twirls as they were',
    );
    await tester.pumpAndSettle();
  });
}
