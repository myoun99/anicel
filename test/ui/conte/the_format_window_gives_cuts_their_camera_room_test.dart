import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_camera_room.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/default_layer_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🗣️I-82 (유저 2026-10-31): 「컷별 카메라움직임 설정은 콘티용지서식에
/// 넣자. 카메라 움직임항목에서 전체 설정이랑 컷 설정 두고, 컷 설정에선
/// 현재컷(컷이름) 이런식으로 텍스트 보여주고 해당 항목안에 버튼있는느낌.
/// 기본값은 정해진대로 서식따름.」 — and a range is the cuts it covers, as the
/// cut button's picks are (절대명령 2).
void main() {
  const button = 'conte-format-cut-camera-room';

  late EditorSessionManager session;

  Cut cut(String id, int sequence) => createDefaultCut(
    cutId: CutId(id),
    name: id,
    layerId: defaultLayerIdForSequence(sequence),
  );

  Future<void> pumpHost(WidgetTester tester, {List<Cut>? cuts}) async {
    session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('room-project'),
        name: 'Rooms',
        createdAt: DateTime.utc(2026, 10, 31),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'V',
            cuts: cuts ?? [cut('C12', 1), cut('C13', 2), cut('C14', 3)],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    final view = ValueNotifier<CanvasViewport?>(null);
    addTearDown(view.dispose);
    final ink = ConteInkController();
    addTearDown(ink.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => ConteTabHost(
              session: session,
              thumbnails: null,
              viewportController: view,
              inkController: ink,
              brushToolState: tool,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String room) async {
    await tap(tester, button);
    await tap(tester, '$button-$room');
  }

  Future<void> save(WidgetTester tester) =>
      tap(tester, 'conte-format-save-button');

  ConteCameraRoom? roomOf(String id) =>
      session.cutById(CutId(id))!.metadata.conteCameraRoom;

  String shownOn(WidgetTester tester, String key) => tester
      .widget<PanelFlyoutButton>(find.byKey(ValueKey<String>(key)))
      .label;

  void selectRange(String from, String to) {
    final axis = session.trackFrameAxis();
    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: axis.entryFor(CutId(from))!.startFrame,
      headGlobalFrame: axis.entryFor(CutId(to))!.startFrame,
    );
  }

  testWidgets('the camera field keeps the whole work\'s and the cut\'s: the '
      'cut named beside its button, on the format\'s until picked', (
    tester,
  ) async {
    await pumpHost(tester);
    await tap(tester, 'conte-format-button');

    expect(find.text('Overall settings'), findsOneWidget);
    expect(find.text('Cut settings'), findsOneWidget);
    expect(find.text('Current cut (C12)'), findsOneWidget);
    expect(shownOn(tester, button), 'As the format');

    await tap(tester, button);
    for (final room in ['format', 'grows', 'inCell']) {
      expect(
        find.byKey(ValueKey<String>('$button-$room')),
        findsOneWidget,
        reason: room,
      );
    }
  });

  testWidgets('a pick is the cut\'s on save alone — the work\'s stays, and one '
      'undo gives both of a save back', (tester) async {
    await pumpHost(tester);
    final work = session.timesheetInfo.conteCameraRoom;

    await tap(tester, 'conte-format-button');
    await pick(tester, 'inCell');
    expect(roomOf('C12'), isNull, reason: 'nothing is written before save');
    await tap(tester, 'conte-format-cover');
    await save(tester);
    expect(roomOf('C12'), ConteCameraRoom.inCell);
    expect(roomOf('C13'), isNull, reason: 'the current cut alone');
    expect(session.timesheetInfo.conteCameraRoom, work);
    expect(session.timesheetInfo.conteCover, isFalse);

    await tap(tester, 'conte-format-button');
    expect(shownOn(tester, button), 'Keep in the cell', reason: 'its own');
    await tap(tester, 'conte-format-cancel-button');

    session.undo();
    await tester.pumpAndSettle();
    expect(roomOf('C12'), isNull);
    expect(session.timesheetInfo.conteCover, isTrue, reason: 'ONE step');
  });

  testWidgets('the format\'s gives a cut back', (tester) async {
    await pumpHost(tester);
    await tap(tester, 'conte-format-button');
    await pick(tester, 'grows');
    await save(tester);
    expect(roomOf('C12'), ConteCameraRoom.grows);

    await tap(tester, 'conte-format-button');
    await pick(tester, 'format');
    await save(tester);
    expect(roomOf('C12'), isNull);
  });

  testWidgets('a save with no pick writes no room', (tester) async {
    await pumpHost(tester);
    await tap(tester, 'conte-format-button');
    await save(tester);
    expect(session.canUndo, isFalse, reason: 'nothing changed');
  });

  testWidgets('a range is what the row is about: its count in the words, and '
      'the pick lands on every cut it covers, ONE undo', (tester) async {
    await pumpHost(tester);
    selectRange('C13', 'C14');
    await tester.pumpAndSettle();

    await tap(tester, 'conte-format-button');
    expect(find.text('Selected cuts (2)'), findsOneWidget);
    await pick(tester, 'inCell');
    await save(tester);

    expect(roomOf('C12'), isNull, reason: 'outside the range');
    expect(roomOf('C13'), ConteCameraRoom.inCell);
    expect(roomOf('C14'), ConteCameraRoom.inCell);

    session.undo();
    await tester.pumpAndSettle();
    expect(roomOf('C13'), isNull);
    expect(roomOf('C14'), isNull);
  });

  testWidgets('a range whose cuts differ keeps each one\'s until a pick — and '
      'the first\'s own, picked again, is a pick', (tester) async {
    await pumpHost(tester);
    await tap(tester, 'conte-format-button');
    await pick(tester, 'inCell');
    await save(tester);
    selectRange('C12', 'C13');
    await tester.pumpAndSettle();

    await tap(tester, 'conte-format-button');
    expect(shownOn(tester, button), 'Keep in the cell', reason: 'the first\'s');
    await save(tester);
    expect((roomOf('C12'), roomOf('C13')), (ConteCameraRoom.inCell, null));

    await tap(tester, 'conte-format-button');
    await pick(tester, 'inCell');
    await save(tester);
    expect((roomOf('C12'), roomOf('C13')), (
      ConteCameraRoom.inCell,
      ConteCameraRoom.inCell,
    ));
  });

  testWidgets('in the gap the row stands, refusing, and the work\'s still '
      'saves', (tester) async {
    await pumpHost(
      tester,
      cuts: [cut('C12', 1), cut('C13', 2).copyWith(leadingGapFrames: 24)],
    );
    final second = session.trackFrameAxis().entryFor(const CutId('C13'))!;
    session.selectGlobalFrame(second.startFrame - 1);
    await tester.pumpAndSettle();
    expect(session.activeCutOrNull, isNull, reason: 'fixture: the gap');

    await tap(tester, 'conte-format-button');

    expect(find.text('No cut selected'), findsOneWidget);
    expect(
      tester
          .widget<PanelFlyoutButton>(find.byKey(const ValueKey<String>(button)))
          .enabled,
      isFalse,
    );
    await tap(tester, 'conte-format-cover');
    await save(tester);
    expect(session.timesheetInfo.conteCover, isFalse);
  });
}
