import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/rail_eyes.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineGridGroundOver;
import 'package:anicel/src/ui/timeline/timeline_block_look.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneKeyMarker;

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';
import '../timeline/timeline_row_chrome_probe.dart';

/// 🗣️I-129-Q1 (유저 2026-10-25 「셋 다 같은 법으로 흐린다」 — 투영 키는 폴더
/// 숨김도 본다(블록과 같은 판정)) and 🗣️I-129 (10-25 23:33 「빈 블록이면
/// 엣지가 검정색이라 엣지가 안보이니, 엣지 회색으로」): on the conte panel,
/// the conte row's grips stand on its blocks as the row draws them — its
/// head's eye, its empty panels' grey — and the keys it projects wear that
/// eye too, a folder's hide included.
void main() {
  const trackId = TrackId('t1');
  const shut = LayerId('shut');
  const conteMark = LayerMark(process: LayerProcess.conte);

  TransformTrack positions(List<int> frames) {
    var position = PropertyTrack<CanvasPoint>.empty();
    for (final frame in frames) {
      position = position.withKey(frame, CanvasPoint(x: 10.0 * frame, y: 0));
    }
    return TransformTrack.empty().copyWith(position: position);
  }

  /// Cuts `a` and `b`, each with a conte keyed at its own 2 and 8, whose
  /// panels hold no picture yet — `a`'s, the head's, in a folder that is
  /// shut as [folderShown] says.
  Project film({required bool folderShown}) {
    Layer conte(String cut, {LayerId? folderId}) => Layer(
      id: LayerId('$cut-conte'),
      name: 'Conte',
      kind: LayerKind.storyboard,
      mark: conteMark,
      folderId: folderId,
      transformTrack: positions([2, 8]),
      frames: [
        Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const []),
      ],
      timeline: {
        0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
      },
    );
    Cut cutOf(String id, List<Layer> layers) => Cut(
      id: CutId(id),
      name: id,
      duration: 12,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: layers,
    );
    return Project(
      id: const ProjectId('grips-and-keys'),
      name: 'Grips and keys',
      createdAt: DateTime.utc(2026, 10, 26),
      tracks: [
        Track(
          id: trackId,
          name: 'V1',
          cuts: [
            cutOf('a', [
              conte('a', folderId: shut),
              createFolderLayer(
                id: shut,
                name: 'shut',
              ).copyWith(isVisible: folderShown),
            ]),
            cutOf('b', [conte('b')]),
          ],
        ),
      ],
    );
  }

  for (final folderShown in [true, false]) {
    final state = folderShown ? 'open' : 'shut';

    testWidgets('folder $state: the conte row\'s grips stand on its blocks '
        'as the row draws them — the head\'s eye, the empty panels\' grey', (
      tester,
    ) async {
      await pumpStoryboardHost(
        tester,
        film(folderShown: folderShown),
        pixelsPerFrame: 12,
      );

      final painter = timelineRowChromePainter(
        tester,
        trackId.value,
        prefix: 'storyboard',
      )!;
      final row = painter.gripRow!;
      expect(row.shown, folderShown, reason: 'the head\'s eye, folder and all');
      expect(row.content, isNotNull, reason: 'the cels it asks');

      final canvas = TestRecordingCanvas();
      painter.paint(
        canvas,
        tester.getSize(
          timelineRowChromeFinder(trackId.value, prefix: 'storyboard'),
        ),
      );
      final inks = {
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawPath)
            (call.invocation.positionalArguments[1] as Paint).color.toARGB32(),
      };
      // No panel holds a picture: every grip is an empty block's, on any
      // row (「꺼진 행의 빈블록은 말한 빈블록이랑 동일하게」).
      expect(inks, {
        timelineGridGroundOver(
          under: row.ground,
          painted: timelineEmptyBlockGrey,
        )!.toARGB32(),
      });
      final black = blockEdgeGripColor(
        BlockEdgeGripInk.rest,
        ground: painter.gripGround,
      );
      expect(
        inks,
        isNot(contains(black.toARGB32())),
        reason: '⛔전제: not the black its paper picks',
      );
    });

    testWidgets('folder $state: the keys the conte row projects wear its '
        'head\'s eye in every cut — a folder\'s hide included', (
      tester,
    ) async {
      await pumpStoryboardHost(
        tester,
        film(folderShown: folderShown),
        surface: const Size(1600, 1000),
        pixelsPerFrame: 12,
      );
      await tester.tap(find.named('storyboard-lane-toggle-a-conte'));
      await tester.pumpAndSettle();

      final marks = find.byType(TimelineLaneKeyMarker);
      final layers = {
        for (final element in marks.evaluate())
          (element.widget as TimelineLaneKeyMarker).layer.id,
      };
      expect(
        layers,
        {const LayerId('a-conte'), const LayerId('b-conte')},
        reason: 'premise: both cuts\' keys are projected',
      );
      for (final element in marks.evaluate()) {
        final layer = (element.widget as TimelineLaneKeyMarker).layer;
        expect(
          RailEyes.of(element, layer).shown,
          folderShown,
          reason: '${layer.id}',
        );
        expect(
          timelineRowLookOf(element, layer).paper == layerMarkColor(conteMark),
          folderShown,
          reason: '${layer.id}: its mark\'s colour',
        );
      }
    });
  }
}
