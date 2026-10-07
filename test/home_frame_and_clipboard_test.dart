// HomePage widget tests — frame names and the clipboard verbs.
// Split from widget_test.dart (2026-09-04) so the suite runs across
// isolates; the shared probes live in helpers/home_page_probes.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart'
    show breakdownMark, unnamedDrawingMark;
import 'package:anicel/main.dart';
import 'package:anicel/src/models/timeline_row_address.dart';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import 'helpers/home_page_probes.dart';

void main() {
  testWidgets('rename to empty clears frame name', (WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());

    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    await renameCurrentFrame(tester, 'A1');
    expectCellText('default-layer-1', 0, 'A1');

    await renameCurrentFrame(tester, '   ');

    expectCellMark('default-layer-1', 0, unnamedDrawingMark);
  });

  testWidgets('conflicting frame name dialog cancel leaves frames unchanged', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    await renameCurrentFrame(tester, 'A1');
    await createSecondAuthoredFrame(tester);

    await renameCurrentFrame(tester, 'A1');

    expect(
      find.byKey(const ValueKey<String>('frame-name-conflict-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('frame-name-conflict-cancel-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('frame-name-conflict-link-button')),
      findsOneWidget,
    );
    expect(find.text('Rename only'), findsNothing);
    // I-18: the notice lists the frames the link takes — here the ONE being
    // renamed, the unnamed second drawing.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('app-notice-details-list')),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('frame-name-conflict-cancel-button')),
    );
    await tester.pumpAndSettle();

    expectCellText('default-layer-1', 0, 'A1');
    expectCellMark('default-layer-1', 1, unnamedDrawingMark);
  });

  testWidgets('conflicting frame name link merges into existing material', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    await renameCurrentFrame(tester, 'A1');
    await createSecondAuthoredFrame(tester);

    await renameCurrentFrame(tester, 'A1');
    await tester.tap(
      find.byKey(const ValueKey<String>('frame-name-conflict-link-button')),
    );
    await tester.pumpAndSettle();

    expectCellText('default-layer-1', 0, 'A1');
    expectCellText('default-layer-1', 1, 'A1');
    expect(find.text('Rename only'), findsNothing);
  });

  testWidgets('rename cancel leaves frame marker unchanged', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    final newFrameButton = find.byKey(
      const ValueKey<String>('new-frame-button'),
    );

    await tester.ensureVisible(newFrameButton);
    await tester.pumpAndSettle();
    await tester.tap(newFrameButton);
    await tester.pumpAndSettle();
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-frame-text-field')),
      'Cancelled',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-frame-cancel-button')),
    );
    await tester.pumpAndSettle();
    expectCellMark('default-layer-1', 0, unnamedDrawingMark);
    expect(find.text('Cancelled'), findsNothing);
  });

  testWidgets('linked frame copy and paste buttons link authored exposures', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    // Copy/paste-linked live in the Frame ▾ flyout (R-toolbar round);
    // enablement reads open the menu themselves.
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-copy-button'),
      ),
      isFalse,
    );
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-paste-linked-button'),
      ),
      isFalse,
    );

    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));

    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-copy-button'),
      ),
      isTrue,
    );

    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-copy-button'),
    );
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-paste-linked-button'),
      ),
      isTrue,
    );

    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-1'),
    );

    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-paste-linked-button'),
    );

    expectCellMark('default-layer-1', 0, unnamedDrawingMark);
    expectCellMark('default-layer-1', 1, unnamedDrawingMark);
  });

  testWidgets(
    'linked paste on a dot-held cell: the drawing wins and the cut-off '
    'dot drops',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      await tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-copy-button'),
      );
      await addLayer(tester);

      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-2-0'),
      );
      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-paste-linked-button'),
        ),
        isFalse,
      );

      // Grow the block to [0,2) and dot its held cell.
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-0'),
      );
      await dragBlockEndGrip(tester, 'default-layer-1', 0, 1);
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-1'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('toggle-mark-button'),
      );
      expectCellMark('default-layer-1', 1, breakdownMark);
      expect(
        selectedCellStateLabel(tester),
        'inbetween mark',
        reason: '⛔전제: the held cell really carries a dot',
      );

      // The paste authors a drawing start on the dot's cell: the covering
      // block shrinks to [0,1) and the cut-off dot goes with it.
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-paste-linked-button'),
      );

      // ⚠️ASKED BY STATE, NOT BY GLYPH. This used to read「the ● is gone and
      // the ○ is there」, which worked only while a dot and an unnamed
      // drawing looked different. 유저 made them one mark (F-149, 2026-09-16:
      // 「이름 없는 기본상태를 속이 찬 동그라미로 통일적용」), so the glyph
      // can no longer say which one the cell is — the cell's state can.
      expectCellMark('default-layer-1', 1, unnamedDrawingMark);
      expect(selectedCellStateLabel(tester), 'drawing start');
    },
  );

  /// 🗣️I-77 (유저 2026-10-06): 「복사/붙여넣기버튼 레이어도 연결. 레이어
  /// 선택,다중선택등에서 복사 붙여넣기버튼 가능하게. 그러고 레이어버튼의
  /// 레이어복사/붙여넣기는 필요없으니 삭제」. ↩️These three drove the Layer ▾
  /// flyout's 'copy-layer-button' and 'paste-layer-button'.
  Future<EditorSessionManager> withTheActiveRowSelected(
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.rowSelectionVerbs.beginRowSelection(
      LayerRowAddress(session.activeLayerId!),
    );
    await tester.pumpAndSettle();
    return session;
  }

  const copyKey = ValueKey<String>('shared-copy-button');
  const pasteKey = ValueKey<String>('shared-paste-independent-button');
  const pasteLinkedKey = ValueKey<String>('shared-paste-linked-button');

  testWidgets('the shared pill copies the selected ROW, and both pastes '
      'light behind it', (WidgetTester tester) async {
    final session = await withTheActiveRowSelected(tester);

    expect(await isActionButtonEnabled(tester, copyKey), isTrue);
    expect(await isActionButtonEnabled(tester, pasteKey), isFalse);
    expect(await isActionButtonEnabled(tester, pasteLinkedKey), isFalse);

    // The Layer ▾ flyout lists none of the three it used to.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-menu-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('duplicate-layer-button')),
      findsOneWidget,
      reason: '⛔전제: the flyout is open',
    );
    for (final gone in const [
      'copy-layer-button',
      'paste-layer-button',
      'timeline-link-duplicate-button',
    ]) {
      expect(find.byKey(ValueKey<String>(gone)), findsNothing, reason: gone);
    }
    await tester.tapAt(const Offset(5, 400));
    await tester.pumpAndSettle();

    await tapToolbarButton(tester, copyKey);

    expect(session.layerClipboard.hasLayerClipboard, isTrue);
    expect(await isActionButtonEnabled(tester, pasteKey), isTrue);
    expect(await isActionButtonEnabled(tester, pasteLinkedKey), isTrue);

    // The row it was copied off goes: nothing is left to share, and the
    // linked paste dims on its own — the independent one stays.
    session.layerVerbs.deleteSelectedLayers();
    await tester.pumpAndSettle();
    expect(await isActionButtonEnabled(tester, pasteLinkedKey), isFalse);
    expect(await isActionButtonEnabled(tester, pasteKey), isTrue);
  });

  testWidgets(
    'the pill\'s paste creates another A, selects it, and undo/redo works',
    (WidgetTester tester) async {
      await withTheActiveRowSelected(tester);

      await tapToolbarButton(tester, copyKey);
      await tapToolbarButton(tester, pasteKey);

      expect(find.text('A'), findsWidgets);
      // Two drawing rows plus the always-present fixtures: S1·S2, CAM 1,
      // the camera, and the track's transition row.
      expect(timelineLayerRows(), findsNWidgets(7));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-selected-layer')),
          matching: find.text('A'),
        ),
        findsOneWidget,
      );

      await tapToolbarButton(tester, const ValueKey<String>('undo-button'));
      expect(timelineLayerRows(), findsNWidgets(6));

      await tapToolbarButton(tester, const ValueKey<String>('redo-button'));
      expect(timelineLayerRows(), findsNWidgets(7));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-selected-layer')),
          matching: find.text('A'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('pasted layer can be renamed and deleted', (
    WidgetTester tester,
  ) async {
    await withTheActiveRowSelected(tester);

    await tapToolbarButton(tester, copyKey);
    await tapToolbarButton(tester, pasteKey);
    // T25: the loose rename is folded into the shared Edit Instance, whose
    // subject is the selection — so the row is named first, exactly as the
    // ONE delete already asks.
    {
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(session.activeLayerId!));
      await tester.pumpAndSettle();
    }
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-layer-text-field')),
      'Pasted',
    );
    await tapToolbarButton(
      tester,
      const ValueKey<String>('rename-layer-ok-button'),
    );

    expect(find.text('Pasted'), findsWidgets);

    // ⑰/F: the ONE delete asks what is selected, so the row is named first.
    // Standing on it is not naming it — ⑨ made those two states independent.
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(session.activeLayerId!));
    await tester.pumpAndSettle();
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-delete-button'),
    );
    await tapToolbarButton(
      tester,
      const ValueKey<String>('delete-layer-confirm-button'),
    );

    expect(find.text('Pasted'), findsNothing);
  });

  testWidgets(
    'Duplicate Layer button duplicates active layer and selects copy',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('duplicate-layer-button'),
        ),
        isTrue,
      );

      await tapToolbarButton(
        tester,
        const ValueKey<String>('duplicate-layer-button'),
      );

      expect(find.text('A'), findsWidgets);
      // Two drawing rows plus the always-present fixtures: S1·S2, CAM 1,
      // the camera, and the track's transition row.
      expect(timelineLayerRows(), findsNWidgets(7));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-selected-layer')),
          matching: find.text('A'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('duplicated layer can be renamed and deleted', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await tapToolbarButton(
      tester,
      const ValueKey<String>('duplicate-layer-button'),
    );
    // T25: the loose rename is folded into the shared Edit Instance, whose
    // subject is the selection — so the row is named first, exactly as the
    // ONE delete already asks.
    {
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(session.activeLayerId!));
      await tester.pumpAndSettle();
    }
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-layer-text-field')),
      'Dup',
    );
    await tapToolbarButton(
      tester,
      const ValueKey<String>('rename-layer-ok-button'),
    );

    expect(find.text('Dup'), findsWidgets);

    // ⑰/F: name the row, then press the ONE delete.
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(session.activeLayerId!));
    await tester.pumpAndSettle();
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-delete-button'),
    );
    await tapToolbarButton(
      tester,
      const ValueKey<String>('delete-layer-confirm-button'),
    );

    expect(find.text('Dup'), findsNothing);
  });
}
