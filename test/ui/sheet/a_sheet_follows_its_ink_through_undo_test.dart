import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';

import '../../helpers/cel_photo_fixture.dart';

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

  /// Each sheet's controller with its geometry synced, and one of its
  /// windows.
  final sheets =
      <
        String,
        ({SheetInkController<Null> Function() make, BrushFrameKey key})
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
          key: timesheetInkPageKey(cutId, 0),
        ),
        'conte': (
          make: () => ConteInkController()
            ..syncGeometry(
              const ConteSheetMetrics(pageWidth: 200, pageHeight: 280),
            ),
          key: conteInkRowKey(const CutId('conte-cut'), 'ink-0'),
        ),
        'envelope': (
          make: () => CutEnvelopeInkController()..syncGeometry(aspectRatio: 1),
          key: envelopeInkBoxKey(cutId, 'box'),
        ),
      };

  /// What a window is written with: a stroke — and a pool photo (I-97),
  /// which the panel hears the same way.
  final writes =
      <
        String,
        void Function(
          SheetInkController<Null> controller,
          BrushFrameKey key,
          HistoryManager history,
        )
      >{
        'a stroke': (controller, key, history) => controller.commitStroke(
          plane: null,
          key: key,
          strokeData: oneDab(),
          historyManager: history,
        ),
        'a photo put': (controller, key, history) => controller.putPhoto(
          plane: null,
          key: key,
          reference: photoOf(1).reference,
          historyManager: history,
        ),
      };

  for (final MapEntry(key: name, value: sheet) in sheets.entries) {
    for (final MapEntry(key: what, value: write) in writes.entries) {
      test('$name: $what, its undo and its redo each tell the panel', () {
        final controller = sheet.make();
        addTearDown(controller.dispose);
        final history = HistoryManager();
        var told = 0;
        controller.addListener(() => told += 1);

        write(controller, sheet.key, history);

        expect(
          controller.hasInkFor(null, sheet.key),
          isTrue,
          reason: 'the CONTROL — it landed',
        );
        expect(told, greaterThan(0));

        told = 0;
        history.undo();

        expect(
          controller.hasInkFor(null, sheet.key),
          isFalse,
          reason: 'the CONTROL — the undo put the surface back',
        );
        expect(
          told,
          greaterThan(0),
          reason:
              'the surface came back and the panel was not told, so the '
              'stroke stayed on screen and the next press undid something '
              'else',
        );

        told = 0;
        history.redo();

        expect(controller.hasInkFor(null, sheet.key), isTrue);
        expect(told, greaterThan(0));
      });
    }
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
