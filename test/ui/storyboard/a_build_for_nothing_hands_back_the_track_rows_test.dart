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
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/storyboard_panel.dart'
    show StoryboardConteCreatePainter, StoryboardPanel;
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_current_row.dart';

import '../storyboard_cut_block_probe.dart';

/// What the host hands the panel, each moved as the app moves it.
typedef _Host = ({
  ValueNotifier<int> notify,
  ValueNotifier<Project> project,
  ValueNotifier<AudioPeaks?> heard,
  ValueNotifier<CutId> active,
  _HeardCut under,
  ValueNotifier<TimelineRowAddress?> standing,
});

/// The cut under the playhead, counting who hears it.
class _HeardCut extends ValueNotifier<CutId?> {
  _HeardCut(super.value);

  int hearers = 0;

  @override
  void addListener(VoidCallback listener) {
    hearers += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    hearers -= 1;
    super.removeListener(listener);
  }
}

/// 🚨I-57 (10-14): A STORYBOARD BUILT AGAIN FOR NOTHING HANDS BACK EVERY ROW
/// OF ITS TRACK'S STRIP AS IT WAS — and builds one again the moment what it
/// shows changes.
///
/// Its host builds it again on every notify it hears — a cut crossed under
/// the playhead among them — and every row of the strip was built again
/// with it: 🔬three fifths of a crossing's paint on the AMMI OP was the S
/// rows' waveforms, painted again for sounds that had not moved, and the
/// largest part of its semantics the conte row's cells, said again.
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

  /// A conte layer of one panel over the whole of cut [cutId].
  Layer conteLayer(String cutId) => Layer(
    id: LayerId('$cutId-sb'),
    name: 'SB',
    kind: LayerKind.storyboard,
    frames: [Frame(id: FrameId('$cutId-a'), duration: 12, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$cutId-a'), length: 12)},
  );

  /// Cuts c1 and c2, twelve frames each, on the track [trackId] with the
  /// sound [se] — each cut named by [names] where it names one, and holding
  /// a conte layer where [conteIn] says so.
  Project projectWith(
    Layer se, {
    String trackId = 't',
    Map<String, String> names = const {},
    Set<String> conteIn = const {},
  }) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 10, 14),
    tracks: [
      Track(
        id: TrackId(trackId),
        name: 'Video',
        seLayers: [se],
        cuts: [
          for (final id in ['c1', 'c2'])
            Cut(
              id: CutId(id),
              name: names[id] ?? id,
              duration: 12,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [if (conteIn.contains(id)) conteLayer(id)],
            ),
        ],
      ),
    ],
  );

  /// The panel as a host builds it: again whenever [_Host.notify] moves, of
  /// what [host] holds then — the cut under the playhead [under] where one
  /// is handed instead.
  Future<void> pumpHost(
    WidgetTester tester,
    _Host host, {
    _HeardCut? under,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: host.notify,
          builder: (_, _, _) => StoryboardPanel(
            project: host.project.value,
            activeCutId: host.active.value,
            cutUnderPlayhead: under ?? host.under,
            currentRowHooks: TimelineCurrentRowHooks(currentRow: host.standing),
            pixelsPerFrame: 8,
            projectFrameRate: ProjectFrameRate.fps24,
            audioPeaksFor: (path) =>
                path == 'voice.wav' ? host.heard.value : null,
          ),
        ),
      ),
    ),
  );

  _Host newHost({AudioPeaks? heard}) {
    final host = (
      notify: ValueNotifier<int>(0),
      project: ValueNotifier<Project>(projectWith(seLayer())),
      heard: ValueNotifier<AudioPeaks?>(heard),
      active: ValueNotifier<CutId>(const CutId('c1')),
      under: _HeardCut(const CutId('c1')),
      standing: ValueNotifier<TimelineRowAddress?>(null),
    );
    addTearDown(host.notify.dispose);
    addTearDown(host.project.dispose);
    addTearDown(host.heard.dispose);
    addTearDown(host.active.dispose);
    addTearDown(host.under.dispose);
    addTearDown(host.standing.dispose);
    return host;
  }

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

  /// Each row's widget as it stands.
  Map<String, Widget> rowsNow(WidgetTester tester) => {
    for (final MapEntry(:key, value: row) in rows.entries)
      key: tester.widget(row),
  };

  testWidgets('built again for nothing, every row of its strip is the row '
      'it had', (tester) async {
    final host = newHost(heard: peaks);
    await pumpHost(tester, host);
    final panelBefore = tester.widget(find.byType(StoryboardPanel));
    final before = rowsNow(tester);
    expect(waveform, findsOneWidget, reason: 'premise: the sound is drawn');

    host.notify.value += 1;
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
    final host = newHost(heard: peaks);
    // Stood on the V row, whose bands wash the cut under the playhead: the
    // crossing is news to its painter, never a row built again.
    host.standing.value = const TrackRowAddress(TrackId('t'));
    await pumpHost(tester, host);
    final before = rowsNow(tester);

    host.under.value = const CutId('c2');
    host.active.value = const CutId('c2');
    host.notify.value += 1;
    await tester.pump();

    for (final MapEntry(:key, value: row) in rowsNow(tester).entries) {
      expect(row, same(before[key]), reason: key);
    }
  });

  testWidgets('🚨a waveform heard after its row was built is drawn — what '
      'the store answers is what the row shows', (tester) async {
    final host = newHost();
    await pumpHost(tester, host);
    expect(waveform, findsNothing, reason: 'premise: still extracting');

    host.heard.value = peaks;
    host.notify.value += 1;
    await tester.pump();

    expect(waveform, findsOneWidget);
  });

  testWidgets('a sound edited is its row built again', (tester) async {
    final host = newHost(heard: peaks);
    await pumpHost(tester, host);
    // The words are painted, fitted to the block: read off the widget.
    String said() => tester
        .widget<DialogueFitText>(
          find.descendant(of: seRow, matching: find.byType(DialogueFitText)),
        )
        .text;
    final before = tester.widget(seRow);
    expect(said(), 'Hey!', reason: 'premise: its words');

    host.project.value = projectWith(seLayer(dialogue: 'Ho!'));
    host.notify.value += 1;
    await tester.pump();

    expect(tester.widget(seRow), isNot(same(before)));
    expect(said(), 'Ho!');
  });

  // 🚨A cut edited lies where it lay: the row is built again for the cut
  // itself, never only for where it lies.
  testWidgets('a cut renamed where it lies is its V row built again — the '
      'block says the new name', (tester) async {
    final host = newHost(heard: peaks);
    await pumpHost(tester, host);
    expect(requireCutBlock(tester, 'c1').title, 'c1', reason: 'premise');

    host.project.value = projectWith(seLayer(), names: {'c1': 'Open'});
    host.notify.value += 1;
    await tester.pump();

    expect(requireCutBlock(tester, 'c1').title, 'Open');
  });

  testWidgets('a conte layer made in a cut is its conte row built again — '
      'the cut\'s button gone', (tester) async {
    final host = newHost(heard: peaks);
    await pumpHost(tester, host);
    List<({int start, int endExclusive})> buttons() =>
        (tester
                    .widget<CustomPaint>(
                      find.byKey(
                        const ValueKey<String>('storyboard-conte-create-t'),
                      ),
                    )
                    .painter!
                as StoryboardConteCreatePainter)
            .spans;
    expect(buttons(), [
      (start: 0, endExclusive: 12),
      (start: 12, endExclusive: 24),
    ], reason: 'premise: neither cut has one');

    host.project.value = projectWith(seLayer(), conteIn: {'c1'});
    host.notify.value += 1;
    await tester.pump();

    expect(buttons(), [(start: 12, endExclusive: 24)]);
  });

  testWidgets('🚨what a V row hears it lets go of — when its track goes, '
      'when it is handed another cut under the playhead, and when the panel '
      'goes', (tester) async {
    final host = newHost(heard: peaks);
    await pumpHost(tester, host);
    final hearing = host.under.hearers;
    expect(hearing, greaterThan(0), reason: 'premise: the V row hears it');

    host.project.value = projectWith(seLayer(), trackId: 'u');
    host.notify.value += 1;
    await tester.pump();
    expect(
      host.under.hearers,
      hearing,
      reason: 'the new track hears it, and the gone one no longer',
    );

    final handedAnew = _HeardCut(const CutId('c1'));
    addTearDown(handedAnew.dispose);
    await pumpHost(tester, host, under: handedAnew);
    expect(host.under.hearers, 0, reason: 'the one it was handed before');
    expect(handedAnew.hearers, hearing);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(handedAnew.hearers, 0);
  });
}
