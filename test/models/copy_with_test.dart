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
import 'package:anicel/src/models/timeline_exposure.dart';

void main() {
  frameNameCopyWithTests();
  test('copyWith changes only specified value object fields', () {
    const size = CanvasSize(width: 100, height: 200);
    final brush = BrushSettings(size: 4);
    const point = StrokePoint(x: 1, y: 2);

    expect(
      size.copyWith(width: 300),
      const CanvasSize(width: 300, height: 200),
    );
    expect(
      brush.copyWith(opacity: 0.25),
      BrushSettings(size: 4, opacity: 0.25),
    );
    expect(point.copyWith(y: 3), const StrokePoint(x: 1, y: 3));
  });

  test('layer timeline defaults empty, copyWith replaces the timeline, and '
      'equality includes breakdown offsets', () {
    final layer = Layer(
      id: const LayerId('layer-1'),
      name: 'Layer',
      frames: const [],
    );
    final dotted = <int, TimelineExposure>{
      3: TimelineExposure.drawing(
        const FrameId('f-3'),
        length: 2,
        breakdownOffsets: const [1],
      ),
    };
    final markedLayer = layer.copyWith(timeline: dotted);

    expect(layer.timeline, isEmpty);
    expect(markedLayer.timeline[3]!.breakdownOffsets, const [1]);
    expect(markedLayer, isNot(layer));
    expect(
      markedLayer,
      Layer(
        id: const LayerId('layer-1'),
        name: 'Layer',
        frames: const [],
        timeline: dotted,
      ),
    );
    expect(
      markedLayer,
      isNot(
        Layer(
          id: const LayerId('layer-1'),
          name: 'Layer',
          frames: const [],
          timeline: {
            3: TimelineExposure.drawing(const FrameId('f-3'), length: 2),
          },
        ),
      ),
    );
  });

  test(
    'copyWith preserves nested lists unless replaced and leaves original unchanged',
    () {
      final stroke = Stroke(
        id: const StrokeId('stroke-1'),
        points: const [StrokePoint(x: 1, y: 2)],
        brushSettings: BrushSettings(),
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

      final renamedProject = project.copyWith(name: 'Renamed');
      final extendedCut = cut.copyWith(duration: 48);
      final hiddenLayer = layer.copyWith(isVisible: false);
      final longerFrame = frame.copyWith(duration: 2);
      final recoloredStroke = stroke.copyWith(
        brushSettings: BrushSettings(color: 0xFFFFFFFF),
      );

      expect(renamedProject.name, 'Renamed');
      expect(renamedProject.tracks, project.tracks);
      expect(project.name, 'Project');
      expect(extendedCut.layers, cut.layers);
      expect(cut.duration, 24);
      expect(hiddenLayer.frames, layer.frames);
      expect(layer.isVisible, isTrue);
      expect(longerFrame.strokes, frame.strokes);
      expect(frame.duration, 1);
      expect(recoloredStroke.points, stroke.points);
      expect(stroke.brushSettings, BrushSettings());
    },
  );
}

void frameNameCopyWithTests() {
  test('frame copyWith sets and clears nullable name', () {
    final frame = Frame(
      id: const FrameId('named-frame'),
      duration: 1,
      strokes: const [],
    );

    final namedFrame = frame.copyWith(name: 'A1');
    final clearedFrame = namedFrame.copyWith(name: null);

    expect(frame.name, isNull);
    expect(namedFrame.name, 'A1');
    expect(clearedFrame.name, isNull);
  });

  test('frame equality includes nullable name', () {
    final unnamedFrame = Frame(
      id: const FrameId('frame'),
      duration: 1,
      strokes: const [],
    );
    final namedFrame = unnamedFrame.copyWith(name: 'A1');

    expect(namedFrame, isNot(unnamedFrame));
    expect(namedFrame, unnamedFrame.copyWith(name: 'A1'));
  });

  test('frame copyWith sets and clears seName independently of name', () {
    final frame = Frame(
      id: const FrameId('se-frame'),
      duration: 1,
      strokes: const [],
      name: '그건 아니라고 생각해',
    );

    final named = frame.copyWith(seName: '앨리스');
    final cleared = named.copyWith(seName: null);

    expect(frame.seName, isNull);
    expect(named.seName, '앨리스');
    expect(named.name, '그건 아니라고 생각해');
    expect(cleared.seName, isNull);
    expect(cleared.name, '그건 아니라고 생각해');
  });

  test('frame equality includes nullable seName', () {
    final bare = Frame(
      id: const FrameId('frame'),
      duration: 1,
      strokes: const [],
    );
    final named = bare.copyWith(seName: '앨리스');

    expect(named, isNot(bare));
    expect(named, bare.copyWith(seName: '앨리스'));
  });
}
