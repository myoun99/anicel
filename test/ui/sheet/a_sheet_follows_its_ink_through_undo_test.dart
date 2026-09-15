import 'package:flutter/foundation.dart'
    show ChangeNotifier, FlutterError, FlutterErrorDetails;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';

/// 🚨F-80 ② — A SHEET HEARS ITS INK COME BACK THROUGH UNDO.
///
/// 유저 2026-09-11: 「드로잉on인상태에서 그릴때 undo로 기록이안되는거같음.
/// 언두해도 언두안되고 다른곳 타임라인 조작이나 그 패널 바깥의 동작이 언두됨」.
///
/// The stroke WAS in history, and undo did put the sheet's surface back.
/// Nothing told the panel. Its ink windows take their surface when the
/// host rebuilds, the host rebuilds when the session or the ink controller
/// notifies, and the controller only notified for a commit. The session's
/// notify after every undo had been covering for that until 44bdeb49
/// (2026-09-10) stopped an undo that moves no row from tidying the document
/// up — so the stroke stayed on screen, and the next press undid whatever
/// came before it: something outside the panel.
///
/// The canvas had this illness on 2026-08-27, and its cure is the law here:
/// follow [BrushFrameStore.celPixelRevision], the one signal every surface
/// write bumps, rather than whoever made the write.
void main() {
  const cutId = CutId('cut-1');

  BrushStrokeCommitData oneDab() => BrushStrokeCommitData(
    sourceDabs: [
      BrushDab(
        center: CanvasPoint(x: 20, y: 20),
        color: 0xFF000000,
        size: 4,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      ),
    ],
  );

  /// Each sheet's controller with its geometry synced, and how to draw on
  /// and read one of its windows — held by its own type, since the three
  /// are separate controllers to the hosts that listen to them.
  final sheets =
      <
        String,
        ({
          ChangeNotifier Function() make,
          void Function(ChangeNotifier controller, HistoryManager history)
          commit,
          bool Function(ChangeNotifier controller) hasInk,
        })
      >{
        'timesheet': (
          make: () => TimesheetInkController()
            ..syncGeometry(
              TimesheetDocumentLayout(
                document: TimesheetDocument.fromCut(
                  cut: Cut(
                    id: cutId,
                    name: 'Cut 1',
                    layers: const [],
                    duration: 48,
                    canvasSize: const CanvasSize(width: 1280, height: 720),
                  ),
                  projectName: 'Project',
                  fps: 24,
                ),
              ),
            ),
          commit: (controller, history) =>
              (controller as TimesheetInkController).commitStroke(
                plane: TimesheetInkPlane.strip,
                key: TimesheetInkController.stripBandKey(cutId, 0),
                strokeData: oneDab(),
                historyManager: history,
              ),
          hasInk: (controller) => (controller as TimesheetInkController)
              .hasInkFor(
                TimesheetInkPlane.strip,
                TimesheetInkController.stripBandKey(cutId, 0),
              ),
        ),
        'conte': (
          make: () => ConteInkController()
            ..syncGeometry(
              const ConteSheetMetrics(pageWidth: 200, pageHeight: 280),
            ),
          commit: (controller, history) =>
              (controller as ConteInkController).commitStroke(
                plane: ConteInkPlane.page,
                key: ConteInkController.pageKey(0),
                strokeData: oneDab(),
                historyManager: history,
              ),
          hasInk: (controller) => (controller as ConteInkController).hasInkFor(
            ConteInkPlane.page,
            ConteInkController.pageKey(0),
          ),
        ),
        'envelope': (
          make: () => CutEnvelopeInkController()..syncGeometry(aspectRatio: 1),
          commit: (controller, history) =>
              (controller as CutEnvelopeInkController).commitStroke(
                plane: null,
                key: envelopeInkBoxKey(cutId, 'box'),
                strokeData: oneDab(),
                historyManager: history,
              ),
          hasInk: (controller) => (controller as CutEnvelopeInkController)
              .hasInkFor(null, envelopeInkBoxKey(cutId, 'box')),
        ),
      };

  for (final MapEntry(key: name, value: sheet) in sheets.entries) {
    test('$name: an undo and a redo of a stroke each tell the panel', () {
      final controller = sheet.make();
      addTearDown(controller.dispose);
      final history = HistoryManager();
      sheet.commit(controller, history);
      expect(
        sheet.hasInk(controller),
        isTrue,
        reason: 'the CONTROL — the stroke landed',
      );
      var told = 0;
      controller.addListener(() => told += 1);

      history.undo();

      expect(
        sheet.hasInk(controller),
        isFalse,
        reason: 'the CONTROL — the undo put the surface back',
      );
      expect(
        told,
        greaterThan(0),
        reason:
            'the surface came back and the panel was not told, so the stroke '
            'stayed on screen and the next press undid something else',
      );

      told = 0;
      history.redo();

      expect(sheet.hasInk(controller), isTrue);
      expect(told, greaterThan(0));
    });
  }

  test('a store that outlives its panel stops calling the closed '
      'controller', () {
    // The session keeps the envelope's store for the life of the project,
    // and the panel's controller goes with the workspace.
    //
    // ⚠️Asked of FlutterError, not of the call. A notifier used after its
    // dispose throws inside the STORE's listener loop, which catches the
    // throw and reports it — so the write returns normally either way, and a
    // plain `test` prints the report without failing. The first version
    // asserted `returnsNormally`, and the mutant that left the listener
    // attached passed it.
    final store = BrushFrameStore();
    final controller = CutEnvelopeInkController(store: store)
      ..syncGeometry(aspectRatio: 1);
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      controller.dispose();
      store.markCelEdited(envelopeInkBoxKey(cutId, 'box'));
    } finally {
      FlutterError.onError = previous;
    }

    expect(
      reported,
      isEmpty,
      reason: 'a write after the close reached a disposed notifier',
    );
  });
}
