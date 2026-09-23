import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/color/color_status_bar.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart'
    show showColorPickerPopup;

import '../../helpers/app_faces.dart';

/// 🚨text-scale-fixed-height-bars (유저 2026-09-18). Asked what a bar of a
/// fixed height does when the OS text size goes up, the answer was
/// 「막대가 글자 크기를 따라 자란다」 — with its stated cost, 「타임라인 위 줄과
/// 컬러 패널이 두꺼워진다」. The two bars it named: the command bar's pills
/// and the colour readout; a census of the whole screen found a third, the
/// canvas view pill.
///
/// 🔬Measured in the app's own face before the fix:
/// - at 1× — the size everyone runs — the readout's hex was 56.5 wide in a
///   54 cell, so `#000000` wrapped its last digit onto a line the 26px bar
///   cut off;
/// - at 1.5× the pills' names stood 25 in their 24, the frame counter
///   OVERFLOWED the command bar by 11px, stripes and all, and the view
///   pill's `100.00%` wrapped inside its 74;
/// - at 2× every word of all three stood taller than its box.
///
/// ⚠️In the app's face or not at all ([loadTheAppFaces]): the test font's
/// glyphs are other widths, and the 1× case does not happen in it.
/// ⚠️And in the real root ([AnicelApp]): a bar is only as tall as the dock
/// and the fold that hold it let it be, and those ask the same questions.
void main() {
  setUpAll(loadTheAppFaces);

  /// Every paragraph under [of] that is shorter than its own text at the
  /// width it was given — a word its box cuts off.
  List<String> wordsCutOff(Finder of) {
    final cut = <String>[];
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        final need = object.getMinIntrinsicHeight(object.size.width);
        if (object.size.height + 0.5 < need) {
          cut.add(
            '「${object.text.toPlainText()}」 ${object.size.height} < $need',
          );
        }
      }
      object.visitChildren(visit);
    }

    for (final element in of.evaluate()) {
      visit(element.renderObject!);
    }
    return cut;
  }

  void atTextScale(WidgetTester tester, double scale) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// The app, with the colour group open beside the timeline.
  Future<void> openTheApp(WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('rail-group-rail-R1')));
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    group('at $scale×', () {
      testWidgets('no word of the command bar is cut off, and the bar is the '
          'height its floor and its fold ask for', (tester) async {
        atTextScale(tester, scale);
        await openTheApp(tester);

        final bar = find.byType(TimelineCommandBar);
        expect(bar, findsOneWidget, reason: 'LIVENESS — the timeline shows');
        expect(wordsCutOff(bar), isEmpty);
        expect(
          tester.getSize(bar).height,
          TimelineCommandBar.heightIn(tester.element(bar)),
          reason: 'one answer to how tall the bar is — the bar itself and '
              'what holds it',
        );
      });

      testWidgets('no word of the canvas view pill is cut off', (tester) async {
        atTextScale(tester, scale);
        await openTheApp(tester);

        final pill = find.byKey(const ValueKey<String>('canvas-view-pill'));
        expect(pill, findsWidgets, reason: 'LIVENESS — a canvas shows');
        expect(
          find.descendant(
            of: pill,
            matching: find.byKey(
              const ValueKey<String>('canvas-viewport-zoom-label'),
            ),
          ),
          findsWidgets,
          reason: 'LIVENESS — the readout is on a pill, not folded away',
        );
        expect(wordsCutOff(pill), isEmpty);
      });

      testWidgets('no word of the colour readout is cut off', (tester) async {
        atTextScale(tester, scale);
        await openTheApp(tester);

        final readout = find.byType(ColorStatusBar);
        expect(readout, findsOneWidget, reason: 'LIVENESS — the readout shows');
        expect(wordsCutOff(readout), isEmpty);
      });

      testWidgets('the picker popup holds its readout whole', (tester) async {
        atTextScale(tester, scale);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showColorPickerPopup(
                    context,
                    color: 0xFF000000,
                    onChanged: (_) {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final readout = find.byType(ColorStatusBar);
        expect(readout, findsOneWidget, reason: 'LIVENESS — the popup opened');
        expect(
          wordsCutOff(readout),
          isEmpty,
          reason: 'and a popup too narrow for it would have thrown an '
              'overflow',
        );
      });
    });
  }

  /// The pills' groups are built once and handed back until something they
  /// show changes — and the OS text size is now one of those things.
  testWidgets('the OS text size changing under a running app reaches the '
      'bar', (tester) async {
    atTextScale(tester, 1.0);
    await openTheApp(tester);

    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    await tester.pumpAndSettle();

    final bar = find.byType(TimelineCommandBar);
    expect(wordsCutOff(bar), isEmpty);
    expect(
      tester.getSize(bar).height,
      greaterThan(TimelineCommandBar.height),
      reason: 'LIVENESS — the bar grew',
    );
  });

  testWidgets('at 1× the bars are the height they were drawn at — nothing '
      'drawn at 1× moves', (tester) async {
    atTextScale(tester, 1.0);
    await openTheApp(tester);

    expect(
      tester.getSize(find.byType(TimelineCommandBar)).height,
      TimelineCommandBar.height,
    );
    expect(
      tester.getSize(find.byType(ColorStatusBar)).height,
      ColorStatusBar.height,
    );
    expect(
      {
        for (final pill in find
            .byKey(const ValueKey<String>('canvas-view-pill'))
            .evaluate())
          (pill.renderObject! as RenderBox).size.height,
      },
      {28},
      reason: 'every view pill as drawn',
    );
  });
}
