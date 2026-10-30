import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_paper.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timesheet_info.dart'
    show TimesheetHeaderField;
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_overlay.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_paper.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_paper_panel.dart';
import 'package:anicel/src/ui/export/export_preview_panel.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/sheet/paper_editing.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_key_funnel.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_paper.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/export_preview_probe.dart';
import '../../helpers/paper_editing_kit.dart';

/// 🗣️I-127 (유저 2026-10-25): 「셀 출력의 타임시트나 컷봉투에도 타임시트
/// 용지패널/컷봉투 용지패널이랑 동일하게 잉크 사용이라던가, 눌러서 원화 이름
/// 텍스트편집이라던가 동등하게 가능하도록. 법 통일하면서. 그리고 도구 단축키
/// 통해서 변경하든 변경가능하게. 동일하게 선택중인 도구로 편집하는느낌.
/// 물론 언두도 가능.」
///
/// The Cels tab's timesheet pages and cut envelope are the panels' papers,
/// over the panels' own ink and switches, under the tool in hand; the
/// window takes the editor's tool keys and its undo; and what the window
/// shows is what the film is after them.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const cutId = CutId('cut');

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  /// One cut, 301: a KEY row A with two cels.
  EditorSessionManager film() => inkEveryCel(EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 32, height: 18),
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: cutId,
              name: '301',
              duration: 2,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  frames: [frame('a1', '1'), frame('a2', '2')],
                  mark: const LayerMark(process: LayerProcess.key),
                ),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
    ),
  ));

  const everything = CelsExportSpec(
    kinds: {ExportCelKind.cel, ExportCelKind.timesheet, ExportCelKind.envelope},
  );


  Future<void> pumpCels(
    WidgetTester tester,
    EditorSessionManager session, {
    PaperEditing? editing,
    EditorKeyRoad? keys,
    CelsExportSpec spec = everything,
  }) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: ExportTabSpecs(cels: spec),
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            formatAvailability: ExportFormatAvailability.permissive(),
            keys: keys,
            paperEditing: editing,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
  }

  Finder keyed(String value) => find.byKey(ValueKey<String>(value));

  Future<void> press(WidgetTester tester, String key) async {
    await tester.ensureVisible(keyed(key));
    await tester.pump();
    await tester.tap(keyed(key), warnIfMissed: false);
    await tester.pump();
  }

  Future<void> standOn(WidgetTester tester, String row) =>
      press(tester, 'export-cels-stand-$row');

  /// The paper shown, as the window rules it.
  ExportPaper paperShown(WidgetTester tester) =>
      tester.widget<ExportPaperPanel>(find.byType(ExportPaperPanel)).paper;

  /// What the timesheet page shown prints in [field].
  String? printed(WidgetTester tester, TimesheetHeaderField field) =>
      (paperShown(tester) as ExportTimesheetPage).layout.typedHeaderValue(
        field,
      );

  /// The canvas panel the paper stands in.
  BrushCanvasPanel paperCanvas(WidgetTester tester) =>
      tester.widget<BrushCanvasPanel>(
        find.descendant(
          of: find.byType(ExportPaperPanel),
          matching: find.byType(BrushCanvasPanel),
        ),
      );

  Future<void> controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> undoKey(WidgetTester tester) =>
      controlKey(tester, LogicalKeyboardKey.keyZ);

  /// [key] on the window's paper — the editor behind the window prints a
  /// sheet of its own.
  Finder onPaper(String key) =>
      find.descendant(of: find.byType(ExportPaperPanel), matching: keyed(key));

  /// Types [text] into the box keyed [box] on the paper shown — through its
  /// editor, keyed [editor] — and lands it.
  Future<void> typeOnPaper(
    WidgetTester tester, {
    required String box,
    required String editor,
    required String text,
  }) async {
    final target = onPaper(box);
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.enterText(onPaper(editor), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  /// Types [text] into the header box of [field] on the page shown, and
  /// lands it.
  Future<void> typeInto(
    WidgetTester tester,
    TimesheetHeaderField field,
    String text,
  ) => typeOnPaper(
    tester,
    box: 'timesheet-${field.name}-edit-p0',
    editor: 'timesheet-header-edit-field',
    text: text,
  );

  BrushStrokeCommitData oneDab() => BrushStrokeCommitData(
    sourceDabs: [
      BrushDab(
        center: CanvasPoint(x: 20, y: 20),
        color: 0xFF000000,
        size: 4,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      ),
    ],
  );

  testWidgets('🎯the timesheet page the list stands on is its panel\'s '
      'paper — the panel\'s ink and switch, the tool in hand — written as '
      'its file: the name on it, its 1:1 on the pill', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final kit = paperEditingKit(session);
    await pumpCels(tester, session, editing: kit);
    await standOn(tester, 'document-timesheet');

    expect(find.byType(ExportPreviewPanel), findsNothing);
    expect(find.byType(TimesheetPaper), findsOneWidget);
    final paper = paperShown(tester) as ExportTimesheetPage;
    expect((paper.cutId, paper.page), (cutId, 0));
    expect(paperCanvas(tester).documentName, '_TS301.png');
    expect(paperCanvas(tester).oneToOneOnPill, isTrue);
    expect(find.byType(TimesheetInkLayer), findsNothing, reason: 'brush off');

    await press(tester, 'export-timesheet-brush-toggle-button');
    expect(kit.timesheetBrushAllowed.value, isTrue, reason: 'its panel\'s');
    final layer = tester.widget<TimesheetInkLayer>(
      find.byType(TimesheetInkLayer),
    );
    expect(layer.controller, same(kit.timesheetInk));
    expect(layer.brushToolState, same(kit.tool));

    final pen = await tester.startGesture(
      tester.getCenter(find.byType(InteractiveBrushEditCanvasView).first),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    for (var step = 0; step < 4; step += 1) {
      await pen.moveBy(const Offset(12, 8));
      await tester.pump();
    }
    await pen.up();
    await tester.pump();
    expect(
      kit.timesheetInk.hasInkFor(null, timesheetInkPageKey(cutId, 0)),
      isTrue,
      reason: 'the stroke lands on the page\'s paper',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the cut envelope is its panel\'s paper too, ruled onto the '
      'paper the export writes', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final kit = paperEditingKit(session);
    kit.envelopeBrushAllowed.value = true;
    await pumpCels(tester, session, editing: kit);
    await standOn(tester, 'document-envelope');

    expect(find.byType(ExportPreviewPanel), findsNothing);
    expect(find.byType(CutEnvelopePaper), findsOneWidget);
    final paper = paperShown(tester) as ExportEnvelopePage;
    expect(paper.owner, cutId);
    expect(paperCanvas(tester).documentName, '_CUT301_envelope.png');
    final overlay = tester.widget<CutEnvelopeInkOverlay>(
      find.byType(CutEnvelopeInkOverlay),
    );
    expect(overlay.controller, same(kit.envelopeInk));
    expect(overlay.brushToolState, same(kit.tool));
    expect(overlay.windows, isNotEmpty);
    session.playbackRig.prerenderScheduler.cancel();
  });

  // 🗣️I-127-Q1 (유저 2026-10-25): 「봉투 용지 패널에도 넣고, 셀 출력은 그대로
  // 부른다」.
  testWidgets('the envelope\'s staff box is typed into as its panel\'s — '
      'the cut\'s worker, printed at once', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpCels(
      tester,
      session,
      editing: paperEditingKit(session),
      // The envelope's own paper: the cut's here is 8px, its words a
      // fraction of a pixel tall.
      spec: CelsExportSpec(
        kinds: everything.kinds,
        envelopePaper: CutEnvelopePaperMode.sheet,
      ),
    );
    await standOn(tester, 'document-envelope');

    await typeOnPaper(
      tester,
      box: 'cut-envelope-staff-name-genga-edit',
      editor: 'cut-envelope-edit-field',
      text: 'ユキ',
    );

    const key = LayerMark(process: LayerProcess.key);
    expect(session.cutById(cutId)!.metadata.staffNameFor(key), 'ユキ');
    expect(
      (paperShown(tester) as ExportEnvelopePage).source.staff[key.keySlug],
      'ユキ',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  // 🗣️I-127-Q2 (유저 2026-10-27): 「같은 값을 찍는 칸은 전부 — 타임시트
  // 머리와 같은 길」.
  testWidgets('the envelope\'s CUT box is typed into as its panel\'s — the '
      'cut\'s name, printed at once', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpCels(
      tester,
      session,
      editing: paperEditingKit(session),
      spec: CelsExportSpec(
        kinds: everything.kinds,
        envelopePaper: CutEnvelopePaperMode.sheet,
      ),
    );
    await standOn(tester, 'document-envelope');

    await typeOnPaper(
      tester,
      box: 'cut-envelope-cut-0-number-edit',
      editor: 'cut-envelope-edit-field',
      text: '302',
    );

    expect(session.cutById(cutId)!.name, '302');
    expect(
      (paperShown(tester) as ExportEnvelopePage).source.cuts.single.name,
      '302',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('on a paper too small to set a line in, a press on the staff '
      'box opens nothing — the cut\'s 8px paper sets its words 0.12px tall', (
    tester,
  ) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpCels(tester, session, editing: paperEditingKit(session));
    await standOn(tester, 'document-envelope');

    expect(onPaper('cut-envelope-staff-name-genga-edit'), findsNothing);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🗣️a box typed in writes its cut and the page prints it at '
      'once; the undo key pressed in the window takes it back', (
    tester,
  ) async {
    final session = film();
    addTearDown(session.dispose);
    final (:road, :invoked, held: _) = recordingKeyRoad(session);
    await pumpCels(
      tester,
      session,
      editing: paperEditingKit(session),
      keys: road,
    );
    await standOn(tester, 'document-timesheet');

    await typeInto(tester, TimesheetHeaderField.name, 'ユキ');
    expect(printed(tester, TimesheetHeaderField.name), 'ユキ');

    // The work's own box: the cut is the one it was, and the page reads
    // the work's title again all the same.
    await typeInto(tester, TimesheetHeaderField.title, '夜に駆ける');
    expect(printed(tester, TimesheetHeaderField.title), '夜に駆ける');

    await undoKey(tester);
    expect(invoked, [EditorActionIds.undo]);
    expect(printed(tester, TimesheetHeaderField.title), isNot('夜に駆ける'));
    await undoKey(tester);
    expect(printed(tester, TimesheetHeaderField.name), isNot('ユキ'));
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a tool key and the undo keys reach the window; a key of the '
      'editor\'s own menus stands behind it', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final (:road, :invoked, held: _) = recordingKeyRoad(session);
    await pumpCels(
      tester,
      session,
      editing: paperEditingKit(session),
      keys: road,
    );
    // ↩️It pressed H, which the shipped keys leave unbound — a key nothing
    // would have taken, window or not.
    expect(
      road.bindings.activatorsFor(EditorActionIds.fileSave),
      contains(const SingleActivator(LogicalKeyboardKey.keyS, control: true)),
      reason: 'the key pressed is the menu\'s',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await controlKey(tester, LogicalKeyboardKey.keyS);
    await undoKey(tester);
    await tester.pump();

    expect(invoked, [EditorActionIds.toolEraser, EditorActionIds.undo]);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a drawing among the papers keeps their brush switch\'s '
      'place, standing off — and with no papers to edit, none stands', (
    tester,
  ) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpCels(tester, session, editing: paperEditingKit(session));
    await standOn(tester, 'a');

    expect(find.byType(ExportPreviewPanel), findsOneWidget);
    expect(
      tester.appIconButton(keyed('export-cel-brush-toggle-button')).onPressed,
      isNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpCels(tester, session);
    await standOn(tester, 'document-timesheet');
    expect(find.byType(ExportPaperPanel), findsNothing);
    expect(find.byType(ExportPreviewPanel), findsOneWidget);
    expect(keyed('export-cel-brush-toggle-button'), findsNothing);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨a drawing\'s picture is drawn again when the history moves '
      'under the window — a stroke, an undo — though the film is the same '
      'project', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final kit = paperEditingKit(session);
    await pumpCels(tester, session, editing: kit);
    // The page written on, then a drawing looked at.
    await standOn(tester, 'document-timesheet');
    await standOn(tester, 'a');
    final project = session.repository.requireProject();
    final before = tester.exportPreviewDocument!.look;

    kit.timesheetInk.commitStroke(
      plane: null,
      key: timesheetInkPageKey(cutId, 0),
      strokeData: oneDab(),
      historyManager: session.historyManager,
    );
    await tester.pump();

    expect(
      session.repository.requireProject(),
      same(project),
      reason: 'premise: the film is the one it was',
    );
    expect(tester.exportPreviewDocument!.look, isNot(before));
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨the cut the window is built around is read again when the '
      'film changes under it — the Image tab names its file for the cut as '
      'it is now', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpCels(tester, session);
    await press(tester, 'export-tab-image');
    expect(tester.exportPreviewName, startsWith('301'), reason: 'premise');

    session.cutVerbs.renameCuts({cutId: '302'});
    await tester.pump();
    expect(tester.exportPreviewName, startsWith('302'));
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯from the editor: the window opens over the workspace\'s own '
      'papers, and a tool key and the undo pressed in it are the '
      'editor\'s', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final strip = tester.widget<EditorTopStrip>(find.byType(EditorTopStrip));
    final session = strip.projects.active;
    final tool = strip.brushTool!;
    expect(tool.value.tool, isNot(CanvasTool.eraser), reason: 'premise');

    await press(tester, 'top-strip-project-button');
    await tester.pumpAndSettle();
    await press(tester, 'menu-file-export');
    await tester.pumpAndSettle();
    final window = tester.widget<ExportDialog>(find.byType(ExportDialog));
    expect(window.keys, isNotNull);
    expect(window.paperEditing!.tool, same(tool));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(tool.value.tool, CanvasTool.eraser);

    await press(tester, 'export-tab-cels');
    await standOn(tester, 'document-timesheet');
    await typeInto(tester, TimesheetHeaderField.name, 'ユキ');
    expect(printed(tester, TimesheetHeaderField.name), 'ユキ');
    await undoKey(tester);
    expect(printed(tester, TimesheetHeaderField.name), isNot('ユキ'));
    session.playbackRig.prerenderScheduler.cancel();
  });
}
