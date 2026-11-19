import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/commands/resize_cut_canvas_command.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️a-canvas-resize-leaves-effect-points-behind-Q1 a (유저 2026-11-20
/// 「a 그대로 둔다」): a V row's fx are the TRACK's — every cut of it keys
/// them on the track's frames (R4) — so a cut's canvas resized with its
/// picture moved leaves their points where they were, while the same fx on
/// the cut's own row goes with the picture.
void main() {
  TransformTrack keyedAt(CanvasPoint point) => TransformTrack.empty()
      .copyWith(position: PropertyTrack(keys: {0: PropertyKey(point)}));

  final radialBlur = LayerEffect.defaults(
    id: const EffectId('radial'),
    kind: EffectKind.radialBlur,
  ).copyWith(points: {'center': keyedAt(CanvasPoint(x: 100, y: 200))});

  test('a cut resized with its picture moved leaves its track\'s chain as '
      'it was, points and all', () {
    const cutId = CutId('cut');
    final repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            effects: [radialBlur],
            cuts: [
              Cut(
                id: cutId,
                name: 'C',
                layers: [
                  Layer(
                    id: const LayerId('row'),
                    name: 'A',
                    frames: const [],
                    timeline: const {},
                    effects: [radialBlur],
                  ),
                ],
                duration: 24,
                canvasSize: const CanvasSize(width: 512, height: 256),
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
    final chain = repository.requireProject().tracks.single.effects;

    ResizeCutCanvasCommand(
      repository: repository,
      cutId: cutId,
      canvasSize: const CanvasSize(width: 1024, height: 512),
      contentOffset: (dx: 256, dy: 128),
    ).execute();

    final track = repository.requireProject().tracks.single;
    expect(identical(track.effects, chain), isTrue);
    final row = track.cuts.single.layers.single;
    expect(
      row.effects.single.points['center']!.position.keyAt(0)!.value,
      CanvasPoint(x: 356, y: 328),
      reason: '⛔전제: the row\'s own went with the picture',
    );
  });
}
