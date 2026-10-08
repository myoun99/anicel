import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
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
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/app_faces.dart';

/// The Cels list's rules column (F-289) was drawn 168 wide around the words
/// it holds — 셀 · 콘티 · 미술 · 디렉션 in one strip, 기준 · 어태치 beside
/// 시트만 — and they are to stand there WHOLE, in the app's own faces.
///
/// 🚨Measured in the app's faces ([loadTheAppFaces]): the test font is
/// wider, and in it 「디렉션」 is two pixels short of its room.
///
/// ↩️The strips stood in a `FittedBox`, which shrank their type where the
/// words ran long, and then as `Flexible`s, which cut 「디렉션」 and
/// 「어태치」 to an equal share of a column they fitted.
void main() {
  setUpAll(loadTheAppFaces);
  setUp(() {
    AppExport.settings.value = AppExportSettings();
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
    );
  });
  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    AppText.settings.value = const AppLanguageSettings();
  });

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

  Future<void> pumpCels(WidgetTester tester, Size surface) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final session = film();
    addTearDown(session.dispose);
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
  }

  Finder inTheBoard(Finder finder) => find.descendant(
    of: find.byKey(const ValueKey<String>('export-cels-board')),
    matching: finder,
  );

  for (final (name, surface) in [
    ('a desktop window', const Size(1480, 900)),
    ('an 11-inch tablet', const Size(1194, 834)),
  ]) {
    testWidgets('in Korean every word of the rules column stands whole — '
        '$name', (tester) async {
      await pumpCels(tester, surface);
      expect(tester.takeException(), isNull);
      final pills = tester.widgetList<Pill>(inTheBoard(find.byType(Pill)));
      expect(
        [for (final pill in pills) pill.label],
        containsAll(['셀', '콘티', '미술', '디렉션', '기준', '어태치', '시트만']),
        reason: 'LIVENESS — these are the words being measured',
      );
      for (final pill in pills) {
        final word = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byWidget(pill),
            matching: find.text(pill.label),
          ),
        );
        expect(
          word.size.width,
          greaterThanOrEqualTo(
            word.getMaxIntrinsicWidth(double.infinity) - 0.01,
          ),
          reason: '「${pill.label}」 is cut short',
        );
      }
    });
  }

  testWidgets('in Korean 시트만 stands beside 기준 · 어태치, on their line', (
    tester,
  ) async {
    await pumpCels(tester, const Size(1480, 900));
    Rect pill(String key) => tester.getRect(
      find.byKey(ValueKey<String>('export-cels-select-$key')),
    );
    expect(pill('sheet').top, pill('base').top);
    expect(pill('sheet').left, greaterThan(pill('attach').right));
  });
}
