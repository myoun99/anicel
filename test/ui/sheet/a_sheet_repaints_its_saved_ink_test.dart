import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

import '../../helpers/a_screen_shows_ink.dart';

/// 🚨A SHEET SHOWS ITS SAVED INK AS IT CHANGES — brush on or off.
///
/// A stroke that lands or undoes changes nothing a sheet's host compares:
/// the windows and their placements stay put, so the host's rebuild hands
/// its ink screens equal inputs. Only the ink controller says the surface
/// changed, and each sheet's ink screens ([SheetInkScreens]) listen to it.
/// With the brush off — every sheet's default since 09-25 — no view of the
/// pen's covers for screens that do not.
///
/// ↩️It asked each sheet's saved-ink painter to repaint till 2026-11-18,
/// when the engine came to show the ink.
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

  /// [key]'s surface on [ink] stroked once through [session]'s history.
  void Function() strokeOn(
    SheetInkController<Null> ink,
    BrushFrameKey key,
    EditorSessionManager session,
  ) => () => ink.commitStroke(
    plane: null,
    key: key,
    strokeData: oneDab(),
    historyManager: session.historyManager,
  );

  // Each sheet's project and its host with its ink controller and the brush
  // off, and the surface of a window it shows, which a stroke goes onto
  // through the session's history.
  final sheets =
      <
        ({
          String name,
          Project Function() project,
          (Widget, SheetInkController<Null>, BrushFrameKey) Function(
            EditorSessionManager session,
          )
          mount,
        })
      >[
        (
          name: 'the timesheet',
          project: createDefaultProject,
          mount: (session) {
            final ink = TimesheetInkController();
            addTearDown(ink.dispose);
            return (
              TimesheetTabHost(session: session, inkController: ink),
              ink,
              timesheetInkPageKey(session.requireActiveCut.id, 0),
            );
          },
        ),
        (
          name: 'the conte',
          project: _oneConteCell,
          mount: (session) {
            final ink = ConteInkController();
            addTearDown(ink.dispose);
            return (
              ConteTabHost(
                session: session,
                thumbnails: null,
                inkController: ink,
              ),
              ink,
              conteInkRowKey(const CutId('c'), 'ink-0'),
            );
          },
        ),
        (
          name: 'the envelope',
          project: createDefaultProject,
          mount: (session) {
            final ink = CutEnvelopeInkController();
            addTearDown(ink.dispose);
            return (
              CutEnvelopeTabHost(session: session, inkController: ink),
              ink,
              envelopeInkBoxKey(session.requireActiveCut.id, 'episode'),
            );
          },
        ),
      ];

  for (final sheet in sheets) {
    testWidgets('${sheet.name} shows its saved ink when a stroke lands and '
        'not once it is undone, with the brush off', (tester) async {
      final session = EditorSessionManager(
        initialProject: sheet.project(),
      );
      addTearDown(session.dispose);
      final (host, ink, key) = sheet.mount(session);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: host)));
      await tester.pumpAndSettle();
      expect(aScreenShowsInkOf(tester, key), isFalse, reason: 'the premise');

      strokeOn(ink, key, session)();
      await tester.pump();
      expect(aScreenShowsInkOf(tester, key), isTrue, reason: 'it landed');

      session.undo();
      await tester.pump();
      expect(aScreenShowsInkOf(tester, key), isFalse, reason: 'undone');
    });
  }
}

/// One cut whose conte block has handwriting — a band the conte shows a
/// window over with the brush off.
Project _oneConteCell() => Project(
  id: const ProjectId('ink-project'),
  name: 'Ink',
  createdAt: DateTime.utc(2026, 11, 18),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'c',
          duration: 6,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: const LayerId('c-sb'),
              name: 'SB',
              kind: LayerKind.storyboard,
              frames: [
                Frame(id: const FrameId('c-0'), duration: 1, strokes: const []),
              ],
              timeline: {
                0: const TimelineExposure.drawing(
                  FrameId('c-0'),
                  length: 6,
                  memo: ExposureMemo(inkId: 'ink-0'),
                ),
              },
            ),
          ],
        ),
      ],
    ),
  ],
);
