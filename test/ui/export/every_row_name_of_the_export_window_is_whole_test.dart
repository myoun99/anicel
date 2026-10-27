import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/app_faces.dart';

/// 🗣️F-486-Q1 (유저 2026-10-27): 「칸 이름만 맞춘다」.
///
/// The settings column's row names stand in one column as wide as the
/// widest name a row there can give in the program's language — the ones a
/// folded accordion or another format holds counted too — so every control
/// starts at one x and no name gives its end up. ↩️The column stood 54 in
/// every language: 「ビットレート」 had 54 of its 60 px, 「Channels」 54 of 61.
///
/// ⚠️Chinese is set in the OS's face (`AppTypography.familyFor`), which the
/// test bed does not have: what it measures there is the test font.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  /// The widest of every row name in [context]'s language, laid out as a
  /// name is — measured here, apart from the window's own measure.
  double widestName(BuildContext context) {
    final theme = Theme.of(context);
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(theme.textTheme.labelSmall);
    var widest = 0.0;
    for (final caption in ExportCaption.values) {
      final painter = TextPainter(
        text: TextSpan(text: caption.wordsIn(AppText.strings), style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width > widest) {
        widest = painter.width;
      }
      painter.dispose();
    }
    return widest;
  }

  /// Opens every accordion the tab shows folded, until none is.
  Future<void> unfoldAll(WidgetTester tester) async {
    for (var round = 0; round < 20; round += 1) {
      final folded = [
        for (final element in find.byType(ExportAccordion).evaluate())
          if (element.widget case final ExportAccordion accordion
              when !accordion.expanded)
            accordion,
      ];
      if (folded.isEmpty) {
        return;
      }
      folded.first.onToggle();
      await tester.pump();
    }
    fail('an accordion would not stay open');
  }

  for (final language in [
    for (final language in AppLanguage.values)
      if (AppTypography.familyFor(language) != null) language,
  ]) {
    testWidgets('🚨every row name stands whole, in one column as wide as the '
        'widest — ${language.name}', (tester) async {
      await loadTheAppFaces();
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      await tester.binding.setSurfaceSize(const Size(1300, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ExportDialog(
              session: session,
              formatAvailability: ExportFormatAvailability.permissive(),
            ),
          ),
        ),
      );
      await tester.pump();
      var names = 0;
      for (final tab in ExportTab.values) {
        await tester.tap(
          find.byKey(ValueKey<String>('export-tab-${tab.jsonValue}')),
        );
        await tester.pump();
        await unfoldAll(tester);
        for (final element in find.byType(ExportModuleRow).evaluate()) {
          final row = element.widget as ExportModuleRow;
          final words = row.caption.wordsIn(AppText.strings);
          final name = find.descendant(
            of: find.byWidget(row),
            matching: find.text(words),
          );
          final paragraph =
              name.evaluate().first.renderObject! as RenderParagraph;
          expect(
            paragraph.size.width,
            // Where the row lays its name out.
            moreOrLessEquals(widestName(element), epsilon: 0.01),
            reason: '${tab.name}: 「$words」 stands in the one column',
          );
          expect(
            paragraph.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(paragraph.size.width + 0.01),
            reason: '${tab.name}: 「$words」 whole',
          );
          names += 1;
        }
      }
      expect(names, greaterThan(0), reason: 'the premise: rows were read');
      session.playbackRig.prerenderScheduler.cancel();
    });
  }
}
