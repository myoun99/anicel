import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/services/commands/convert_to_linked_cut_plan.dart';
import 'package:anicel/src/ui/dialogs/convert_to_linked_cut_dialog.dart';

/// 겸용 변경 dialog (L4): the 안내문 spells out links, 원본 승리
/// replacements and appearing layers before anything executes; Link pops
/// the chosen target cut id.
void main() {
  const replaced = ['2 · A · 1', '2 · A · 2', '2 · B · 1'];
  const linkingPreview = ConvertToLinkedCutPreviewData(
    targetCutName: '2',
    linkingLayerNames: ['A', 'B'],
    layerNamesAppearingInTarget: ['only-here'],
    layerNamesAppearingInOrigin: ['only-there'],
    replacedDrawings: replaced,
    joiningFrameCount: 2,
    linksAnything: true,
  );

  Future<CutId?> show(
    WidgetTester tester, {
    required ConvertToLinkedCutPreviewData? Function(CutId) previewOf,
    List<({CutId id, String name})>? candidates,
  }) async {
    CutId? result;
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<CutId>(
                context: context,
                builder: (context) => ConvertToLinkedCutDialog(
                  activeCutName: '1',
                  candidates:
                      candidates ?? [(id: const CutId('cut-2'), name: '2')],
                  previewOf: previewOf,
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(popped, isFalse);
    return result;
  }

  testWidgets('a single candidate preselects; the 안내문 lists links, '
      '원본 승리 replacements and appearing layers; Link pops the id', (
    tester,
  ) async {
    await show(tester, previewOf: (_) => linkingPreview);

    // F-303: the layers it links are LISTED under their heading — ↩️they
    // were joined into the sentence 「Links A, B.」.
    expect(find.text('Layers linked (2)'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(
      find.textContaining('replaced by the origin\'s (원본 승리)'),
      findsOneWidget,
    );
    // I-18 link-notice-Q1 「겸용 변환 안내문을 목록으로」: the drawings it
    // replaces are listed, open, under that line.
    for (final drawing in replaced) {
      expect(
        find.descendant(
          // One list among several now: any of the window's lists.
          of: find.byKey(const ValueKey<String>('app-notice-details-list')),
          matching: find.text(drawing),
        ),
        findsOneWidget,
        reason: drawing,
      );
    }
    expect(
      find.textContaining('2 drawing(s) join the shared set.'),
      findsOneWidget,
    );
    expect(find.text('Added to "2" (1)'), findsOneWidget);
    expect(find.text('only-here'), findsOneWidget);
    expect(find.text('Added to this cut (1)'), findsOneWidget);
    expect(find.text('only-there'), findsOneWidget);
    expect(find.textContaining('Undo restores both cuts.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('convert-linked-cut-confirm-button')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('nothing-to-link preview disables Link and says why', (
    tester,
  ) async {
    const emptyPreview = ConvertToLinkedCutPreviewData(
      targetCutName: '2',
      linkingLayerNames: [],
      layerNamesAppearingInTarget: [],
      layerNamesAppearingInOrigin: [],
      replacedDrawings: [],
      joiningFrameCount: 0,
      linksAnything: false,
    );
    await show(tester, previewOf: (_) => emptyPreview);

    expect(find.textContaining('Nothing to link'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('convert-linked-cut-confirm-button')),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('multiple candidates start unselected: no preview, Link '
      'disabled until a cut is picked', (tester) async {
    await show(
      tester,
      previewOf: (_) => linkingPreview,
      candidates: [
        (id: const CutId('cut-2'), name: '2'),
        (id: const CutId('cut-3'), name: '3'),
      ],
    );

    expect(find.text('Layers linked (2)'), findsNothing);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('convert-linked-cut-confirm-button')),
    );
    expect(confirm.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('convert-linked-cut-target')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    expect(find.text('Layers linked (2)'), findsOneWidget);
  });
}
