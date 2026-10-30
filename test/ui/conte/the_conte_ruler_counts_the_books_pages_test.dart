import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler.dart';

import '../../helpers/storyboard_host.dart';

/// 🗣️I-81-Q3 (유저 2026-10-30): 「콘티용지패널의 페이지 기준」 — the
/// storyboard's ruler, under the page view, counts the pages the conte book
/// prints: each begins on its first cell's frame, wherever the paper's five
/// rows ran out.
void main() {
  Cut cut(String id, List<int> panels) {
    final frames = <Frame>[];
    final timeline = <int, TimelineExposure>{};
    var start = 0;
    for (final (index, length) in panels.indexed) {
      final frame = FrameId('$id-$index');
      frames.add(Frame(id: frame, duration: 1, strokes: const []));
      timeline[start] = TimelineExposure.drawing(frame, length: length);
      start += length;
    }
    return Cut(
      id: CutId(id),
      name: id,
      duration: start,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: [
        Layer(
          id: LayerId('$id-sb'),
          name: 'SB',
          kind: LayerKind.storyboard,
          frames: frames,
          timeline: timeline,
        ),
      ],
    );
  }

  Project film(List<List<Cut>> tracks) => Project(
    id: const ProjectId('pages'),
    name: 'Pages',
    createdAt: DateTime.utc(2026, 10, 30),
    tracks: [
      for (final (index, cuts) in tracks.indexed)
        Track(id: TrackId('t$index'), name: 'T$index', cuts: cuts),
    ],
  );

  // Five panels a page: the sixth, the third of `b`, begins the second.
  final cuts = [
    cut('a', [10, 20, 30]),
    cut('b', [40, 50, 60, 70]),
    cut('c', [80]),
  ];

  test('each page begins on the frame of its first cell, on the track', () {
    expect(contePageHeadsOf(film([cuts]), aspect: 16 / 9), [0, 150]);
  });

  test('a book of one page is one page, however long the film', () {
    expect(contePageHeadsOf(film([[cut('a', [900])]]), aspect: 16 / 9), [0]);
  });

  test('every page but the first takes a head — the book\'s own count', () {
    final long = film([
      [for (var at = 0; at < 13; at += 1) cut('c$at', [24])],
    ]);
    final book = layoutConteSheet(buildConteSheetSource(long));
    expect(book, hasLength(3), reason: 'fixture: thirteen rows, five a page');
    expect(contePageHeadsOf(long, aspect: 16 / 9), [0, 120, 240]);
  });

  test('a file carrying a second track counts its first\'s pages: one ruler '
      'cannot count two axes (전제 8)', () {
    final twoTracks = film([
      [for (var at = 0; at < 7; at += 1) cut('a$at', [24])],
      [for (var at = 0; at < 7; at += 1) cut('b$at', [10])],
    ]);
    expect(contePageHeadsOf(twoTracks, aspect: 16 / 9), [0, 120]);
  });

  testWidgets('🎯under the page view the conte panel\'s ruler counts the '
      'book\'s pages; off it, none', (tester) async {
    final project = film([cuts]);
    TimelineFrameRuler ruler() => tester.widget<TimelineFrameRuler>(
      find.byKey(const ValueKey<String>('storyboard-frame-ruler')),
    );

    await pumpStoryboardHost(tester, project);
    expect(ruler().pages, isNull, reason: 'the frames view lays no book');

    await pumpStoryboardHost(
      tester,
      project,
      rulerView: FrameRulerView.pages,
    );
    expect(
      ruler().pages,
      const TimelineRulerPages.startingAt([0, 150]),
    );
  });
}
