import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
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
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/canvas/flip_hud_overlay.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_preview_panel.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_key_funnel.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/export_preview_probe.dart';
import '../../helpers/paper_editing_kit.dart';

/// 🗣️I-153-Q2 (유저 2026-11-04): 「셀 탭에 키 + 손가락 플립」 — the canvas's
/// keys and its one-finger flip on the Cels tab, read by the same bindings
/// and the same gesture: a block's step the drawings of the row stood on,
/// as ◀ ▶ do, a row's step the rail's rows; no window over the preview,
/// and a tick at each landing as the 「플립 진동」 setting says.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    AppInput.settings.value = const AppInputSettings();
  });

  const cutId = CutId('cut');
  const key = LayerMark(process: LayerProcess.key);

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  /// One cut, 301: A with three drawings under B with two, every one inked.
  EditorSessionManager film() => inkEveryCel(EditorSessionManager(
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
              duration: 3,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  mark: key,
                  frames: [
                    frame('a1', '1'),
                    frame('a2', '2'),
                    frame('a3', '3'),
                  ],
                ),
                Layer(
                  id: const LayerId('b'),
                  name: 'B',
                  mark: key,
                  frames: [frame('b1', '1'), frame('b2', '2')],
                ),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
    ),
  ));

  Future<void> pumpCels(
    WidgetTester tester,
    EditorSessionManager session,
    EditorKeyRoad keys,
  ) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: const ExportTabSpecs(
        cels: CelsExportSpec(kinds: {ExportCelKind.cel}),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            formatAvailability: ExportFormatAvailability.permissive(),
            keys: keys,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, String key) async {
    final found = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(found);
    await tester.pump();
    await tester.tap(found, warnIfMissed: false);
    await tester.pump();
  }

  Future<void> standOnA(WidgetTester tester) async {
    expect(
      [
        for (final row in tester
            .widget<ExportCelsBoard>(find.byType(ExportCelsBoard))
            .rows)
          row.idValue,
      ],
      ['b', 'a'],
      reason: '⛔전제: B stands over A, as the timeline stacks them',
    );
    await press(tester, 'export-cels-stand-a');
    expect(tester.exportPreviewLine, 'A1.png · 1 / 3', reason: '⛔전제');
  }

  /// The key [actionId] is bound to on [road] — whatever the preset in use
  /// binds it to — pressed as a hand does, its modifiers held round it.
  Future<void> pressBound(
    WidgetTester tester,
    EditorKeyRoad road,
    String actionId,
  ) async {
    final bound = road.bindings.activatorsFor(actionId).first;
    final held = [
      if (bound.control) LogicalKeyboardKey.controlLeft,
      if (bound.alt) LogicalKeyboardKey.altLeft,
      if (bound.shift) LogicalKeyboardKey.shiftLeft,
      if (bound.meta) LogicalKeyboardKey.metaLeft,
    ];
    for (final modifier in held) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(bound.trigger);
    for (final modifier in held.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump();
  }

  testWidgets('🗣️the sheet\'s keys walk the Cels list: a block\'s step the '
      'drawings of the row stood on, a row\'s the rows — and none reaches '
      'the editor', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final (:road, :invoked, held: _) = recordingKeyRoad(session);
    await pumpCels(tester, session, road);
    await standOnA(tester);

    await pressBound(tester, road, EditorActionIds.drawingNext);
    expect(tester.exportPreviewLine, 'A2.png · 2 / 3');
    await pressBound(tester, road, EditorActionIds.drawingNext);
    expect(tester.exportPreviewLine, 'A3.png · 3 / 3');
    await pressBound(tester, road, EditorActionIds.drawingNext);
    expect(tester.exportPreviewLine, 'A3.png · 3 / 3', reason: 'its end');
    await pressBound(tester, road, EditorActionIds.drawingPrevious);
    expect(tester.exportPreviewLine, 'A2.png · 2 / 3');

    await pressBound(tester, road, EditorActionIds.layerUp);
    expect(tester.exportPreviewLine, 'B2.png · 2 / 2');
    await pressBound(tester, road, EditorActionIds.layerUp);
    expect(tester.exportPreviewLine, 'B2.png · 2 / 2', reason: 'the top');
    await pressBound(tester, road, EditorActionIds.layerDown);
    expect(tester.exportPreviewLine, 'A2.png · 2 / 3');

    expect(invoked, isEmpty, reason: 'the editor behind stood still');
  });

  // 🗣️I-153-Q4 (유저 2026-11-04): 「프레임 키도 그림을 넘긴다」 — the list has
  // no frames. The preset the app starts on binds the bare ← → to them.
  testWidgets('🗣️the frame keys walk the drawings too — the list has no '
      'frames, and the preset the app starts on binds ← → to them', (
    tester,
  ) async {
    final session = film();
    addTearDown(session.dispose);
    final (:road, :invoked, held: _) = recordingKeyRoad(session);
    expect(
      road.bindings.activatorsFor(EditorActionIds.frameNext).first,
      const SingleActivator(LogicalKeyboardKey.arrowRight),
      reason: '⛔전제: the bare → is the next frame',
    );
    await pumpCels(tester, session, road);
    await standOnA(tester);

    await pressBound(tester, road, EditorActionIds.frameNext);
    expect(tester.exportPreviewLine, 'A2.png · 2 / 3');
    await pressBound(tester, road, EditorActionIds.frameNext);
    expect(tester.exportPreviewLine, 'A3.png · 3 / 3');
    await pressBound(tester, road, EditorActionIds.framePrevious);
    expect(tester.exportPreviewLine, 'A2.png · 2 / 3');
    expect(invoked, isEmpty, reason: 'the editor behind stood still');
  });

  testWidgets('the keys turn as the list does — on the editor\'s X-sheet, '
      '→ is still the next drawing — and the editor\'s turn is back once '
      'the window closes', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final (:road, invoked: _, held: _) = recordingKeyRoad(session);
    // The preset whose moves are the bare arrows — the ones a sheet turns.
    road.bindings.setPreset(ShortcutPreset.anicel);
    expect(
      road.bindings.activatorsFor(EditorActionIds.drawingNext).first,
      const SingleActivator(LogicalKeyboardKey.arrowRight),
      reason: '⛔전제',
    );
    final xSheet = FlipHudController()..framesRunVertically = true;
    addTearDown(xSheet.dispose);
    road.bindings.sheet = xSheet;
    await pumpCels(tester, session, road);
    await standOnA(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.exportPreviewLine, 'A2.png · 2 / 3');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.exportPreviewLine, 'B2.png · 2 / 2');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(road.bindings.sheet, same(xSheet));
  });

  testWidgets('on another tab the moves stand down — the list stays where '
      'it stood, and the editor hears none of them', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final (:road, :invoked, held: _) = recordingKeyRoad(session);
    await pumpCels(tester, session, road);
    await standOnA(tester);

    await press(tester, 'export-tab-sequence');
    await pressBound(tester, road, EditorActionIds.drawingNext);
    await pressBound(tester, road, EditorActionIds.layerUp);
    await press(tester, 'export-tab-cels');

    expect(tester.exportPreviewLine, 'A1.png · 1 / 3');
    expect(invoked, isEmpty);
  });

  group('a finger along the preview', () {
    /// The preview's gesture layer, where a finger lands on it.
    Offset onThePreview(WidgetTester tester) => tester.getCenter(
      find.descendant(
        of: find.byType(ExportPreviewPanel),
        matching: find.byType(CanvasViewportGestureLayer),
      ),
    );

    /// One finger dragged one step's way [along], past it and short of a
    /// second, and lifted — the controller's hold run out, and a pause past
    /// the haptic coalesce on the wall clock, so the next landing ticks.
    Future<void> flip(WidgetTester tester, Offset along) async {
      final finger = await tester.startGesture(
        onThePreview(tester),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await finger.moveBy(
        along * (CanvasViewportGestureLayer.flipStepExtent + 12),
      );
      await tester.pump();
      await finger.up();
      await tester.pump(
        FlipHudController.holdAfterRelease + FlipHudController.fadeOut,
      );
      await tester.runAsync(
        () => Future<void>.delayed(FlipHudController.hapticCoalesce * 2),
      );
    }

    /// Every haptic the platform is asked for, from here on.
    List<String> ticks(WidgetTester tester) {
      final asked = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          asked.add('${call.arguments}');
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      return asked;
    }

    testWidgets('🗣️flips as it flips the canvas: across, the drawings; up '
        'and down, the rows — a tick at each picture landed on, none where '
        'it stays, and no window over the preview', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      final (:road, :invoked, held: _) = recordingKeyRoad(session);
      await pumpCels(tester, session, road);
      await standOnA(tester);
      expect(
        tester
            .widget<BrushCanvasPanel>(
              find.descendant(
                of: find.byType(ExportPreviewPanel),
                matching: find.byType(BrushCanvasPanel),
              ),
            )
            .oneFingerAction,
        CanvasTouchDragAction.flip,
      );
      final asked = ticks(tester);

      await flip(tester, const Offset(1, 0));
      expect(tester.exportPreviewLine, 'A2.png · 2 / 3');
      expect(asked, hasLength(1));
      expect(find.byType(FlipHudOverlay), findsNothing);

      await flip(tester, const Offset(0, -1));
      expect(tester.exportPreviewLine, 'B2.png · 2 / 2');
      expect(asked, hasLength(2));

      await flip(tester, const Offset(1, 0));
      expect(tester.exportPreviewLine, 'B2.png · 2 / 2', reason: 'its end');
      expect(asked, hasLength(2), reason: 'no new picture, no tick');

      await flip(tester, const Offset(-1, 0));
      expect(tester.exportPreviewLine, 'B1.png · 1 / 2');
      expect(asked, hasLength(3));
      expect(invoked, isEmpty, reason: 'the editor behind stood still');
    });

    testWidgets('with 「플립 진동」 off it flips without a tick', (
      tester,
    ) async {
      AppInput.settings.value = const AppInputSettings(flipHaptics: false);
      final session = film();
      addTearDown(session.dispose);
      final (:road, invoked: _, held: _) = recordingKeyRoad(session);
      await pumpCels(tester, session, road);
      await standOnA(tester);
      final asked = ticks(tester);

      await flip(tester, const Offset(1, 0));
      expect(tester.exportPreviewLine, 'A2.png · 2 / 3');
      expect(asked, isEmpty);
    });

    // 🗣️I-153-Q4: the extra finger is the one-frame step, as Shift is on the
    // keys — and on a list with no frames it walks the drawings.
    testWidgets('🗣️with a finger more on the glass, a step along still walks '
        'the drawings — the one-frame step, on a list with no frames', (
      tester,
    ) async {
      final session = film();
      addTearDown(session.dispose);
      final (:road, :invoked, held: _) = recordingKeyRoad(session);
      await pumpCels(tester, session, road);
      await standOnA(tester);
      final at = onThePreview(tester);

      final finger = await tester.startGesture(
        at,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await finger.moveBy(
        const Offset(CanvasViewportGestureLayer.flipStepExtent + 12, 0),
      );
      await tester.pump();
      expect(tester.exportPreviewLine, 'A2.png · 2 / 3', reason: '⛔전제');

      final more = await tester.startGesture(
        at + const Offset(0, 60),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await finger.moveBy(
        const Offset(CanvasViewportGestureLayer.flipStepExtent, 0),
      );
      await tester.pump();
      expect(tester.exportPreviewLine, 'A3.png · 3 / 3');

      await more.up();
      await finger.up();
      await tester.pump(
        FlipHudController.holdAfterRelease + FlipHudController.fadeOut,
      );
      expect(invoked, isEmpty, reason: 'the editor behind stood still');
    });

    testWidgets('on another tab one finger moves the page, as it did', (
      tester,
    ) async {
      final session = film();
      addTearDown(session.dispose);
      final (:road, invoked: _, held: _) = recordingKeyRoad(session);
      await pumpCels(tester, session, road);
      await press(tester, 'export-tab-sequence');
      expect(
        tester
            .widget<BrushCanvasPanel>(
              find.descendant(
                of: find.byType(ExportPreviewPanel),
                matching: find.byType(BrushCanvasPanel),
              ),
            )
            .oneFingerAction,
        CanvasTouchDragAction.navigate,
      );
    });
  });
}
