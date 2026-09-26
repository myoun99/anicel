import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/services/persistence/volatile_scratch_files.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart'
    show CanvasSelectionDocument;
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/open_projects.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart'
    show TimesheetInkPlane;
import 'package:anicel/src/ui/timesheet_tab_host.dart';

import '../helpers/app_icon_button_probe.dart';
import '../helpers/draw_on_current_frame.dart';
import '../helpers/panel_finders.dart';
import '../helpers/project_scratch_folder.dart';

/// I-7 through the window (유저 2026-09-26): 「여러 프로젝트 열수있게할거야 …
/// 상단띠에 프로젝트 리스트있고 닫기버튼있고. 그래서 새 프로젝트는 현재 프로젝트
/// 냅두고 새로 여는거야」 — and 「다 뜯어고치면서 대개편해줘. 최대한 법
/// 통일하면서」. What the tabs have to keep straight: which project the window
/// shows, what each project keeps while it is behind, what closing asks, and
/// that nothing of one project reaches another.
void main() {
  Future<OpenProjects> pumpApp(WidgetTester tester) async {
    // A desktop window: at the test default the strip's middle holds no
    // two tabs, and they wait in its overflow list — the row's own rule.
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorTopStrip>(find.byType(EditorTopStrip)).projects;
  }

  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> newProject(WidgetTester tester) async {
    await tapKey(tester, 'top-strip-project-button');
    await tapKey(tester, 'menu-file-new');
  }

  String untitled(int n) =>
      AppText.strings.untitledProjectTab.replaceAll('{n}', '$n');

  testWidgets('New project opens a tab of its own BESIDE the one open — the '
      'window follows it, and the first keeps its work behind it', (
    tester,
  ) async {
    final projects = await pumpApp(tester);
    final first = projects.active;
    first.cutVerbs.createCut();
    final cuts = first.repository.requireProject().tracks.first.cuts.length;
    await tester.pumpAndSettle();

    await newProject(tester);

    expect(projects.sessions, hasLength(2));
    final second = projects.active;
    expect(identical(second, first), isFalse);
    expect(identical(workspaceOf(tester).session, second), isTrue);
    expect(find.text(untitled(1)), findsOneWidget);
    expect(find.text(untitled(2)), findsOneWidget);

    await tapKey(tester, 'project-tab-0');
    expect(identical(projects.active, first), isTrue);
    expect(identical(workspaceOf(tester).session, first), isTrue);
    expect(
      first.repository.requireProject().tracks.first.cuts.length,
      cuts,
      reason: 'the project behind the other tab kept its work',
    );
  });

  testWidgets('every panel is made again for the project on screen — none '
      'keeps the last one\'s session', (tester) async {
    final projects = await pumpApp(tester);
    final firstCanvas = tester.state(find.byType(EditorCanvasArea));
    final firstHost = tester.state(find.byType(MainCanvasBrushHost));
    await newProject(tester);
    final session = projects.active;
    for (final canvas in tester.widgetList<EditorCanvasArea>(
      find.byType(EditorCanvasArea),
    )) {
      expect(identical(canvas.session, session), isTrue);
    }
    for (final host in tester.widgetList<TimelineTabHost>(
      find.byType(TimelineTabHost),
    )) {
      expect(identical(host.session, session), isTrue);
    }
    expect(
      identical(tester.state(find.byType(EditorCanvasArea)), firstCanvas),
      isFalse,
      reason: 'a new canvas, not the last project\'s carried across',
    );
    expect(
      identical(tester.state(find.byType(MainCanvasBrushHost)), firstHost),
      isFalse,
      reason: 'and the brush host under the WINDOW\'s region key with it — '
          'a GlobalKey carries what is under it',
    );
  });

  testWidgets('a clean tab closes at its ✕ without a question; a DIRTY one '
      'asks with its project on screen, and Cancel keeps it', (tester) async {
    final projects = await pumpApp(tester);
    final first = projects.active;
    await newProject(tester);
    await tapKey(tester, 'project-tab-close-1');
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsNothing,
    );
    expect(projects.sessions, [first]);

    first.cutVerbs.createCut();
    expect(first.projectFile.hasUnsavedChanges, isTrue, reason: 'CONTROL');
    await newProject(tester);
    final second = projects.active;
    await tapKey(tester, 'project-tab-close-0');
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsOneWidget,
    );
    expect(
      identical(projects.active, first),
      isTrue,
      reason: 'the question is asked with its project on screen',
    );
    await tapKey(tester, 'system-exit-cancel');
    expect(projects.sessions, [first, second]);

    await tapKey(tester, 'project-tab-close-0');
    await tapKey(tester, 'system-exit-close');
    expect(projects.sessions, [second]);
    expect(identical(workspaceOf(tester).session, second), isTrue);
  });

  testWidgets('🗣️I-7-Q1: closing the LAST tab leaves an untitled project on '
      'screen', (tester) async {
    final projects = await pumpApp(tester);
    final only = projects.active;
    await tapKey(tester, 'project-tab-close-0');
    expect(projects.sessions, hasLength(1));
    expect(identical(projects.active, only), isFalse);
    expect(identical(workspaceOf(tester).session, projects.active), isTrue);
    expect(find.text(untitled(2)), findsOneWidget);
  });

  testWidgets('the marquee is the PROJECT\'s: a selection made in one tab is '
      'not in the next, and is there again when it comes back', (
    tester,
  ) async {
    await pumpApp(tester);
    final channel = workspaceOf(tester).canvasSelectionCommands!;
    // Frames, not a settle, from here on: a marquee's ants march.
    Future<void> press(String key) async {
      await tester.tap(find.byKey(ValueKey<String>(key)));
      for (var frame = 0; frame < 4; frame += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final region = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 10, top: 10, right: 60, bottom: 40),
    );
    channel.setRegion(region);
    await tester.pump();

    await press('top-strip-project-button');
    await press('menu-file-new');
    expect(channel.region, isNull, reason: 'the new project has none');
    expect(
      channel.regionHistoryRecorder,
      isNotNull,
      reason: 'the canvas made for this project recorded its history hook '
          'BEFORE the last one\'s let go — it must not have been taken off',
    );

    await press('project-tab-0');
    expect(channel.region, same(region));
  });

  testWidgets('a notice about a project BEHIND the one on screen waits for '
      'its tab', (tester) async {
    final projects = await pumpApp(tester);
    final first = projects.active;
    await newProject(tester);
    first.voiceRecording.voiceRecordingNotice.value = 'take landed';
    await tester.pumpAndSettle();
    expect(find.text('take landed'), findsNothing, reason: 'not over another');

    await tapKey(tester, 'project-tab-0');
    expect(find.text('take landed'), findsOneWidget);
  });

  testWidgets('Save As onto a file another tab has open is refused in words, '
      'and binds nothing there', (tester) async {
    final folder = Directory.systemTemp.createTempSync('qa_project_tabs_');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path.replaceAll(r'\', '/')}/Taken.anicel';
    final projects = await pumpApp(tester);
    final first = projects.active;
    first.projectFile.bindToSavedFile(path, mediaInFile: {}, cleanAsOf: 0);
    await newProject(tester);
    final second = projects.active;
    FolderPicker.debugSaveDestinationPicker = ({
      required String suggestedName,
      String? initialDirectory,
    }) async => FolderGrant(
      status: FolderPickStatus.granted,
      path: path,
      kind: GrantKind.file,
    );

    await tapKey(tester, 'top-strip-project-button');
    await tapKey(tester, 'menu-file-save-as');

    expect(
      find.byKey(const ValueKey<String>('file-open-in-another-tab-notice')),
      findsOneWidget,
    );
    expect(find.text(AppText.strings.fileOpenInAnotherTab), findsOneWidget);
    expect(second.projectFile.path, isNull, reason: 'no second writer');
    expect(File(path).existsSync(), isFalse, reason: 'not a byte written');
  });

  test('the census adds up EVERY open project, and what the app holds once '
      'is counted once', () {
    final a = EditorSessionManager(initialProject: createDefaultProject());
    final b = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.renderCaches.storyboardThumbnailBytes = 100;
    b.renderCaches.storyboardThumbnailBytes = 23;
    int row(List<EditorSessionManager> sessions, String id) =>
        collectMemoryCensus(
          sessions,
        ).items.singleWhere((item) => item.id == id).bytes;
    expect(row([a, b], 'storyboardThumbnails'), 123);
    expect(
      row([a, b], 'brushTips'),
      row([a], 'brushTips'),
      reason: 'the tips and the held piece are the app\'s, not a tab\'s',
    );
  });

  testWidgets('the project BEHIND the one on screen has no canvas: the window '
      'takes its canvas hooks off it, and hangs them on the one in front', (
    tester,
  ) async {
    final projects = await pumpApp(tester);
    final first = projects.active;
    expect(first.canvasHasSelection, isNotNull, reason: 'CONTROL');
    await newProject(tester);
    expect(first.canvasHasSelection, isNull);
    expect(first.clearCanvasSelection, isNull);
    expect(first.pixelVerbCanvas, isNull);
    final second = projects.active;
    expect(second.canvasHasSelection, isNotNull);
    expect(second.clearCanvasSelection, isNotNull);
    expect(second.pixelVerbCanvas, isNotNull);
  });

  testWidgets('a file that fails to open leaves the tabs as they were, and '
      'lets the session it was read into go', (tester) async {
    final folder = Directory.systemTemp.createTempSync('qa_project_tabs_');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path.replaceAll(r'\', '/')}/Broken.anicel';
    File(path).writeAsStringSync('not an archive');
    final seeded = const RecentProjects().withOpened(RecentProject(path: path));
    AppRecent.projects.value = seeded;
    RecentProjectsStore().save(seeded);
    addTearDown(() {
      AppRecent.projects.value = const RecentProjects();
      RecentProjectsStore().save(const RecentProjects());
    });
    final projects = await pumpApp(tester);
    final only = projects.active;
    // What the open sessions' undo stacks may park — each open session
    // adds its budget, so a session the failed open kept would show here.
    final room = VolatileScratchFiles.ceilingBytes;

    await tapKey(tester, 'top-strip-project-button');
    final recents = find.byKey(const ValueKey<String>('menu-recent-projects'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(recents));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('menu-recent-$path')));
    for (var attempt = 0; attempt < 200; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text(AppText.strings.commonNotice).evaluate().isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    expect(
      find.text(AppText.strings.commonNotice),
      findsOneWidget,
      reason: 'CONTROL: the open failed, and said so',
    );
    await tester.pumpAndSettle();

    expect(projects.sessions, [only], reason: 'no tab for a failed open');
    expect(
      VolatileScratchFiles.ceilingBytes,
      room,
      reason: 'the session the file was read into was let go',
    );
  });

  testWidgets('F-123 into a new tab: a file opened from the menu puts the '
      'tools back where it was saved — the file is read before its tab '
      'exists, and the tools come back when the tab does', (tester) async {
    final folder = Directory.systemTemp.createTempSync('qa_project_tabs_');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path.replaceAll(r'\', '/')}/Tools.anicel';
    final projects = await pumpApp(tester);
    final tool = workspaceOf(tester).brushTool!;
    tool.value = tool.value.copyWith(tool: CanvasTool.eraser);
    await tester.pump();
    await tester.runAsync(
      () => projects.active.projectDoor.saveProjectToFile(
        path,
        asked: SaveAsked.byAPerson,
      ),
    );
    // Clean now, so its ✕ asks nothing; a fresh untitled tab takes its place.
    await tapKey(tester, 'project-tab-close-0');
    tool.value = tool.value.copyWith(tool: CanvasTool.brush);
    await tester.pump();

    FolderPicker.debugFilePicker = ({
      required List<XTypeGroup> acceptedTypeGroups,
      required bool allowMultiple,
    }) async => [
      FolderGrant(
        status: FolderPickStatus.granted,
        path: path,
        kind: GrantKind.file,
      ),
    ];
    await tapKey(tester, 'top-strip-project-button');
    await tester.tap(find.byKey(const ValueKey<String>('menu-file-open')));
    for (var attempt = 0; attempt < 200; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (projects.active.projectFile.path == path) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    expect(projects.active.projectFile.path, path, reason: 'CONTROL: opened');
    for (var frame = 0; frame < 20; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(tool.value.tool, CanvasTool.eraser);
  });

  testWidgets('a tab closed while the clock is writing its file is let go '
      'only once the write ends — never mid-write', (tester) async {
    final projects = await pumpApp(tester);
    await newProject(tester);
    final closing = projects.active;
    // What the open sessions' undo stacks may park: a session that is let
    // go takes its share with it, which is how this sees the letting go.
    final withIt = VolatileScratchFiles.ceilingBytes;
    closing.projectFile.beginSave();

    await tapKey(tester, 'project-tab-close-1');
    expect(projects.sessions, hasLength(1), reason: 'the tab is gone');
    await tester.pump();
    await tester.pump();
    expect(
      VolatileScratchFiles.ceilingBytes,
      withIt,
      reason: 'kept while its save is still writing',
    );

    closing.projectFile.endSave();
    await tester.pump();
    await tester.pump();
    expect(
      VolatileScratchFiles.ceilingBytes,
      lessThan(withIt),
      reason: 'let go once the write ended',
    );
  });

  testWidgets('a stroke drawn in the project on screen goes into THAT '
      'project\'s drawings — the canvas is made again for it, not carried '
      'over from the tab before', (tester) async {
    /// A new cel on [project]'s current frame, a pen stroke across the
    /// canvas, and the key the stroke should have gone to.
    Future<BrushFrameKey> strokeIn(EditorSessionManager project) async {
      project.createDrawingAtCurrentFrame();
      await tester.pumpAndSettle();
      final selection = project.editingCanvas.activeBrushEditorSelection!;
      final pen = await tester.startGesture(
        visibleCanvasPoint(tester),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      for (var step = 0; step < 4; step += 1) {
        await pen.moveBy(const Offset(12, 8));
        await tester.pump();
      }
      await pen.up();
      await tester.pumpAndSettle();
      return project.brushFrameKeyForCut(
        project.requireActiveCut,
        selection.layerId,
        selection.frameId,
      );
    }

    bool inked(EditorSessionManager project, BrushFrameKey key) =>
        project.renderCaches.brushFrameStore.celHasRenderableContent(key);

    final projects = await pumpApp(tester);
    final first = projects.active;
    expect(
      inked(first, await strokeIn(first)),
      isTrue,
      reason: 'CONTROL: the stroke lands in the one project open',
    );

    await newProject(tester);
    final second = projects.active;
    final key = await strokeIn(second);
    expect(
      inked(second, key),
      isTrue,
      reason: 'the stroke is the second project\'s drawing',
    );
    expect(
      inked(first, key),
      isFalse,
      reason: 'and not written into the project that went behind',
    );
  });

  testWidgets('the marquee of the project coming on screen keeps its undo — '
      'the canvas it replaces takes off only the recorder IT put on', (
    tester,
  ) async {
    final projects = await pumpApp(tester);
    final first = projects.active;
    final channel = workspaceOf(tester).canvasSelectionCommands!;
    final recorder = channel.regionHistoryRecorder;
    expect(recorder, isNotNull, reason: 'CONTROL: the canvas records');

    // The new project's canvas installs its recorder in the same build that
    // retires the old canvas, and the old one's dispose runs after it. A
    // canvas re-installs on its next rebuild, so the hole a careless
    // dispose leaves is FRAMES wide — every frame is asked.
    await tapKey(tester, 'top-strip-project-button');
    await tester.tap(find.byKey(const ValueKey<String>('menu-file-new')));
    for (var frame = 0; frame < 20; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        channel.regionHistoryRecorder,
        isNotNull,
        reason: 'frame $frame of the switch',
      );
    }
    await tester.pumpAndSettle();
    expect(identical(projects.active, first), isFalse, reason: 'premise');
    expect(
      identical(channel.regionHistoryRecorder, recorder),
      isFalse,
      reason: 'the recorder is the new canvas\'s own',
    );
  });

  testWidgets('a lift the canvas is holding LANDS in its own project before '
      'another comes on screen — it is never carried into the next', (
    tester,
  ) async {
    final projects = await pumpApp(tester);
    final first = projects.active;
    final channel = workspaceOf(tester).canvasSelectionCommands!;
    // Stands in for a mounted selection layer holding a lift: the brush
    // (the default tool) mounts none, so nothing takes this binding over.
    final landedOn = <CanvasSelectionDocument>[];
    final owner = Object();
    channel.bind(
      owner,
      hasSelection: () => false,
      deselect: () {},
      movePending: () => true,
      confirmPendingMove: () => landedOn.add(channel.document),
    );
    addTearDown(() => channel.unbind(owner));

    await newProject(tester);
    expect(
      landedOn,
      [same(first.canvasSelection)],
      reason: 'landed once, while the channel still showed its project',
    );
  });

  testWidgets('the held keys follow the stroke of the project ON SCREEN', (
    tester,
  ) async {
    final projects = await pumpApp(tester);
    await newProject(tester);
    final tool = workspaceOf(tester).brushTool!;
    projects.active.setBrushInputActive(true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(
      tool.value.tool,
      CanvasTool.brush,
      reason: 'a stroke is live in the project on screen: the switch waits',
    );
    projects.active.setBrushInputActive(false);
    await tester.pump();
    expect(tool.value.tool, CanvasTool.eyedropper);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
  });

  testWidgets('the timesheet shows ITS project\'s ink — one tab\'s memos '
      'are not on another\'s sheet, and are there again when it comes back', (
    tester,
  ) async {
    // The sheet ships open in the right dock (R26 #31).
    final projects = await pumpApp(tester);
    final first = projects.active;
    // Real ink to write the memo with: the drawing a stroke leaves.
    drawOnCurrentFrame(first);
    final drawn = first.editingCanvas.activeBrushEditorSelection!;
    final ink = first.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      first.brushFrameKeyForCut(
        first.requireActiveCut,
        drawn.layerId,
        drawn.frameId,
      ),
    )!;
    final key = timesheetInkStripKey(first.requireActiveCut.id, 0);
    first.renderCaches.timesheetInkStripStore.storeBakedSurface(key, ink);
    await tester.pump();
    bool sheetShowsMemo() => tester
        .widget<TimesheetTabHost>(find.byType(TimesheetTabHost))
        .inkController!
        .hasInkFor(TimesheetInkPlane.strip, key);
    expect(sheetShowsMemo(), isTrue, reason: 'CONTROL: its own sheet');

    await newProject(tester);
    expect(
      sheetShowsMemo(),
      isFalse,
      reason: 'the same cut id in another project is another sheet',
    );

    await tapKey(tester, 'project-tab-0');
    expect(sheetShowsMemo(), isTrue);
  });

  testWidgets('leaving asks EVERY project with unsaved work, each with its '
      'own tab on screen — and Cancel on any one keeps the window', (
    tester,
  ) async {
    final projects = await pumpApp(tester);
    final first = projects.active;
    first.cutVerbs.createCut();
    await newProject(tester);
    final second = projects.active;
    second.cutVerbs.createCut();
    await tester.pumpAndSettle();

    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsOneWidget,
    );
    expect(identical(projects.active, first), isTrue, reason: 'its own tab');
    await tapKey(tester, 'system-exit-close');
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsOneWidget,
      reason: 'the next project with unsaved work is asked too',
    );
    expect(identical(projects.active, second), isTrue, reason: 'its own tab');
    await tapKey(tester, 'system-exit-cancel');
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsNothing,
    );
    expect(projects.sessions, [first, second], reason: 'the window stays');
  });

  testWidgets('🗣️I-7: what one tab copies, another pastes — its pill lights '
      'for the app\'s copy, the linked paste stays home, and the paste is '
      'that project\'s own cel', (tester) async {
    final projects = await pumpApp(tester);
    final first = projects.active;
    drawOnCurrentFrame(first);
    first.copyFrameAtCurrentFrame();
    await newProject(tester);
    final second = projects.active;
    final before = second.activeLayer!.frames.length;

    const paste = ValueKey<String>('shared-paste-independent-button');
    const link = ValueKey<String>('shared-paste-linked-button');
    expect(tester.appIconButton(find.byKey(paste)).onPressed, isNotNull);
    expect(
      tester.appIconButton(find.byKey(link)).onPressed,
      isNull,
      reason: 'a link is the same cel, and that cel is the first project\'s',
    );
    await tapKey(tester, paste.value);
    expect(second.activeLayer!.frames, hasLength(before + 1));
  });

  testWidgets('a project whose file went while it was behind says so when '
      'its tab comes back', (tester) async {
    final folder = Directory.systemTemp.createTempSync('qa_project_tabs_');
    deleteAfterSessionEnds(folder);
    final projects = await pumpApp(tester);
    projects.active.projectFile.bindToSavedFile(
      '${folder.path.replaceAll(r'\', '/')}/Gone.anicel',
      mediaInFile: {},
      cleanAsOf: 0,
    );
    await newProject(tester);
    const notice = ValueKey<String>('project-file-vanished-notice');
    expect(find.byKey(notice), findsNothing);

    await tapKey(tester, 'project-tab-0');
    expect(find.byKey(notice), findsOneWidget);
  });
}
