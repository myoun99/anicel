import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/dart_sources.dart';
import '../../helpers/panel_finders.dart';

/// 🚨★★★**THE EYEDROPPER ANSWERS UNDER EVERY TOOL** (F-299).
///
/// 🗣️유저 2026-10-05: 「채우기 도구인상태에서 스포이드 단축키로 도구 안바뀜.
/// **어떤 도구 들고있던 규칙 만들지말고 법 통일해서 작동하도록**」.
///
/// Through the real shell — the app's own shortcut road and keyboard, with
/// each tool's own layer mounted over the canvas — because the road was
/// never the part that differed by tool: the hold asked which tool was in
/// hand, and took only over the three the drawing view presses for.
///
/// ↩️A pen or mouse button mapped to the eyedropper is the same law, and
/// stopped at those three tools too — and at none on a frame with no cel
/// (measured 2026-10-06): it was read inside the drawing view. The panel
/// reads it now, and the two button roads are pinned here beside the keys.
void main() {
  const frameId = FrameId('pe-frame');
  const layerId = LayerId('pe-layer');

  /// A one-row project standing on a cel — or, with [cel] false, on a
  /// frame that has none.
  Project project({bool cel = true}) => Project(
    id: const ProjectId('pe-project'),
    name: 'Eyedropper',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('pe-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('pe-cut'),
            name: 'pe-cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: 'pe-layer',
                frames: [
                  if (cel)
                    Frame(
                      id: frameId,
                      name: 'A',
                      duration: 1,
                      strokes: const [],
                    ),
                ],
                timeline: {
                  if (cel)
                    0: const TimelineExposure.drawing(frameId, length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<ValueNotifier<BrushToolState>> pumpShell(
    WidgetTester tester, {
    bool cel = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project(cel: cel))),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!;
  }

  Future<void> take(
    WidgetTester tester,
    ValueNotifier<BrushToolState> brush,
    CanvasTool tool,
  ) async {
    brush.value = brush.value.copyWith(tool: tool);
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('its key takes the eyedropper from every tool', (tester) async {
    final brush = await pumpShell(tester);
    for (final tool in CanvasTool.values) {
      await take(tester, brush, tool);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump();
      expect(brush.value.tool, CanvasTool.eyedropper, reason: tool.name);
    }
  });

  testWidgets('🚨Alt held is the eyedropper under every tool whose own drag '
      'does not read Alt, and letting go gives the tool back', (tester) async {
    // ⛔Spelled here, not asked of the predicate: an oracle that follows the
    // code it checks agrees with whatever the code says.
    const keepsItsAlt = {CanvasTool.select, CanvasTool.move};
    final brush = await pumpShell(tester);
    for (final tool in CanvasTool.values) {
      await take(tester, brush, tool);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(
        brush.value.tool,
        keepsItsAlt.contains(tool) ? tool : CanvasTool.eyedropper,
        reason: '${tool.name}, Alt held',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(brush.value.tool, tool, reason: '${tool.name}, Alt let go');
    }
  });

  // 🚨The BUTTONS, through the real shell: every tool's own layer is
  // mounted over the canvas when the press comes, and goes away under the
  // pointer when the hold takes the tool.
  for (final cel in [true, false]) {
    final where = cel ? 'on a cel' : 'on a frame with no cel';

    testWidgets('🚨a held RIGHT button is the eyedropper under every tool, '
        '$where — and letting go gives the tool back', (tester) async {
      final brush = await pumpShell(tester, cel: cel);
      final at = visibleCanvasPoint(tester);
      for (final tool in CanvasTool.values) {
        await take(tester, brush, tool);

        final right = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        expect(
          brush.value.tool,
          CanvasTool.eyedropper,
          reason: '${tool.name}, held',
        );
        // The tool's layer is gone from under a pointer still down.
        await right.moveTo(at + const Offset(30, 10));
        await tester.pump();
        await right.up();
        await tester.pump();

        expect(brush.value.tool, tool, reason: '${tool.name}, let go');
        expect(tester.takeException(), isNull, reason: tool.name);
      }
    });

    testWidgets('🚨a pen\'s barrel pressed in hover is the eyedropper under '
        'every tool, $where', (tester) async {
      final brush = await pumpShell(tester, cel: cel);
      final at = visibleCanvasPoint(tester);
      Future<void> hover(int buttons) async {
        tester.binding.handlePointerEvent(
          PointerHoverEvent(
            kind: PointerDeviceKind.stylus,
            position: at,
            buttons: buttons,
          ),
        );
        await tester.pump();
      }

      for (final tool in CanvasTool.values) {
        await take(tester, brush, tool);
        await hover(0);

        await hover(kPrimaryStylusButton);
        expect(
          brush.value.tool,
          CanvasTool.eyedropper,
          reason: '${tool.name}, barrel down',
        );

        await hover(0);
        expect(brush.value.tool, tool, reason: '${tool.name}, barrel up');
        expect(tester.takeException(), isNull, reason: tool.name);
      }
    });
  }

  test('the tools that keep their Alt are the two whose drag reads it', () {
    expect(
      [
        for (final tool in CanvasTool.values)
          if (canvasToolReadsAlt(tool)) tool,
      ],
      [CanvasTool.select, CanvasTool.move],
      reason: 'the selection subtracts with it, the transform scales about '
          'the far corner — F-299-Q1',
    );
  });

  /// ⛔The predicate is a second place that has to know who reads Alt, so
  /// the first is counted: a third reader on the canvas turns this red, and
  /// whoever adds it says which tool keeps its Alt.
  test('⛔Alt is read by the selection\'s drag and the transform\'s, and by '
      'nothing else on the canvas', () {
    final readers = <String>[];
    var scanned = 0;
    for (final file in dartFilesUnder('lib/src/ui')) {
      scanned += 1;
      for (final line in file.readAsLinesSync()) {
        final comment = line.indexOf('//');
        final code = comment < 0 ? line : line.substring(0, comment);
        if (code.contains('isAltPressed')) {
          readers.add(libPath(file));
        }
      }
    }
    expect(scanned, greaterThan(300), reason: 'the scan found lib/src/ui');
    expect(readers..sort(), [
      // The transform box's scale modifier, and the marquee's combine mode.
      'lib/src/ui/canvas/canvas_selection_layer.dart',
      'lib/src/ui/canvas/canvas_selection_layer.dart',
      // The shortcut window, hearing a chord being typed in.
      'lib/src/ui/shortcuts/shortcut_settings_dialog.dart',
    ]);
  });
}
