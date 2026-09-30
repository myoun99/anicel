import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/dialogs/link_window.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import 'storyboard_cut_block_probe.dart';

/// 🗣️I-25 (유저 2026-09-14): 「링크컷/링크레이어 등 좀 더 알기쉽게. 우선
/// 링크컷이 발생해있는 경우, 모든 컷에 적용. 내용은 컷블록에서 컷 이름 오른쪽에
/// 링크아이콘(레이어에서 사용하는거랑 똑같은 것) 사용. 그리고 해당 버튼 클릭시
/// 공용창 띄움. 링크된 대상의 리스트(보기만). 그리고 링크해제 버튼. 해제버튼은
/// 현재 컷을 독립시킴. 레이어도 똑같이 버튼누르면 링크 대상 리스트 표시.
/// 여기서 링크컷일경우엔 링크해제버튼 비활성화하고 툴팁으로 링크컷이기때문에
/// 불가능하다고 띄움. 링크컷아니면 해제해도 되니까 해제버튼 활성화. 그리고
/// 레이어 버튼의 링크해제는 필요없어졌으니 삭제. 그리고 레이어 여러개 선택후
/// 작동하는건 참조버튼 그대로 공용화된거 사용」.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  group('the session', () {
    test('a linked cut is named by its partner, and its rows cannot leave '
        'alone', () {
      final s = session();
      final source = s.requireActiveCut.id;
      expect(s.cutVerbs.linkedCutIds, isEmpty);
      expect(s.layerVerbs.activeCutIsLinkedCut, isFalse);

      s.cutVerbs.createLinkedCutFromActiveCut();
      final linked = s.requireActiveCut.id;

      expect(s.cutVerbs.linkedCutIds, {source, linked});
      expect(s.cutVerbs.linkedCutLines(source), [s.cutById(linked)!.name]);
      expect(s.layerVerbs.activeCutIsLinkedCut, isTrue);
    });

    test('a link duplicate is not a linked cut, and its rows unlink as one '
        'undo', () {
      final s = session();
      final row = s.activeLayerId!;
      s.layerVerbs.linkDuplicateActiveLayer();
      final copy = s.activeLayerId!;
      expect(copy, isNot(row), reason: 'the premise: two linked rows');
      expect(s.layerVerbs.activeCutIsLinkedCut, isFalse);
      final depth = s.historyManager.undoCount;

      s.layerVerbs.unlinkLayers([row, copy]);

      expect(
        [s.layerVerbs.isLayerLinked(row), s.layerVerbs.isLayerLinked(copy)],
        [false, false],
      );
      expect(s.historyManager.undoCount, depth + 1);
    });
  });

  group('the window', () {
    Future<void> pump(
      WidgetTester tester, {
      required VoidCallback? unlink,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLinkWindow(
                  context,
                  targets: const ['C002 · A', 'C003 · A'],
                  unlink: unlink,
                  unlinkOffReason: 'why not',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the linked places and unlinks', (tester) async {
      var unlinked = 0;
      await pump(tester, unlink: () => unlinked += 1);
      expect(find.text('C002 · A'), findsOneWidget);
      expect(find.text('C003 · A'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('link-window-unlink')));
      await tester.pumpAndSettle();

      expect(unlinked, 1);
      expect(find.byKey(const ValueKey<String>('link-window')), findsNothing);
    });

    testWidgets('an unlink it may not do stays in place, off, and says why', (
      tester,
    ) async {
      await pump(tester, unlink: null);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('link-window-unlink')),
      );
      expect(button.onPressed, isNull);
      expect(find.byTooltip('why not'), findsOneWidget);
    });
  });

  group('the entrances', () {
    Future<void> roomy(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    Future<void> timeline(WidgetTester tester, EditorSessionManager s) async {
      await roomy(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: s,
              builder: (context, _) => TimelineTabHost(
                session: s,
                orientation: TimelineOrientation.horizontal,
                onOrientationChanged: (_) {},
                pixelsPerFrame: 24,
                onPixelsPerFrameChanged: (_) {},
                showSeconds: false,
                onShowSecondsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openBadge(WidgetTester tester, LayerId row) async {
      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-link-badge-${row.value}')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a linked row\'s badge opens the window, and its button '
        'unlinks every selected row', (tester) async {
      final s = session();
      final row = s.activeLayerId!;
      s.layerVerbs.linkDuplicateActiveLayer();
      final copy = s.activeLayerId!;
      s.rowSelection.value = [LayerRowAddress(row), LayerRowAddress(copy)];
      await timeline(tester, s);

      await openBadge(tester, row);
      expect(find.byKey(const ValueKey<String>('link-window')), findsOneWidget);
      expect(
        find.text('${s.requireActiveCut.name} · ${s.layerById(copy)!.name}'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('link-window-unlink')));
      await tester.pumpAndSettle();

      expect(
        [s.layerVerbs.isLayerLinked(row), s.layerVerbs.isLayerLinked(copy)],
        [false, false],
        reason: '「참조버튼 그대로 공용화된거」 — pressed inside the selection',
      );
    });

    testWidgets('on a linked cut the row\'s button is off and says why', (
      tester,
    ) async {
      final s = session();
      s.cutVerbs.createLinkedCutFromActiveCut();
      await timeline(tester, s);

      await openBadge(tester, s.activeLayerId!);

      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('link-window-unlink')),
      );
      expect(button.onPressed, isNull);
      expect(
        find.byTooltip(AppText.strings.linkWindowUnlinkLinkedCut),
        findsOneWidget,
      );
    });

    testWidgets('a linked cut\'s name wears the link icon, which opens the '
        'window, whose button makes the cut independent', (tester) async {
      final s = session();
      final source = s.requireActiveCut.id;
      s.cutVerbs.createLinkedCutFromActiveCut();
      final linked = s.requireActiveCut.id;
      await roomy(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: s,
              builder: (context, _) => StoryboardTabHost(
                session: s,
                pixelsPerFrame: 12,
                onPixelsPerFrameChanged: (_) {},
                showSeconds: false,
                onShowSecondsChanged: (_) {},
                thumbnails: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final painter = cutBlocksPainter(tester);
      final block = painter.blockForCut(source)!;
      expect(block.isLinkedCut, isTrue);
      final icon = painter.linkAffordanceRectOf(block)!;
      expect(
        icon.left,
        greaterThan(block.topBand.left),
        reason: 'right of the name, in the top band',
      );
      await tester.tapAt(
        tester.getTopLeft(cutBlocksFinder()) + icon.center,
      );
      await tester.pumpAndSettle();
      expect(find.text(s.cutById(linked)!.name), findsWidgets);

      await tester.tap(find.byKey(const ValueKey<String>('link-window-unlink')));
      await tester.pumpAndSettle();

      expect(s.cutVerbs.cutIsLinked(source), isFalse, reason: '독립시킴');
      expect(s.cutVerbs.linkedCutIds, isNot(contains(CutId(source.value))));
    });
  });
}
