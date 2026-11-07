import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackTransitionLayer;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
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
          layers: [
            Layer(
              id: LayerId('t$t-conte'),
              name: 't$t conte',
              kind: LayerKind.storyboard,
              frames: panels.frames,
              timeline: panels.timeline,
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

  testWidgets('the conte\'s rows keep their images through a growth of the '
      'runway', (tester) async {
    await pumpStoryboardHost(
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
      surface: const Size(1400, 900),
      pixelsPerFrame: cell,
    );
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
    expect(
      find.byType(TimelineBlockEdgeGrip),
      findsAtLeastNWidgets(8),
      reason: '⛔premise: each track\'s sound and span wear their grips',
    );
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
}
