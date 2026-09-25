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
import 'package:anicel/src/ui/timeline/se_audio_lane.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

import 'timeline_frame_geometry_probe.dart';

/// F-113 (유저 2026-09-12): 「컷2부터는 두 파형이 서로 다름. 스토리보드패널의
/// 파형은 정확한데 타임라인패널 파형은 어긋남」. A block spilling into the cut
/// starts at frame 0 of the cut's row with its sound already under way —
/// both waveforms the timeline draws for it (the row's underlay and the
/// audio lane's editing strip) must start that far into the file.

// 2.0 s of peaks → 48 frames at fps 24.
final _peaks = AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160));

Layer _spillingRow({int offsetFrames = 0}) => Layer(
  id: const LayerId('se-1'),
  name: 'S1',
  kind: LayerKind.se,
  frames: const [],
  timeline: const {0: TimelineExposure.drawing(FrameId('f0'), length: 3)},
  audioClips: [
    AudioClip(
      filePath: 'voice.wav',
      frameId: const FrameId('f0'),
      offsetFrames: offsetFrames,
    ),
  ],
);

WaveformPainter _painterUnder(WidgetTester tester, Finder host) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: host,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is CustomPaint && widget.painter is WaveformPainter,
                ),
              ),
            )
            .painter!
        as WaveformPainter;

void main() {
  Future<void> pumpCellsRow(WidgetTester tester, {int? lead}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Material(
              child: TimelineFrameCellsRow(
                layer: _spillingRow(),
                playbackFrameCount: 6,
                geometry: testFrameGeometry(
                  frameCellExtent: 48,
                  frameEndIndexExclusive: 10,
                ),
                crossAxisExtent: 52,
                exposureStateForLayer: (_, _) =>
                    TimelineCellExposureState.uncovered,
                onSelectLayer: (_) {},
                onSelectFrame: (_) {},
                audioPeaksFor: (_) => _peaks,
                projectFrameRate: ProjectFrameRate.fps24,
                spillInLeadFrames: lead,
              ),
            ),
          ),
        ),
      );

  testWidgets('🚨the row\'s underlay waveform starts that far into the sound',
      (tester) async {
    await pumpCellsRow(tester, lead: 14);
    const strip = ValueKey<String>('timeline-audio-clip-se-1-0-b0');
    expect(_painterUnder(tester, find.byKey(strip)).leadingFrames, 14);

    await pumpCellsRow(tester);
    expect(
      _painterUnder(tester, find.byKey(strip)).leadingFrames,
      0,
      reason: 'a block that starts in this cut is drawn from the file start',
    );
  });

  testWidgets('🚨the audio lane\'s editing strip starts there too, on top of '
      'the clip\'s own trim', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Material(
            child: SeAudioLaneFrameRow(
              layer: _spillingRow(offsetFrames: 3),
              frameStartIndex: 0,
              frameEndIndexExclusive: 10,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: const TimelineGridMetrics(
                frameCellWidth: 48,
                layerRowHeight: 52,
              ),
              frameRate: ProjectFrameRate.fps24,
              audioPeaksFor: (_) => _peaks,
              spillInLeadFrames: 14,
            ),
          ),
        ),
      ),
    );
    expect(
      _painterUnder(
        tester,
        find.byKey(const ValueKey<String>('timeline-audio-lane-span-se-1-0-b0')),
      ).leadingFrames,
      17,
    );
  });
}
