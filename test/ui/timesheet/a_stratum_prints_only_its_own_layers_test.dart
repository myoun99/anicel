import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/envelope/cut_envelope_source.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_painter.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/app_faces.dart';

/// 🚨A STRATUM PRINTS WHAT ITS LAYERS SAY, AND NOTHING ELSE (F-269).
///
/// 유저 2026-10-03: 「타임시트 on off버튼이 카메라레이어에서 적용하면
/// 타임시트용지에 바로 반영안됨 … 애니메이션레이어쪽도 문제있는데 텍스트
/// 두번칠해지는느낌? off해서 껐는데 글자가 남아있고, 글자가 연하게 됬을뿐임.
/// 다른탭 갓다 돌아오면 정상적으로 사라져있음」.
///
/// Each stratum is baked on its own and re-records for its own inputs
/// alone — the ink for the ink. The cells pass printed the values into
/// every stratum that was not the form, the ink's included, so a value
/// turned off stayed in the ink's bake until the panel was built again,
/// and every value showed twice while it was on (the export: three times).
/// So a sheet full of values — cells, a camera instruction, an SE line, a
/// memo — is printed a stratum at a time: the ink and the picture strata,
/// with no ink and no picture, print nothing at all.
void main() {
  setUpAll(loadTheAppFaces);

  final document = TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut'),
      name: '12',
      duration: 24,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      metadata: const CutMetadata(note: 'O.L'),
      layers: [
        Layer(
          id: const LayerId('a'),
          name: 'A',
          kind: LayerKind.animation,
          frames: [
            Frame(id: const FrameId('a-1'), duration: 1, strokes: const []),
            Frame(id: const FrameId('a-2'), duration: 1, strokes: const []),
          ],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('a-1'), length: 6),
            6: TimelineExposure.drawing(FrameId('a-2'), length: 6),
          },
        ),
        Layer(
          id: const LayerId('s'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('s-1'),
              duration: 1,
              strokes: const [],
              name: 'あいうえお',
            ),
          ],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('s-1'), length: 8),
          },
        ),
        Layer(
          id: const LayerId('cam'),
          name: 'CAM',
          kind: LayerKind.instruction,
          frames: const [],
          timeline: const {},
          instructions: {
            0: const InstructionEvent(instructionId: 'pan', length: 6),
          },
        ),
      ],
    ),
    projectName: 'P',
    fps: 24,
    info: const TimesheetInfo(title: 'T'),
    instructionDefById: CameraInstructionSet.standard.defById,
  );

  /// The pixels [layers] print of the document, the whole of it.
  Future<Uint8List> printed(
    WidgetTester tester,
    Set<SheetPaintLayer> layers, {
    required bool continuous,
  }) async {
    final painter = TimesheetDocumentPainter(
      document: document,
      layout: TimesheetDocumentLayout(
        document: document,
        continuous: continuous,
      ),
      face: const TextStyle(
        fontFamily: AppTypography.bundledFamily,
        fontFamilyFallback: AppTypography.bundledFallback,
      ),
      words: timesheetWordsIn(AppLanguage.ja),
      layers: layers,
    );
    final size = painter.layout.documentSize;
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), size);
    final picture = recorder.endRecording();
    final bytes = (await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    picture.dispose();
    return bytes;
  }

  /// How many pixels hold anything.
  int inked(Uint8List rgba) {
    var count = 0;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 0) {
        count += 1;
      }
    }
    return count;
  }

  for (final continuous in [false, true]) {
    final view = continuous ? 'the continuous view' : 'the pages';
    testWidgets('$view: the values print in the content stratum', (
      tester,
    ) async {
      expect(
        inked(
          await printed(
            tester,
            SheetStratum.content.layers,
            continuous: continuous,
          ),
        ),
        greaterThan(0),
        reason: 'LIVENESS: the sheet has values to print',
      );
    });

    for (final stratum in [SheetStratum.ink, SheetStratum.picture]) {
      testWidgets('🎯$view: the ${stratum.name} stratum prints none of the '
          'values — no cell, no instruction, no SE line, no memo', (
        tester,
      ) async {
        expect(
          inked(await printed(tester, stratum.layers, continuous: continuous)),
          0,
        );
      });
    }
  }

  // The cut envelope bakes the same strata through the same shell: held to
  // the same law. (The conte's marks each name their own layer, so its
  // printer cannot print one into another's stratum.)
  group('the cut envelope', () {
    final layout = CutEnvelopeLayout.fit(
      form: CutEnvelopePresets.analog,
      paperWidth: 1280,
      paperHeight: 720,
    );
    const source = CutEnvelopeSource(title: 'T', episode: '12', note: 'O.L');

    Future<Uint8List> printed(
      WidgetTester tester,
      Set<SheetPaintLayer> layers,
    ) async {
      final recorder = ui.PictureRecorder();
      CutEnvelopePainter(
        layout: layout,
        source: source,
        face: const TextStyle(
          fontFamily: AppTypography.bundledFamily,
          fontFamilyFallback: AppTypography.bundledFallback,
        ),
        layers: layers,
      ).paint(ui.Canvas(recorder), const Size(1280, 720));
      final picture = recorder.endRecording();
      final bytes = (await tester.runAsync(() async {
        final image = await picture.toImage(1280, 720);
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
      picture.dispose();
      return bytes;
    }

    testWidgets('its values print in the content stratum', (tester) async {
      expect(
        inked(await printed(tester, SheetStratum.content.layers)),
        greaterThan(0),
        reason: 'LIVENESS: the envelope has values to print',
      );
    });

    for (final stratum in [SheetStratum.ink, SheetStratum.picture]) {
      testWidgets('its ${stratum.name} stratum prints none of them', (
        tester,
      ) async {
        expect(inked(await printed(tester, stratum.layers)), 0);
      });
    }
  });
}
