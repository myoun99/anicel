import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';

/// 🗣️I-20-Q2 (유저 2026-09-30): 「콘티 대사 칸에도 찍는다 — 이름 뒤 괄호」 —
/// read off the SE block by the sheet's builder, not by hand.
void main() {
  List<String> printed(SeLineType type) {
    final project = Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 10, 1),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('c'),
              name: '1',
              duration: 24,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: const [],
            ),
          ],
          seLayers: [
            Layer(
              id: const LayerId('se'),
              name: 'S1',
              kind: LayerKind.se,
              frames: [
                Frame(
                  id: const FrameId('se-f'),
                  duration: 6,
                  strokes: const [],
                  name: 'やめて',
                  seName: 'A子',
                  seType: type,
                ),
              ],
              timeline: {
                2: const TimelineExposure.drawing(FrameId('se-f'), length: 6),
              },
            ),
          ],
        ),
      ],
    );
    return [
      for (final line in buildConteSheetSource(project).cuts.single.dialogue)
        line.printed,
    ];
  }

  test('the builder hands the block\'s delivery to the dialogue column', () {
    expect(printed(SeLineType.on), ['A子「やめて」']);
    expect(printed(SeLineType.off), ['A子(OFF)「やめて」']);
    expect(printed(SeLineType.mono), ['A子(MONO)「やめて」']);
  });
}
