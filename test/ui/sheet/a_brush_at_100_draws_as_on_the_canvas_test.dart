import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';

/// 🚨A BRUSH AT 100% DRAWS ON EVERY SHEET AS IT DOES ON THE CANVAS.
///
/// 유저 2026-09-26 (one-paper-brush-width-Q2): 「해상도를 캔버스처럼
/// 낮추기」 — the sheets' handwriting at the canvas's grade, so a brush of a
/// size at 100% is as wide on the sheet as on the canvas. Read through the
/// mapping the brush itself draws by — each ink window's view of its
/// surface under the panel's viewport — on the three sheets: the ink view
/// of a window at the panel's 100% is a 100% view.
///
/// The envelope's ink is the FORM's, whatever paper it prints on, so its
/// grade holds where the form prints on the default shooting frame.
void main() {
  final atHundred = CanvasViewport(zoom: 1);
  const cutId = CutId('39');

  Cut cut(int duration) => Cut(
    id: cutId,
    name: '39',
    duration: duration,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: [
      Layer(
        id: const LayerId('sb'),
        name: 'SB',
        kind: LayerKind.storyboard,
        frames: [
          Frame(id: const FrameId('sb-0'), duration: 1, strokes: const []),
          Frame(id: const FrameId('sb-5'), duration: 1, strokes: const []),
        ],
        timeline: const {
          0: TimelineExposure.drawing(
            FrameId('sb-0'),
            length: 5,
            memo: ExposureMemo(inkId: 'ink-0'),
          ),
          5: TimelineExposure.drawing(
            FrameId('sb-5'),
            length: 5,
            memo: ExposureMemo(inkId: 'ink-5'),
          ),
        },
      ),
    ],
  );

  void expectCanvasGrade(Iterable<SheetInkWindow> windows) {
    expect(windows, isNotEmpty, reason: 'fixture: the sheet has windows');
    for (final window in windows) {
      expect(
        window.inkViewport(atHundred).zoom,
        closeTo(1, 1e-3),
        reason: window.id,
      );
    }
  }

  test('the timesheet: every window, page and strip', () {
    final document = TimesheetDocument.fromCut(
      cut: cut(200),
      projectName: 'P',
      fps: 24,
    );
    final layout = TimesheetDocumentLayout(document: document);
    expectCanvasGrade(
      timesheetInkWindows(layout: layout, pagedLayout: layout, cutId: cutId),
    );
  });

  test('the conte: the page and every block\'s row', () {
    final project = Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 9, 26),
      tracks: [
        Track(id: const TrackId('t'), name: 'Video', cuts: [cut(10)]),
      ],
    );
    final body = layoutConteBook(
      buildConteSheetSource(project),
    ).where((page) => page.kind == ContePageKind.body);
    expect(body, isNotEmpty, reason: 'fixture: a body page');
    expectCanvasGrade([for (final page in body) ...conteInkWindows(page)]);
  });

  for (final form in CutEnvelopePresets.all) {
    test('the envelope (${form.id}): every box, on the default frame', () {
      expectCanvasGrade(
        envelopeInkWindows(
          CutEnvelopeLayout.fit(
            form: form,
            paperWidth: defaultProjectCameraSize.width.toDouble(),
            paperHeight: defaultProjectCameraSize.height.toDouble(),
          ),
          cutId,
        ),
      );
    });
  }
}
