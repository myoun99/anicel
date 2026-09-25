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
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

/// 🚨★★★**A WAVEFORM THAT LANDS AFTER ITS ROW WAS BUILT IS DRAWN** (유저
/// 09-25: 「콘티패널에선 그냥 블록에서 파형보이는데 타임라인에선 안보여.
/// … 이름/대사 지정하니까 보이네」, card `F-178` ⑥).
///
/// A take's conform runs after the take is placed, so its SE row is first
/// built with no peaks. The timeline memoizes rows by their Layer, and the
/// store's notification rebuilds the host with the SAME layer — the memo
/// handed the blank row back until an edit made a new one. The storyboard
/// keeps no such memo, which is why it showed the waveform all along.
///
/// ⚠️[_uncovered] is ONE function for every pump, as the session's tear-off
/// is in the app: a fresh closure is a new memo key, and a memo that misses
/// on every pump would pass the first pin with the key left as it was.
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

  Widget body(AudioPeaks? landed) => MaterialApp(
    home: Scaffold(
      body: Material(
        child: TimelineFrameRowsScrollBody(
          rows: buildTimelineDisplayRows(
            layers: [layer],
            expandedLayerIds: const {},
            lanesForLayer: (_) => const [],
          ),
          playbackFrameCount: 24,
          frameStartIndex: 0,
          frameEndIndexExclusive: 10,
          leadingFrameSpacerWidth: 0,
          trailingFrameSpacerWidth: 0,
          totalFrameContentWidth: 480,
          metrics: TimelineGridMetrics.defaults,
          exposureStateForLayer: _uncovered,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          audioPeaksFor: (_) => landed,
          projectFrameRate: ProjectFrameRate.fps24,
        ),
      ),
    ),
  );

  final waveforms = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is WaveformPainter,
  );

  testWidgets('🚨the same layer, rebuilt once the peaks land, shows them — '
      'no edit needed', (tester) async {
    await tester.pumpWidget(body(null));
    expect(waveforms, findsNothing, reason: 'the premise: still extracting');

    await tester.pumpWidget(body(peaks));

    expect(
      waveforms,
      findsOneWidget,
      reason:
          'the memo handed the row built before the peaks back, until an '
          'edit replaced the layer',
    );
  });

  testWidgets('and a rebuild with nothing new hands the same row back — '
      'the memo still holds', (tester) async {
    await tester.pumpWidget(body(peaks));
    final first = tester.widget(find.byType(TimelineFrameCellsRow));

    await tester.pumpWidget(body(peaks));

    expect(
      identical(tester.widget(find.byType(TimelineFrameCellsRow)), first),
      isTrue,
      reason: 'only the waveform the row paints joined its key',
    );
  });
}

/// Every cell uncovered, from one function for every pump.
TimelineCellExposureState _uncovered(Layer _, int _) =>
    TimelineCellExposureState.uncovered;
