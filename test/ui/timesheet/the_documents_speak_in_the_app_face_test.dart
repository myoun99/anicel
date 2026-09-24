import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/run_edge_fixtures.dart';

/// 🗣️documents-in-which-face-Q1 (유저 2026-09-24: 「둘다 앱글꼴로 통일」):
/// the timesheet and the cut envelope — their panels and every export of
/// them — write in the app's face. Both named no face and printed in the
/// OS's, so one project exported from two machines came out in two hands.
///
/// ⚠️The oracle is every paragraph as PAINTED, the document set twice in
/// two real faces: each must come out different. A word set from scratch
/// names no face, falls back to the same font both times and comes out the
/// same — so no text site can hide in a count.
void main() {
  testWidgets('every word the sheet writes is in the face it is handed', (
    tester,
  ) async {
    await loadTheAppFaces();
    final document = _sheet();
    final layout = TimesheetDocumentLayout(document: document);
    List<(double, double)> writtenIn(String family) {
      final painted = _Paragraphs();
      TimesheetDocumentPainter(
        document: document,
        layout: layout,
        face: TextStyle(fontFamily: family),
      ).paint(painted, layout.documentSize);
      return painted.metrics;
    }

    final biz = writtenIn('BIZ UDPGothic');
    final nanum = writtenIn('Nanum Gothic');
    // The premise: every writer on the sheet wrote — the numbers, the
    // letters, the cels and the ×, the hold word down its column, the memo,
    // the instruction and the dialogue.
    expect(biz.length, nanum.length);
    expect(biz.length, greaterThan(40));
    for (var i = 0; i < biz.length; i += 1) {
      expect(
        biz[i],
        isNot(nanum[i]),
        reason: 'paragraph $i came out the same in both faces — set from '
            'scratch, it named none',
      );
    }
  });

  testWidgets('every word the envelope writes is in the face it is handed', (
    tester,
  ) async {
    await loadTheAppFaces();
    final layout = CutEnvelopeLayout.fit(
      form: CutEnvelopePresets.analog,
      paperWidth: 1280,
      paperHeight: 720,
    );
    const source = CutEnvelopeSource(
      title: 'Title',
      episode: '12',
      note: 'Note',
    );
    List<(double, double)> writtenIn(String family) {
      final painted = _Paragraphs();
      CutEnvelopePainter(
        layout: layout,
        source: source,
        face: TextStyle(fontFamily: family),
      ).paint(painted, const Size(1280, 720));
      return painted.metrics;
    }

    final biz = writtenIn('BIZ UDPGothic');
    final nanum = writtenIn('Nanum Gothic');
    expect(biz.length, nanum.length);
    expect(biz.length, greaterThan(3), reason: 'the premise: labels and text');
    for (var i = 0; i < biz.length; i += 1) {
      expect(
        biz[i],
        isNot(nanum[i]),
        reason: 'paragraph $i came out the same in both faces',
      );
    }
  });
}

/// A cut that makes every writer on the sheet write: a drawing held with
/// its hold word (止め), an empty run's ×, an SE line, a camera instruction
/// and the Direction memo.
TimesheetDocument _sheet() => TimesheetDocument.fromCut(
  cut: Cut(
    id: const CutId('cut-1'),
    name: '1',
    duration: 12,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    metadata: const CutMetadata(note: 'Memo'),
    layers: [
      rederiveRunBehaviors(
        Layer(
          id: const LayerId('a'),
          name: 'A',
          frames: [
            Frame(id: const FrameId('a-f1'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(
              FrameId('a-f1'),
              length: 2,
              endEdge: holdMark,
            ),
          },
        ),
        cutFrameCount: 8,
      ),
      Layer(
        id: const LayerId('b'),
        name: 'B',
        frames: [
          Frame(id: const FrameId('b-f1'), duration: 1, strokes: const []),
        ],
        timeline: {
          4: const TimelineExposure.drawing(FrameId('b-f1'), length: 1),
        },
      ),
      Layer(
        id: const LayerId('s'),
        name: 'S1',
        kind: LayerKind.se,
        frames: [
          Frame(
            id: const FrameId('s-f1'),
            duration: 1,
            strokes: const [],
            name: 'あいうえお',
          ),
        ],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('s-f1'), length: 8),
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
  instructionDefById: CameraInstructionSet.standard.defById,
);

/// Every paragraph painted: its natural width and its baseline — two faces
/// that agree on one of them seldom agree on both.
class _Paragraphs implements Canvas {
  final metrics = <(double, double)>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      metrics.add((paragraph.maxIntrinsicWidth, paragraph.alphabeticBaseline));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
