import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_run_end_handles.dart';
import 'package:anicel/src/ui/timeline/timeline_silhouette_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WHAT EACH DASHED LINE IN THE APP ASKS OF THE ONE WALK (`dashesAlong`,
/// measured on its own in `dashed_path_test`): how long its dashes and its
/// gaps are, and whether they march.
///
/// Three painters walked their own dashes until 2026-10-06 and nothing
/// measured where those dashes fell — the look was pinned by eye. They read
/// the one walk now, and what each hands it is said here, so the day one of
/// them hands it something else is a red test and not a drawing nobody
/// compares.
void main() {
  /// How long each contour of every path a painting strokes is, call by
  /// call — a dashed line is a contour a dash.
  List<List<double>> strokedPaths(void Function(Canvas canvas) painting) {
    final paths = <List<double>>[];
    expect(
      painting,
      paints..everything((method, arguments) {
        if (method == #drawPath) {
          paths.add([
            for (final contour in (arguments.first as Path).computeMetrics())
              (contour.length * 1000).roundToDouble() / 1000,
          ]);
        }
        return true;
      }),
    );
    return paths;
  }

  group('the selection\'s ants', () {
    // A marquee 30 by 20: an outline 100 long.
    SelectionAntsPainter ants(double turn) => SelectionAntsPainter(
      repaint: AlwaysStoppedAnimation<double>(turn),
      viewport: CanvasViewport(zoom: 1),
      committedRegion: null,
      screenOffset: Offset.zero,
      marqueeShapes: [
        CanvasSelectionShape([
          CanvasPoint(x: 10, y: 10),
          CanvasPoint(x: 40, y: 10),
          CanvasPoint(x: 40, y: 30),
          CanvasPoint(x: 10, y: 30),
        ]),
      ],
      openTrail: const [],
    );

    test('🚨are five of line and four of none, over the whole outline in '
        'white', () {
      final [white, dashes] = strokedPaths(
        (canvas) => ants(0).paint(canvas, const Size(100, 100)),
      );

      expect(white, [100]);
      // From 0, 9, 18 … 99: twelve, the last cut off by the outline's end.
      expect(dashes, [...List.filled(11, 5.0), 1.0]);
    });

    test('🚨and they MARCH: half a turn on, the pattern has slid half its '
        'own length back', () {
      final [_, dashes] = strokedPaths(
        (canvas) => ants(0.5).paint(canvas, const Size(100, 100)),
      );

      // From 4.5, 13.5 … 94.5: eleven whole dashes.
      expect(dashes, List.filled(11, 5.0));
    });
  });

  group('the timeline\'s repeat span', () {
    test('is dashed five on, four off, each dash a stroke of its own', () {
      final paths = strokedPaths(
        (canvas) => paintTimelineRunPatternSpan(
          canvas,
          const Rect.fromLTWH(0, 0, 100, 20),
          corner: Radius.zero,
        ),
      );

      // Drawn a pixel in: 98 by 18, an outline 232 long. From 0, 9 … 225.
      expect(paths, List.filled(26, [5.0]));
    });
  });

  group('the drop silhouette', () {
    test('is dashed four on, three off, each dash a stroke of its own', () {
      const size = Size(60, 20);
      final outline =
          (Path()..addRRect(
                RRect.fromRectAndRadius(
                  Offset.zero & size,
                  timelineBlockCornerRadiusAt(cellExtent: 60, crossExtent: 20),
                ).deflate(0.5),
              ))
              .computeMetrics()
              .single
              .length;

      final paths = strokedPaths(
        (canvas) => const TimelineSilhouettePainter(
          frames: 1,
          axis: Axis.horizontal,
        ).paint(canvas, size),
      );

      // A dash every seven along the outline, four long but for the last —
      // to a quarter: the box is rounded, and a dash cut from a corner is a
      // curve of its own, measured again (3.979 and 4.136 were both read on
      // this box).
      expect(paths, hasLength((outline / 7).ceil()));
      for (final dash in paths.take(paths.length - 1)) {
        expect(dash.single, closeTo(4, 0.25));
      }
      expect(paths.last.single, lessThan(4.25));
    });
  });
}
