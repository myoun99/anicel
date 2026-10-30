import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_grid_stack.dart';
import 'package:anicel/src/ui/widgets/named.dart';

/// A SCROLL ACROSS THE FRAMES BUILDS NO FRAME BODY, on either grid
/// (xsheet-bucket-crossing-rebuilds-the-frame-body, 2026-10-30): the rows
/// and the columns are built for the full frames and window themselves off
/// the bucket, and so does the cursor over them.
///
/// ↩️The x-sheet's stack sat in a builder of the bucket, which handed its
/// lane columns and its cursor the window, so every crossing built the
/// whole frame body again — every column's box and the stack around them
/// (measured on 10-11: 642 layers painted a crossing, the timeline 370).
void main() {
  final aBody = RegExp('^(timeline-row-|xsheet-column-|xsheet-row-cells-)');

  for (final (grid, toggle, axis, standing) in [
    ('timeline', null, Axis.horizontal, 'timeline-selected-cell'),
    (
      'x-sheet',
      'timeline-orientation-toggle-button',
      Axis.vertical,
      'xsheet-selected-cell',
    ),
  ]) {
    testWidgets('a scroll of the $grid across its buckets builds none of its '
        'frame body', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: _longCut())),
      );
      await tester.pumpAndSettle();
      if (toggle != null) {
        await tester.tap(find.byKey(ValueKey<String>(toggle)));
        await tester.pumpAndSettle();
      }
      final frames = [
        for (final state in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        ))
          if (state.position.axis == axis &&
              state.position.maxScrollExtent > 2000)
            state.position,
      ];
      expect(frames, hasLength(1), reason: '⛔전제: the frames\' scroll');

      final built = <String>[];
      var stacks = 0;
      var elements = 0;
      // Far past a span (96px at the least), so the offset crosses buckets.
      frames.single.jumpTo(frames.single.pixels + 400);
      debugOnRebuildDirtyWidget = (element, _) {
        elements += 1;
        switch (element.widget) {
          case Named(:final name?):
            built.add(name);
          case TimelineFrameGridStack():
            stacks += 1;
        }
      };
      try {
        await tester.pump();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }

      expect(
        built.where(aBody.hasMatch),
        isEmpty,
        reason: 'the crossing built the frame body again: $built',
      );
      expect(stacks, 0, reason: 'nor the stack it stands in');
      expect(
        elements,
        greaterThan(0),
        reason: 'CONTROL: the crossing built what follows the scroll',
      );
    });

    // The cursor is built for the full frames too, and tells what it shows
    // by the window: the cell you stand on is said while the window holds
    // it, and not once the frames have scrolled it away.
    testWidgets('the cell the $grid stands on is said while its window holds '
        'it, and not once a scroll takes the window past', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: _longCut())),
      );
      await tester.pumpAndSettle();
      if (toggle != null) {
        await tester.tap(find.byKey(ValueKey<String>(toggle)));
        await tester.pumpAndSettle();
      }
      final cell = find.byKey(ValueKey<String>(standing));
      expect(cell, findsOneWidget, reason: '⛔전제: frame 0, in view');

      final frames = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .map((state) => state.position)
          .where((p) => p.axis == axis && p.maxScrollExtent > 2000)
          .single;
      frames.jumpTo(frames.maxScrollExtent / 2);
      await tester.pump();

      expect(cell, findsNothing);
    });
  }
}

/// One cut long enough to scroll far, under six layers.
Project _longCut() => Project(
  id: const ProjectId('bucket-crossing'),
  name: 'Bucket crossing',
  createdAt: DateTime.utc(2026, 10, 30),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'c',
          duration: 1200,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            for (var i = 0; i < 6; i += 1)
              Layer(id: LayerId('l$i'), name: 'L$i', frames: const []),
          ],
        ),
      ],
    ),
  ],
);
