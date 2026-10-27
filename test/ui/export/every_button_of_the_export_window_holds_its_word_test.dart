import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/app_faces.dart';

/// 🗣️F-486 (유저 2026-10-27): 「출력창 셀 탭, 콘티같은거 일본어에서 빈
/// 버튼되는데 아마 길어서 문제생기는듯. 일단 출력창 버튼들 자동맞춤해서
/// 글자에 맞게 되도록」.
///
/// Every button of the export window — a pill, a list button, a glyph
/// button that writes a word — shows its whole word, on every tab, at the
/// window's least, in each face the app ships. ↩️The Cels list's rules stood
/// 168 wide in every language: 「絵コンテ」 got 22 of its 43 px, 「ディレクション」
/// 22 of its 71.
///
/// ⚠️Chinese is set in the OS's face (`AppTypography.familyFor`), which the
/// test bed does not have: what it measures there is the test font.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const cutId = CutId('cut');
  EditorSessionManager film() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 32, height: 18),
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: cutId,
              name: '301',
              duration: 2,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  frames: [
                    Frame(
                      id: const FrameId('a1'),
                      duration: 1,
                      strokes: const [],
                      name: '1',
                    ),
                  ],
                  mark: const LayerMark(process: LayerProcess.key),
                ),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  /// Every word a button of [type] sets short of its own width, and by how
  /// much.
  List<String> cutWords(WidgetTester tester, Type type) => [
    for (final element in find
        .descendant(of: find.byType(type), matching: find.byType(RichText))
        .evaluate())
      if (element.renderObject case final RenderParagraph paragraph)
        if ((
              given: paragraph.size.width,
              whole: paragraph.getMaxIntrinsicWidth(double.infinity),
            )
            case (:final given, :final whole) when given + 0.5 < whole)
          '「${paragraph.text.toPlainText()}」 '
              '${given.toStringAsFixed(1)} of ${whole.toStringAsFixed(1)}',
  ];

  for (final language in [
    for (final language in AppLanguage.values)
      if (AppTypography.familyFor(language) != null) language,
  ]) {
    testWidgets('🚨every button holds its whole word on every tab — '
        '${language.name}', (tester) async {
      await loadTheAppFaces();
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      final session = film();
      addTearDown(session.dispose);
      // A screen whose share is narrower than the window's least and whose
      // room is not: the window stands at its least.
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
      for (final tab in ExportTab.values) {
        await tester.tap(
          find.byKey(ValueKey<String>('export-tab-${tab.jsonValue}')),
        );
        await tester.pump();
        for (final type in [Pill, PanelFlyoutChip, AppIconButton]) {
          expect(
            cutWords(tester, type),
            isEmpty,
            reason: '${tab.name}: the ${type}s',
          );
        }
      }
      session.playbackRig.prerenderScheduler.cancel();
    });
  }

  testWidgets('the rules stand as wide as their widest strip of kinds where '
      'that is wider than their least — and at their least where it is not', (
    tester,
  ) async {
    await loadTheAppFaces();
    final widths = <AppLanguage, double>{};
    for (final language in [AppLanguage.ko, AppLanguage.ja]) {
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      final session = film();
      addTearDown(session.dispose);
      await tester.binding.setSurfaceSize(const Size(1300, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
      await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
      await tester.pump();
      double stripOf(String pill) => tester
          .getSize(
            find
                .ancestor(
                  of: find.byKey(ValueKey<String>('export-cels-kind-$pill')),
                  matching: find.byType(PillStrip),
                )
                .first,
          )
          .width;
      final need = tester
          .widget<ExportCelsBoard>(find.byType(ExportCelsBoard))
          .rulesNeed;
      widths[language] = tester
          .getSize(find.byKey(const ValueKey<String>('export-cels-rules')))
          .width;
      if (language == AppLanguage.ja) {
        expect(
          need,
          moreOrLessEquals(
            16 + [stripOf('cel'), stripOf('timesheet')].reduce(
              (a, b) => a > b ? a : b,
            ),
            epsilon: 0.01,
          ),
          reason: 'its padding and its widest strip, every word whole',
        );
      }
      session.playbackRig.prerenderScheduler.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(widths[AppLanguage.ko], ExportCelsBoard.leastRulesWidth);
    expect(
      widths[AppLanguage.ja],
      greaterThan(ExportCelsBoard.leastRulesWidth),
    );
  });
}
