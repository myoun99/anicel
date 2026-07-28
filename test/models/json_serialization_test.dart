import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';

void main() {
  frameNameJsonTests();
  test('round-trips a full project hierarchy through JSON', () {
    final project = Project(
      id: const ProjectId('project-1'),
      name: 'Project',
      tracks: [
        Track(
          id: const TrackId('track-1'),
          name: 'Video',
          // The track's SE floor, so loading's ensure keeps the round-trip
          // an identity (SE rows are TRACK-owned).
          seLayers: withEnsuredTrackSeLayers(
            const TrackId('track-1'),
            const [],
          ),
          cuts: [
            Cut(
              id: const CutId('cut-1'),
              name: 'Cut 1',
              // Include the SE/instruction fixture rows loading would
              // backfill, so the round-trip stays an identity.
              layers: withEnsuredSectionLayers(const CutId('cut-1'), [
                Layer(
                  id: const LayerId('layer-1'),
                  name: 'Line',
                  frames: [
                    Frame(
                      id: const FrameId('frame-1'),
                      duration: 2,
                      strokes: [
                        Stroke(
                          id: const StrokeId('stroke-1'),
                          points: const [
                            StrokePoint(x: 10.5, y: 20.25),
                            StrokePoint(x: 30.5, y: 40.25),
                          ],
                          brushSettings: BrushSettings(
                            color: 0xFFFFFFFF,
                            size: 6,
                            opacity: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ]),
              duration: 48,
              canvasSize: const CanvasSize(width: 1920, height: 1080),
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026, 6, 2),
      frameRate: const ProjectFrameRate.integer(24),
    );

    final restored = Project.fromJson(project.toJson());

    expect(restored, project);
    expect(restored.toJson(), project.toJson());
  });

  test('cut leadingGap serializes only when set; legacy JSON loads '
      'gap-free', () {
    final gapped = Cut(
      id: const CutId('gapped'),
      name: 'Gapped',
      // Loading backfills the section fixtures — include them so the
      // round-trip stays an identity.
      layers: withEnsuredSectionLayers(const CutId('gapped'), const []),
      duration: 12,
      leadingGapFrames: 5,
      canvasSize: const CanvasSize(width: 8, height: 8),
    );
    final json = gapped.toJson();
    expect(json['leadingGap'], 5);
    expect(Cut.fromJson(json), gapped);

    // Gap 0 is the default and stays OUT of the JSON (shape-based
    // migration: legacy files simply have no key).
    final flush = gapped.copyWith(leadingGapFrames: 0);
    final flushJson = flush.toJson();
    expect(flushJson.containsKey('leadingGap'), isFalse);
    expect(Cut.fromJson(flushJson).leadingGapFrames, 0);
  });

  test('layer timeline map serializes and deserializes drawing entries '
      'with breakdown offsets', () {
    final layer = Layer(
      id: const LayerId('layer-timeline'),
      name: 'Timeline Layer',
      frames: [
        Frame(id: const FrameId('frame-a'), duration: 2, strokes: const []),
      ],
      timeline: {
        0: TimelineExposure.drawing(
          const FrameId('frame-a'),
          length: 6,
          breakdownOffsets: const [2, 4],
        ),
      },
    );

    final restored = Layer.fromJson(layer.toJson());

    expect(restored, layer);
    expect(restored.timeline[0]!.breakdownOffsets, const [2, 4]);
  });

  test(
    'old layer JSON without timeline derives timeline from frame durations',
    () {
      final json = {
        'id': const LayerId('old-layer').toJson(),
        'name': 'Old Layer',
        'frames': [
          Frame(
            id: const FrameId('a'),
            duration: 3,
            strokes: const [],
          ).toJson(),
          Frame(
            id: const FrameId('b'),
            duration: 2,
            strokes: const [],
          ).toJson(),
        ],
        'isVisible': true,
        'opacity': 1.0,
      };

      final layer = Layer.fromJson(json);

      expect(
        layer.timeline[0],
        TimelineExposure.drawing(const FrameId('a'), length: 3),
      );
      expect(
        layer.timeline[3],
        TimelineExposure.drawing(const FrameId('b'), length: 2),
      );
    },
  );
}

void frameNameJsonTests() {
  test('frame JSON includes name when present and round trips it', () {
    final frame = Frame(
      id: const FrameId('named-frame'),
      duration: 2,
      strokes: const [],
      name: 'A1',
    );

    final json = frame.toJson();
    final decoded = Frame.fromJson(json);

    expect(json['name'], 'A1');
    expect(decoded, frame);
  });

  test('frame JSON includes seName only when present and round trips it', () {
    final frame = Frame(
      id: const FrameId('se-frame'),
      duration: 2,
      strokes: const [],
      name: '그건 아니라고 생각해',
      seName: '앨리스',
    );

    final json = frame.toJson();
    expect(json['seName'], '앨리스');
    expect(Frame.fromJson(json), frame);

    final bare = Frame(
      id: const FrameId('bare-frame'),
      duration: 1,
      strokes: const [],
    );
    expect(bare.toJson().containsKey('seName'), isFalse);
    expect(Frame.fromJson(bare.toJson()).seName, isNull);
  });

  test('old frame JSON without name loads with null name', () {
    final frame = Frame.fromJson({
      'id': const FrameId('old-frame').toJson(),
      'duration': 1,
      'strokes': const <dynamic>[],
    });

    expect(frame.name, isNull);
    expect(frame.toJson().containsKey('name'), isFalse);
  });
}
