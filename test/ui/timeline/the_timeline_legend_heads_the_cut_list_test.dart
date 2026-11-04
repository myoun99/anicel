import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show EditorActionIds;
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart'
    show editorActionLabel;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/repaint_strays.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️I-154 (유저 2026-11-04): 「타임라인패널의 레전드행의 레이어부분,
/// 콘티패널에선 타임라인 버튼 보여주도록 바꼈으니 여기도 활용. 현재컷 이름을
/// 여기로 옮겨서, 누르면 컷 바꿀수있게 리스트팝오버로 비춤 … 그리고 해당
/// 레전드의 컷버튼 누르면 콘티패널은 타임라인 이름변경 삭제같은거 있는데
/// 여기선 이름변경만. 일단은. 그러고 추가로 컷 버튼에 이름변경, 레이어버튼에도
/// 이름변경 추가」.
void main() {
  Cut cut(String id, String name) => Cut(
    id: CutId(id),
    name: name,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [Layer(id: LayerId('$id-layer'), name: 'A', frames: const [])],
  );

  Project project({List<Track>? tracks}) => Project(
    id: const ProjectId('cut-list'),
    name: 'Cut list',
    createdAt: DateTime.utc(2026, 11, 4),
    tracks:
        tracks ??
        [
          Track(
            id: const TrackId('t'),
            name: 'Video',
            cuts: [cut('cut-a', '001'), cut('cut-b', '002')],
          ),
        ],
  );

  Finder byKey(String key) => find.byKey(ValueKey<String>(key));

  /// The tab as the app's window of 1600 × 1000 laid it, standing in cut A.
  Future<EditorSessionManager> open(
    WidgetTester tester, {
    Project? of,
  }) async {
    final session = await pumpTimelineHost(
      tester,
      of ?? project(),
      surface: const Size(1003, 446),
    );
    session.selectCut(const CutId('cut-a'));
    await tester.pumpAndSettle();
    return session;
  }

  final heading = byKey('legend-heading');

  String headingWords(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: heading, matching: byKey('legend-layer')),
      )
      .data!;

  Future<void> openList(WidgetTester tester) async {
    await tester.tap(heading);
    await tester.pumpAndSettle();
  }

  Cut cutOf(EditorSessionManager session, String id) => session.repository
      .requireProject()
      .tracks
      .expand((track) => track.cuts)
      .singleWhere((cut) => cut.id == CutId(id));

  testWidgets('the legend\'s heading names the cut stood in, with a c '
      'before it, where the rows\' heading stood — and the bar names none', (
    tester,
  ) async {
    final session = await open(tester);

    expect(headingWords(tester), 'c001');
    expect(find.text(AppText.strings.tlLegendLayer), findsNothing);
    expect(
      byKey('timeline-cut-name'),
      findsNothing,
      reason: '「현재컷 이름을 여기로 옮겨서」',
    );

    session.selectCut(const CutId('cut-b'));
    await tester.pumpAndSettle();
    expect(headingWords(tester), 'c002', reason: 'the name follows the cut');
  });

  // 🚨I-22 ③ · I-57: the name turns over on a scrub's move, so it is drawn
  // on a layer of its own, and the legend is kept across the crossing.
  testWidgets('a scrub over another cut names it at the crossing — the '
      'words\' layer repaints and nothing else of the legend', (tester) async {
    final session = await open(tester);
    session.frameScrub.scrubGlobalFrame(20);
    await tester.pump();
    final header = find.byType(TimelineLayerControlsHeader);
    final legend = tester.renderObject(header);
    // Inside the legend: the grid it heads stands on one too.
    final own = find.descendant(
      of: header,
      matching: find.ancestor(
        of: find.descendant(of: heading, matching: byKey('legend-layer')),
        matching: find.byType(TickLayer),
      ),
    );
    expect(own, findsOneWidget, reason: 'a layer of the words\' own');
    final layer = tester.renderObject(own);

    // Cut A is frames [0, 24) of the track; this is inside cut B.
    session.frameScrub.scrubGlobalFrame(26);
    await tester.pump(null, EnginePhase.layout);
    final strays = repaintStrays(legend, allowed: {layer});
    await tester.pump();

    expect(headingWords(tester), 'c002', reason: '⛔전제: the move crossed');
    expect(strays, isEmpty);
    session.frameScrub.commitFrameScrub();
    await tester.pumpAndSettle();
  });

  testWidgets('the list: the timeline\'s cuts, the one stood in in the '
      'accent — and choosing a row stands in it', (tester) async {
    final session = await open(tester);
    await openList(tester);

    expect(find.text(AppText.strings.cuts), findsWidgets);
    expect(
      find.text('Video'),
      findsNothing,
      reason: 'one track: no track heads its cuts',
    );
    Color inkOf(String id, String written) => tester
        .widget<Text>(
          find.descendant(
            of: byKey('cut-list-$id'),
            matching: find.text(written),
          ),
        )
        .style!
        .color!;
    expect(inkOf('cut-a', 'c001'), AppColors.accent, reason: 'stood in');
    expect(inkOf('cut-b', 'c002'), isNot(AppColors.accent));

    await tester.tap(byKey('cut-list-cut-b'));
    await tester.pumpAndSettle();

    expect(session.activeCutId, const CutId('cut-b'));
    expect(headingWords(tester), 'c002');
  });

  testWidgets('a timeline of several tracks heads each track\'s cuts with '
      'its name', (tester) async {
    await open(
      tester,
      of: project(
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [cut('cut-a', '001'), cut('cut-b', '002')],
          ),
          Track(
            id: const TrackId('t2'),
            name: 'V2',
            cuts: [cut('cut-c', '003')],
          ),
        ],
      ),
    );
    await openList(tester);

    final down = [
      find.text('V1'),
      byKey('cut-list-cut-a'),
      byKey('cut-list-cut-b'),
      find.text('V2'),
      byKey('cut-list-cut-c'),
    ].map((row) => tester.getTopLeft(row).dy).toList();
    expect(down, [...down]..sort(), reason: 'each track over its cuts');
  });

  testWidgets('a row\'s pencil names THAT cut — the one stood in stays, '
      'and it is one step', (tester) async {
    final session = await open(tester);
    await openList(tester);
    expect(
      tester
          .widget<AppIconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is AppIconButton &&
                  widget.keyValue == 'cut-list-cut-b-rename',
            ),
          )
          .tooltip,
      editorActionLabel(EditorActionIds.cutRename),
      reason: 'the cut button\'s rename, by its name',
    );
    await tester.tap(byKey('cut-list-cut-b-rename'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(byKey('rename-cut-text-field'))
          .controller!
          .text,
      '002',
    );
    await tester.enterText(byKey('rename-cut-text-field'), '010');
    await tester.tap(byKey('rename-cut-confirm-button'));
    await tester.pumpAndSettle();

    expect(cutOf(session, 'cut-b').name, '010');
    expect(cutOf(session, 'cut-a').name, '001');
    expect(session.activeCutId, const CutId('cut-a'));
    expect(headingWords(tester), 'c001');

    session.undo();
    await tester.pumpAndSettle();
    expect(cutOf(session, 'cut-b').name, '002', reason: 'one step');
  });

  testWidgets('the cut button\'s menu and the layer button\'s each head '
      'with their rename', (tester) async {
    final session = await open(tester);

    await tester.tap(byKey('cut-menu-button'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(byKey('rename-cut-button')).dy,
      lessThan(tester.getTopLeft(byKey('edit-cut-note-button')).dy),
      reason: 'at the head of the menu',
    );
    await tester.tap(byKey('rename-cut-button'));
    await tester.pumpAndSettle();
    await tester.enterText(byKey('rename-cut-text-field'), '100');
    await tester.tap(byKey('rename-cut-confirm-button'));
    await tester.pumpAndSettle();
    expect(cutOf(session, 'cut-a').name, '100');
    expect(headingWords(tester), 'c100');

    await tester.tap(byKey('timeline-layer-menu-button'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(byKey('timeline-rename-layer-button')).dy,
      lessThan(tester.getTopLeft(byKey('timeline-detach-layer-button')).dy),
      reason: 'at the head of the menu',
    );
    await tester.tap(byKey('timeline-rename-layer-button'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(byKey('rename-layer-text-field'))
          .controller!
          .text,
      'A',
    );
    await tester.enterText(byKey('rename-layer-text-field'), 'BG');
    await tester.tap(byKey('rename-layer-ok-button'));
    await tester.pumpAndSettle();
    expect(cutOf(session, 'cut-a').layers.single.name, 'BG');
  });
}
