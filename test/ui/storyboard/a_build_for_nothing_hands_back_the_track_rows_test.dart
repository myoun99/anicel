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
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';

/// 🚨I-57 (10-14): A STORYBOARD BUILT AGAIN FOR NOTHING HANDS BACK ITS
/// TRACK'S S ROWS AND ITS TRANSITION ROW AS THEY WERE — and builds one
/// again the moment what it shows changes.
///
/// Its host builds it again on every notify it hears — a cut crossed under
/// the playhead among them — and every row of the strip was built again
/// with it: 🔬three fifths of a crossing's paint on the AMMI OP was the S
/// rows' waveforms, painted again for sounds that had not moved.
void main() {
  final peaks = AudioPeaks(
    bucketsPerSecond: 80,
    peaks: Float32List.fromList(List.filled(80, 0.5)),
  );

  Layer seLayer({String dialogue = 'Hey!'}) => Layer(
    id: const LayerId('se'),
    name: 'S1',
    kind: LayerKind.se,
    frames: [
      Frame(
        id: const FrameId('se-f'),
        duration: 12,
        name: dialogue,
        strokes: const [],
      ),
    ],
    timeline: {0: const TimelineExposure.drawing(FrameId('se-f'), length: 12)},
    audioClips: [
      AudioClip(filePath: 'voice.wav', frameId: const FrameId('se-f')),
    ],
  );

  Project projectWith(Layer se) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 10, 14),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        seLayers: [se],
        cuts: [
          for (final id in ['c1', 'c2'])
            Cut(
              id: CutId(id),
              name: id,
              duration: 12,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: const [],
            ),
        ],
      ),
    ],
  );

  /// The panel as a host builds it: again whenever [notify] moves, on the
  /// project [project] holds then, standing in the cut [active] names then,
  /// its sounds' peaks [heard] as the store has them then.
  Future<void> pumpHost(
    WidgetTester tester, {
    required ValueNotifier<int> notify,
    required ValueNotifier<Project> project,
    required ValueNotifier<AudioPeaks?> heard,
    required ValueNotifier<CutId> active,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: notify,
          builder: (_, _, _) => StoryboardPanel(
            project: project.value,
            activeCutId: active.value,
            pixelsPerFrame: 8,
            projectFrameRate: ProjectFrameRate.fps24,
            audioPeaksFor: (path) => path == 'voice.wav' ? heard.value : null,
          ),
        ),
      ),
    ),
  );

  final seRow = find.byKey(const ValueKey<String>('storyboard-se-row-0-1'));
  final waveform = find.byKey(
    const ValueKey<String>('storyboard-audio-clip-se-0-b0'),
  );

  /// Every row of the track's strip, by the key it wears.
  final rows = {
    for (final key in [
      'storyboard-camera-row-t',
      'storyboard-transition-row-t',
      'storyboard-se-row-0-1',
      'storyboard-track-timeline-area-t',
      'storyboard-conte-row-t',
    ])
      key: find.byKey(ValueKey<String>(key)),
  };

  ({
    ValueNotifier<int> notify,
    ValueNotifier<Project> project,
    ValueNotifier<AudioPeaks?> heard,
    ValueNotifier<CutId> active,
  })
  host({AudioPeaks? heard}) {
    final notify = ValueNotifier<int>(0);
    final project = ValueNotifier<Project>(projectWith(seLayer()));
    final heardNow = ValueNotifier<AudioPeaks?>(heard);
    final active = ValueNotifier<CutId>(const CutId('c1'));
    addTearDown(notify.dispose);
    addTearDown(project.dispose);
    addTearDown(heardNow.dispose);
    addTearDown(active.dispose);
    return (notify: notify, project: project, heard: heardNow, active: active);
  }

  /// Each row's widget as it stands.
  Map<String, Widget> rowsNow(WidgetTester tester) => {
    for (final MapEntry(:key, value: row) in rows.entries)
      key: tester.widget(row),
  };

  testWidgets('built again for nothing, every row of its strip is the row '
      'it had', (tester) async {
    final (:notify, :project, :heard, :active) = host(heard: peaks);
    await pumpHost(
      tester,
      notify: notify,
      project: project,
      heard: heard,
      active: active,
    );
    final panelBefore = tester.widget(find.byType(StoryboardPanel));
    final before = rowsNow(tester);
    expect(waveform, findsOneWidget, reason: 'premise: the sound is drawn');

    notify.value += 1;
    await tester.pump();

    expect(
      tester.widget(find.byType(StoryboardPanel)),
      isNot(same(panelBefore)),
      reason: 'premise: the panel was built again',
    );
    for (final MapEntry(:key, value: row) in rowsNow(tester).entries) {
      expect(row, same(before[key]), reason: key);
    }
  });

  testWidgets('🚨a cut crossed builds no row of the strip — none of them '
      'shows which cut you stand in', (tester) async {
    final (:notify, :project, :heard, :active) = host(heard: peaks);
    await pumpHost(
      tester,
      notify: notify,
      project: project,
      heard: heard,
      active: active,
    );
    final before = rowsNow(tester);

    active.value = const CutId('c2');
    notify.value += 1;
    await tester.pump();

    for (final MapEntry(:key, value: row) in rowsNow(tester).entries) {
      expect(row, same(before[key]), reason: key);
    }
  });

  testWidgets('🚨a waveform heard after its row was built is drawn — what '
      'the store answers is what the row shows', (tester) async {
    final (:notify, :project, :heard, :active) = host();
    await pumpHost(
      tester,
      notify: notify,
      project: project,
      heard: heard,
      active: active,
    );
    expect(waveform, findsNothing, reason: 'premise: still extracting');

    heard.value = peaks;
    notify.value += 1;
    await tester.pump();

    expect(waveform, findsOneWidget);
  });

  testWidgets('a sound edited is its row built again', (tester) async {
    final (:notify, :project, :heard, :active) = host(heard: peaks);
    await pumpHost(
      tester,
      notify: notify,
      project: project,
      heard: heard,
      active: active,
    );
    // The words are painted, fitted to the block: read off the widget.
    String said() => tester
        .widget<DialogueFitText>(
          find.descendant(of: seRow, matching: find.byType(DialogueFitText)),
        )
        .text;
    final before = tester.widget(seRow);
    expect(said(), 'Hey!', reason: 'premise: its words');

    project.value = projectWith(seLayer(dialogue: 'Ho!'));
    notify.value += 1;
    await tester.pump();

    expect(tester.widget(seRow), isNot(same(before)));
    expect(said(), 'Ho!');
  });
}
