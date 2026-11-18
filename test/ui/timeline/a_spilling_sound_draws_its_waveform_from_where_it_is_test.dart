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
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuWaveView;

import 'timeline_frame_geometry_probe.dart';

/// F-113 (유저 2026-09-12): 「컷2부터는 두 파형이 서로 다름. 스토리보드패널의
/// 파형은 정확한데 타임라인패널 파형은 어긋남」. A block spilling into the cut
/// starts at frame 0 of the cut's row with its sound already under way —
/// the waveform the timeline draws for it (on the row's cells) must start
/// that far into the file. ↩️The SE audio lane drew a second one, an
/// editing strip, until the lane went (I-140).

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

/// The row's one sound as its cells' tile shows the span [0, 3) of it at a
/// ratio of 1 ([TimelineRowCellsPainter.wavesIn]).
GpuWaveView _waveOf(WidgetTester tester) =>
    (tester
                    .widget<CustomPaint>(
                      find.byWidgetPredicate(
                        (widget) =>
                            widget is CustomPaint &&
                            widget.painter is TimelineRowCellsPainter,
                      ),
                    )
                    .painter!
                as TimelineRowCellsPainter)
        .wavesIn(0, 3, 1)
        .single
        .view;

void main() {
  Future<void> pumpCellsRow(
    WidgetTester tester, {
    int? lead,
    int offsetFrames = 0,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Material(
              child: TimelineFrameCellsRow(
                layer: _spillingRow(offsetFrames: offsetFrames),
                drawnFrameCount: 6,
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

  testWidgets('🚨the row\'s waveform starts that far into the sound',
      (tester) async {
    await pumpCellsRow(tester, lead: 14);
    expect(_waveOf(tester).leadingFrames, 14);

    await pumpCellsRow(tester);
    expect(
      _waveOf(tester).leadingFrames,
      0,
      reason: 'a block that starts in this cut is drawn from the file start',
    );
  });

  testWidgets('a frame of the row\'s sound is drawn as long as a frame cell '
      '— along the row, not across it', (tester) async {
    await pumpCellsRow(tester);
    // Cells 48 along and the row 52 across: the two sides differ, so a
    // wave that measured the wrong one draws its sound at another scale.
    final wave = _waveOf(tester);
    expect((wave.frameQ8, wave.acrossQ8), (48 * 256, 52 * 256));
  });

  testWidgets('🚨and on top of the clip\'s own trim', (tester) async {
    await pumpCellsRow(tester, lead: 14, offsetFrames: 3);
    expect(_waveOf(tester).leadingFrames, 17);
  });
}
