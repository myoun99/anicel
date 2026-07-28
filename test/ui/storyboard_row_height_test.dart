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
import 'package:anicel/src/ui/storyboard_panel.dart';

/// The V row's height is the user's to set, all the way down to the floor —
/// and the floor has to be a height the row actually fits in (feedback #8:
/// "v행 최대로줄이면 bottom 오버플로우 9픽셀남").
const _trackId = TrackId('h-track');

Project _project() => Project(
  id: const ProjectId('h-project'),
  name: 'Heights',
  createdAt: DateTime.utc(2026, 7, 28),
  tracks: [
    Track(
      id: _trackId,
      // A NAMED track: the name is the second line of the rail label, and
      // two stacked lines are what used to overflow the short row.
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('cut-1'),
          name: 'cut-1',
          duration: 10,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: const LayerId('cut-1-cel'),
              name: 'A',
              frames: const [],
              timeline: const {},
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
}

double _railHeight(WidgetTester tester) => tester
    .getSize(
      find.byKey(
        ValueKey<String>('storyboard-track-label-row-${_trackId.value}'),
      ),
    )
    .height;

void main() {
  testWidgets('the rail row fits at the SHORTEST height the stepper reaches', (
    tester,
  ) async {
    await _openStoryboard(tester);

    final shorter = find.byKey(
      const ValueKey<String>('storyboard-row-shorter-button'),
    );
    // Walk all the way to the floor: the stepper stops there on its own.
    var previous = -1.0;
    while (_railHeight(tester) != previous) {
      previous = _railHeight(tester);
      await tester.tap(shorter);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'the rail row overflowed at ${_railHeight(tester)}px',
      );
    }

    expect(_railHeight(tester), StoryboardPanel.minTrackLaneHeight);
  });

  testWidgets('a track NAME does not make the short row overflow — it is the '
      'line that stands down', (tester) async {
    await _openStoryboard(tester);

    final shorter = find.byKey(
      const ValueKey<String>('storyboard-row-shorter-button'),
    );
    for (var i = 0; i < 12; i += 1) {
      await tester.tap(shorter);
      await tester.pumpAndSettle();
    }
    expect(_railHeight(tester), StoryboardPanel.minTrackLaneHeight);

    // The track's LABEL is what a row must always show; its name is the
    // detail that yields when there is no room for two lines.
    expect(
      find.byKey(ValueKey<String>('storyboard-track-label-${_trackId.value}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
