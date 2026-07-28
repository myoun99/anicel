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
import 'package:anicel/src/ui/timeline/se_audio_lane.dart'
    show TimelineAudioLaneCallbacks;
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// One second of audio at half amplitude → 24 frames at 24 fps.
final _peaks = AudioPeaks(
  bucketsPerSecond: 80,
  peaks: Float32List.fromList(List.filled(80, 0.5)),
);

/// SE layer with a 12-frame entry carrying a frame-linked sound: the block
/// IS the window — the waveform starts at the block start and clips to the
/// block's 12 frames (the file itself is 24 frames long).
Layer _seLayer() => Layer(
  id: const LayerId('wave-se'),
  name: 'S1',
  kind: LayerKind.se,
  frames: [Frame(id: const FrameId('wave-f'), duration: 12, strokes: const [])],
  timeline: {0: const TimelineExposure.drawing(FrameId('wave-f'), length: 12)},
  audioClips: const [
    AudioClip(filePath: 'voice.wav', frameId: FrameId('wave-f')),
  ],
);

void main() {
  testWidgets('timeline SE row paints the clip waveform and the context '
      'menu removes it', (tester) async {
    final removed = <(LayerId, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePanel(
            layers: [_seLayer()],
            activeLayerId: null,
            frameCursor: ValueNotifier<int>(0),
            playbackFrameCount: 48,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            orientation: TimelineOrientation.horizontal,
            onOrientationChanged: (_) {},
            projectFrameRate: const ProjectFrameRate.integer(24),
            // Classic zoom: this file's pixel oracles assume 48 px/frame.
            pixelsPerFrame: 48,
            audioPeaksFor: (path) => path == 'voice.wav' ? _peaks : null,
            audioLane: TimelineAudioLaneCallbacks(
              onRemoveClip: (layerId, clipIndex) =>
                  removed.add((layerId, clipIndex)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final strip = find.byKey(
      const ValueKey<String>('timeline-audio-clip-wave-se-0-b0'),
    );
    expect(strip, findsOneWidget);
    // The block is the window: [0, 12) of the 24-frame file at 48 px/frame.
    expect(tester.getSize(strip).width, moreOrLessEquals(12 * 48));

    // The strip is wider than the viewport — long-press a visible spot
    // near its left edge instead of the (offscreen) center.
    await tester.longPressAt(tester.getTopLeft(strip) + const Offset(30, 10));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('audio-clip-menu-remove')),
    );
    await tester.pumpAndSettle();
    expect(removed, [(const LayerId('wave-se'), 0)]);
  });

  testWidgets('the storyboard SE row paints the TRACK layer\'s waveform '
      'clamped at the block (cut ends no longer clip)', (tester) async {
    final project = Project(
      id: const ProjectId('wave-project'),
      name: 'Wave',
      createdAt: DateTime.utc(2026, 7, 8),
      tracks: [
        Track(
          id: const TrackId('wave-track'),
          name: 'Video',
          // SE rows are TRACK-owned: the 12-frame block windows the
          // 24-frame file regardless of the cut's 12-frame duration.
          seLayers: [_seLayer()],
          cuts: [
            Cut(
              id: const CutId('wave-cut'),
              name: 'Wave Cut',
              duration: 12,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: const [],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: project,
            activeCutId: const CutId('wave-cut'),
            pixelsPerFrame: 8,
            projectFrameRate: const ProjectFrameRate.integer(24),
            audioPeaksFor: (path) => path == 'voice.wav' ? _peaks : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final strip = find.byKey(
      const ValueKey<String>('storyboard-audio-clip-wave-se-0-b0'),
    );
    expect(strip, findsOneWidget);
    expect(tester.getSize(strip).width, moreOrLessEquals(12 * 8));
  });
}
