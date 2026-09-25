import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// 🚨A SHEET REPAINTS ITS SAVED INK WHEN THE INK CHANGES — brush on or off.
///
/// A stroke that lands or undoes changes nothing a sheet's painter
/// compares: the windows, their placements and the live keys stay put, so
/// the host's rebuild hands the painter equal inputs. Only the ink
/// controller says the surface changed, and each sheet's saved-ink painter
/// listens to it. With the brush off — every sheet's default since 09-25 —
/// no live window covers for a painter that does not.
void main() {
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

  // Each sheet's host with its ink controller and the brush off, the key of
  // the paint that prints its saved ink, and a stroke onto one of its
  // surfaces through the session's history.
  final sheets =
      <
        ({
          String name,
          String paint,
          (Widget, void Function()) Function(EditorSessionManager session)
          mount,
        })
      >[
        (
          name: 'the timesheet',
          paint: 'timesheet-ink-paint',
          mount: (session) {
            final ink = TimesheetInkController();
            addTearDown(ink.dispose);
            return (
              TimesheetTabHost(
                session: session,
                continuous: false,
                onContinuousChanged: (_) {},
                inkController: ink,
              ),
              () => ink.commitStroke(
                plane: TimesheetInkPlane.strip,
                key: timesheetInkStripKey(session.requireActiveCut.id, 0),
                strokeData: oneDab(),
                historyManager: session.historyManager,
              ),
            );
          },
        ),
        (
          name: 'the conte',
          paint: 'conte-page',
          mount: (session) {
            final ink = ConteInkController();
            addTearDown(ink.dispose);
            return (
              ConteTabHost(
                session: session,
                thumbnailFor: null,
                inkController: ink,
              ),
              () => ink.commitStroke(
                plane: ConteInkPlane.page,
                key: conteInkPageKey(0),
                strokeData: oneDab(),
                historyManager: session.historyManager,
              ),
            );
          },
        ),
        (
          name: 'the envelope',
          paint: 'cut-envelope-page',
          mount: (session) {
            final ink = CutEnvelopeInkController();
            addTearDown(ink.dispose);
            return (
              CutEnvelopeTabHost(session: session, inkController: ink),
              () => ink.commitStroke(
                plane: null,
                key: envelopeInkBoxKey(session.requireActiveCut.id, 'box'),
                strokeData: oneDab(),
                historyManager: session.historyManager,
              ),
            );
          },
        ),
      ];

  for (final sheet in sheets) {
    testWidgets('${sheet.name} repaints its saved ink when a stroke lands '
        'and when it is undone, with the brush off', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final (host, stroke) = sheet.mount(session);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: host)));
      await tester.pumpAndSettle();
      RenderObject printed() =>
          tester.renderObject(find.byKey(ValueKey<String>(sheet.paint)).first);
      expect(printed().debugNeedsPaint, isFalse, reason: 'fixture: painted');

      stroke();
      expect(printed().debugNeedsPaint, isTrue, reason: 'the stroke landed');
      await tester.pump();
      expect(printed().debugNeedsPaint, isFalse, reason: 'fixture: painted');

      session.undo();
      expect(printed().debugNeedsPaint, isTrue, reason: 'the undo took it');
    });
  }
}
