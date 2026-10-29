import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_row_reach.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart'
    show StoryboardCameraRowPainter, StoryboardCutStartsPainter;
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';

/// THE PROJECTION ROWS' PAINTERS READ THE VIEW OFF THE GEOMETRY
/// (storyboard-strips-build-on-every-view-pixel, 2026-10-30): the camera
/// row's ground and the cut starts draw the panel's window, and how far the
/// view reaches is the live geometry's — so a wider view repaints them, and
/// the rows holding them are not built again for it.
///
/// ↩️Each took the breadth as a field its row handed down, and every pixel
/// of a rail splitter's drag built the row again to hand it.
void main() {
  // Ten-pixel cells: a bucket is ten of them, and a view of 100px reaches
  // three spans — frames [0, 30).
  const cell = 10.0;

  late TimelineFrameGeometryHandle geometry;
  late ValueNotifier<int> bucket;
  setUp(() {
    geometry = TimelineFrameGeometryHandle(viewOf(100));
    bucket = ValueNotifier<int>(0);
  });
  tearDown(() {
    geometry.dispose();
    bucket.dispose();
  });

  test('a cut start past the view\'s window draws no line, and a view that '
      'reaches it does', () {
    final painter = StoryboardCutStartsPainter(
      starts: const [0, 25, 500],
      geometry: geometry,
      colorScheme: const ColorScheme.light(),
      windowBucket: bucket,
    );
    expect(painter.cutStarts(), hasLength(2), reason: '0 and 25');

    geometry.value = viewOf(6000);

    expect(painter.cutStarts(), hasLength(3), reason: 'and 500 now');
  });

  test('the のりしろ washes as far as the view\'s window, and a view that '
      'reaches on washes on', () {
    final cut = Cut(
      id: const CutId('c'),
      name: 'c',
      duration: 10,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: const [],
    );
    // A cut [0, 10) whose のりしろ runs on to 1000.
    final painter = StoryboardCameraRowPainter(
      reaches: [
        CameraRowReach(
          entry: StoryboardTimelineLayoutEntry(
            trackId: const TrackId('t'),
            cutId: cut.id,
            trackIndex: 0,
            cutIndex: 0,
            startFrame: 0,
            endFrame: 10,
            duration: 10,
            cut: cut,
          ),
          mediaStart: 0,
          mediaEnd: 1000,
          arrivingUntil: 0,
          leavingFrom: 1000,
        ),
      ],
      geometry: geometry,
      crossAxisExtent: 20,
      colorScheme: const ColorScheme.light(),
      windowBucket: bucket,
    );
    expect(
      [for (final wash in painter.noriShiroWashes()) wash.right],
      [30 * cell],
      reason: 'washed to the window\'s end',
    );

    geometry.value = viewOf(6000);

    expect(
      [for (final wash in painter.noriShiroWashes()) wash.right],
      [greaterThan(30 * cell)],
      reason: 'a wider view washes on',
    );
  });
}

/// The panel's axis, its view [view] pixels across.
TimelineFrameGeometry viewOf(double view) => TimelineFrameGeometry(
  frameCellExtent: 10,
  frameStartIndex: 0,
  frameEndIndexExclusive: 2000,
  viewExtentPx: view,
);
