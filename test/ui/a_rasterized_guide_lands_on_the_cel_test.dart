import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import 'package:anicel/src/services/canvas_color_sampler.dart'
    show surfacePixelRgba;
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/settle_async.dart';

/// 🗣️vanishing-point-types-Q5 (유저 2026-10-16): 래스터라이즈 draws 「지금
/// 레이어의 지금 셀에」 — not the new row the question recommended — and
/// 「되돌리기 한 번으로 취소」. Q6: 「화면에 보이는 그대로 … 용지 안만」.
///
/// The bake lands through the paste's door (`pieceLandings`), so a range,
/// a selection and a cel-less frame answer as the paste's do — pinned
/// there. What is the bake's own: the picture is the CANVAS's, so a row
/// drawn somewhere else on the canvas takes it where that row shows it.
void main() {
  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  ({int left, int top, int rightExclusive, int bottomExclusive})? inkOf(
    EditorSessionManager session,
  ) {
    final coordinator = session.pixelEditing.coordinator!;
    return bitmapSurfaceContentBounds(
      coordinator.currentSurfaceOf(coordinator.activeFrameKey),
    );
  }

  testWidgets('🚨래스터라이즈 draws the picked guide\'s lines into the cel you '
      'stand on — inside the paper, on the row\'s own cel — as ONE undo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final workspace = workspaceOf(tester);
    final session = workspace.session;
    // The default project has no cel at the playhead.
    session.createDrawingAtCurrentFrame();
    final paper = session.requireActiveCut.canvasSize;
    const id = GuideId('p');
    session.cutVerbs.setActiveCutGuides(
      CutGuides(guides: [newPerspectiveGuide(id, paper, '퍼스 1')]),
    );
    session.cutVerbs.selectedGuideId = id;
    final tool = workspace.brushTool!;
    tool.value = tool.value.copyWith(tool: CanvasTool.guide);
    await tester.pumpAndSettle();
    // The tool settings group ships closed on the left rail (slot 2).
    final group = EditorWorkspace.railGroupId(right: false, slot: 2);
    await tester.tap(find.byKey(ValueKey<String>('rail-group-$group')));
    await tester.pumpAndSettle();
    final rows = session.requireActiveCut.layers.length;
    final steps = session.historyManager.undoCount;
    expect(inkOf(session), isNull, reason: '⛔premise: a blank cel');

    final button = find.byKey(const ValueKey<String>('guide-rasterize'));
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    // The bake reads the picture back off the engine: real time.
    expect(await settleAsync(tester, () => inkOf(session) != null), isTrue);

    final ink = inkOf(session)!;
    expect(ink.left, greaterThanOrEqualTo(0));
    expect(ink.top, greaterThanOrEqualTo(0));
    expect(ink.rightExclusive, lessThanOrEqualTo(paper.width));
    expect(ink.bottomExclusive, lessThanOrEqualTo(paper.height));
    final coordinator = session.pixelEditing.coordinator!;
    expect(
      surfacePixelRgba(
            coordinator.currentSurfaceOf(coordinator.activeFrameKey),
            100,
            paper.height ~/ 2,
          )! &
          0xFF,
      greaterThan(0),
      reason: 'the eye level through the middle is part of what it shows',
    );
    expect(session.requireActiveCut.layers, hasLength(rows), reason: 'Q5');
    expect(session.historyManager.undoCount, steps + 1);

    session.historyManager.undo();
    await tester.pump();
    expect(inkOf(session), isNull, reason: 'one undo takes it off');
  });

  testWidgets('🚨a row drawn twice the size takes the picture where IT shows '
      'it on the canvas — half the size, half as far from the middle', (
    tester,
  ) async {
    const cel = FrameId('posed-cel');
    const row = LayerId('posed');
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: Project(
            id: const ProjectId('posed-project'),
            name: 'Posed',
            createdAt: DateTime.utc(2026),
            tracks: [
              Track(
                id: const TrackId('posed-track'),
                name: 'Video Track',
                cuts: [
                  Cut(
                    id: const CutId('posed-cut'),
                    name: 'posed-cut',
                    duration: defaultCutDuration,
                    canvasSize: defaultCutCanvasSize,
                    layers: [
                      Layer(
                        id: row,
                        name: row.value,
                        frames: [
                          Frame(
                            id: cel,
                            name: cel.value,
                            duration: 1,
                            strokes: const [],
                          ),
                        ],
                        timeline: {
                          0: const TimelineExposure.drawing(cel, length: 1),
                        },
                        // Twice the size about the canvas's middle.
                        transformTrack: TransformTrack.empty().copyWith(
                          scale: PropertyTrack<CanvasPoint>.empty().withKey(
                            0,
                            uniformScale(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final session = workspaceOf(tester).session;
    session.selectLayer(row);
    session.selectFrameIndex(0);
    await tester.pump();
    final middle = (
      x: defaultCutCanvasSize.width ~/ 2,
      y: defaultCutCanvasSize.height ~/ 2,
    );

    // A square 20 across, 40 right of and below the canvas's middle.
    session.pixelVerbs.landCanvasPicture(
      CutPiece(
        image: BrushStampImage(
          id: 'square',
          width: 20,
          height: 20,
          rgba: Uint8List.fromList([
            for (var i = 0; i < 20 * 20; i += 1) ...[255, 0, 0, 255],
          ]),
        ),
        originLeft: middle.x + 40,
        originTop: middle.y + 40,
      ),
      description: 'Rasterize guide',
    );
    await tester.pump();

    final ink = inkOf(session);
    expect(ink, isNotNull, reason: 'the row took the picture');
    expect(ink!.left, inInclusiveRange(middle.x + 19, middle.x + 21));
    expect(ink.top, inInclusiveRange(middle.y + 19, middle.y + 21));
    expect(ink.rightExclusive, inInclusiveRange(middle.x + 29, middle.x + 31));
    expect(ink.bottomExclusive, inInclusiveRange(middle.y + 29, middle.y + 31));
  });
}
