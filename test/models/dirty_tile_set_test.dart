import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('DirtyTileSet', () {
    final a = TileCoord(x: 0, y: 0);
    final b = TileCoord(x: 1, y: 0);
    final c = TileCoord(x: 0, y: 1);

    test('empty set has length 0', () {
      expect(DirtyTileSet.empty().length, 0);
      expect(DirtyTileSet.empty().isEmpty, isTrue);
      expect(DirtyTileSet.empty().isNotEmpty, isFalse);
    });

    test('constructor stores coords', () {
      final set = DirtyTileSet([a, b]);
      expect(set.coords, {a, b});
    });

    test('constructor defensively copies input coords', () {
      final input = {a};
      final set = DirtyTileSet(input);
      input.add(b);
      expect(set.coords, {a});
    });

    test('coords getter is unmodifiable', () {
      final coords = DirtyTileSet([a]).coords;
      expect(() => coords.add(b), throwsUnsupportedError);
    });

    test('contains returns true for stored coord', () {
      expect(DirtyTileSet([a]).contains(a), isTrue);
    });

    test('contains returns false for missing coord', () {
      expect(DirtyTileSet([a]).contains(b), isFalse);
    });

    /// ⛔There is no one-coordinate `add` to test: it existed, its only
    /// caller folded a commit's tiles in one at a time, and each call
    /// rebuilt the whole set. `addAll` with one coordinate is that case.
    test('addAll of one coord returns a new set with it', () {
      expect(DirtyTileSet([a]).addAll([b]).coords, {a, b});
    });

    test('addAll does not mutate original', () {
      final original = DirtyTileSet([a]);
      final next = original.addAll([b]);
      expect(original.coords, {a});
      expect(next.coords, {a, b});
    });

    /// 🚨The getter used to be `Set.unmodifiable(_coords)` — a fresh copy
    /// per read, over a field the constructor had already made
    /// unmodifiable. Nothing BEHAVIOURAL could see it; identity can, and
    /// identity is what makes the read free.
    test('🚨reading coords twice hands back the SAME set, not a copy', () {
      final set = DirtyTileSet([a, b]);
      expect(identical(set.coords, set.coords), isTrue);
    });

    test('addAll returns new set with all coords', () {
      expect(DirtyTileSet([a]).addAll([b, c]).coords, {a, b, c});
    });
    /// 🪦**THE SET ALGEBRA IS GONE, AND SO ARE ITS CASES.** `remove`,
    /// `union`, `intersect`, `difference` and `copyWith` were never called
    /// from lib — these tests were the only reason they compiled. What a
    /// commit actually does with a dirty set is build it once and read it,
    /// which is `addAll`, `contains` and `coords`.

    test('fromRegion derives touched tiles', () {
      expect(
        DirtyTileSet.fromRegion(
          region: DirtyRegion(
            left: 255,
            top: 0,
            rightExclusive: 257,
            bottomExclusive: 1,
          ),
          tileSize: 256,
        ).coords,
        {a, b},
      );
    });

    test('fromRegions merges touched tiles from multiple regions', () {
      expect(
        DirtyTileSet.fromRegions(
          regions: [
            DirtyRegion(left: 0, top: 0, rightExclusive: 1, bottomExclusive: 1),
            DirtyRegion(
              left: 0,
              top: 255,
              rightExclusive: 1,
              bottomExclusive: 257,
            ),
          ],
          tileSize: 256,
        ).coords,
        {a, c},
      );
    });

    test('equality ignores insertion order', () {
      expect(DirtyTileSet([a, b]), DirtyTileSet([b, a]));
    });

    test('hashCode ignores insertion order', () {
      expect(DirtyTileSet([a, b]).hashCode, DirtyTileSet([b, a]).hashCode);
    });

    test('toJson/fromJson round-trips', () {
      final set = DirtyTileSet([a, b]);
      expectJsonRoundTrip(set, DirtyTileSet.fromJson);
    });
  });
}
