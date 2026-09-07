import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_scrub.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨THE SCRUB IS ONE OBJECT, AND THE AXIS IS ITS ONLY TURN.
///
/// The timeline's ruler runs the frame axis across the top and the X-sheet's
/// rail runs it down the side. They used to be two collaborators with the
/// same six members, one spelled with `.dx` and `size.width` and the other
/// with `.dy` and `size.height` — and the two drifted apart exactly once
/// already (R10 R6's press rule reached the rail and not the ruler).
///
/// So this asks the SAME question of both axes and demands the transposed
/// answer: the same distance along the strip picks the same frame, and the
/// same edge lands the same pan.
void main() {
  const cellExtent = 24.0;
  const stripExtent = 400.0;

  TimelineCellExposureState stateFor(layer, int frameIndex) =>
      TimelineCellExposureState.uncovered;

  /// A strip that scrolls along [axis], its viewport carrying [key].
  Widget strip(Axis axis, GlobalKey key, ScrollController controller) {
    final horizontal = axis == Axis.horizontal;
    return SizedBox(
      width: stripExtent,
      height: stripExtent,
      child: SingleChildScrollView(
        key: key,
        scrollDirection: axis,
        controller: controller,
        child: SizedBox(
          width: horizontal ? stripExtent * 10 : stripExtent,
          height: horizontal ? stripExtent : stripExtent * 10,
        ),
      ),
    );
  }

  /// The pointer position that is [along] the strip whose box is [key].
  Offset alongPoint(WidgetTester tester, GlobalKey key, Axis axis) =>
      tester.getTopLeft(find.byKey(key));

  group('the two axes answer alike', () {
    late Map<Axis, GlobalKey> keys;
    late Map<Axis, ScrollController> controllers;
    late Map<Axis, List<int>> picked;
    late Map<Axis, TimelineFrameScrub> scrubs;

    Future<void> pumpStrips(WidgetTester tester) async {
      keys = {Axis.horizontal: GlobalKey(), Axis.vertical: GlobalKey()};
      controllers = {
        Axis.horizontal: ScrollController(),
        Axis.vertical: ScrollController(),
      };
      picked = {Axis.horizontal: <int>[], Axis.vertical: <int>[]};
      addTearDown(() {
        for (final controller in controllers.values) {
          controller.dispose();
        }
      });

      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (final axis in Axis.values)
                  strip(axis, keys[axis]!, controllers[axis]!),
              ],
            ),
          ),
        ),
      );

      scrubs = {
        for (final axis in Axis.values)
          axis: TimelineFrameScrub(
            axis: axis,
            viewportKey: keys[axis]!,
            controller: controllers[axis]!,
            hooks: () => TimelineGridHooks(
              activeLayerId: const LayerId('layer-1'),
              frameCursor: ValueNotifier<int>(0),
              playbackFrameCount: 1000,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: picked[axis]!.add,
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
            ),
            frameCellExtent: () => cellExtent,
            renderedFrameCount: () => 1000,
            scrolledFrameOffset: () => 0,
          ),
      };
    }

    testWidgets('the same distance ALONG the strip picks the same frame', (
      tester,
    ) async {
      await pumpStrips(tester);

      for (final along in [40.0, 100.0, 216.0, 300.0]) {
        for (final axis in Axis.values) {
          final origin = alongPoint(tester, keys[axis]!, axis);
          scrubs[axis]!.pressAt(
            origin +
                (axis == Axis.horizontal ? Offset(along, 8) : Offset(8, along)),
          );
        }
      }

      expect(picked[Axis.horizontal], [1, 4, 9, 12]);
      expect(
        picked[Axis.vertical],
        picked[Axis.horizontal],
        reason: 'the transposed input must give the transposed answer',
      );
    });

    testWidgets('a PRESS in the edge band pans neither axis, and a DRAG '
        'there pans both by the same amount', (tester) async {
      await pumpStrips(tester);

      // R10 R6: landing near an end is not a push toward it.
      for (final axis in Axis.values) {
        final origin = alongPoint(tester, keys[axis]!, axis);
        scrubs[axis]!.pressAt(
          origin +
              (axis == Axis.horizontal
                  ? const Offset(stripExtent - 2, 8)
                  : const Offset(8, stripExtent - 2)),
        );
      }
      for (final axis in Axis.values) {
        expect(
          controllers[axis]!.offset,
          0,
          reason: '$axis pressed, not pushed',
        );
      }

      for (final axis in Axis.values) {
        final origin = alongPoint(tester, keys[axis]!, axis);
        scrubs[axis]!.dragTo(
          origin +
              (axis == Axis.horizontal
                  ? const Offset(stripExtent - 2, 8)
                  : const Offset(8, stripExtent - 2)),
        );
      }
      expect(controllers[Axis.horizontal]!.offset, greaterThan(0));
      expect(
        controllers[Axis.vertical]!.offset,
        controllers[Axis.horizontal]!.offset,
        reason: 'one edge band, one delta, both axes',
      );
    });

    testWidgets('a scrub reports a frame once per gesture until it moves on', (
      tester,
    ) async {
      await pumpStrips(tester);

      for (final axis in Axis.values) {
        final origin = alongPoint(tester, keys[axis]!, axis);
        Offset at(double along) =>
            origin +
            (axis == Axis.horizontal ? Offset(along, 8) : Offset(8, along));
        scrubs[axis]!
          ..pressAt(at(100))
          ..dragTo(at(104))
          ..dragTo(at(130))
          ..resetTracking()
          ..dragTo(at(130));
      }

      for (final axis in Axis.values) {
        expect(picked[axis], [
          4,
          5,
          5,
        ], reason: 'the dedupe is the law, on both axes ($axis)');
      }
    });
  });
}
