import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

import '../../helpers/frame_census.dart';

const _inkLayerKey = ValueKey<String>('timesheet-ink-layer');
const _inkToggleKey = ValueKey<String>('timesheet-brush-toggle-button');
const _editorKey = ValueKey<String>('timesheet-header-edit-field');
const _titleZoneKey = ValueKey<String>('timesheet-header-edit-title-p0');
const _memoZoneKey = ValueKey<String>('timesheet-memo-edit-p0');

void main() {
  late EditorSessionManager session;
  late TimesheetInkController inkController;
  late BrushFrameStore stripStore;
  late ValueNotifier<BrushToolState> brushTool;

  Future<void> pumpHost(WidgetTester tester, {bool brushAllowed = true}) async {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    stripStore = BrushFrameStore();
    inkController = TimesheetInkController(stripStore: stripStore);
    addTearDown(inkController.dispose);
    brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brushTool.dispose);

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var enabled = brushAllowed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TimesheetTabHost(
              session: session,
              continuous: false,
              onContinuousChanged: (_) {},
              viewport: CanvasViewport(),
              onViewportChanged: (_) {},
              inkController: inkController,
              brushToolState: brushTool,
              brushAllowed: enabled,
              onBrushAllowedChanged: (next) => setState(() => enabled = next),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('TimesheetTabHost brush switch', () {
    testWidgets('switching the brush off unmounts the ink windows; on '
        'restores them', (tester) async {
      await pumpHost(tester);

      expect(find.byKey(_inkLayerKey), findsOneWidget);

      await tester.tap(find.byKey(_inkToggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_inkLayerKey), findsNothing);

      await tester.tap(find.byKey(_inkToggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_inkLayerKey), findsOneWidget);
    });

    // 유저 2026-09-26: 「다 통일해줘. 기능은 어차피 생길수있어」 — the sheet
    // printed no ink of its own, so with the switch off (every sheet's
    // default since 09-25) its writing vanished; the conte's and the
    // envelope's stayed.
    testWidgets('🚨the saved ink prints with the brush OFF too; with it ON, '
        'the windows the live layer shows stand down', (tester) async {
      await pumpHost(tester, brushAllowed: false);
      final band = timesheetInkStripKey(session.requireActiveCut.id, 0);
      stripStore.storeBakedSurface(band, _inkedSurface());
      await tester.pump();
      TimesheetDocumentPainter printed() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey<String>('timesheet-ink-paint')),
                  )
                  .painter!
              as TimesheetDocumentPainter;

      expect(find.byKey(_inkLayerKey), findsNothing, reason: 'the premise');
      expect(printed().ink.map((window) => window.key), contains(band));
      expect(printed().inkImageFor!(band), isNotNull);
      expect(printed().liveInkKeys, isEmpty);

      await tester.tap(find.byKey(_inkToggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_inkLayerKey), findsOneWidget);
      expect(printed().liveInkKeys, contains(band));
    });

    // H40 ② (2026-09-24): the ink layer was rebuilt on every brush change —
    // each frame of a settings slider drag. Its windows read the brush when
    // a stroke starts now, so a change reaches none of them.
    testWidgets('a brush change rebuilds no ink window, and the windows read '
        'the brush in hand', (tester) async {
      await pumpHost(tester);
      expect(find.byKey(_inkLayerKey), findsOneWidget);

      final next = brushTool.value.copyWith(size: 40, color: 0xFF336699);
      final census = await frameCensus(tester, () => brushTool.value = next);

      expect(census.rebuilt, isNot(contains(SheetInkLayer)));
      expect(census.rebuilt, isNot(contains(InteractiveBrushEditCanvasView)));
      final windows = tester.widgetList<InteractiveBrushEditCanvasView>(
        find.byType(InteractiveBrushEditCanvasView),
      );
      expect(windows, isNotEmpty);
      for (final window in windows) {
        expect(window.inputSettings(), next.toInputSettings());
      }
    });

    // ⛔없다가 생기는 UI 금지: the gap panel (no cut under the playhead)
    // carries the switch too, in the same place.
    testWidgets('the switch keeps its place when the playhead stands in a '
        'gap and the sheet empties', (tester) async {
      await pumpHost(tester, brushAllowed: false);
      session.cutVerbs.createCut();
      final track = session.repository.requireProject().tracks.first;
      final firstEnd = track.cuts[0].duration;
      session.repository.updateCutLeadingGap(
        cutId: track.cuts[1].id,
        leadingGapFrames: 4,
      );
      session.selectCut(track.cuts[0].id);
      await tester.pumpAndSettle();
      final withCut = tester.getCenter(find.byKey(_inkToggleKey));

      session.selectGlobalFrame(firstEnd + 1);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('timesheet-empty-no-cut')),
        findsOneWidget,
        reason: 'fixture: the gap panel is up',
      );
      expect(find.byKey(_inkToggleKey), findsOneWidget);
      expect(tester.getCenter(find.byKey(_inkToggleKey)), withCut);
    });

    testWidgets('with the brush on, a tap on a header box draws instead of '
        'opening the editor (pen-on-paper rule)', (tester) async {
      await pumpHost(tester);

      await tester.tap(find.byKey(_titleZoneKey), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(_editorKey), findsNothing);
    });
  });

  group('TimesheetTabHost header editing (brush off)', () {
    testWidgets('editing the TITLE box commits to the project timesheet '
        'info', (tester) async {
      await pumpHost(tester, brushAllowed: false);

      await tester.tap(find.byKey(_titleZoneKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_editorKey), 'YOASOBI');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(session.timesheetInfo.title, 'YOASOBI');
    });

    testWidgets('editing the memo band commits the cut note', (tester) async {
      await pumpHost(tester, brushAllowed: false);

      await tester.tap(find.byKey(_memoZoneKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_editorKey), 'カットO.L');

      // Tap the document margin — covered only by the tap-away barrier.
      final paperOrigin = tester.getTopLeft(
        find.byKey(const ValueKey<String>('timesheet-content-paint')),
      );
      await tester.tapAt(paperOrigin + const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(session.cutVerbs.activeCutNote, 'カットO.L');
    });
  });
}

/// A small inked surface — what a landed stroke leaves in a store.
BitmapSurface _inkedSurface() => BitmapSurface(
  canvasSize: const CanvasSize(width: 16, height: 16),
  tileSize: 8,
  tiles: {
    TileCoord(x: 0, y: 0): BitmapTile(
      size: 8,
      pixels: Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 255),
    ),
  },
);
