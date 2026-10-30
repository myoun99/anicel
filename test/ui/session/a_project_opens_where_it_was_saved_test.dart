import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/panel_view_memory.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart'
    show timelineFramePlaceLabel;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★A PROJECT OPENS WHERE IT WAS SAVED (F-123).
///
/// 유저 2026-09-13: 「… 액티브컷,액티브레이어,인덱스 를 저장해서 열 때
/// 반영되도록. 존재안하는게 있으면 해당 분야만 초기값으로」.
///
/// Through a real save and a real open: the door writes where the work
/// stood beside the project and reads it back. And through BOTH save roads —
/// the second save of a project appends, and an append that forgot the
/// field would reopen on the first cut as if nothing had been saved.
void main() {
  late Directory directory;
  late String projectPath;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-resume-');
    deleteAfterSessionEnds(directory);
    projectPath = '${directory.path}/scene.anicel';
  });

  /// The default project with a second cut, so "the first cut" and "the cut
  /// that was open" are two different answers.
  Project twoCuts() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            ...track.cuts,
            createDefaultCut(
              cutId: const CutId('c2'),
              name: '2',
              layerId: const LayerId('c2-drawing'),
            ),
          ],
        ),
      ],
    );
  }

  test('the cut, the row and the frame come back — and coming back is not '
      'an edit', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    s.selectCut(const CutId('c2'));
    // Not the top row: the top row is where an open lands anyway.
    final row = s.activeCutOrNull!.layers[1];
    s.selectLayer(row.id);
    s.selectFrameIndex(5);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(reopened.activeCutId, const CutId('c2'));
    expect(reopened.activeLayerId, row.id);
    expect(reopened.currentFrameIndex, 5);
    expect(
      reopened.cutUnderPlayhead.listenable.value,
      const CutId('c2'),
      reason: 'what shows the cut under the playhead hears the open — its '
          'settle ends in a notify',
    );
    expect(
      reopened.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'where the work stood is not an edit',
    );
    reopened.dispose();
  });

  test('🚨an APPEND save carries the newer place, not the first one', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.selectCut(const CutId('c2'));
    s.selectFrameIndex(7);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(reopened.activeCutId, const CutId('c2'));
    expect(reopened.currentFrameIndex, 7);
    reopened.dispose();
  });

  test('a cut or a row the project no longer has falls back ALONE — the '
      'frame still lands', () async {
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(
        project: twoCuts(),
        cels: const [],
        sessionFields: const AnicelSessionFields(
          resume: {'cutId': 'gone', 'layerId': 'gone-too', 'frameIndex': 3},
        ),
      ),
    );

    final opened = await openedSession(projectPath);
    final firstCut = twoCuts().tracks.first.cuts.first;
    expect(
      opened.activeCutId,
      firstCut.id,
      reason: 'the cut is gone: the first cut, as a file without one opens',
    );
    expect(
      opened.activeLayerId,
      firstCut.layers.first.id,
      reason: 'the row is gone: the top row',
    );
    expect(
      opened.currentFrameIndex,
      3,
      reason: 'the frame is a part of its own and still lands',
    );
    opened.dispose();
  });

  test('🚨a saved row the FILE hides — its folder shut — opens standing on '
      'the folder: the standing law asks at an open too (F-169)', () async {
    const folder = LayerId('f');
    const member = LayerId('m');
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final project = base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                ...cut.layers,
                Layer(
                  id: member,
                  name: 'm',
                  frames: const [],
                  timeline: const {},
                  folderId: folder,
                ),
                createFolderLayer(id: folder, name: 'F').copyWith(
                  collapsed: true,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(
        project: project,
        cels: const [],
        sessionFields: AnicelSessionFields(
          resume: {'cutId': cut.id.value, 'layerId': member.value},
        ),
      ),
    );

    final opened = await openedSession(projectPath);
    expect(
      opened.activeLayerId,
      folder,
      reason: 'the row the file names is off the screen, so the open stands '
          'on the row that stands in for it — the shut folder',
    );
    opened.dispose();
  });

  test('a file saved before the place was kept opens as it always did',
      () async {
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(project: twoCuts(), cels: const []),
    );

    final opened = await openedSession(projectPath);
    final firstCut = twoCuts().tracks.first.cuts.first;
    expect(opened.activeCutId, firstCut.id);
    expect(opened.activeLayerId, firstCut.layers.first.id);
    expect(opened.currentFrameIndex, 0);
    expect(opened.playbackRig.playbackMode, defaultPlaybackMode);
    opened.dispose();
  });

  test('a file that says nothing of the playback mode plays as a new '
      'project does — whatever the session played by before', () async {
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(project: twoCuts(), cels: const []),
    );

    final opened = await openedSession(
      projectPath,
      before: (session) => session.playbackRig.setPlaybackMode(
        PlaybackMode.values.firstWhere((mode) => mode != defaultPlaybackMode),
      ),
    );

    expect(opened.playbackRig.playbackMode, defaultPlaybackMode);
    opened.dispose();
  });

  test('🚨the playback mode comes back with the file — and picking it is no '
      'edit: no undo step, no unsaved mark (유저 답 playback-quality-undo-Q1 '
      '「언두 안 됨 — 보기 설정처럼(저장은 됨)」, of the setting whose seat it '
      'took)', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    final picked = PlaybackMode.values.firstWhere(
      (mode) => mode != defaultPlaybackMode,
    );

    s.playbackRig.setPlaybackMode(picked);

    expect(s.historyManager.canUndo, isFalse);
    expect(s.projectFile.hasUnsavedChanges, isFalse);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(reopened.playbackRig.playbackMode, picked);
    reopened.dispose();
  });

  test('🚨each cut comes back at the timeline zoom it was left at — through '
      'the append too — and a cut nobody zoomed is handed none (F-253 → '
      'F-267, 유저 2026-10-01: 「프로젝트와 같이 저장되도록」)', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    final first = s.activeCutId!;
    s.timelineZoom.remember(const CutId('c2'), 37.5);
    // A cut deleted since it was zoomed: the memory keeps no list of cuts.
    s.timelineZoom.remember(const CutId('gone'), 9);
    expect(
      s.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'zooming is no edit — the zoom rides beside the project',
    );
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.timelineZoom.remember(const CutId('c2'), 12);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(reopened.timelineZoom.zoomOf(const CutId('c2')), 12);
    expect(
      reopened.timelineZoom.zoomOf(first),
      isNull,
      reason: 'it opens at the default, not at another cut\'s zoom',
    );
    expect(
      reopened.timelineZoom.byCut.keys,
      [const CutId('c2')],
      reason: 'a cut the project no longer has falls back alone, as the '
          'cut a resume names does',
    );
    expect(reopened.projectFile.hasUnsavedChanges, isFalse);
    reopened.dispose();
  });

  test('🚨the conte comes back at its zoom and each panel scrolled where it '
      'was — through the append too — and none of it is an edit (F-267, '
      '유저 2026-10-01: 「다시 열면 그대로 열리도록」)', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    final views = s.panelViews;
    views.storyboardPixelsPerFrame.value = 3.5;
    views.frameAxisOffsets['timeline']!.value = 480;
    views.frameAxisOffsets['storyboard']!.value = 96;
    views.layerAxisOffsets['timeline']!.value = 150;
    expect(
      s.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'zooming and scrolling are no edit — they ride beside the '
          'project',
    );
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    views.frameAxisOffsets['timeline']!.value = 640;
    views.layerAxisOffsets['xsheet']!.value = 72;
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    final back = reopened.panelViews;
    expect(back.storyboardPixelsPerFrame.value, 3.5);
    expect(back.frameAxisOffsets['timeline']!.value, 640);
    expect(back.frameAxisOffsets['storyboard']!.value, 96);
    expect(
      back.frameAxisOffsets['xsheet']!.value,
      0,
      reason: 'a panel left at its start opens at its start',
    );
    expect(
      back.layerAxisOffsets['timeline']!.value,
      150,
      reason: 'the rows too — along the OTHER axis',
    );
    expect(back.layerAxisOffsets['xsheet']!.value, 72);
    expect(reopened.projectFile.hasUnsavedChanges, isFalse);
    reopened.dispose();
  });

  test('🚨the rulers\' count comes back with the file — through the '
      'append, and turned back too — and turning it is no edit (F-354, 유저 '
      '2026-10-13: 「초+코마 표시 설정한게 저장되도록. 파일안에. 열렸을때 '
      '같은상태 유지하고싶어서」)', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    final steps = s.historyManager.undoCount;
    s.panelViews.rulerView.value = FrameRulerView.secondsPlusFrames;
    expect(
      s.historyManager.undoCount,
      steps,
      reason: 'no undo step takes the display back',
    );
    expect(
      s.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'and turning it marks nothing unsaved',
    );
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(
      reopened.panelViews.rulerView.value,
      FrameRulerView.secondsPlusFrames,
    );
    expect(
      reopened.framePlaceLabel(30),
      timelineFramePlaceLabel(
        frameIndex: 30,
        framesPerSecond: reopened.projectSettings.projectFrameRate.countingBase,
        showSeconds: true,
      ),
      reason: 'a list that names a frame writes it as the ruler does',
    );
    expect(reopened.projectFile.hasUnsavedChanges, isFalse);
    // 🗣️I-81: the third count, the page view, keeps too.
    reopened.panelViews.rulerView.value = FrameRulerView.pages;
    await reopened.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    reopened.dispose();

    final paged = await openedSession(projectPath);
    expect(paged.panelViews.rulerView.value, FrameRulerView.pages);
    paged.panelViews.rulerView.value = FrameRulerView.frames;
    await paged.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    paged.dispose();

    final again = await openedSession(projectPath);
    expect(
      again.panelViews.rulerView.value,
      FrameRulerView.frames,
      reason: 'turned back to frames, the file keeps that too',
    );
    again.dispose();
  });

  test('🚨each file comes back at the page and the framing it was left at in '
      'the viewers — through the append too — and none of it is an edit '
      '(F-382, 유저 2026-10-17: 「해당 파일에 저장한단느낌」)', () async {
    const conte = 'C:/work/conte.pdf';
    final s = EditorSessionManager(initialProject: twoCuts());
    final framing = CanvasViewport(zoom: 2, panX: -40, panY: 12.5);
    s.mediaFileViews
      ..rememberPage(conte, 3)
      ..rememberFraming(conte, viewer: 'media-viewer-sub', framing: framing);
    expect(
      s.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'looking at a reference is no edit — its view rides beside the '
          'project',
    );
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.mediaFileViews.rememberPage(conte, 4);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    final views = reopened.mediaFileViews;
    expect(views.pageOf(conte), 4);
    expect(views.framingOf(conte, viewer: 'media-viewer-sub'), framing);
    expect(
      views.framingOf(conte, viewer: 'media-viewer'),
      isNull,
      reason: 'the framing is the viewer\'s — the other never framed it',
    );
    expect(reopened.projectFile.hasUnsavedChanges, isFalse);
    reopened.dispose();
  });

  test('a file that says nothing of the panels opens them as a new project '
      'does — the conte at its default zoom, each panel at its start',
      () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(
      reopened.panelViews.storyboardPixelsPerFrame.value,
      PanelViewMemory.defaultStoryboardPixelsPerFrame,
    );
    for (final offset in [
      ...reopened.panelViews.frameAxisOffsets.values,
      ...reopened.panelViews.layerAxisOffsets.values,
    ]) {
      expect(offset.value, 0);
    }
    expect(
      reopened.panelViews.rulerView.value,
      FrameRulerView.frames,
      reason: 'frames, as a new project writes them',
    );
    reopened.dispose();
  });

  test('🚨the header graphs and the lanes pinned to them come back with the '
      'file — through the append too — and turning them is no edit; a row '
      'the project no longer has falls back ALONE (유저 답 F-360-Q1 「보기 '
      '설정처럼 — 저장은 되고 언두는 안 됨」)', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    final row = s.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    final graph = laneGroupKey(row, transformGroupHeaderLane.laneId);
    final pin = laneGroupKey(row, 'opacity');
    // A row deleted since its graph was opened: the rail keeps no list of
    // rows.
    final gone = laneGroupKey(
      const LayerId('gone'),
      transformGroupHeaderLane.laneId,
    );
    // The group the graph stands in is the row's fold — an edit (F-360) —
    // so it is open before the first save.
    final presses = SessionRowButtonPresses(s)..toggleLaneGroup(graph);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    final steps = s.historyManager.undoCount;
    presses
      ..toggleLaneGraph(graph)
      ..toggleLaneGraph(gone)
      ..toggleLanePin(pin)
      ..toggleLanePin(gone)
      ..plotLaneGraph(graph, LaneGraphMode.speed);
    expect(
      s.historyManager.undoCount,
      steps,
      reason: 'no undo step takes a graph back',
    );
    expect(
      s.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'and turning one marks nothing unsaved',
    );
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    presses
      ..resizeLaneGraph(graph, 240)
      ..enlargeLaneGraph(graph);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(
      reopened.railView.laneGraphs.value,
      LaneGraphsView(
        open: {
          graph: const LaneGraph(
            extent: 240,
            mode: LaneGraphMode.speed,
            enlarged: true,
          ),
        },
        pinned: {pin},
      ),
    );
    expect(reopened.projectFile.hasUnsavedChanges, isFalse);
    reopened.dispose();
  });
}
