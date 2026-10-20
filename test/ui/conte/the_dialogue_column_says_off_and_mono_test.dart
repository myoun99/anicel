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
import 'package:anicel/src/models/sheet_sources.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';

/// 🗣️I-20-Q2 (유저 2026-09-30): 「콘티 대사 칸에도 찍는다 — 이름 뒤 괄호」 —
/// read off the SE block by the sheet's builder, not by hand.
void main() {
  final cut = Cut(
    id: const CutId('c'),
    name: '1',
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: const [],
  );

  /// The track's one SE row: a line of A子's, delivered [type], its sheet
  /// switch [onTimesheet].
  Layer seRow(SeLineType type, {bool onTimesheet = true}) => Layer(
    id: const LayerId('se'),
    name: 'S1',
    kind: LayerKind.se,
    onTimesheet: onTimesheet,
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
    timeline: {2: const TimelineExposure.drawing(FrameId('se-f'), length: 6)},
  );

  /// What the conte sheet's dialogue column prints of [row].
  List<String> printed(Layer row) {
    final project = Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 10, 1),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          cuts: [cut],
          seLayers: [row],
        ),
      ],
    );
    return [
      for (final line in buildConteSheetSource(project).cuts.single.dialogue)
        line.printed,
    ];
  }

  test('the builder hands the block\'s delivery to the dialogue column', () {
    expect(printed(seRow(SeLineType.on)), ['A子「やめて」']);
    expect(printed(seRow(SeLineType.off)), ['A子(OFF)「やめて」']);
    expect(printed(seRow(SeLineType.mono)), ['A子(MONO)「やめて」']);
  });

  // 🗣️F-345 (유저 2026-10-12): 「se트랙 타임시트off시, 콘티용지패널에도 대사
  // 안적도록」.
  test('F-345: an SE row with its sheet switch off writes no line on the '
      'conte sheet — nor on the timesheet, by the one law', () {
    final off = seRow(SeLineType.on, onTimesheet: false);
    expect(printed(off), isEmpty);
    expect(
      SheetSources.of(cut: cut, trackSeLayers: [off]).seLayers,
      isEmpty,
    );

    final on = seRow(SeLineType.on);
    expect(printed(on), ['A子「やめて」'], reason: '⛔전제: switched on, it does');
    expect(
      SheetSources.of(cut: cut, trackSeLayers: [on]).seLayers,
      hasLength(1),
    );
  });
}
