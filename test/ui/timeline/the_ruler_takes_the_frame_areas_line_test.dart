import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';

import '../../helpers/raster_parity.dart';

/// 🚨D8-2 (유저 2026-08-22) — **A STANDING LAW, NOT ONE INSTRUCTION.**
///
/// > 「프레임영역 왼쪽 선 좋은데 **룰러도 통일.** 프레임영역은 **기본 뭔가
/// > 바뀌면 룰러랑 통일**임」
///
/// D8 gave the frame area a leading hairline and the ruler did not get one,
/// because the two are built by two sibling `Expanded`s in two different
/// Rows and only one of them wore the decoration. The line is a WIDGET now
/// ([TimelineFrameAreaEdge]) so there is nothing to keep in step by hand.
///
/// ⚠️Asserting "two wearers exist" is what makes this a law rather than a
/// repair: a future edit that adds the line to one area alone fails here.
void main() {
  Project project() => Project(
    id: const ProjectId('edge-project'),
    name: 'Edge',
    createdAt: DateTime.utc(2026, 8, 22),
    tracks: [
      Track(
        id: const TrackId('edge-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('edge-cut'),
            name: '1',
            duration: 12,
            canvasSize: const CanvasSize(width: 320, height: 180),
            layers: [
              Layer(
                id: const LayerId('edge-cel'),
                name: 'A',
                frames: [
                  Frame(
                    id: const FrameId('edge-f1'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('edge-f1'), length: 4),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  testWidgets('the ruler and the rows wear the SAME leading edge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();

    final edges = find.byType(TimelineFrameAreaEdge);
    expect(
      edges,
      findsNWidgets(2),
      reason: 'one for the sticky header (the ruler) and one for the body '
          '(the rows) — 「프레임영역은 기본 뭔가 바뀌면 룰러랑 통일임」',
    );

    // And they stand in the same column: the line marks where the frames
    // begin, so two different x positions would be two different lines.
    final rects = [
      for (var i = 0; i < 2; i += 1) tester.getRect(edges.at(i)),
    ];
    expect(
      rects[0].left,
      moreOrLessEquals(rects[1].left, epsilon: 0.5),
      reason: 'the ruler sits directly above the rows, so its leading edge '
          'is the same vertical line continued upward',
    );
  });

  testWidgets('and it is drawn OVER the area, taking no layout room', (
    tester,
  ) async {
    const ground = Color(0xFFE53935);
    await pumpSurface(
      tester,
      const TimelineFrameAreaEdge(child: ColoredBox(color: ground)),
      left: 20,
      width: 100,
      height: 50,
    );
    final edge = find.byType(TimelineFrameAreaEdge);
    expect(
      tester.getRect(
        find.descendant(of: edge, matching: find.byType(ColoredBox)),
      ),
      tester.getRect(edge),
      reason: 'a line over the area cannot shift the LayoutBuilder underneath '
          'it — this is the half that keeps the viewport width honest',
    );

    final bytes = await captureBytes(tester);
    expect(
      capturePixelAt(tester, bytes, const Offset(20.5, 45)),
      Theme.of(tester.element(edge)).colorScheme.outlineVariant,
      reason: 'the area\'s first column is the line, over what the area '
          'draws there',
    );
    expect(
      capturePixelAt(tester, bytes, const Offset(25, 45)),
      ground,
      reason: '⛔premise: the area is drawn',
    );
  });
}
