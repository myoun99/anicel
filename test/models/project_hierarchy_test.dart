import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';

void main() {
  test(
    'creates the full Project -> Track -> Cut -> Layer -> Frame -> Stroke hierarchy',
    () {
      final stroke = Stroke(
        id: const StrokeId('stroke-1'),
        points: const [StrokePoint(x: 1, y: 2), StrokePoint(x: 3, y: 4)],
        brushSettings: BrushSettings(size: 8),
      );
      final frame = Frame(
        id: const FrameId('frame-1'),
        duration: 1,
        strokes: [stroke],
      );
      final layer = Layer(
        id: const LayerId('layer-1'),
        name: 'Line',
        frames: [frame],
      );
      final cut = Cut(
        id: const CutId('cut-1'),
        name: 'Cut 1',
        layers: [layer],
        duration: 24,
        canvasSize: const CanvasSize(width: 1280, height: 720),
      );
      final track = Track(
        id: const TrackId('track-1'),
        name: 'Video',
        cuts: [cut],
      );
      final project = Project(
        id: const ProjectId('project-1'),
        name: 'Project',
        tracks: [track],
        createdAt: DateTime.utc(2026),
      );

      expect(project.tracks.single, track);
      expect(project.tracks.single.cuts.single, cut);
      expect(project.tracks.single.cuts.single.layers.single, layer);
      expect(
        project.tracks.single.cuts.single.layers.single.frames.single,
        frame,
      );
      expect(
        project
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames
            .single
            .strokes
            .single,
        stroke,
      );
    },
  );

  test('defensively copies child lists as unmodifiable lists', () {
    final strokes = <Stroke>[
      Stroke(
        id: const StrokeId('stroke-1'),
        points: const [StrokePoint(x: 1, y: 2)],
        brushSettings: BrushSettings(),
      ),
    ];
    final frame = Frame(
      id: const FrameId('frame-1'),
      duration: 1,
      strokes: strokes,
    );

    strokes.clear();

    expect(frame.strokes, hasLength(1));
    expect(
      () => frame.strokes.add(frame.strokes.first),
      throwsUnsupportedError,
    );
  });
}
