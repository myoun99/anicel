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
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineBlockCornerRadiusAt;

import '../storyboard_cut_block_probe.dart';

/// 🗣️F-248 (유저 2026-09-30 「외곽라인말고 블럭을 바탕색으로서 강조색 표시.
/// 전처럼 연하게」, 10-01 「재생헤드가 선 블록」), on the conte: the unit you
/// stand on wears the standing wash — an S row's sound, the one cell beside
/// it, a lane's cell — and the V row's cut wears it on its bands instead
/// (`storyboard_cut_block_bands_test`), never over its pictures. One
/// standing place: on an S row, the S row's block alone (유저 10-01 「s행에서면
/// s행블록만 칠해지도록」).
///
/// 🗣️F-268 (유저 2026-10-03): 「블록에선 블록이 꼭짓점 둥그니까 괜찮은데 빈칸은
/// 각진 사각형이기때문에 그에맞춰 사각형으로 칠하도록」 — and it wears the SHAPE
/// of what it stands on: a sound's or a span's corner, a cell's square.
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
              // Two panels: [0, 3) and [3, 8).
              Layer(
                id: const LayerId('sb'),
                name: 'SB',
                kind: LayerKind.storyboard,
                frames: [
                  for (final id in ['p-1', 'p-2'])
                    Frame(id: FrameId(id), duration: 1, strokes: const []),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('p-1'), length: 3),
                  3: TimelineExposure.drawing(FrameId('p-2'), length: 5),
                },
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

  /// The corner the wash wears, and the one a BLOCK of its own cells wears.
  BorderRadiusGeometry? corner(WidgetTester tester) =>
      (tester.widget<DecoratedBox>(wash).decoration as BoxDecoration)
          .borderRadius;
  BorderRadius blockCorner(WidgetTester tester) => BorderRadius.all(
    timelineBlockCornerRadiusAt(
      cellExtent: playhead(tester).width,
      crossExtent: tester.getRect(wash).height,
    ),
  );

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
    expect(
      cutBlocksPainter(tester).blocks().single.isStanding,
      isFalse,
      reason: 'one standing place — the V row\'s cut wears none',
    );
    expect(corner(tester), blockCorner(tester), reason: 'a sound is round');
    expect(blockCorner(tester), isNot(BorderRadius.zero), reason: '⛔전제');

    session.selectGlobalFrame(5);
    await tester.pumpAndSettle();
    expect(washed(tester, 5).start, 5);
    expect(washed(tester, 5).end, 6);
    expect(corner(tester), BorderRadius.zero, reason: 'F-268: 빈칸은 각지게');
  });

  testWidgets('a stand on another row repaints the V row at once — its '
      'bands let go of the wash', (tester) async {
    final session = await openConte(tester);
    final render = tester.renderObject(cutBlocksFinder());
    expect(render.debugNeedsPaint, isFalse, reason: 'premise: settled');
    session.standing.selectRow(const LayerRowAddress(LayerId('se-row-1')));
    expect(render.debugNeedsPaint, isTrue);
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
    expect(corner(tester), blockCorner(tester));

    session.selectGlobalFrame(2);
    await tester.pumpAndSettle();
    expect(washed(tester, 2).end - washed(tester, 2).start, 1);
    expect(corner(tester), BorderRadius.zero, reason: 'F-268: beside it');
  });

  testWidgets('on the V row, nothing over its pictures — the cut under the '
      'playhead wears it on its bands', (tester) async {
    await openConte(tester);
    expect(
      find.byKey(const ValueKey<String>('storyboard-standing-cell')),
      findsOneWidget,
      reason: 'premise: the rail rests on the V row and stands there',
    );
    expect(wash, findsNothing);
    expect(cutBlocksPainter(tester).blocks().single.isStanding, isTrue);
  });

  // 🗣️I-73 (유저 2026-10-08: 「콘티행에 서야 콘티행에 서도록」): the conte row
  // is a row of its own, and its panel is the block you stand on there.
  testWidgets('on the conte row, its panel — and the cut above it wears '
      'none', (tester) async {
    final session = await openConte(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('storyboard-conte-label-sb-track')),
    );
    await tester.pumpAndSettle();
    session.selectGlobalFrame(4);
    await tester.pumpAndSettle();

    expect(washed(tester, 4), (
      start: 3,
      end: 8,
      row: rowOf(tester, 'storyboard-conte-row-sb-track'),
    ));
    expect(corner(tester), blockCorner(tester), reason: 'a frame block');
    expect(
      cutBlocksPainter(tester).blocks().single.isStanding,
      isFalse,
      reason: 'one standing place — the V row\'s cut wears none',
    );

    session.selectGlobalFrame(1);
    await tester.pumpAndSettle();
    expect(washed(tester, 1).start, 0);
    expect(washed(tester, 1).end, 3);
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
    expect(corner(tester), BorderRadius.zero, reason: 'F-268: a lane\'s cell');
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
