import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️F-227 (유저 2026-09-29): 「컷ol은 두 컷이 동시에 존재하는 상태면서
/// 오버랩하는건데 아직까지도 이상한 상태임. 컷1이 fo하다가 갑자기 컷2가 fi하는
/// 상태」.
///
/// The PIXELS of the editing canvas standing inside an O.L. Paper is a green
/// sentinel and the backdrop red: the canvas used to thin the cut to the
/// BACKDROP there — a dip, half an O.L on each side of the boundary. The
/// other cut is what takes that share, and it brings its own paper.
void main() {
  const paperArgb = 0xFF00FF00;

  bool isPaper(int r, int g, int b) => g > 200 && r < 80 && b < 80;

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 320, height: 180),
    layers: [
      Layer(
        id: LayerId('row-$id'),
        name: 'A',
        frames: [Frame(id: FrameId('cel-$id'), duration: 1, strokes: const [])],
        timeline: {
          0: TimelineExposure.drawing(FrameId('cel-$id'), length: 24),
        },
      ),
    ],
  );

  /// Green paper on a red backdrop, an O.L over frames 18..29, standing on
  /// the first cut's frame 21 — a quarter of the way into the dissolve.
  /// [partnered] false leaves a gap after the first cut instead of the
  /// second, so the O.L closes onto nothing.
  EditorSessionManager standingInAnOl({required bool partnered}) {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [
              cut('a'),
              if (partnered)
                cut('b')
              else
                cut('b').copyWith(leadingGapFrames: 48),
            ],
          ),
        ],
      ),
    );
    s.projectSettings.setProjectBackground(
      const ProjectBackground.color(paperArgb),
    );
    s.projectSettings.setProjectBackdrop(0xFFFF0000);
    s.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    s.selectFrameIndex(21);
    return s;
  }

  Future<void> pumpArea(WidgetTester tester, EditorSessionManager s) async {
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(false);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: s,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// How many pixels of the canvas area are paper, untinted.
  Future<int> paperPixels(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .descendant(
            of: find.byType(EditorCanvasArea),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final image = (await tester.runAsync(boundary.toImage))!;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    image.dispose();
    var count = 0;
    for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
      if (isPaper(
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      )) {
        count += 1;
      }
    }
    return count;
  }

  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('inside an O.L the other cut takes the fade\'s share — its '
      'paper, not the backdrop', (tester) async {
    final s = standingInAnOl(partnered: true);
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    expect(
      find.byKey(const ValueKey<String>('canvas-ol-partner')),
      findsOneWidget,
    );
    expect(
      await paperPixels(tester),
      greaterThan(5000),
      reason: 'two papers mixed are paper — no red dip',
    );
    await drainWarming(tester);
  });

  testWidgets('CONTROL: an O.L closing onto a gap still thins to the '
      'backdrop — nothing else is there', (tester) async {
    final s = standingInAnOl(partnered: false);
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    expect(
      find.byKey(const ValueKey<String>('canvas-ol-partner')),
      findsNothing,
    );
    expect(
      await paperPixels(tester),
      lessThan(500),
      reason: 'the paper is red-tinted — only its antialiased edge escapes',
    );
    await drainWarming(tester);
  });
}
