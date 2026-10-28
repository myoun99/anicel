import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/canvas_read_source.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/frame_census.dart';
import '../../helpers/rail_group_button.dart';

/// 🚨I-57 ㉢ (10-13, measured on the user's project): every tool's settings
/// panel is kept alive, and each one rebuilt on EVERY session notify — a
/// cut switch rebuilt them all, 121 widgets a panel, and so did a stroke's
/// commit, though the brush's panel shows nothing of the cut. The panel
/// rebuilds by what it shows of the session now (`SlicedListenableBuilder`):
/// news that moves none of it stops at the host — and every part of what
/// it shows still reaches it, read here one part at a time.
const _first = CutId('first');
const _second = CutId('second');
const _third = CutId('third');

final _mirror = DrawingGuide(
  id: const GuideId('mirror'),
  name: 'Mirror',
  shape: SymmetryShape(
    axis: GuideAxis(origin: CanvasPoint(x: 320, y: 180), angleDegrees: 90),
    lineCount: 2,
  ),
);

Layer _drawing(String id) => Layer(
  id: LayerId(id),
  name: id,
  frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
  timeline: const {},
);

Cut _cut(CutId id, List<Layer> layers, {CanvasSize? size}) => Cut(
  id: id,
  name: id.value,
  duration: 12,
  canvasSize: size ?? const CanvasSize(width: 640, height: 360),
  layers: layers,
);

/// The real app with the tool settings group open on the rail, standing on
/// the first cut's `a1`.
Future<EditorSessionManager> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: Project(
          id: const ProjectId('tool-settings'),
          name: 'Tool settings',
          createdAt: DateTime.utc(2026, 10, 13),
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Video',
              cuts: [
                _cut(_first, [_drawing('a1'), _drawing('a2')]),
                _cut(_second, [_drawing('b1'), _drawing('b2')]),
                // A canvas of another size: the selection tool's invert
                // reaches out to the canvas's edge, so the panel holds it.
                _cut(
                  _third,
                  [_drawing('c1')],
                  size: const CanvasSize(width: 320, height: 180),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await pressToolSettingsButton(tester);
  await tester.pumpAndSettle();
  final session = tester
      .widget<EditorWorkspace>(find.byType(EditorWorkspace))
      .session;
  session.selectLayer(const LayerId('a1'));
  await tester.pumpAndSettle();
  for (final panel in _toolSettings) {
    expect(find.byType(panel), findsOneWidget, reason: 'LIVENESS: $panel');
  }
  return session;
}

const _toolSettings = [ToolSettingsPanel, BrushSettingsPanel];

ToolSettingsPanel _panel(WidgetTester tester) =>
    tester.widget<ToolSettingsPanel>(find.byType(ToolSettingsPanel));

void main() {
  testWidgets('a cut switch that moves nothing they show rebuilds none of '
      'the tool settings', (tester) async {
    final session = await _open(tester);

    final census = await frameCensus(tester, () => session.selectCut(_second));

    expect(session.activeCutId, _second, reason: 'LIVENESS: it switched');
    expect(
      census.rebuilt,
      isNotEmpty,
      reason: 'LIVENESS: the switch rebuilt what shows the cut',
    );
    for (final panel in _toolSettings) {
      expect(census.rebuilt, isNot(contains(panel)), reason: '$panel');
    }
  });

  testWidgets('news about another row rebuilds none of them', (tester) async {
    final session = await _open(tester);

    final census = await frameCensus(
      tester,
      () => session.selectLayer(const LayerId('a2')),
    );

    expect(session.activeLayerId, const LayerId('a2'), reason: 'LIVENESS');
    for (final panel in _toolSettings) {
      expect(census.rebuilt, isNot(contains(panel)), reason: '$panel');
    }
  });

  group('what they show still reaches them', () {
    testWidgets('the cut\'s guides', (tester) async {
      final session = await _open(tester);

      final census = await frameCensus(
        tester,
        () => session.cutVerbs.setActiveCutGuides(
          CutGuides(guides: [_mirror], activeSymmetryId: _mirror.id),
        ),
      );

      expect(census.rebuilt, contains(ToolSettingsPanel));
    });

    testWidgets('the guide picked', (tester) async {
      final session = await _open(tester);
      session.cutVerbs.setActiveCutGuides(CutGuides(guides: [_mirror]));
      await tester.pumpAndSettle();

      final census = await frameCensus(
        tester,
        () => session.cutVerbs.selectedGuideId = _mirror.id,
      );

      expect(census.rebuilt, contains(ToolSettingsPanel));
    });

    testWidgets('a canvas of another size', (tester) async {
      final session = await _open(tester);

      final census = await frameCensus(
        tester,
        () => session.selectCut(_third),
      );

      expect(census.rebuilt, contains(ToolSettingsPanel));
    });

    testWidgets('the program\'s language — news the session never carries', (
      tester,
    ) async {
      final session = await _open(tester);
      final settings = session.languageSettings.value;

      final census = await frameCensus(
        tester,
        () => session.languageSettings.value = settings.copyWith(
          programLanguage: settings.programLanguage == AppLanguage.ko
              ? AppLanguage.ja
              : AppLanguage.ko,
        ),
      );

      expect(census.rebuilt, contains(ToolSettingsPanel));
    });

    testWidgets('the layers the fill reads', (tester) async {
      final session = await _open(tester);
      final panel = _panel(tester);
      panel.onFillOptionsChanged(
        panel.fillOptions.copyWith(source: CanvasReadSource.layer),
      );
      await tester.pumpAndSettle();

      final census = await frameCensus(
        tester,
        () => session.selectLayer(const LayerId('a2')),
      );

      expect(census.rebuilt, contains(ToolSettingsPanel));
    });

    testWidgets('the layers the eyedropper reads', (tester) async {
      final session = await _open(tester);
      _panel(tester).onEyedropperSourceChanged!(CanvasReadSource.layer);
      await tester.pumpAndSettle();

      final census = await frameCensus(
        tester,
        () => session.selectLayer(const LayerId('a2')),
      );

      expect(census.rebuilt, contains(ToolSettingsPanel));
    });
  });

  group('the cut\'s guide list', () {
    Future<EditorSessionManager> openOnGuides(WidgetTester tester) async {
      final session = await _open(tester);
      await tester.tap(find.byKey(const ValueKey<String>('tool-guide-button')));
      await tester.pumpAndSettle();
      expect(find.byType(GuideLibraryList), findsOneWidget, reason: 'LIVENESS');
      return session;
    }

    testWidgets('a cut switch with the same guides rebuilds it not', (
      tester,
    ) async {
      final session = await openOnGuides(tester);

      final census = await frameCensus(
        tester,
        () => session.selectCut(_second),
      );

      expect(session.activeCutId, _second, reason: 'LIVENESS: it switched');
      expect(census.rebuilt, isNot(contains(GuideLibraryList)));
    });

    testWidgets('a guide drawn rebuilds it', (tester) async {
      final session = await openOnGuides(tester);

      final census = await frameCensus(
        tester,
        () => session.cutVerbs.setActiveCutGuides(
          CutGuides(guides: [_mirror]),
        ),
      );

      expect(census.rebuilt, contains(GuideLibraryList));
    });
  });
}
