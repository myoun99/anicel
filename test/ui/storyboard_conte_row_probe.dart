import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart'
    show StoryboardConteCreatePainter;
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

/// The storyboard's CONTE row is PAINTED — by the timeline's own row
/// painter, on the cuts' conte layers laid on the track's axis — so tests
/// read it off that painter, the way the timeline's row probes do, and its
/// create buttons off the painter that draws them.
Finder conteRowFinder(String trackId) =>
    find.byKey(ValueKey<String>('storyboard-conte-row-$trackId'));

Finder conteCellsFinder(String trackId) =>
    find.byKey(ValueKey<String>('storyboard-conte-cells-$trackId'));

Finder conteCreateFinder(String trackId) =>
    find.byKey(ValueKey<String>('storyboard-conte-create-$trackId'));

/// The row's box on screen.
Rect conteRowRect(WidgetTester tester, String trackId) =>
    tester.getRect(conteRowFinder(trackId));

/// The painter that draws the row's blocks.
TimelineRowCellsPainter conteRowPainter(WidgetTester tester, String trackId) =>
    tester.widget<CustomPaint>(conteCellsFinder(trackId)).painter!
        as TimelineRowCellsPainter;

/// The row as it is drawn: one layer on the track's axis.
Layer conteRowShown(WidgetTester tester, String trackId) =>
    conteRowPainter(tester, trackId).layer;

/// The row's blocks as `start: length`, on the track's axis, in order.
Map<int, int> conteRowBlocks(WidgetTester tester, String trackId) => {
  for (final entry in conteRowShown(tester, trackId).timeline.entries)
    entry.key: entry.value.length!,
};

/// The lengths the row's blocks print at their ends, as `(start, text)` —
/// the timeline row's own run labels.
List<(int, String)> conteRowRunLabels(WidgetTester tester, String trackId) => [
  for (final label
      in (tester
                  .widget<CustomPaint>(
                    find.byKey(
                      ValueKey<String>(
                        'storyboard-run-labels-'
                        '${trackConteRowId(TrackId(trackId))}',
                      ),
                    ),
                  )
                  .foregroundPainter!
              as TimelineRowRunLabelsPainter)
          .runLabels())
    (label.startIndex, label.text),
];

/// The name the row's rail label prints.
String? conteRowName(WidgetTester tester, String trackId) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey<String>('storyboard-conte-label-$trackId')),
        matching: find.byType(Text),
      ),
    )
    .data;

/// The plates of the row's create buttons — one over every cut that has no
/// conte layer — in the row's own coordinates.
List<RRect> conteCreatePlates(WidgetTester tester, String trackId) =>
    (tester.widget<CustomPaint>(conteCreateFinder(trackId)).painter!
            as StoryboardConteCreatePainter)
        .plates();

/// The stretches of the row its cells are held to, as the path the row is
/// clipped by — in the row's own coordinates.
Path conteCellsClip(WidgetTester tester, String trackId) {
  final clip = tester.widget<ClipPath>(
    find.ancestor(
      of: conteCellsFinder(trackId),
      matching: find.byType(ClipPath),
    ).first,
  );
  return clip.clipper!.getClip(tester.getSize(conteRowFinder(trackId)));
}
