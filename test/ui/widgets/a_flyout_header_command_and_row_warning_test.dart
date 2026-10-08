import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool's faces), the two things the app's one picker
/// (F-230) lacked for the list of faces 유저 took on 2026-10-06 — 「글꼴 ＋」
/// over the faces, and of a face that may not ride in a project: 「글꼴
/// 고를때든 도구 설정에서 해당 글꼴에 … 적어두자」:
///
/// • a HEADER can carry one command at its end — the ＋ of a list things
///   are brought into;
/// • a ROW can carry a warning under its name, as tall as the sentence
///   needs.
///
/// Both went into the picker, not round it.
void main() {
  const opener = ValueKey<String>('flyout-under-test');

  Future<void> pumpList(
    WidgetTester tester,
    List<PanelFlyoutEntry> Function() entries,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: PanelFlyoutButton(
              key: opener,
              label: 'Faces',
              entriesBuilder: entries,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(opener));
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  PanelFlyoutRowAction bring(VoidCallback onPressed) => PanelFlyoutRowAction(
    keyValue: 'face-bring',
    icon: Icons.add,
    tooltip: 'Bring a face',
    does: PanelFlyoutActionDoes.adds,
    onPressed: onPressed,
  );

  group('a header\'s command', () {
    testWidgets('🚨pressed, closes the list and runs — and no row is '
        'chosen', (tester) async {
      final heard = <String>[];
      await pumpList(
        tester,
        () => [
          PanelFlyoutHeader('Faces', action: bring(() => heard.add('bring'))),
          PanelFlyoutItem(
            keyValue: 'row-a',
            label: 'a',
            onSelected: () => heard.add('chose a'),
          ),
        ],
      );
      expect(key('face-bring'), findsOneWidget, reason: '⛔fixture');

      await tester.tap(key('face-bring'));
      await tester.pumpAndSettle();

      expect(heard, ['bring']);
      expect(key('row-a'), findsNothing, reason: 'the list closed');
    });

    testWidgets('runs AFTER the list has closed', (tester) async {
      bool? listStillOpen;
      await pumpList(
        tester,
        () => [
          PanelFlyoutHeader(
            'Faces',
            action: bring(
              () => listStillOpen = tester
                  .state<NavigatorState>(find.byType(Navigator))
                  .canPop(),
            ),
          ),
          const PanelFlyoutItem(keyValue: 'row-a', label: 'a'),
        ],
      );

      await tester.tap(key('face-bring'));
      await tester.pumpAndSettle();

      expect(listStillOpen, isFalse);
    });

    testWidgets('🚨is LIVE in a row that is not: its glyph is drawn at full '
        'strength, in the colour a plus wears everywhere', (tester) async {
      await pumpList(
        tester,
        () => [
          PanelFlyoutHeader('Faces', action: bring(() {})),
          const PanelFlyoutItem(keyValue: 'row-a', label: 'a'),
        ],
      );

      final glyph = find.descendant(
        of: key('face-bring'),
        matching: find.byIcon(Icons.add),
      );
      expect(
        tester.widget<Icon>(glyph).color,
        AppColors.addGlyph(enabled: true),
      );
      expect(IconTheme.of(tester.element(glyph)).opacity, 1.0);
      // The header itself is no command: it is the caption it always was.
      expect(
        tester
            .widget<PopupMenuItem<PanelFlyoutItem>>(key('face-bring-header'))
            .enabled,
        isFalse,
      );
    });

    testWidgets('the caption keeps its height with a command at its end, '
        'and a caption with none draws no button', (tester) async {
      await pumpList(
        tester,
        () => [
          PanelFlyoutHeader('Faces', action: bring(() {})),
          const PanelFlyoutHeader('Brought'),
          const PanelFlyoutItem(keyValue: 'row-a', label: 'a'),
        ],
      );

      expect(tester.getSize(key('face-bring-header')).height, 24);
      final plain = find.ancestor(
        of: find.text('Brought'),
        matching: find.byType(PopupMenuItem<PanelFlyoutItem>),
      );
      expect(tester.getSize(plain).height, 24);
      expect(
        find.descendant(of: plain, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('what a command does is what colours its glyph', () {
    PanelFlyoutRowAction doing(PanelFlyoutActionDoes does) =>
        PanelFlyoutRowAction(
          keyValue: 'k',
          icon: Icons.circle,
          tooltip: 't',
          does: does,
          onPressed: () {},
        );

    test('a plus the accent, a delete the delete red, anything else the '
        'row\'s own ink', () {
      expect(
        doing(PanelFlyoutActionDoes.adds).glyphColor,
        AppColors.addGlyph(enabled: true),
      );
      expect(
        doing(PanelFlyoutActionDoes.deletes).glyphColor,
        AppColors.deleteGlyph(enabled: true),
      );
      expect(doing(PanelFlyoutActionDoes.other).glyphColor, isNull);
      expect(
        PanelFlyoutRowAction(
          keyValue: 'k',
          icon: Icons.circle,
          tooltip: 't',
          onPressed: () {},
        ).does,
        PanelFlyoutActionDoes.other,
      );
    });
  });

  group('a row\'s warning', () {
    const short = 'Shows in another face.';
    final long = 'This font may not be put inside a document that is edited, '
        'so it changes when opened on another device. ' * 3;

    testWidgets('🚨is written under the row\'s name, in the warning colour '
        '— and the row is as tall as the sentence needs', (tester) async {
      await pumpList(
        tester,
        () => [
          const PanelFlyoutItem(keyValue: 'row-plain', label: 'Plain'),
          const PanelFlyoutItem(
            keyValue: 'row-short',
            label: 'Probe Sans',
            warning: short,
          ),
          PanelFlyoutItem(
            keyValue: 'row-long',
            label: 'Probe Serif',
            warning: long,
          ),
        ],
      );

      final written = tester.widget<Text>(find.text(short));
      expect(written.style!.color, AppColors.danger);
      // Under the name, inside the row.
      final row = tester.getRect(key('row-short'));
      final name = tester.getRect(find.text('Probe Sans'));
      final warning = tester.getRect(find.text(short));
      expect(warning.top, greaterThanOrEqualTo(name.bottom));
      expect(row.contains(warning.topLeft), isTrue);
      expect(row.contains(warning.bottomRight), isTrue);
      expect(warning.left, name.left, reason: 'in the row\'s own gutter');

      // A row with none is the height every row is; one with a sentence is
      // taller, and a longer sentence taller still — never cut.
      final plain = tester.getSize(key('row-plain')).height;
      final withShort = row.height;
      final withLong = tester.getSize(key('row-long')).height;
      expect(plain, flyoutRowHeight);
      expect(withShort, greaterThan(plain));
      expect(withLong, greaterThan(withShort));
      expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('🚨the row is still the row: a press on its name chooses '
        'it, and so does a press on its warning', (tester) async {
      final heard = <String>[];
      List<PanelFlyoutEntry> entries() => [
        PanelFlyoutItem(
          keyValue: 'row-short',
          label: 'Probe Sans',
          warning: short,
          onSelected: () => heard.add('chose'),
        ),
      ];

      await pumpList(tester, entries);
      await tester.tap(find.text('Probe Sans'));
      await tester.pumpAndSettle();
      expect(heard, ['chose']);

      await pumpList(tester, entries);
      await tester.tap(find.text(short));
      await tester.pumpAndSettle();
      expect(heard, ['chose', 'chose']);
    });

    testWidgets('🚨a list is as tall as its warnings make it when it '
        'chooses which way to open: one that would not fit below its '
        'button opens above it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // The button's bottom stands 60 from the window's: a row is 32 and
      // the list's own padding 16, so ONE plain row fits below — and one
      // with a warning under it does not.
      Future<Rect> rowOpenedFrom(PanelFlyoutItem item) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: PanelFlyoutButton(
                    key: opener,
                    label: 'Faces',
                    entriesBuilder: () => [item],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(opener));
        await tester.pumpAndSettle();
        return tester.getRect(key(item.keyValue));
      }

      Rect button() => tester.getRect(find.byKey(opener));
      final plain = await rowOpenedFrom(
        const PanelFlyoutItem(keyValue: 'row-plain', label: 'Plain'),
      );
      expect(plain.top, greaterThanOrEqualTo(button().bottom));
      await tester.tapAt(const Offset(390, 10));
      await tester.pumpAndSettle();

      final warned = await rowOpenedFrom(
        const PanelFlyoutItem(
          keyValue: 'row-short',
          label: 'Probe Sans',
          warning: short,
        ),
      );
      expect(warned.bottom, lessThanOrEqualTo(button().top));
    });

    testWidgets('a warned row carries its own command where every row '
        'does: at the end of its NAME\'s line', (tester) async {
      await pumpList(
        tester,
        () => [
          PanelFlyoutItem(
            keyValue: 'row-short',
            label: 'Probe Sans',
            warning: short,
            action: PanelFlyoutRowAction(
              keyValue: 'row-short-delete',
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              does: PanelFlyoutActionDoes.deletes,
              onPressed: () {},
            ),
          ),
        ],
      );

      final name = tester.getRect(find.text('Probe Sans'));
      final button = tester.getRect(key('row-short-delete'));
      expect(button.center.dy, closeTo(name.center.dy, 1));
    });
  });
}
