import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';

/// A movie kept as a reference is one held cel; every position of it is a
/// MOVIE CEL, named by the held cel and how far into the movie it is.
void main() {
  test('a movie cel names its held cel and how far into the movie it is', () {
    final id = movieCelFrameId(const FrameId('f-1'), 27);
    expect(movieCelOf(id), (held: const FrameId('f-1'), elapsed: 27));
    expect(
      movieCelOf(const FrameId('f-1')),
      isNull,
      reason: 'a cel of its own is not a movie cel',
    );
    expect(
      movieCelOf(const FrameId('@m3')),
      isNull,
      reason: 'no held cel before the mark',
    );
    expect(
      movieCelOf(const FrameId('f-1@m-3')),
      isNull,
      reason: 'no position lies before the movie starts',
    );
  });

  test('only a reference to a MOVIE is a movie reference', () {
    Layer layer(String? path) {
      final plain = Layer(
        id: const LayerId('l'),
        name: 'l',
        frames: const [],
        timeline: const {},
      );
      return path == null
          ? plain
          : plain.copyWith(mediaReference: MediaReference(assetPath: path));
    }

    expect(isMovieReference(layer('/takes/a.mov')), isTrue);
    expect(
      isMovieReference(layer('/stills/a.png')),
      isFalse,
      reason: 'a still reference\'s cel IS its pixels',
    );
    expect(isMovieReference(layer(null)), isFalse);
  });

  test('a position counts from the BLOCK\'s start, plus the file\'s IN '
      'point — wherever the block stands', () {
    var ids = 0;
    final planned = planMovieReferenceLayer(
      referencePath: '/takes/a.mov',
      displayName: 'a',
      span: (first: 3, count: 4),
      mint: ImportIdMint(
        nextLayerId: () => LayerId('movie-${++ids}'),
        nextFrameId: (layerId) => FrameId('${layerId.value}-held'),
        nextCutId: () => CutId('cut-${++ids}'),
      ),
    );
    final moved = planned.copyWith(
      timeline: SplayTreeMap<int, TimelineExposure>()
        ..[5] = planned.timeline[0]!,
    );
    final held = moved.frames.single.id;

    expect(resolveExposedFrameAt(moved, 4), isNull);
    expect(resolveExposedFrameAt(moved, 5)!.id, movieCelFrameId(held, 3));
    expect(resolveExposedFrameAt(moved, 8)!.id, movieCelFrameId(held, 6));
    expect(resolveExposedFrameAt(moved, 9), isNull, reason: 'past the block');
  });
}
