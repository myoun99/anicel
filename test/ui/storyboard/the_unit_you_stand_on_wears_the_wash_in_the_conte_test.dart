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
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackTransitionLayer;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;

import '../storyboard_cut_block_probe.dart';

/// 🗣️F-248 (유저 2026-09-30 「외곽라인말고 블럭을 바탕색으로서 강조색 표시.
/// 전처럼 연하게」, 10-01 「재생헤드가 선 블록」), on the conte: the unit you
/// stand on wears the standing wash — an S row's sound, the one cell beside
/// it, a lane's cell — and the V row's cut wears it in its plate instead
/// (`storyboard_cut_block_bands_test`), never over its pictures.
///
/// The timeline's half is `the_block_you_stand_on_wears_the_wash_test`.
void main() {
  const trackEffect = EffectId('sb-fx');

  Project project() => Project(
    id: const ProjectId('conte-wash'),
    name: 'Conte wash',
    createdAt: DateTime.utc(2026, 10, 1),
    tracks: [
      Track(
        id: const TrackId('sb-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-1'),
            name: 'cut-1',
            duration: 8,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: const LayerId('cel'),
                name: 'A',
                frames: const [],
                timeline: const {},
              ),
            ],
          ),
        ],
        // A span over [5, 7).
        transitionLayer: createTrackTransitionLayer(
          const TrackId('sb-track'),
        ).copyWith(
          instructions: {
            5: const InstructionEvent(instructionId: 'ol', length: 2),
          },
        ),
        effects: [
          LayerEffect(
            id: trackEffect,
            kind: EffectKind.brightnessContrast,
            parameters: {'brightness': EffectParameter(value: 0.4)},
          ),
        ],
        seLayers: [
          Layer(
            id: const LayerId('se-row-1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              Frame(
                id: const FrameId('f-one'),
                duration: 3,
                name: 'One!',
                strokes: const [],
              ),
            ],
            // A sound over [1, 4).
            timeline: const {
              1: TimelineExposure.drawing(FrameId('f-one'), length: 3),
            },
          ),
        ],
      ),
    ],
  );

  Future<EditorSessionManager> openConte(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  Future<EditorSessionManager> standOnTheSRow(WidgetTester tester) async {
    final session = await openConte(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('storyboard-se-label-sb-track-1'),
        ),
        matching: find.text('S1'),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  final wash = find.byKey(const ValueKey<String>('storyboard-standing-wash'));
  Rect playhead(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey<String>('storyboard-playhead')));

  /// The frames the wash covers, read against the playhead's cell at
  /// [frame], and the row it lies on.
  ({int start, int end, Rect row}) washed(WidgetTester tester, int frame) {
    final cell = playhead(tester).width;
    final origin = playhead(tester).left - frame * cell;
    final rect = tester.getRect(wash);
    return (
      start: ((rect.left - origin) / cell).round(),
      end: ((rect.right - origin) / cell).round(),
      row: Rect.fromLTRB(0, rect.top, 0, rect.bottom),
    );
  }

  Rect rowOf(WidgetTester tester, String key) {
    final row = tester.getRect(find.byKey(ValueKey<String>(key)));
    return Rect.fromLTRB(0, row.top, 0, row.bottom);
  }

  testWidgets('on an S row, its sound — and beside it, the one cell', (
    tester,
  ) async {
    final session = await standOnTheSRow(tester);
    session.selectGlobalFrame(2);
    await tester.pumpAndSettle();
    expect(washed(tester, 2), (
      start: 1,
      end: 4,
      row: rowOf(tester, 'storyboard-se-row-0-1'),
    ));

    session.selectGlobalFrame(5);
    await tester.pumpAndSettle();
    expect(washed(tester, 5).start, 5);
    expect(washed(tester, 5).end, 6);
  });

  testWidgets('on the transition row, its span', (tester) async {
    final session = await openConte(tester);
    session.standing.selectRow(
      LayerRowAddress(session.activeTrack.transitionLayer.id),
    );
    session.selectGlobalFrame(6);
    await tester.pumpAndSettle();
    expect(washed(tester, 6), (
      start: 5,
      end: 7,
      row: rowOf(tester, 'storyboard-transition-row-sb-track'),
    ));
  });

  testWidgets('on the V row, nothing over its pictures — the cut under the '
      'playhead wears it in its plate', (tester) async {
    await openConte(tester);
    expect(
      find.byKey(const ValueKey<String>('storyboard-standing-cell')),
      findsOneWidget,
      reason: 'premise: the rail rests on the V row and stands there',
    );
    expect(wash, findsNothing);
    expect(cutBlocksPainter(tester).blocks().single.isStanding, isTrue);
  });

  testWidgets('on a lane, its cell', (tester) async {
    await openConte(tester);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-toggle-sb-track'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-group-toggle-v-track:sb-track-'
          '${effectGroupLaneId(trackEffect)}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final laneKey =
        'storyboard-track-lane-row-0-${effectLaneId(trackEffect, 'brightness')}';
    final lane = find.byKey(ValueKey<String>(laneKey));
    await tester.ensureVisible(lane);
    await tester.pumpAndSettle();
    final laneRect = tester.getRect(lane);
    await tester.tapAt(Offset(laneRect.left + 6, laneRect.center.dy));
    await tester.pumpAndSettle();

    expect(washed(tester, 0), (start: 0, end: 1, row: rowOf(tester, laneKey)));
  });

  testWidgets('through a comma drag on the sound, the sound as it is '
      'previewed (H12)', (tester) async {
    final session = await standOnTheSRow(tester);
    session.selectGlobalFrame(2);
    await tester.pumpAndSettle();
    expect(
      session.edgeDrag.beginExposureEdgeDrag(
        layerId: const LayerId('se-row-1'),
        blockStartIndex: 1,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
      reason: 'premise: the sound is there to grab',
    );
    session.edgeDrag.updateExposureEdgeDrag(2);
    await tester.pump();
    expect(washed(tester, 2).end, 6);

    session.edgeDrag.cancelExposureEdgeDrag();
    await tester.pumpAndSettle();
  });
}
