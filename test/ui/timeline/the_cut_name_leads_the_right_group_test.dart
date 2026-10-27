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
import 'package:anicel/src/ui/cut_command_group.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/repaint_strays.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';

/// The tab as the app's window of 1600 × 1000 laid it.
const _panel = Size(1003, 446);

/// 🗣️F-491 (유저 2026-10-27): 「컷 이름 표시 역시 이게 아닌듯. 컷 버튼 옆에
/// 있는데 너무 쓸데없이 공간차지함. 다른곳으로 이동하고싶음. 위치는 전처럼
/// 오른쪽묶음의 제일 왼쪽에 위치. 정렬은 해당 위치에서 오른쪽정렬. 그리고 컷
/// 이름 앞에 c 붙이도록. 즉 컷이름 500이면 c500 되도록」 · (23:15)
/// 「오른쪽묶음엔 컷이름/줌/fit 이순서로 남도록」.
///
/// 🗣️F-463 ④ (유저 2026-10-25): 「글자는 숫자+영어기준 5글자까지만
/// 정상적으로 표시하도록. 그 이상은 생략. 호버하면 풀네임 뜨도록
/// 툴팁표시」. ↩️It stood in the cut pill right of its 컷 from F-463 ④, and
/// between the frame counter and the zoom's − before that (I-57, 유저
/// 2026-10-01) — the same on both tabs, as it is now.
void main() {
  Cut cut(String id, String name) => Cut(
    id: CutId(id),
    name: name,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [Layer(id: LayerId('$id-layer'), name: 'A', frames: const [])],
  );

  Project project({String first = '001', String second = '002'}) => Project(
    id: const ProjectId('cut-name'),
    name: 'Cut name',
    createdAt: DateTime.utc(2026, 10, 1),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [cut('cut-a', first), cut('cut-b', second)],
      ),
    ],
  );

  const name = ValueKey<String>('timeline-cut-name');
  const zoom = ValueKey<String>('timeline-zoom-readout');

  /// The tab alone — the timeline's ([pumpTimelineHost]) or the
  /// storyboard's ([pumpStoryboardHost]) — as the app's window of
  /// 1600 × 1000 laid it.
  Future<EditorSessionManager> open(
    WidgetTester tester, {
    bool storyboard = false,
    Project? of,
  }) => storyboard
      ? pumpStoryboardHost(tester, of ?? project(), surface: _panel)
      : pumpTimelineHost(tester, of ?? project(), surface: _panel);

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(name)).data!;

  String told(WidgetTester tester) => tester
      .widget<AppTooltip>(
        find.ancestor(of: find.byKey(name), matching: find.byType(AppTooltip)),
      )
      .message;

  /// The bar's right group: the cut's name, the zoom and its fit.
  final rightGroup = find.byType(TimelineViewCluster);

  for (final storyboard in [false, true]) {
    final tab = storyboard ? 'storyboard' : 'timeline';

    testWidgets('the $tab names the cut with a c before it, at the head of '
        'the bar\'s right group, out of the cut pill', (tester) async {
      final session = await open(tester, storyboard: storyboard);

      session.selectCut(const CutId('cut-a'));
      await tester.pumpAndSettle();
      expect(shown(tester), 'c001', reason: '「컷이름 500이면 c500」');
      expect(
        find.descendant(
          of: find.byType(CutCommandGroup),
          matching: find.byKey(name),
        ),
        findsNothing,
        reason: '「컷 버튼 옆에 있는데 너무 쓸데없이 공간차지함」',
      );
      expect(
        find.descendant(of: rightGroup, matching: find.byKey(name)),
        findsOneWidget,
      );
      final nameRect = tester.getRect(find.byKey(name));
      final zoomRect = tester.getRect(find.byKey(zoom));
      final fitRect = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-zoom-fit-button')),
      );
      expect(
        [nameRect.right <= zoomRect.left, zoomRect.right <= fitRect.left],
        [isTrue, isTrue],
        reason: '「오른쪽묶음엔 컷이름/줌/fit 이순서로」',
      );
      final buttons = find.descendant(
        of: rightGroup,
        matching: find.byType(AppIconButton),
      );
      expect(buttons, findsWidgets, reason: '⛔전제');
      for (final button in buttons.evaluate()) {
        expect(
          tester.getRect(find.byWidget(button.widget)).left,
          greaterThanOrEqualTo(nameRect.right),
          reason: '「오른쪽묶음의 제일 왼쪽에」: '
              '${(button.widget as AppIconButton).keyValue} after it',
        );
      }

      session.selectCut(const CutId('cut-b'));
      await tester.pumpAndSettle();
      expect(shown(tester), 'c002', reason: 'the name follows the cut');
    });

    testWidgets('on the $tab, the name stands at its place\'s right, against '
        'the zoom — a short one and the widest alike', (tester) async {
      final session = await open(
        tester,
        storyboard: storyboard,
        of: project(first: '1', second: 'WWWWW'),
      );
      session.selectCut(const CutId('cut-a'));
      await tester.pumpAndSettle();
      final short = tester.getRect(find.byKey(name));
      final readout = tester.getRect(find.byKey(zoom));
      expect(shown(tester), 'c1');

      session.selectCut(const CutId('cut-b'));
      await tester.pumpAndSettle();
      final widest = tester.getRect(find.byKey(name));
      expect(shown(tester), 'cWWWWW', reason: 'the widest five, whole');
      expect(told(tester), 'cWWWWW');
      expect(widest.width, greaterThan(short.width), reason: '⛔전제');
      expect(short.right, widest.right, reason: '「오른쪽정렬」');
      expect(
        tester.getRect(find.byKey(zoom)),
        readout,
        reason: 'the place stays; only its words change',
      );
      expect(readout.left - widest.right, inInclusiveRange(0, 4));
    });

    testWidgets('on the $tab, five characters stand whole and a sixth is cut '
        'off — the whole name is the tooltip\'s', (tester) async {
      final session = await open(
        tester,
        storyboard: storyboard,
        of: project(second: '001234'),
      );
      session.selectCut(const CutId('cut-b'));
      await tester.pumpAndSettle();
      expect(shown(tester), 'c00123…', reason: '「그 이상은 생략」');
      expect(told(tester), 'c001234', reason: '「호버하면 풀네임」');
    });

    // 🗣️I-57, after seeing it (유저 2026-10-01): 「스크럽중에도 통일해서
    // 컷이름 갱신되게. 컷 실제로 바뀔때 한번」. ↩️The name was the ACTIVE
    // cut's, and a scrub left the active cut alone (UI-R7 #9) — so it named
    // the cut being left until the release. Since I-57 ② the scrub crosses
    // into the cut under it, and the name turns over with that crossing.
    testWidgets('a scrub over another cut names it — once, at the crossing '
        '— on the $tab', (tester) async {
      final session = await open(tester, storyboard: storyboard);
      session.selectCut(const CutId('cut-a'));
      await tester.pumpAndSettle();
      expect(shown(tester), 'c001', reason: '⛔전제');
      var heard = 0;
      void count() => heard += 1;
      session.cutUnderPlayhead.cutName.addListener(count);
      addTearDown(
        () => session.cutUnderPlayhead.cutName.removeListener(count),
      );

      // Cut A is frames [0, 24) of the track; these are all inside cut B.
      for (final frame in [26, 27, 30, 31]) {
        session.frameScrub.scrubGlobalFrame(frame);
        await tester.pump();
      }
      expect(session.frameScrub.active.value, isTrue, reason: '⛔전제: live');
      expect(
        session.activeCutId,
        const CutId('cut-b'),
        reason: 'the scrub crossed into it',
      );
      expect(shown(tester), 'c002');
      expect(heard, 1, reason: '「컷 실제로 바뀔때 한번」 — not once per frame');

      session.frameScrub.commitFrameScrub();
      await tester.pumpAndSettle();
      expect(
        shown(tester),
        'c002',
        reason: 'the release lands where it showed',
      );
    });

    // 🚨I-22 ③: the name turns over on a scrub's move, so it is drawn on a
    // layer of its own — the bar's own is a tick layer too, and the app's
    // scrub pin lets it repaint, pills and all.
    testWidgets('a crossing repaints the name\'s layer and nothing else of '
        'the $tab\'s bar', (tester) async {
      final session = await open(tester, storyboard: storyboard);
      session.selectCut(const CutId('cut-a'));
      await tester.pumpAndSettle();
      session.frameScrub.scrubGlobalFrame(20);
      await tester.pump();
      final bar = tester.renderObject(find.byType(TimelineCommandBar));
      // Inside the right group: the bar stands on one too.
      final own = find.descendant(
        of: rightGroup,
        matching: find.ancestor(
          of: find.byKey(name),
          matching: find.byType(TickLayer),
        ),
      );
      expect(own, findsOneWidget, reason: 'a layer of the name\'s own');
      final layer = tester.renderObject(own);

      session.frameScrub.scrubGlobalFrame(26);
      await tester.pump(null, EnginePhase.layout);
      final strays = repaintStrays(bar, allowed: {layer});
      await tester.pump();

      expect(shown(tester), 'c002', reason: '⛔전제: the move crossed');
      expect(strays, isEmpty);
    });
  }

  testWidgets('a rename of the cut reaches the name', (tester) async {
    final session = await open(tester);
    session.selectCut(const CutId('cut-a'));
    await tester.pumpAndSettle();

    session.cutVerbs.renameCuts({const CutId('cut-a'): '010'});
    await tester.pumpAndSettle();

    expect(shown(tester), 'c010');
    expect(told(tester), 'c010');
  });
}
