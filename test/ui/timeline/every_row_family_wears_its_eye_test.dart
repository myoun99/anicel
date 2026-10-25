import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show TimelineGridLaw;
import 'package:anicel/src/ui/timeline/timeline_block_look.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineDrawingInkColor;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart'
    show SeSpanVisual;

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️I-129 (유저 2026-10-25): 「타임라인, 엑스시트, 콘티패널 등 모든
/// 가족에 적용」 — every family of row on both of the timeline's faces, as
/// the app mounts it: a row whose own eye is off and a row a folder above
/// hides wear the switched-off look on their blocks, their numbers and the
/// words laid on them; a shown row beside them does not.
void main() {
  const finish = LayerMark(process: LayerProcess.finish);

  /// A row [id] with one block over frames 0–3 — an SE row's carrying the
  /// line 「ガチャ」.
  Layer row(
    String id, {
    LayerKind kind = LayerKind.animation,
    bool isVisible = true,
    String? inside,
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    mark: finish,
    isVisible: isVisible,
    folderId: inside == null ? null : LayerId(inside),
    frames: [
      Frame(
        id: FrameId('$id-1'),
        duration: 1,
        strokes: const [],
        name: kind == LayerKind.se ? 'ガチャ' : null,
      ),
    ],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-1'), length: 4)},
  );

  Project film() => Project(
    id: const ProjectId('eyes'),
    name: 'Eyes',
    createdAt: DateTime.utc(2026, 10, 25),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V1',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'c',
            duration: 24,
            canvasSize: const CanvasSize(width: 320, height: 180),
            layers: [
              row('shown'),
              row('own-eye-off', isVisible: false),
              row('in-folder', inside: 'F'),
              Layer(
                id: const LayerId('F'),
                name: 'F',
                kind: LayerKind.folder,
                isVisible: false,
                frames: const [],
                timeline: const {},
              ),
              row('se-shown', kind: LayerKind.se),
              row('se-off', kind: LayerKind.se, isVisible: false),
            ],
          ),
        ],
      ),
    ],
  );

  for (final orientation in TimelineOrientation.values) {
    testWidgets('${orientation.name}: each row wears its eye', (tester) async {
      await pumpTimelineHost(tester, film(), orientation: orientation);
      final prefix = orientation == TimelineOrientation.vertical
          ? 'xsheet'
          : 'timeline';

      for (final (id, shown) in [
        ('shown', true),
        ('own-eye-off', false),
        ('in-folder', false),
        ('se-shown', true),
        ('se-off', false),
      ]) {
        final row = tester.widget<CustomPaint>(
          find.named('$prefix-row-cells-$id'),
        );
        final cells = row.painter! as TimelineRowCellsPainter;
        expect(cells.shown, shown, reason: '$id: its blocks');
        final labels = row.foregroundPainter! as TimelineRowRunLabelsPainter;
        expect(labels.shown, shown, reason: '$id: its numbers');
      }

      // The words an SE block carries are ink on it, in its look.
      for (final (id, shown) in [('se-shown', true), ('se-off', false)]) {
        final span = find.byWidgetPredicate(
          (widget) => widget is SeSpanVisual && widget.layer.id == LayerId(id),
        );
        final words = tester.widget<DialogueFitText>(
          find.descendant(of: span, matching: find.byType(DialogueFitText)),
        );
        final look = timelineBlockLook(
          shown ? TimelineBlockState.shown : TimelineBlockState.hidden,
          paper: layerMarkColor(finish),
          ink: timelineDrawingInkColor,
          ground: TimelineGridLaw.maybeOf(tester.element(span))?.ground,
        );
        expect(words.color, look.ink, reason: id);
        expect(
          words.color == timelineDrawingInkColor,
          shown,
          reason: '⛔전제: $id — the switched-off words are not the shown ones',
        );
      }
    });
  }
}
