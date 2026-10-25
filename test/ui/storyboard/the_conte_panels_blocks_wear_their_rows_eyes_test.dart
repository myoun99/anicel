import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
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
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackTransitionLayer, transitionLayerIdForTrack;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show TimelineGridLaw, timelineGridGroundOver;
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart'
    show SePaperSpan;

import '../../helpers/storyboard_host.dart';
import '../storyboard_conte_row_probe.dart';

/// 🗣️I-129 (유저 2026-10-25): 「타임라인, 엑스시트, 콘티패널 등 모든
/// 가족에 적용」 — the conte panel's blocks wear their rows' eyes as the
/// timeline's do: the conte row its head's — the one eye a track's conte
/// lays on its row in every cut — and the S rows their own.
void main() {
  const trackId = TrackId('t1');
  const conteMark = LayerMark(process: LayerProcess.conte);
  const seMark = LayerMark(process: LayerProcess.finish);

  Layer conte(String cut, {required bool isVisible}) => Layer(
    id: LayerId('$cut-conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    mark: conteMark,
    isVisible: isVisible,
    frames: [Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
    },
  );

  Cut cutOf(String id, Layer conte) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [conte],
  );

  /// Cuts `a` and `b`, each with a conte shown as [conteShown] says, an S
  /// row with one block, shown as [seShown] says, and an O.L on the
  /// transition row, shown as [transitionShown] says.
  Project film({
    bool conteShown = true,
    bool seShown = true,
    bool transitionShown = true,
  }) => Project(
    id: const ProjectId('eyes'),
    name: 'Eyes',
    createdAt: DateTime.utc(2026, 10, 25),
    tracks: [
      Track(
        id: trackId,
        name: 'V1',
        transitionLayer: createTrackTransitionLayer(trackId).copyWith(
          isVisible: transitionShown,
          instructions: const {
            8: InstructionEvent(instructionId: 'ol', length: 5),
          },
        ),
        seLayers: [
          Layer(
            id: const LayerId('s1'),
            name: 'S1',
            kind: LayerKind.se,
            mark: seMark,
            isVisible: seShown,
            frames: [
              Frame(id: const FrameId('s'), duration: 6, strokes: const []),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('s'), length: 6),
            },
          ),
        ],
        cuts: [
          cutOf('a', conte('a', isVisible: conteShown)),
          cutOf('b', conte('b', isVisible: conteShown)),
        ],
      ),
    ],
  );

  Color off(Color painted, {required Color? under}) => timelineGridGroundOver(
    under: under,
    painted: painted.withValues(alpha: painted.a * AppColors.offAlpha),
  )!;

  for (final conteShown in [true, false]) {
    testWidgets('the conte row wears its head\'s eye over every cut — its '
        'paper and its numbers — ${conteShown ? 'shown' : 'hidden'}', (
      tester,
    ) async {
      await pumpStoryboardHost(
        tester,
        film(conteShown: conteShown),
        pixelsPerFrame: 12,
      );

      final painter = conteRowPainter(tester, trackId.value);
      expect(painter.shown, conteShown);
      // Its panels hold no picture yet: 「꺼진 행의 빈블록은 말한 빈블록이랑
      // 동일하게」 — the hollow block, shown or hidden.
      for (final frame in [2, 14]) {
        expect(
          painter.resolvedCellStyleFor(frame).background,
          painter.paperGround,
          reason: '@$frame — cut ${frame < 12 ? 'a' : 'b'}',
        );
      }
      expect(
        runLabels(tester, '${trackConteRowId(trackId)}').shown,
        conteShown,
        reason: 'its numbers, as its blocks',
      );
    });
  }

  for (final seShown in [true, false]) {
    testWidgets('an S row\'s paper is its colour label in its look — '
        '${seShown ? 'shown' : 'hidden'}', (tester) async {
      await pumpStoryboardHost(tester, film(seShown: seShown));

      final span = find.descendant(
        of: find.byKey(const ValueKey<String>('storyboard-se-paper-s1-0')),
        matching: find.byType(SePaperSpan),
      );
      final label = layerMarkColor(seMark);
      final ground = TimelineGridLaw.maybeOf(tester.element(span))?.ground;
      expect(
        tester.widget<SePaperSpan>(span).paper,
        seShown ? label : off(label, under: ground),
      );
      expect(
        runLabels(tester, 's1').shown,
        seShown,
        reason: 'its numbers, as its blocks',
      );
    });
  }

  for (final transitionShown in [true, false]) {
    testWidgets('the transition row\'s paper is its colour label in its '
        'look — ${transitionShown ? 'shown' : 'hidden'}', (tester) async {
      await pumpStoryboardHost(tester, film(transitionShown: transitionShown));

      final row = transitionLayerIdForTrack(trackId);
      final span = find.descendant(
        of: find.byKey(
          ValueKey<String>('storyboard-transition-paper-$row-8'),
        ),
        matching: find.byType(SePaperSpan),
      );
      final label = layerMarkColor(createTrackTransitionLayer(trackId).mark);
      final ground = TimelineGridLaw.maybeOf(tester.element(span))?.ground;
      expect(
        tester.widget<SePaperSpan>(span).paper,
        transitionShown ? label : off(label, under: ground),
      );
      expect(
        runLabels(tester, '$row').shown,
        transitionShown,
        reason: 'its numbers, as its blocks',
      );
    });
  }
}

/// The painter that numbers row [rowId]'s blocks in the conte panel.
TimelineRowRunLabelsPainter runLabels(WidgetTester tester, String rowId) =>
    tester
            .widget<CustomPaint>(
              find.byKey(ValueKey<String>('storyboard-run-labels-$rowId')),
            )
            .foregroundPainter!
        as TimelineRowRunLabelsPainter;
