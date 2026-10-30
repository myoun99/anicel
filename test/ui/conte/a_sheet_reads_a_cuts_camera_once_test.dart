import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';

/// Any edit lays the conte book again, and a moving camera is the dearest
/// thing it reads (a 400-cut work spent 1000ms there of 1080ms, measured
/// 2026-10-31). The reading is kept on the cut, so these pin both halves of
/// that: a cut nothing touched is read once, and nothing the reading asks
/// of the work is served stale.
void main() {
  const track = TrackId('track');

  Cut moving(String id, {double reach = 300}) {
    final block = FrameId('$id-block');
    return Cut(
      id: CutId(id),
      name: id,
      duration: 48,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      camera: CutCamera(
        keyframes: {
          0: CameraPose(center: CanvasPoint(x: 0, y: 0), zoom: 1),
          36: CameraPose(center: CanvasPoint(x: reach, y: 0), zoom: 1),
        },
      ),
      layers: [
        Layer(
          id: LayerId('$id-sb'),
          name: 'SB',
          kind: LayerKind.storyboard,
          frames: [Frame(id: block, duration: 1, strokes: const [])],
          timeline: {0: TimelineExposure.drawing(block, length: 48)},
        ),
      ],
    );
  }

  Project work() => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 10, 31),
    tracks: [
      Track(id: track, name: 'V', cuts: [moving('c1'), moving('c2')]),
    ],
  );

  ConteCellSource cell(Project project, int cut) =>
      buildConteSheetSource(project).cuts[cut].cells.single;

  test('a cut nothing touched keeps its reading through the next book', () {
    final project = work();
    final before = cell(project, 0);
    expect(before.camera, isNotNull, reason: 'fixture: the camera moves');
    expect(before.cameraLines, isNotEmpty, reason: 'fixture: it writes');

    final after = cell(project.copyWith(name: 'Renamed'), 0);
    expect(identical(after.camera, before.camera), isTrue);
    expect(identical(after.cameraLines, before.cameraLines), isTrue);
  });

  test('the cut an edit touched reads again, and only it', () {
    final project = work();
    final (first, second) = (cell(project, 0), cell(project, 1));

    final edited = project.copyWith(
      tracks: [
        project.tracks.single.copyWith(
          cuts: [
            moving('c1', reach: 900),
            project.tracks.single.cuts[1],
          ],
        ),
      ],
    );

    expect(cell(edited, 0).camera?.field, isNot(first.camera?.field));
    expect(identical(cell(edited, 1).camera, second.camera), isTrue);
  });

  test('a camera of another size reads again', () {
    final project = work();
    final before = cell(project, 0).camera?.screen;
    final after = cell(
      project.copyWith(cameraSize: const CanvasSize(width: 960, height: 540)),
      0,
    ).camera?.screen;
    expect(after, isNot(before));
  });

  test('another count writes its lines again', () {
    final project = work();
    final before = cell(project, 0).cameraLines;
    final after = cell(
      project.copyWith(frameRate: const ProjectFrameRate.integer(12)),
      0,
    ).cameraLines;
    expect(after, isNot(before));
  });

  test('another glossary writes its lines again', () {
    final project = work();
    final before = cell(project, 0).cameraLines;
    expect(before.join(), contains('PAN'), reason: 'fixture: a pan');

    final after = cell(
      project.copyWith(
        cameraInstructions: CameraInstructionSet(
          defs: [
            for (final def in project.cameraInstructions.defs)
              if (def.id == 'pan')
                const CameraInstructionDef(
                  id: 'pan',
                  name: 'ヨコ',
                  iconKey: 'pan',
                )
              else
                def,
          ],
        ),
      ),
      0,
    ).cameraLines;
    expect(after.join(), contains('ヨコ'));
  });
}
