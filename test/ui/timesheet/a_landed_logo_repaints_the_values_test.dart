import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_strata.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// An XDTS sheet's values print the company logo (I-162-Q5), which the
/// painter asks for while it paints and gets once it is read: the read
/// that lands repaints the values — and the form, which prints no picture,
/// does not hear it. Where the sheet prints no logo the values print no
/// picture and stay baked ([TimesheetDocument.printedLogo]).
void main() {
  /// The values' and the form's paints of a cut printed on [kind] in a
  /// work whose logo is [logo], once a read lands.
  Future<({bool values, bool form})> repaintedByALanding(
    WidgetTester tester, {
    required TimesheetSheetKind kind,
    required String? logo,
  }) async {
    const cutId = CutId('cut');
    final document = TimesheetDocument.fromCut(
      cut: Cut(
        id: cutId,
        name: '1',
        duration: 24,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
        metadata: CutMetadata(sheetKind: kind),
        layers: const [],
      ),
      projectName: 'P',
      fps: 24,
      info: TimesheetInfo(logoAssetPath: logo),
    );
    final drag = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(drag.dispose);
    final stroking = ValueNotifier<bool>(false);
    addTearDown(stroking.dispose);
    final landed = ValueNotifier<int>(0);
    addTearDown(landed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: 320,
            child: TimesheetStrata(
              layout: TimesheetDocumentLayout(document: document),
              viewport: CanvasViewport(panX: 0, panY: 0, zoom: 1),
              words: timesheetWordsIn(AppLanguage.ja),
              dragPreview: drag,
              cutId: cutId,
              stroking: stroking,
              imageFor: (path, {width}) => null,
              imageRepaint: landed,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    RenderCustomPaint paintOf(String stratum) =>
        tester.renderObject<RenderCustomPaint>(
          find.byKey(ValueKey<String>('timesheet-$stratum-paint')),
        );
    final values = paintOf('content');
    final form = paintOf('form');
    expect(values.debugNeedsPaint, isFalse, reason: 'the premise: settled');
    expect(form.debugNeedsPaint, isFalse, reason: 'the premise: settled');

    landed.value += 1;

    return (values: values.debugNeedsPaint, form: form.debugNeedsPaint);
  }

  testWidgets('a logo that lands repaints the values, not the form', (
    tester,
  ) async {
    expect(
      await repaintedByALanding(
        tester,
        kind: TimesheetSheetKind.xdtsA3SixSeconds,
        logo: 'logo.png',
      ),
      (values: true, form: false),
    );
  });

  testWidgets('our own sheet has no logo place, and a sheet of a work with '
      'no logo prints none: their values stay baked when a picture lands', (
    tester,
  ) async {
    expect(
      await repaintedByALanding(
        tester,
        kind: TimesheetSheetKind.sixSeconds,
        logo: 'logo.png',
      ),
      (values: false, form: false),
    );
    expect(
      await repaintedByALanding(
        tester,
        kind: TimesheetSheetKind.xdtsA3SixSeconds,
        logo: null,
      ),
      (values: false, form: false),
    );
  });
}
