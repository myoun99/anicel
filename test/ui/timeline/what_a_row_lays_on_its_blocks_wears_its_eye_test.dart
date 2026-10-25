import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/waveform_painter.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_block_look.dart';
import 'package:anicel/src/ui/timeline/timeline_block_word.dart'
    show TimelineBlockText;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineDrawingInkColor;
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_span_name.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// 🗣️I-129 (유저 2026-10-25): 「이 비지블시 비활성화색은 키던
/// 프레임블록이던 동일하게 법통일해서」 — what a row lays over its blocks
/// wears the row's eye as its blocks do: an instruction span's mark, its
/// name and its words, an SE row's waveform, and the name of the camera's
/// move between two keys. Each is pumped on its own, so the row's own eye
/// is what answers ([RailEyes.of]).
void main() {
  const cellExtent = 48.0;
  const crossExtent = 30.0;

  /// The look [layer]'s row lays [ink] in, shown or hidden.
  TimelineBlockLook lookOf(
    Layer layer, {
    required bool shown,
    required Color ink,
  }) => timelineBlockLook(
    shown ? TimelineBlockState.shown : TimelineBlockState.hidden,
    paper: layerMarkColor(layer.mark),
    ink: ink,
  );

  Future<void> pumpSpans(
    WidgetTester tester,
    int cells,
    List<Widget> Function(BuildContext context) spans,
  ) => tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: cellExtent * cells,
        height: crossExtent,
        child: Builder(
          builder: (context) => TimelineFixedFrameSpanLayer(
            geometry: TimelineFrameGeometry(
              frameCellExtent: cellExtent,
              frameStartIndex: 0,
              frameEndIndexExclusive: cells,
            ),
            crossAxisExtent: crossExtent,
            axis: Axis.horizontal,
            children: spans(context),
          ),
        ),
      ),
    ),
  );

  for (final shown in [true, false]) {
    final state = shown ? 'shown' : 'hidden';

    testWidgets('$state: an instruction span\'s mark, its name and its '
        'words', (tester) async {
      final layer = Layer(
        id: const LayerId('cam-1'),
        name: 'CAM 1',
        kind: LayerKind.instruction,
        isVisible: shown,
        frames: const [],
        timeline: const {},
        instructions: const {
          0: InstructionEvent(instructionId: 'pan', length: 5, valueA: 'A'),
        },
      );
      final defById = CameraInstructionSet.standard.defById;
      await pumpSpans(
        tester,
        5,
        (_) => timelineRowInstructionOverlays(
          layer: layer,
          frameStartIndex: 0,
          frameEndIndexExclusive: 5,
          axis: Axis.horizontal,
          defById: defById,
        ),
      );
      final span = find.byKey(
        const ValueKey<String>('timeline-instruction-cam-1-0'),
      );

      final termInk = timelineInstructionInk(defById('pan'));
      final mark = lookOf(layer, shown: shown, ink: termInk).ink;
      final painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: span,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    '${widget.painter.runtimeType}' ==
                        '_InstructionMarkPainter',
              ),
            ),
          )
          .painter;
      expect((painter as dynamic).color, mark, reason: 'its mark');
      final name = tester.widget<TimelineSpanName>(
        find.descendant(of: span, matching: find.byType(TimelineSpanName)),
      );
      expect(name.ink, mark, reason: 'its name');
      final words = lookOf(
        layer,
        shown: shown,
        ink: timelineDrawingInkColor,
      ).ink;
      expect(
        tester
            .widget<TimelineBlockText>(
              find.descendant(
                of: span,
                matching: find.byWidgetPredicate(
                  (widget) => widget is TimelineBlockText && widget.text == 'A',
                ),
              ),
            )
            .style
            .color,
        words,
        reason: 'its A word',
      );
      expect(
        (mark == termInk, words == timelineDrawingInkColor),
        (shown, shown),
        reason: '⛔전제: the switched-off ink is not the shown one',
      );
    });

    testWidgets('$state: an SE row\'s waveform', (tester) async {
      final layer = Layer(
        id: const LayerId('se-1'),
        name: 'S1',
        kind: LayerKind.se,
        isVisible: shown,
        frames: const [],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('f0'), length: 3),
        },
        audioClips: [
          AudioClip(filePath: 'take.wav', frameId: const FrameId('f0')),
        ],
      );
      final peaks = AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160));
      await pumpSpans(
        tester,
        3,
        (context) => timelineRowAudioOverlays(
          context,
          layer: layer,
          frameStartIndex: 0,
          frameEndIndexExclusive: 3,
          axis: Axis.horizontal,
          frameRate: ProjectFrameRate.fps24,
          audioPeaksFor: (_) => peaks,
        ),
      );

      final waveform =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is CustomPaint &&
                          widget.painter is WaveformPainter,
                    ),
                  )
                  .painter!
              as WaveformPainter;
      final ink = lookOf(layer, shown: shown, ink: timelineSeWaveformInk).ink;
      expect(waveform.color, ink);
      expect(
        ink == timelineSeWaveformInk,
        shown,
        reason: '⛔전제: the switched-off ink is not the shown one',
      );
    });

    testWidgets('$state: the name of the camera\'s move, in its keys\' '
        'colour', (tester) async {
      final layer = Layer(
        id: const LayerId('camera'),
        name: 'Camera',
        kind: LayerKind.camera,
        isVisible: shown,
        frames: const [],
      );
      CameraPose at(double x) =>
          CameraPose(center: CanvasPoint(x: x, y: 0), zoom: 1);
      final spans = timelineUnionKeyMarkerSpans(
        keyPrefix: 'timeline',
        layer: layer,
        lane: cameraUnionHeader(
          CutCamera(keyframes: {2: at(0), 8: at(30)}).track,
          defById: CameraInstructionSet.standard.defById,
        ),
        crossExtent: crossExtent,
        axis: Axis.horizontal,
      ).cast<TimelineFrameSpan>();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: cellExtent * 7,
            height: crossExtent,
            child: spans[1].child,
          ),
        ),
      );

      final paper = lookOf(
        layer,
        shown: shown,
        ink: timelineDrawingInkColor,
      ).paper!;
      final name = tester.widget<TimelineSpanName>(
        find.byType(TimelineSpanName),
      );
      expect(name.ink, paper);
      expect(
        paper == layerMarkColor(layer.mark),
        shown,
        reason: '⛔전제: the switched-off colour is not the shown one',
      );
    });
  }
}
