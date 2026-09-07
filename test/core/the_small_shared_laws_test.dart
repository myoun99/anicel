import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/argb_channels.dart';
import 'package:anicel/src/core/contain_rect.dart';
import 'package:anicel/src/core/copy_with_sentinel.dart';
import 'package:anicel/src/core/identity_memo.dart';
import 'package:anicel/src/core/inserted_at.dart';
import 'package:anicel/src/core/mapped_or_same.dart';
import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/core/set_toggle.dart';
import 'package:anicel/src/core/unit_direction.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/rgba_image_bytes.dart';
import 'package:anicel/src/services/brush_preset_id_mint.dart';

/// The small shared laws in `core` and beside it — each one replaced two
/// to four hand-written copies, and none was named by a test (the audit's
/// untested-file pass, 2026-09-05).
void main() {
  group('argb channels — the four bytes of 0xAARRGGBB, named once', () {
    test('each accessor reads its own byte and nothing of its neighbours', () {
      expect(argbAlpha(0x80123456), 0x80);
      expect(argbRed(0x80123456), 0x12);
      expect(argbGreen(0x80123456), 0x34);
      expect(argbBlue(0x80123456), 0x56);
    });

    test('a full-range colour masks to bytes — no sign, no spill', () {
      expect(argbAlpha(0xFFFFFFFF), 0xFF);
      expect(argbRed(0x00FF0000), 0xFF);
      expect(argbGreen(0x0000FF00), 0xFF);
      expect(argbBlue(0x000000FF), 0xFF);
      expect(argbRed(0xFF00FFFF), 0);
    });
  });

  group('IdentityMemo — rebuilt when the identity or the key moves, and '
      'only then', () {
    test('the same identity and key answers the SAME instance without a '
        'second build', () {
      final memo = IdentityMemo<List<int>>();
      final subject = Object();
      var builds = 0;
      List<int> build() {
        builds += 1;
        return [builds];
      }

      final first = memo.resolve(identity: subject, key: 'a', build: build);
      final again = memo.resolve(identity: subject, key: 'a', build: build);
      expect(identical(first, again), isTrue);
      expect(builds, 1);
    });

    test('a new identity rebuilds; so does a new key on the old identity', () {
      final memo = IdentityMemo<int>();
      final one = Object();
      final two = Object();
      var builds = 0;
      int build() => ++builds;

      expect(memo.resolve(identity: one, key: 1, build: build), 1);
      expect(memo.resolve(identity: two, key: 1, build: build), 2);
      expect(memo.resolve(identity: two, key: 2, build: build), 3);
      expect(memo.resolve(identity: two, key: 2, build: build), 3);
    });

    test('identity is `identical`, never `==` — an equal-but-distinct '
        'object is a change (a Project\'s == is a deep value compare)', () {
      final memo = IdentityMemo<int>();
      var builds = 0;
      int build() => ++builds;
      expect(memo.resolve(identity: _Twin(), build: build), 1);
      expect(memo.resolve(identity: _Twin(), build: build), 2);
      final same = _Twin();
      expect(memo.resolve(identity: same, build: build), 3);
      expect(memo.resolve(identity: same, build: build), 3);
    });
  });

  group('premultiply — one rounding, or a seam between a stroke and its '
      'landed pixels', () {
    Uint8List pixel(int r, int g, int b, int a) =>
        Uint8List.fromList([r, g, b, a]);

    test('opaque bytes are left EXACTLY alone', () {
      final bytes = pixel(10, 200, 255, 255);
      premultiplyRgbaInPlace(bytes);
      expect(bytes, [10, 200, 255, 255]);
    });

    test('a transparent pixel loses its colour — a premultiplied buffer '
        'with colour under alpha 0 blends as a halo', () {
      final bytes = pixel(10, 200, 255, 0);
      premultiplyRgbaInPlace(bytes);
      expect(bytes, [0, 0, 0, 0]);
    });

    test('mul255Round is the app-wide rounding, not a plain divide', () {
      // 128 * 128 / 255 = 64.25; the app's rounding answers 64, and the
      // exact quarter-way cases are where a drifted copy shows.
      expect(mul255Round(128, 128), 64);
      expect(mul255Round(255, 255), 255);
      expect(mul255Round(255, 128), 128);
      expect(mul255Round(1, 1), 0);
      expect(mul255Round(0, 200), 0);
    });

    test('every value round-trips at full alpha', () {
      for (var value = 0; value <= 255; value += 1) {
        expect(mul255Round(value, 255), value, reason: 'value $value');
      }
    });

    test('the copy leaves the source straight', () {
      final straight = pixel(200, 100, 50, 128);
      final premultiplied = premultipliedRgbaCopy(straight);

      expect(straight, [200, 100, 50, 128], reason: 'untouched');
      expect(premultiplied[3], 128);
      expect(premultiplied[0], mul255Round(200, 128));
    });

    test('a whole buffer is walked, four bytes at a time', () {
      final bytes = Uint8List.fromList([
        ...[255, 255, 255, 0],
        ...[255, 255, 255, 255],
        ...[100, 100, 100, 128],
      ]);
      premultiplyRgbaInPlace(bytes);

      expect(bytes.sublist(0, 4), [0, 0, 0, 0]);
      expect(bytes.sublist(4, 8), [255, 255, 255, 255]);
      expect(bytes.sublist(8, 12), [
        mul255Round(100, 128),
        mul255Round(100, 128),
        mul255Round(100, 128),
        128,
      ]);
    });
  });

  group('unitDirection', () {
    test('an axis direction is exactly the axis', () {
      expect(unitDirection(5, 0), (dx: 1.0, dy: 0.0));
      expect(unitDirection(0, -5), (dx: 0.0, dy: -1.0));
    });

    test('a diagonal comes out unit-length', () {
      final direction = unitDirection(3, 4)!;
      expect(direction.dx, closeTo(0.6, 1e-12));
      expect(direction.dy, closeTo(0.8, 1e-12));
    });

    test('🚨a vanishing point MILLIONS of units away still resolves — '
        'squaring before scaling is what overflows', () {
      final direction = unitDirection(3e200, 4e200)!;
      expect(direction.dx, closeTo(0.6, 1e-12));
      expect(direction.dy, closeTo(0.8, 1e-12));
    });

    test('a vanishingly SHORT vector resolves too', () {
      final direction = unitDirection(3e-200, 4e-200)!;
      expect(direction.dx, closeTo(0.6, 1e-12));
      expect(direction.dy, closeTo(0.8, 1e-12));
    });

    test('no direction is null, not a zero vector', () {
      expect(unitDirection(0, 0), isNull);
      expect(unitDirection(double.nan, 1), isNull);
      expect(unitDirection(double.infinity, 1), isNull);
    });
  });

  group('containRect — 늘어난 도장은 도장이 아니다', () {
    test('a wide picture letterboxes: full width, centred vertically', () {
      expect(
        containRect(const Size(200, 100), const Rect.fromLTWH(0, 0, 100, 100)),
        const Rect.fromLTWH(0, 25, 100, 50),
      );
    });

    test('a tall picture pillarboxes: full height, centred horizontally', () {
      expect(
        containRect(const Size(100, 200), const Rect.fromLTWH(0, 0, 100, 100)),
        const Rect.fromLTWH(25, 0, 50, 100),
      );
    });

    test('the slot is honoured where it SITS, not at the origin', () {
      expect(
        containRect(
          const Size(20, 10),
          const Rect.fromLTWH(30, 40, 100, 100),
        ),
        const Rect.fromLTWH(30, 65, 100, 50),
      );
    });

    test('a picture larger than the slot shrinks; a smaller one grows — '
        'contain is a fit, not a cap', () {
      expect(
        containRect(const Size(400, 400), const Rect.fromLTWH(0, 0, 100, 100)),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
      expect(
        containRect(const Size(10, 10), const Rect.fromLTWH(0, 0, 100, 100)),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
    });

    test('an exact-ratio picture fills the slot with nothing left over', () {
      expect(
        containRect(const Size(64, 32), const Rect.fromLTWH(5, 5, 128, 64)),
        const Rect.fromLTWH(5, 5, 128, 64),
      );
    });

    test('a picture with no area answers an empty rect at the slot origin', () {
      expect(
        containRect(Size.zero, const Rect.fromLTWH(7, 9, 100, 100)),
        const Rect.fromLTWH(7, 9, 0, 0),
      );
    });
  });

  group('insertedAt', () {
    test('a null index appends', () {
      expect(insertedAt([1, 2], 3, null), [1, 2, 3]);
    });

    test('an index places, and the original list is not touched', () {
      final original = [1, 2, 3];
      expect(insertedAt(original, 9, 1), [1, 9, 2, 3]);
      expect(original, [1, 2, 3]);
    });

    test('an out-of-range index CLAMPS rather than throwing', () {
      expect(insertedAt([1, 2], 9, -5), [9, 1, 2]);
      expect(insertedAt([1, 2], 9, 40), [1, 2, 9]);
    });

    test('inserting into nothing gives the one item', () {
      expect(insertedAt(<int>[], 9, 3), [9]);
    });
  });

  group('mappedOrSame — the identity-preserving walk every write-time '
      'normalization stands on', () {
    test('when no item changes the SAME list comes back, not a copy', () {
      final items = ['a', 'b', 'c'];
      expect(identical(mappedOrSame(items, (item) => item), items), isTrue);
    });

    test('nothing at all comes back as itself', () {
      final items = <String>[];
      expect(identical(mappedOrSame(items, (item) => '$item!'), items), isTrue);
    });

    test('one changed item gives a NEW list with only that slot replaced, '
        'and the original is not touched', () {
      final items = ['a', 'b', 'c'];
      final next = mappedOrSame(items, (item) => item == 'b' ? 'B' : item);
      expect(identical(next, items), isFalse);
      expect(next, ['a', 'B', 'c']);
      expect(items, ['a', 'b', 'c']);
    });

    test('an EQUAL but not identical result still counts as a change — the '
        'walk asks identity, not ==', () {
      final a = Object();
      final items = [a];
      final next = mappedOrSame(items, (item) => Object());
      expect(identical(next, items), isFalse);
      expect(identical(next.single, a), isFalse);
    });

    test('every item is visited, in order, exactly once', () {
      final seen = <int>[];
      mappedOrSame([3, 1, 2], (item) {
        seen.add(item);
        return item;
      });
      expect(seen, [3, 1, 2]);
    });
  });

  group('estimatedImageBytes', () {
    test('is the same number BitmapTile bills for the pixels we own', () {
      expect(estimatedImageBytes(64, 32), 64 * 32 * BitmapTile.bytesPerPixel);
    });

    test('a zero dimension costs nothing', () {
      expect(estimatedImageBytes(0, 100), 0);
    });
  });

  group('BrushPresetIdMint — a pack may name two brushes the same', () {
    test('a fresh name mints itself', () {
      expect(BrushPresetIdMint().next('ink').value, 'ink');
    });

    test(
      'a collision takes -2, -3, … in ORDER — a re-import has to land '
      'on the same ids or it duplicates the pack instead of replacing it',
      () {
        final mint = BrushPresetIdMint();
        expect(
          [for (var i = 0; i < 4; i += 1) mint.next('ink').value],
          ['ink', 'ink-2', 'ink-3', 'ink-4'],
        );
      },
    );

    test('a name that COLLIDES with a generated suffix skips past it', () {
      final mint = BrushPresetIdMint();
      expect(mint.next('ink').value, 'ink');
      expect(mint.next('ink-2').value, 'ink-2');
      expect(
        mint.next('ink').value,
        'ink-3',
        reason: 'the suffix walk keeps going until it finds a free one',
      );
    });

    test('two mints do not share a numbering — one file, one mint', () {
      expect(BrushPresetIdMint().next('ink').value, 'ink');
      expect(BrushPresetIdMint().next('ink').value, 'ink');
    });
  });

  group('the copyWith sentinel', () {
    test('is its own identity, so "not provided" and "set to null" are '
        'different arguments', () {
      expect(identical(copyWithSentinel, copyWithSentinel), isTrue);
      expect(copyWithSentinel, isNot(isNull));
    });
  });

  group('toggledSet — the copy-then-flip law of the view-state sets', () {
    test('an absent value is added, a present one is removed', () {
      expect(toggledSet(const <int>{}, 1), <int>{1});
      expect(toggledSet(const <int>{1}, 1), isEmpty);
    });

    test('the other members survive both directions', () {
      expect(toggledSet(const <int>{1, 2}, 3), <int>{1, 2, 3});
      expect(toggledSet(const <int>{1, 2, 3}, 2), <int>{1, 3});
    });

    test('the source set is never touched — the answer is a NEW set', () {
      final source = <int>{1, 2};
      final next = toggledSet(source, 2);
      expect(source, <int>{1, 2});
      expect(identical(next, source), isFalse);
      expect(toggledSet(source, 9), isNot(same(source)));
    });

    test('toggling twice returns to where it started', () {
      expect(toggledSet(toggledSet(const <String>{'a'}, 'b'), 'b'), <String>{
        'a',
      });
    });
  });
}

/// Every instance is EQUAL to every other — what a rebuilt-equal Project
/// looks like to `==`, and exactly what the memo must not mistake for the
/// same object.
class _Twin {
  @override
  bool operator ==(Object other) => other is _Twin;

  @override
  int get hashCode => 0;
}
