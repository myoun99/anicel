import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_dab_dirty_region.dart';

void main() {
  BrushDab dab({
    double x = 10,
    double y = 10,
    double size = 4,
    double opacity = 1,
    double flow = 1,
    BrushTipShape tipShape = BrushTipShape.round,
    int sequence = 0,
  }) {
    return BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: 0xFF000000,
      size: size,
      opacity: opacity,
      flow: flow,
      hardness: 1,
      tipShape: tipShape,
      pressure: 1,
      sequence: sequence,
    );
  }

  group('dirtyRegionForBrushDab', () {
    test('returns null for zero size', () {
      expect(dirtyRegionForBrushDab(dab(size: 0)), isNull);
    });

    test('returns null for zero opacity', () {
      expect(dirtyRegionForBrushDab(dab(opacity: 0)), isNull);
    });

    test('returns null for zero flow', () {
      expect(dirtyRegionForBrushDab(dab(flow: 0)), isNull);
    });

    test('creates conservative bounds for integer center and even size', () {
      expect(
        dirtyRegionForBrushDab(dab(x: 10, y: 10, size: 4)),
        DirtyRegion(left: 8, top: 8, rightExclusive: 12, bottomExclusive: 12),
      );
    });

    test('creates conservative bounds for fractional center', () {
      expect(
        dirtyRegionForBrushDab(dab(x: 10.5, y: 10.5, size: 3)),
        DirtyRegion(left: 9, top: 9, rightExclusive: 12, bottomExclusive: 12),
      );
    });

    test('keeps raw bounds across the origin (pasteboard space)', () {
      expect(
        dirtyRegionForBrushDab(dab(x: 1, y: 1, size: 4)),
        DirtyRegion(left: -1, top: -1, rightExclusive: 3, bottomExclusive: 3),
      );
    });

    test('uses same conservative bounds for round and square tips', () {
      final round = dirtyRegionForBrushDab(
        dab(x: 10.25, y: 12.75, size: 5, tipShape: BrushTipShape.round),
      );
      final square = dirtyRegionForBrushDab(
        dab(x: 10.25, y: 12.75, size: 5, tipShape: BrushTipShape.square),
      );
      expect(round, square);
    });
  });

  group('dirtyRegionsForBrushDabSequence', () {
    test('returns one region per effective dab', () {
      final regions = dirtyRegionsForBrushDabSequence(
        BrushDabSequence([dab(sequence: 0), dab(x: 20, y: 20, sequence: 1)]),
      );
      expect(regions, [
        DirtyRegion(left: 8, top: 8, rightExclusive: 12, bottomExclusive: 12),
        DirtyRegion(left: 18, top: 18, rightExclusive: 22, bottomExclusive: 22),
      ]);
    });

    test('skips non-effective dabs', () {
      final regions = dirtyRegionsForBrushDabSequence(
        BrushDabSequence([
          dab(size: 0, sequence: 0),
          dab(opacity: 0, sequence: 1),
          dab(flow: 0, sequence: 2),
          dab(sequence: 3),
        ]),
      );
      expect(regions, [
        DirtyRegion(left: 8, top: 8, rightExclusive: 12, bottomExclusive: 12),
      ]);
    });

    test('preserves dab order', () {
      final regions = dirtyRegionsForBrushDabSequence(
        BrushDabSequence([dab(x: 30, sequence: 0), dab(x: 5, sequence: 1)]),
      );
      expect(regions.map((region) => region.left), [28, 3]);
    });
  });

  group('dirtyRegionForBrushDabSequence', () {
    test('returns null for empty sequence', () {
      expect(dirtyRegionForBrushDabSequence(BrushDabSequence()), isNull);
    });

    test('returns null when all dabs are non-effective', () {
      expect(
        dirtyRegionForBrushDabSequence(
          BrushDabSequence([dab(size: 0), dab(opacity: 0, sequence: 1)]),
        ),
        isNull,
      );
    });

    test('returns one dab region for one effective dab', () {
      expect(
        dirtyRegionForBrushDabSequence(BrushDabSequence([dab()])),
        DirtyRegion(left: 8, top: 8, rightExclusive: 12, bottomExclusive: 12),
      );
    });

    test('unions multiple effective dab regions', () {
      expect(
        dirtyRegionForBrushDabSequence(
          BrushDabSequence([dab(x: 10, y: 10), dab(x: 30, y: 5)]),
        ),
        DirtyRegion(left: 8, top: 3, rightExclusive: 32, bottomExclusive: 12),
      );
    });
  });

  group('dirtyTileSetForBrushDabSequence', () {
    test('returns empty set for empty sequence', () {
      expect(
        dirtyTileSetForBrushDabSequence(
          sequence: BrushDabSequence(),
          tileSize: 10,
        ).isEmpty,
        isTrue,
      );
    });

    test('returns empty set when all dabs are non-effective', () {
      expect(
        dirtyTileSetForBrushDabSequence(
          sequence: BrushDabSequence([dab(size: 0), dab(flow: 0, sequence: 1)]),
          tileSize: 10,
        ).isEmpty,
        isTrue,
      );
    });

    test('derives tile coords per dab region', () {
      final set = dirtyTileSetForBrushDabSequence(
        sequence: BrushDabSequence([
          dab(x: 1, y: 1, size: 2),
          dab(x: 101, y: 1, size: 2),
        ]),
        tileSize: 10,
      );
      expect(set.coords, {TileCoord(x: 0, y: 0), TileCoord(x: 10, y: 0)});
    });

    test('merges duplicate tile coords', () {
      final set = dirtyTileSetForBrushDabSequence(
        sequence: BrushDabSequence([
          dab(x: 1, y: 1, size: 2),
          dab(x: 2, y: 2, size: 2),
        ]),
        tileSize: 10,
      );
      expect(set.coords, {TileCoord(x: 0, y: 0)});
    });

    test('rejects zero tileSize', () {
      expect(
        () => dirtyTileSetForBrushDabSequence(
          sequence: BrushDabSequence([dab()]),
          tileSize: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative tileSize', () {
      expect(
        () => dirtyTileSetForBrushDabSequence(
          sequence: BrushDabSequence([dab()]),
          tileSize: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  test('service does not mutate BrushDabSequence', () {
    final first = dab(sequence: 0);
    final second = dab(x: 20, sequence: 1);
    final sequence = BrushDabSequence([first, second]);
    final before = sequence.dabs;

    dirtyRegionsForBrushDabSequence(sequence);
    dirtyRegionForBrushDabSequence(sequence);
    dirtyTileSetForBrushDabSequence(sequence: sequence, tileSize: 10);

    expect(sequence.dabs, before);
  });
}
