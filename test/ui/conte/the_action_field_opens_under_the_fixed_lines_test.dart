import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_book_page.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/sheet/sheet_text_edit_layer.dart';

/// 🗣️I-93 (유저 2026-10-12): 「이 고정텍스트는 지울수없도록? 편집할때마다
/// 바뀌는」 — the camera's lines head a cell's ACTION column and no one
/// types into them: a tap on the column edits the words under them, and
/// the field types where the page prints those words (F-188: 「액션란 메모
/// 시작할때 ui가 써져있는거랑 다름」).
void main() {
  const line = conteCellTextSize * conteLineHeight;

  CameraPose at(double x) => CameraPose(center: CanvasPoint(x: x, y: 0));

  /// One cut of [duration] frames, one conte block over it with words
  /// typed in, its camera keyed [keys].
  Project project(
    Map<int, CameraPose> keys, {
    int duration = 24,
    bool fixedText = true,
  }) => Project(
    id: const ProjectId('fixed-lines'),
    name: 'Fixed lines',
    createdAt: DateTime.utc(2026, 10, 30),
    timesheetInfo: TimesheetInfo.empty.copyWith(conteFixedText: fixedText),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: '1',
            duration: duration,
            canvasSize: const CanvasSize(width: 640, height: 360),
            camera: CutCamera(keyframes: keys),
            layers: [
              Layer(
                id: const LayerId('sb'),
                name: 'SB',
                kind: LayerKind.storyboard,
                frames: [
                  Frame(
                    id: const FrameId('sb-0'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: {
                  0: TimelineExposure.drawing(
                    const FrameId('sb-0'),
                    length: duration,
                    memo: const ExposureMemo(actionMemo: 'ハヤト走る'),
                  ),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// The panel on [initial]; the body page's one cell and its ACTION
  /// target.
  Future<({ContePlacedCell cell, SheetTextTarget target})> pump(
    WidgetTester tester,
    Project initial,
  ) async {
    final session = EditorSessionManager(initialProject: initial);
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConteTabHost(session: session, thumbnails: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final body = find.byWidgetPredicate(
      (widget) =>
          widget is ConteBookPage && widget.page.kind == ContePageKind.body,
    );
    final cell = tester.widget<ConteBookPage>(body).page.cells.single;
    final target = tester
        .widget<SheetTextEditLayer>(
          find.descendant(of: body, matching: find.byType(SheetTextEditLayer)),
        )
        .targets
        .single;
    expect(
      find.byKey(ValueKey<String>('conte-action-edit-c-${cell.cellIndex}')),
      findsOneWidget,
      reason: 'fixture: the cell offers its words',
    );
    return (cell: cell, target: target);
  }

  testWidgets('🎯the field opens under the cell\'s three lines — where the '
      'page prints the words typed there', (tester) async {
    final (:cell, :target) = await pump(
      tester,
      project({5: at(0), 15: at(40)}),
    );
    final top = cell.actionRect.top + 3 * line;

    expect(target.box.top, closeTo(top, 1e-9));
    expect(target.textRect.top, closeTo(top + 4, 1e-9));
    expect(target.text, 'ハヤト走る', reason: 'the lines are not its words');
  });

  testWidgets('with the lines taken out of the sheet, the field opens at the '
      'top of the column', (tester) async {
    final (:cell, :target) = await pump(
      tester,
      project({5: at(0), 15: at(40)}, fixedText: false),
    );

    expect(target.box.top, cell.actionRect.top);
    expect(target.textRect.top, cell.actionRect.top + 4);
  });

  testWidgets('lines that outrun the cell\'s rows leave the field no height '
      '— never one upside down', (tester) async {
    // A key every second frame, back and forth: a PAN line to each.
    final (:cell, :target) = await pump(
      tester,
      project({
        for (var frame = 0; frame < 120; frame += 2)
          frame: at(frame % 4 == 0 ? 0 : 40),
      }, duration: 120),
    );
    expect(
      cell.source.cameraLines.length * line,
      greaterThan(target.box.bottom - cell.actionRect.top),
      reason: 'fixture: the lines run past the rows',
    );

    expect(target.box.height, closeTo(8, 1e-9));
    expect(target.textRect.height, closeTo(0, 1e-9));
    expect(tester.takeException(), isNull);
  });
}
