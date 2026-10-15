import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/waveform_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_rows_scroll_body.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edges.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

import '../../helpers/row_berths_in_order.dart';

/// 🚨★★★**A WAVEFORM THAT LANDS AFTER ITS ROW WAS BUILT IS DRAWN** (유저
/// 09-25: 「콘티패널에선 그냥 블록에서 파형보이는데 타임라인에선 안보여.
/// … 이름/대사 지정하니까 보이네」, card `F-178` ⑥).
///
/// A take's conform runs after the take is placed, so its SE row is first
/// built with no peaks. The timeline memoized rows by their Layer, and the
/// store's notification rebuilds the host with the SAME layer — the memo
/// handed the blank row back until an edit made a new one. The storyboard
/// keeps no such memo, which is why it showed the waveform all along.
///
/// 🚨I-57 (10-13): a row is kept by its shape now, and the peaks reach it
/// as its world ([BerthWorld]) — its pictures are built again, the row is
/// not.
///
/// ⚠️[_uncovered] and [_peaksFor] are ONE function for every pump, as the
/// session's tear-offs are in the app: a fresh closure is a new memo key,
/// and a memo that misses on every pump would pass the first pin with the
/// world left as it was.
void main() {
  final layer = Layer(
    id: const LayerId('se-1'),
    name: 'S1',
    kind: LayerKind.se,
    frames: const [],
    timeline: const {0: TimelineExposure.drawing(FrameId('f0'), length: 3)},
    audioClips: [AudioClip(filePath: 'take.wav', frameId: const FrameId('f0'))],
  );
  final peaks = AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160));
  final rows = buildTimelineDisplayRows(
    layers: [layer],
    expandedLayerIds: const {},
    lanesForLayer: (_) => const [],
  );

  setUp(() => _landed = null);

  Widget body() => MaterialApp(
    home: Scaffold(
      body: Material(
        child: TimelineFrameRowsScrollBody(
          rows: rows,
          berths: berthsInOrder(rows),
          edges: TimelineRowEdges.uniform(
            1,
            TimelineGridMetrics.defaults.layerRowHeight,
          ),
          hooks: TimelineGridHooks(
            activeLayerId: null,
            frameCursor: ValueNotifier<int>(0),
            playbackFrameCount: 24,
            exposureStateForLayer: _uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            audioPeaksFor: _peaksFor,
            projectFrameRate: ProjectFrameRate.fps24,
          ),
          frameStartIndex: 0,
          frameEndIndexExclusive: 10,
          leadingFrameSpacerWidth: 0,
          trailingFrameSpacerWidth: 0,
          totalFrameContentWidth: 480,
          metrics: TimelineGridMetrics.defaults,
        ),
      ),
    ),
  );

  final waveforms = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is WaveformPainter,
  );

  testWidgets('🚨the same layer, rebuilt once the peaks land, shows them — '
      'no edit needed', (tester) async {
    await tester.pumpWidget(body());
    expect(waveforms, findsNothing, reason: 'the premise: still extracting');
    final row = tester.widget(find.byType(TimelineFrameCellsRow));

    _landed = peaks;
    await tester.pumpWidget(body());

    expect(
      waveforms,
      findsOneWidget,
      reason:
          'the memo handed the row built before the peaks back, until an '
          'edit replaced the layer',
    );
    expect(
      identical(tester.widget(find.byType(TimelineFrameCellsRow)), row),
      isTrue,
      reason: 'the peaks reach the row as its world; its shape is the same',
    );
  });

  testWidgets('and a rebuild with nothing new hands the same row back — '
      'the memo still holds', (tester) async {
    _landed = peaks;
    await tester.pumpWidget(body());
    final first = tester.widget(find.byType(TimelineFrameCellsRow));
    final drawn = tester.widget(waveforms);

    await tester.pumpWidget(body());

    expect(
      identical(tester.widget(find.byType(TimelineFrameCellsRow)), first),
      isTrue,
      reason: 'only the waveform the row paints joined its world',
    );
    expect(
      identical(tester.widget(waveforms), drawn),
      isTrue,
      reason: 'a world that did not move builds no picture again',
    );
  });
}

/// The conform store as the host reads it: peaks land when they land.
AudioPeaks? _landed;

/// The store's peaks, from one function for every pump.
AudioPeaks? _peaksFor(String _) => _landed;

/// Every cell uncovered, from one function for every pump.
TimelineCellExposureState _uncovered(Layer _, int _) =>
    TimelineCellExposureState.uncovered;
