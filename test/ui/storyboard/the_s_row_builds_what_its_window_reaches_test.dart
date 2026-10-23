// The storyboard's S row spans the whole film, and it built the pieces of
// every sound of the track — paper, waveform, words, grips, drop places —
// on every build: 🔬a fifth of reopening the storyboard on the AMMI OP
// (frame-panels-build-in-one-frame, 2026-10-24). It builds those of the
// panel's window now, as the painters beside it draw theirs.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';

/// One cut [frames] long under a track whose S row holds a sound at frame 2
/// and one [far] on — each named after its words, and carrying
/// [audioClips].
Project _project({
  required int far,
  int frames = 4000,
  List<AudioClip> audioClips = const [],
}) => Project(
  id: const ProjectId('s-row-window'),
  name: 'S row window',
  createdAt: DateTime.utc(2026, 10, 24),
  tracks: [
    Track(
      id: const TrackId('s-row-window-track'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('cut-1'),
          name: 'cut-1',
          duration: frames,
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
      seLayers: [
        Layer(
          id: const LayerId('se-row-1'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('near'),
              duration: 6,
              name: 'Near!',
              seName: 'Near',
              strokes: const [],
            ),
            Frame(
              id: const FrameId('far'),
              duration: 40,
              name: 'Far!',
              seName: 'Far',
              strokes: const [],
            ),
          ],
          timeline: {
            2: const TimelineExposure.drawing(FrameId('near'), length: 6),
            far: const TimelineExposure.drawing(FrameId('far'), length: 40),
          },
          audioClips: audioClips,
        ),
      ],
    ),
  ],
);

/// The storyboard on [project], two pixels a frame — a chip's length is
/// eight frames there, four times the window's overscan.
Future<void> _open(WidgetTester tester, Project project) async {
  await tester.pumpWidget(
    MaterialApp(home: HomePage(key: UniqueKey(), initialProject: project)),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
  tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session
          .panelViews
          .storyboardPixelsPerFrame
          .value =
      2;
  await tester.pumpAndSettle();
}

/// The storyboard's frame area — what scrolls along the frames.
List<ScrollPosition> _frameAreas(WidgetTester tester) => [
  for (final state in tester.stateList<ScrollableState>(
    find.descendant(
      of: find.byType(StoryboardPanel),
      matching: find.byType(Scrollable),
    ),
  ))
    if (state.position.axis == Axis.horizontal &&
        state.position.maxScrollExtent > 0)
      state.position,
];

/// Scrolls the storyboard's frame area to [offset].
Future<void> _scrollTo(WidgetTester tester, double offset) async {
  for (final position in _frameAreas(tester)) {
    position.jumpTo(offset);
  }
  await tester.pumpAndSettle();
}

Finder _key(String name) => find.byKey(ValueKey<String>(name));

void main() {
  testWidgets('an S row builds the pieces of the sounds its window reaches '
      '— and a sound further on once the view goes there', (tester) async {
    await _open(tester, _project(far: 3000));
    final panel = tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
    expect(panel.pixelsPerFrame, 2, reason: '⛔전제');

    expect(_key('storyboard-se-paper-se-row-1-2'), findsOneWidget);
    expect(_key('storyboard-se-label-se-row-1-2'), findsOneWidget);
    expect(_key('storyboard-se-grip-se-row-1-0-end'), findsOneWidget);
    for (final far in [
      'storyboard-se-paper-se-row-1-3000',
      'storyboard-se-label-se-row-1-3000',
      'storyboard-se-grip-se-row-1-1-start',
      'storyboard-se-grip-se-row-1-1-end',
      'storyboard-se-cell-drop-se-row-1-3040',
    ]) {
      expect(_key(far), findsNothing, reason: '$far lies far past the view');
    }

    await _scrollTo(tester, 3000 * 2 - 20);

    for (final far in [
      'storyboard-se-paper-se-row-1-3000',
      'storyboard-se-label-se-row-1-3000',
      'storyboard-se-grip-se-row-1-1-start',
      'storyboard-se-grip-se-row-1-1-end',
      'storyboard-se-cell-drop-se-row-1-3040',
    ]) {
      expect(_key(far), findsOneWidget, reason: '$far is in view now');
    }
    expect(_key('storyboard-se-paper-se-row-1-2'), findsNothing);
    expect(_key('storyboard-se-grip-se-row-1-0-end'), findsNothing);
  });

  // A name stands in the frames free before its block (F-358), so a sound
  // that starts just past the window can show its chip inside the view.
  testWidgets('a sound just past the window still builds its words, whose '
      'name stands in the view', (tester) async {
    // Where the window ends at the last pixel of a bucket: the view is two
    // cells and a hair short of it there — what a chip's eight frames reach
    // past.
    await _open(tester, _project(far: 3000));
    final viewportWidth = _frameAreas(tester).first.viewportDimension;
    final bucketWidth = timelineFrameWindowSpanFor(2) * 2.0;
    final offset = bucketWidth * 10 - 1;
    expect(
      timelineFrameWindowBucketOf(offset: offset, cellExtent: 2),
      9,
      reason: '⛔전제: the last pixel of a bucket',
    );
    final window = visibleFrameWindowFor(
      bucket: ValueNotifier<int>(9),
      viewportMainExtent: viewportWidth,
      cellExtent: 2,
      frameStartIndex: 0,
      frameEndIndexExclusive: 1 << 30,
    );
    final edge = window.endIndexExclusive;

    await _open(tester, _project(far: edge));
    await _scrollTo(tester, offset);
    expect(
      _key('storyboard-se-paper-se-row-1-$edge'),
      findsNothing,
      reason: '⛔전제: the sound starts past the window',
    );

    final chip = tester.getRect(find.bySemanticsLabel('SE name Far'));
    final rowLeft = tester.getTopLeft(_key('storyboard-se-row-0-1')).dx;
    expect(
      chip.left,
      lessThan(rowLeft + offset + viewportWidth),
      reason: 'its name stands in the view, so its words are built',
    );
  });

  // The waveforms are the window's too — the overlay that draws them takes
  // the window (an_se_row_draws_the_sounds_over_its_window_test); this is
  // the row handing it over.
  testWidgets('and only the window\'s sounds draw their waveforms', (
    tester,
  ) async {
    final peaks = AudioPeaks(
      bucketsPerSecond: 80,
      peaks: Float32List.fromList(List.filled(80, 0.5)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: _project(
              far: 3000,
              audioClips: [
                for (final sound in ['near', 'far'])
                  AudioClip(filePath: 'voice.wav', frameId: FrameId(sound)),
              ],
            ),
            activeCutId: const CutId('cut-1'),
            pixelsPerFrame: 2,
            projectFrameRate: ProjectFrameRate.fps24,
            audioPeaksFor: (path) => path == 'voice.wav' ? peaks : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_key('storyboard-audio-clip-se-row-1-0-b2'), findsOneWidget);
    expect(
      _key('storyboard-audio-clip-se-row-1-1-b3000'),
      findsNothing,
      reason: 'a sound far past the view draws no waveform',
    );
  });
}
