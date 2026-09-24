import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_exposure.dart';
import '../timeline/timeline_beat_lines.dart' show TimelineGridLaw;
import '../timeline/timeline_cell_exposure_state.dart';
import '../timeline/timeline_frame_geometry.dart';
import '../timeline/timeline_frame_span_layout.dart';
import '../timeline/timeline_instruction_row_visual.dart';
import '../timeline/timeline_row_cells_painter.dart';
import '../timeline/timeline_se_row_visual.dart';

/// Live preview inside the instance-edit dialogs: a synthetic block on up
/// to [maxKoma] frames rendered through the REAL row code — the timeline's
/// own row painter for the paper, and the SE/instruction overlays — so the
/// dialog shows exactly what the timeline will. [axis] follows the current
/// timeline orientation — horizontal in the timeline, vertical in the
/// X-sheet — and a wider (or taller) dialog shows more koma via
/// LayoutBuilder.
///
/// 🚨The paper came from a widget of its own (`TimelineFrameCell`) until
/// 2026-09-24 — a twin of the painted rows that had kept the per-cell border
/// D32/D38 took off them, so this block wore a box round every koma that no
/// timeline block wears, and it ignored the block-frame-lines switch (유저
/// 2026-09-24) the rows answer. It asks the row painter now, under a grid
/// law of its own, like any other host.
class InstanceEditPreview extends StatefulWidget {
  const InstanceEditPreview.se({
    super.key,
    required this.axis,
    required String dialogue,
    required String seName,
  }) : _kind = LayerKind.se,
       _dialogue = dialogue,
       _seName = seName,
       _event = null,
       _defById = null;

  const InstanceEditPreview.instruction({
    super.key,
    required this.axis,
    required InstructionEvent event,
    required CameraInstructionDef? Function(String instructionId) defById,
  }) : _kind = LayerKind.instruction,
       _dialogue = '',
       _seName = '',
       _event = event,
       _defById = defById;

  final Axis axis;
  final LayerKind _kind;
  final String _dialogue;
  final String _seName;
  final InstructionEvent? _event;
  final CameraInstructionDef? Function(String instructionId)? _defById;

  static const int maxKoma = 6;
  static const double komaExtent = 44;
  static const double crossExtent = 52;
  static const double _verticalMainBudget = 240;

  Layer _previewLayer(int komaCount) {
    const frameId = FrameId('instance-preview-frame');
    return switch (_kind) {
      LayerKind.se => Layer(
        id: const LayerId('instance-preview'),
        name: 'preview',
        kind: LayerKind.se,
        frames: [
          Frame(
            id: frameId,
            duration: komaCount,
            strokes: const [],
            name: _dialogue,
            seName: _seName.isEmpty ? null : _seName,
          ),
        ],
        timeline: {0: TimelineExposure.drawing(frameId, length: komaCount)},
      ),
      _ => Layer(
        id: const LayerId('instance-preview'),
        name: 'preview',
        kind: LayerKind.instruction,
        frames: const [],
        timeline: const {},
        instructions: {0: _event!.copyWith(length: komaCount)},
      ),
    };
  }

  @override
  State<InstanceEditPreview> createState() => _InstanceEditPreviewState();
}

class _InstanceEditPreviewState extends State<InstanceEditPreview> {
  /// The koma strip's frame axis, republished per layout — the row painter
  /// reads its geometry through a handle, as it does in the timeline.
  final TimelineFrameGeometryHandle _geometry = TimelineFrameGeometryHandle(
    const TimelineFrameGeometry(
      frameCellExtent: InstanceEditPreview.komaExtent,
      frameStartIndex: 0,
      frameEndIndexExclusive: 0,
    ),
  );

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const komaExtent = InstanceEditPreview.komaExtent;
    const crossExtent = InstanceEditPreview.crossExtent;
    final axis = widget.axis;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mainBudget = axis == Axis.horizontal
            ? constraints.maxWidth
            : InstanceEditPreview._verticalMainBudget;
        final komaCount = (mainBudget / komaExtent).floor().clamp(
          2,
          InstanceEditPreview.maxKoma,
        );
        final layer = widget._previewLayer(komaCount);
        final geometry = TimelineFrameGeometry(
          frameCellExtent: komaExtent,
          frameStartIndex: 0,
          frameEndIndexExclusive: komaCount,
        );
        _geometry.value = geometry;

        // The synthetic block always covers [0, komaCount). An instruction
        // row's band reads the layer's own event; this answers the SE's.
        TimelineCellExposureState stateAt(Layer layer, int frameIndex) {
          if (frameIndex < 0 || frameIndex >= komaCount) {
            return TimelineCellExposureState.uncovered;
          }
          return frameIndex == 0
              ? TimelineCellExposureState.drawingStart
              : TimelineCellExposureState.held;
        }

        final overlays = widget._kind == LayerKind.se
            ? timelineRowSeLabelOverlays(
                layer: layer,
                frameStartIndex: 0,
                frameEndIndexExclusive: komaCount,
                axis: axis,
                keyPrefix: 'instance-preview',
              )
            : timelineRowInstructionOverlays(
                layer: layer,
                frameStartIndex: 0,
                frameEndIndexExclusive: komaCount,
                axis: axis,
                defById: widget._defById!,
                keyPrefix: 'instance-preview',
              );

        final mainExtent = komaCount * komaExtent;
        return Align(
          alignment: Alignment.centerLeft,
          child: IgnorePointer(
            child: SizedBox(
              key: const ValueKey<String>('instance-edit-preview'),
              width: axis == Axis.horizontal ? mainExtent : crossExtent,
              height: axis == Axis.horizontal ? crossExtent : mainExtent,
              // A host of its own: no known ground under a dialog, and the
              // koma strip counts from frame 0 with no fps to weight by.
              child: TimelineGridLaw(
                ground: null,
                framesPerSecond: 0,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Builder(
                        builder: (context) {
                          final law = TimelineGridLaw.maybeOf(context)!;
                          return CustomPaint(
                            key: const ValueKey<String>(
                              'instance-preview-cells',
                            ),
                            painter: TimelineRowCellsPainter(
                              layer: layer,
                              geometry: _geometry,
                              crossAxisExtent: crossExtent,
                              exposureStateForLayer: stateAt,
                              colorScheme: Theme.of(context).colorScheme,
                              baseTextStyle: DefaultTextStyle.of(
                                context,
                              ).style,
                              axis: axis,
                              paperGround: law.ground,
                              blockFrameLines: law.blockFrameLines,
                              framesPerSecond: law.framesPerSecond,
                            ),
                          );
                        },
                      ),
                    ),
                    // The span overlays place themselves off the frame
                    // geometry (the timeline's own mechanism); the preview
                    // hands them the koma strip's.
                    Positioned.fill(
                      child: TimelineFixedFrameSpanLayer(
                        geometry: geometry,
                        crossAxisExtent: crossExtent,
                        axis: axis,
                        children: overlays,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
