import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_form.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/envelope/cut_envelope_source.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_overlay.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_painter.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';

import '../helpers/frame_census.dart';

/// The envelope PANEL: the sheet inside the canvas shell, with the ink a
/// hand writes on it.
///
/// The contract that costs the most to get wrong is the split between the
/// two things that can show a box's ink — the painter bakes what is SAVED,
/// a mounted window shows what is LIVE — because only a handful of boxes
/// are ever mounted. Miss it and everything written in a small cell simply
/// disappears when the cell is not being written in.
void main() {
  const owner = CutId('cut-1');

  /// A two-box form: one cell to write in, one beside it to prove ink does
  /// not spill.
  const testForm = CutEnvelopeForm(
    id: 'test',
    name: 'Test',
    aspectRatio: 1,
    boxes: [
      EnvelopeBox(
        id: 'left',
        rect: EnvelopeRect(x: 0, y: 0, width: 0.5, height: 1),
      ),
      EnvelopeBox(
        id: 'right',
        rect: EnvelopeRect(x: 0.5, y: 0, width: 0.5, height: 1),
      ),
    ],
  );

  CutEnvelopeLayout layoutOn(double paper) => CutEnvelopeLayout.fit(
    form: testForm,
    paperWidth: paper,
    paperHeight: paper,
  );

  Future<ui.Image> solidInk(int width, int height) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFF0000),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  Future<(int, int, int)> pixelAt(ui.Image image, int x, int y) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (y * image.width + x) * 4;
    return (
      data!.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  }

  Future<ui.Image> paintSheet(CutEnvelopePainter painter, double size) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Size(size, size));
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(size.round(), size.round());
    } finally {
      picture.dispose();
    }
  }

  testWidgets('SAVED ink is drawn by the painter where it was written — '
      'which is the only reason writing in a box that is not currently '
      'mounted stays visible', (tester) async {
    await tester.runAsync(() async {
      final layout = layoutOn(200);
      final leftKey = envelopeInkBoxKey(owner, 'left');
      // A quarter of the left box's surface slice (2048 × 4096), inked
      // solid: it lands on the box's top-left quarter and nowhere else.
      final ink = await solidInk(512, 1024);
      addTearDown(ink.dispose);

      final rendered = await paintSheet(
        CutEnvelopePainter(
          face: const TextStyle(),
          layout: layout,
          source: const CutEnvelopeSource(),
          inkOwner: owner,
          inkImageFor: (key) => key == leftKey ? ink : null,
        ),
        200,
      );
      addTearDown(rendered.dispose);

      final inside = await pixelAt(rendered, 12, 25);
      expect(inside.$1, greaterThan(200), reason: 'the left box is inked');
      expect(inside.$2, lessThan(60));
      // The painter samples the box's SURFACE SLICE, not the whole image:
      // stretching the image over the box instead would put ink here, and
      // every stroke would print in the wrong place at the wrong size.
      final below = await pixelAt(rendered, 60, 150);
      expect(below.$2, greaterThan(200), reason: 'still paper further in');
      final beside = await pixelAt(rendered, 150, 25);
      expect(beside.$2, greaterThan(200), reason: 'the next box is untouched');
    });
  });

  testWidgets('a box whose window is LIVE is skipped, so a stroke never '
      'composites twice', (tester) async {
    await tester.runAsync(() async {
      final layout = layoutOn(200);
      final leftKey = envelopeInkBoxKey(owner, 'left');
      final ink = await solidInk(512, 1024);
      addTearDown(ink.dispose);

      final rendered = await paintSheet(
        CutEnvelopePainter(
          face: const TextStyle(),
          layout: layout,
          source: const CutEnvelopeSource(),
          inkOwner: owner,
          inkImageFor: (key) => key == leftKey ? ink : null,
          liveInkKeys: {leftKey},
        ),
        200,
      );
      addTearDown(rendered.dispose);

      final inside = await pixelAt(rendered, 12, 25);
      expect(
        inside.$2,
        greaterThan(200),
        reason: 'the live window draws this one; the painter stands down',
      );
    });
  });

  test('mounting or unmounting a window has to repaint the sheet — the '
      'baked ink under it appears and disappears', () {
    final layout = layoutOn(200);
    final leftKey = envelopeInkBoxKey(owner, 'left');
    CutEnvelopePainter painterWith(Set<BrushFrameKey> live) =>
        CutEnvelopePainter(
          face: const TextStyle(),
          layout: layout,
          source: const CutEnvelopeSource(),
          inkOwner: owner,
          liveInkKeys: live,
        );

    expect(painterWith({leftKey}).shouldRepaint(painterWith({})), isTrue);
    expect(painterWith({}).shouldRepaint(painterWith({})), isFalse);
  });

  group('host', () {
    Project project() => Project(
      id: const ProjectId('envelope-project'),
      name: 'Envelope',
      createdAt: DateTime.utc(2026, 8, 6),
      tracks: [
        Track(
          id: const TrackId('t1'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('39'),
              name: '39',
              duration: 24,
              canvasSize: const CanvasSize(width: 640, height: 480),
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  kind: LayerKind.animation,
                  frames: const [],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    Future<(EditorSessionManager, CutEnvelopeInkController)> pumpEnvelope(
      WidgetTester tester, {
      bool brushAllowed = false,
      ValueNotifier<BrushToolState>? brush,
    }) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      final ink = CutEnvelopeInkController();
      addTearDown(ink.dispose);
      final tool =
          brush ?? ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(tool.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CutEnvelopeTabHost(
              session: session,
              inkController: ink,
              brushToolState: tool,
              brushAllowed: brushAllowed,
              onBrushAllowedChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (session, ink);
    }

    testWidgets('the panel draws the sheet inside the canvas shell, with '
        'the brush OFF until it is asked for', (tester) async {
      await pumpEnvelope(tester);

      expect(
        find.byKey(const ValueKey<String>('cut-envelope-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('envelope-brush-toggle-button')),
        findsOneWidget,
      );
      expect(find.byType(CutEnvelopeInkOverlay), findsNothing);
    });

    testWidgets('with the brush on the overlay mounts only the boxes big '
        'enough to write in — never all 86', (tester) async {
      await pumpEnvelope(tester, brushAllowed: true);

      final overlay = tester.widget<CutEnvelopeInkOverlay>(
        find.byType(CutEnvelopeInkOverlay),
      );
      expect(overlay.windows, isNotEmpty);
      expect(
        overlay.windows.length,
        lessThan(CutEnvelopePresets.analog.inkBoxes.length),
        reason: 'the gate is the whole reason per-window input is affordable',
      );
    });

    // H40 ② (2026-09-24): the overlay was rebuilt on every brush change —
    // each frame of a settings slider drag. Its windows read the brush when
    // a stroke starts now, so a change reaches none of them.
    testWidgets('a brush change rebuilds no ink window, and the windows read '
        'the brush in hand', (tester) async {
      final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      await pumpEnvelope(tester, brushAllowed: true, brush: brush);
      expect(find.byType(CutEnvelopeInkOverlay), findsOneWidget);

      final next = brush.value.copyWith(size: 40, color: 0xFF336699);
      final census = await frameCensus(tester, () => brush.value = next);

      expect(census.rebuilt, isNot(contains(CutEnvelopeInkOverlay)));
      expect(census.rebuilt, isNot(contains(InteractiveBrushEditCanvasView)));
      final windows = tester.widgetList<InteractiveBrushEditCanvasView>(
        find.byType(InteractiveBrushEditCanvasView),
      );
      expect(windows, isNotEmpty);
      for (final window in windows) {
        expect(window.inputSettings(), next.toInputSettings());
      }
    });

    testWidgets('the status strip offers both bundled forms and switching '
        'reprints the sheet', (tester) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var formId = CutEnvelopePresets.analogId;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: CutEnvelopeTabHost(
                session: session,
                formId: formId,
                onFormIdChanged: (next) => setState(() => formId = next),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'envelope-form-${CutEnvelopePresets.digitalId}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(formId, CutEnvelopePresets.digitalId);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey<String>('cut-envelope-page')),
                  )
                  .painter!
              as CutEnvelopePainter;
      expect(painter.layout.form.id, CutEnvelopePresets.digitalId);
    });

    testWidgets('a stroke lands on the box it started in and one undo '
        'clears it', (tester) async {
      final (session, ink) = await pumpEnvelope(tester, brushAllowed: true);

      final overlay = tester.widget<CutEnvelopeInkOverlay>(
        find.byType(CutEnvelopeInkOverlay),
      );
      final window = overlay.windows.first;
      final origin = tester.getTopLeft(find.byType(CutEnvelopeInkOverlay));
      final rect = window.screenRect(overlay.viewport);

      expect(ink.hasInkFor(null, window.key), isFalse);
      final gesture = await tester.startGesture(
        origin + rect.center,
        pointer: 7,
      );
      await tester.pump();
      await gesture.moveTo(origin + rect.center + const Offset(6, 4));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(ink.hasInkFor(null, window.key), isTrue);
      expect(
        window.key,
        envelopeInkBoxKey(const CutId('39'), window.id),
        reason: 'the owning cut keys the sheet',
      );
      session.historyManager.undo();
      expect(ink.hasInkFor(null, window.key), isFalse);
    });

    // ↩️The envelope kept a bare stroke flag the timesheet and the conte
    // each wired to the session; this sheet never was, so a cut switch could
    // land under the pen mid-stroke. One hold for the three now.
    testWidgets('a stroke holds the brush input the way a canvas stroke '
        'does — seeks and cut switches wait for the pen (R15-⑤)', (
      tester,
    ) async {
      final (session, _) = await pumpEnvelope(tester, brushAllowed: true);
      final overlay = tester.widget<CutEnvelopeInkOverlay>(
        find.byType(CutEnvelopeInkOverlay),
      );
      final window = overlay.windows.first;
      final origin = tester.getTopLeft(find.byType(CutEnvelopeInkOverlay));
      final rect = window.screenRect(overlay.viewport);

      expect(session.brushInputActive.value, isFalse);
      final gesture = await tester.startGesture(
        origin + rect.center,
        pointer: 7,
      );
      await tester.pump();
      await gesture.moveTo(origin + rect.center + const Offset(6, 4));
      await tester.pump();
      expect(session.brushInputActive.value, isTrue);
      expect(session.editingInteractionBusy, isTrue);

      await gesture.up();
      await tester.pump();
      expect(session.brushInputActive.value, isFalse);
    });
  });
}
