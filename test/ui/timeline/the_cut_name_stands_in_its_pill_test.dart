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
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/repaint_strays.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';

/// The tab as the app's window of 1600 × 1000 laid it.
const _panel = Size(1003, 446);

/// 🗣️F-463 ④ (유저 2026-10-25): 「컷 번호 보여주는거만 컷 알약안에, 컷
/// 버튼 오른쪽에 표시하도록 변경. 글자는 숫자+영어기준 5글자까지만
/// 정상적으로 표시하도록. 그 이상은 생략. 호버하면 풀네임 뜨도록
/// 툴팁표시」. ↩️It stood between the frame counter and the zoom's −
/// (I-57, 유저 2026-10-01) — the same on both tabs, as it is now.
void main() {
  Cut cut(String id, String name) => Cut(
    id: CutId(id),
    name: name,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [Layer(id: LayerId('$id-layer'), name: 'A', frames: const [])],
  );

  Project project({String first = 'c001', String second = 'c002'}) => Project(
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
  const cutButton = ValueKey<String>('cut-menu-button');
  const newCut = ValueKey<String>('new-cut-button');

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

  for (final storyboard in [false, true]) {
    final tab = storyboard ? 'storyboard' : 'timeline';

    testWidgets('the $tab names the cut inside its pill, right of 컷',
        (tester) async {
      final session = await open(tester, storyboard: storyboard);

      session.selectCut(const CutId('cut-a'));
      await tester.pumpAndSettle();
      expect(shown(tester), 'c001');
      final nameRect = tester.getRect(find.byKey(name));
      expect(
        tester.getRect(find.byKey(cutButton)).right,
        lessThanOrEqualTo(nameRect.left),
        reason: '「컷 버튼 오른쪽에」',
      );
      expect(
        nameRect.right,
        lessThanOrEqualTo(tester.getRect(find.byKey(newCut)).left),
        reason: '「컷 알약안에」 — before the pill\'s ＋',
      );

      session.selectCut(const CutId('cut-b'));
      await tester.pumpAndSettle();
      expect(shown(tester), 'c002', reason: 'the name follows the cut');
    });

    testWidgets('on the $tab, five characters stand whole and a sixth is cut '
        'off — the whole name is the tooltip\'s', (tester) async {
      final session = await open(
        tester,
        storyboard: storyboard,
        of: project(first: 'WWWWW', second: 'c00123'),
      );
      session.selectCut(const CutId('cut-a'));
      await tester.pumpAndSettle();
      final five = tester.getRect(find.byKey(name));
      expect(shown(tester), 'WWWWW', reason: 'the widest five, whole');
      expect(told(tester), 'WWWWW');

      session.selectCut(const CutId('cut-b'));
      await tester.pumpAndSettle();
      expect(shown(tester), 'c0012…', reason: '「그 이상은 생략」');
      expect(told(tester), 'c00123', reason: '「호버하면 풀네임」');
      expect(
        tester.getRect(find.byKey(name)),
        five,
        reason: 'the place stays; only its words change',
      );
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
      // The nearest: the bar stands on one too.
      final layer = tester.renderObject(
        find
            .ancestor(of: find.byKey(name), matching: find.byType(TickLayer))
            .first,
      );

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

    session.cutVerbs.renameCuts({const CutId('cut-a'): 'c010'});
    await tester.pumpAndSettle();

    expect(shown(tester), 'c010');
    expect(told(tester), 'c010');
  });
}
