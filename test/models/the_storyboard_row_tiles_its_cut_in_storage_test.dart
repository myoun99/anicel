import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/covering_storyboard_normalize.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// 🚨THE STORYBOARD ROW TILES ITS CUT IN STORAGE, NOT ONLY WHEN DERIVED.
///
/// The strip reads a DERIVED coverage while the timeline paints the row's
/// stored blocks, so a stored hole is invisible where it is made and plain
/// where it is not. Every verb that writes the row without writing the cut
/// can make one, which is why this runs as a repository-write
/// normalization rather than in any of them.
///
/// ⛔And it REFUSES rather than repairs when a division sits at or past the
/// cut's end: the reader drops those keys, so filling from it would DELETE
/// that panel. A normalization must never be the thing that loses a
/// drawing.
void main() {
  Layer storyboard(Map<int, TimelineExposure> timeline) => Layer(
    id: const LayerId('sb'),
    name: 'storyboard',
    frames: const [],
    timeline: timeline,
    kind: LayerKind.storyboard,
  );

  TimelineExposure block(String id, int length) =>
      TimelineExposure.drawing(FrameId(id), length: length);

  Cut cutOf(List<Layer> layers, {int duration = 12}) => Cut(
    id: const CutId('c'),
    name: 'c',
    layers: layers,
    duration: duration,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Map<int, TimelineExposure> rowOf(Cut cut) => cut.layers.single.timeline;

  Map<int, int> lengthsOf(Cut cut) => {
    for (final entry in rowOf(cut).entries)
      if (entry.value.length != null) entry.key: entry.value.length!,
  };

  test('a row that already tiles the cut passes through IDENTICAL — an '
      'already-normal cut must not churn the repository', () {
    final cut = cutOf([
      storyboard({0: block('a', 5), 5: block('b', 7)}),
    ]);

    expect(identical(cutWithCoveringStoryboardRow(cut), cut), isTrue);
  });

  test('a stored HOLE at the end is filled to the cut', () {
    final normalized = cutWithCoveringStoryboardRow(
      cutOf([
        storyboard({0: block('a', 5)}),
      ]),
    );

    expect(lengthsOf(normalized), {0: 12});
  });

  test('a row that OVERRUNS the cut is pulled back to it', () {
    final normalized = cutWithCoveringStoryboardRow(
      cutOf([
        storyboard({0: block('a', 40)}),
      ]),
    );

    expect(lengthsOf(normalized), {0: 12});
  });

  test('a hole BETWEEN blocks closes without moving the later block', () {
    final normalized = cutWithCoveringStoryboardRow(
      cutOf([
        storyboard({0: block('a', 2), 6: block('b', 6)}),
      ]),
    );

    expect(
      lengthsOf(normalized),
      {0: 6, 6: 6},
      reason:
          'the earlier block stretches into the gap; the panel that '
          'starts at 6 is still the panel that starts at 6',
    );
  });

  test('⛔a division PAST the cut end is REFUSED, not repaired — filling '
      'from a reader that drops those keys would delete the panel', () {
    final cut = cutOf([
      storyboard({0: block('a', 5), 20: block('b', 3)}),
    ]);

    expect(
      identical(cutWithCoveringStoryboardRow(cut), cut),
      isTrue,
      reason: 'a normalization must never be the thing that loses a drawing',
    );
  });

  test('⛔a division exactly AT the cut end is refused too — the end is '
      'exclusive', () {
    final cut = cutOf([
      storyboard({0: block('a', 5), 12: block('b', 3)}),
    ]);

    expect(identical(cutWithCoveringStoryboardRow(cut), cut), isTrue);
  });

  test('a NEGATIVE key cannot be built at all — Layer refuses one, which '
      'is why this law does not test for it', () {
    // The invariant lives at the boundary that can enforce it. A guard
    // here would be a second answer to a question already settled, and
    // an unreachable branch nobody can make go wrong (measured
    // 2026-09-05: the `key < 0` clause this file used to carry could not
    // be reached, so it was deleted with this test in its place).
    expect(() => storyboard({-3: block('a', 5)}), throwsArgumentError);
  });

  test('a cut with no duration is left alone', () {
    final cut = cutOf([
      storyboard({0: block('a', 5)}),
    ], duration: 0);

    expect(identical(cutWithCoveringStoryboardRow(cut), cut), isTrue);
  });

  test('an EMPTY storyboard row is left alone — there is nothing to tile '
      'the cut with', () {
    final cut = cutOf([storyboard(const {})]);

    expect(identical(cutWithCoveringStoryboardRow(cut), cut), isTrue);
  });

  test(
    'only the STORYBOARD row is touched — the image row has its own law',
    () {
      final image = Layer(
        id: const LayerId('img'),
        name: 'image',
        frames: const [],
        timeline: {0: block('x', 2)},
        kind: LayerKind.image,
      );
      final normalized = cutWithCoveringStoryboardRow(
        cutOf([
          image,
          storyboard({0: block('a', 5)}),
        ]),
      );

      expect(
        identical(normalized.layers.first, image),
        isTrue,
        reason:
            'untouched rows keep their identity, so downstream caches do '
            'not rebuild what did not change',
      );
      expect(normalized.layers.last.timeline[0]!.length, 12);
    },
  );
}
