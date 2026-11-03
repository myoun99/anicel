import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A GIF's octree palette: at most the colours it is asked for, found in a
/// picture, each pixel then given its NEAREST one.
///
/// ↩️It was the image package's `OctreeQuantizer`, which the AI check of
/// 2026-11-04 caught twice over (I-152: 「빨강 획까지 전부 파랑」 ·
/// 「획이 통째로 없다」): it folds a branch into its parent one leaf at a
/// time, so a parent left holding colours AND children is in no palette and
/// its colours are lost; and it finds a pixel's entry by walking the tree,
/// so a colour the tree never held — every colour a dither makes — stops at
/// a branch and takes entry 0. Here a branch is folded whole, deepest and
/// thinnest first (Gervautz–Purgathofer), and an entry is found by
/// distance.
class GifOctreeQuantizer extends img.Quantizer {
  GifOctreeQuantizer._(this.palette, this._entries);

  /// The palette of at most [colors] that an octree finds in [picture] —
  /// every colour of it while it holds no more than that.
  factory GifOctreeQuantizer(img.Image picture, {required int colors}) {
    final counts = _countsOf(picture);
    final root = _Branch(0);
    final branches = List.generate(_depth, (_) => <_Branch>[]);
    for (final MapEntry(key: rgb, value: count) in counts.entries) {
      root.add(rgb, count, branches);
    }
    var leaves = counts.length;
    // Never the root: folding it leaves one colour of up to eight.
    for (var depth = _depth - 1; depth > 0 && leaves > colors; depth -= 1) {
      final level = branches[depth]
        ..sort((a, b) => a.count.compareTo(b.count));
      for (final branch in level) {
        if (leaves <= colors) {
          break;
        }
        final under = branch.leavesUnder;
        // A fold that would leave fewer than asked is left to the merge.
        if (leaves - (under - 1) >= colors) {
          branch.fold();
          leaves -= under - 1;
        }
      }
    }
    final found = <_Branch>[];
    root.collectLeaves(found);
    _mergeDownTo(found, colors);
    final palette = img.PaletteUint8(found.length, 3);
    final entries = <int, int>{};
    for (final (index, leaf) in found.indexed) {
      final (r, g, b) = leaf.mean;
      palette.setRgb(index, r, g, b);
      entries.putIfAbsent(_key(r, g, b), () => index);
    }
    return GifOctreeQuantizer._(palette, entries);
  }

  /// How deep a colour's branch goes: a bit of each channel a level.
  static const int _depth = 8;

  @override
  final img.PaletteUint8 palette;

  /// Each palette colour's entry, the first where two are alike.
  final Map<int, int> _entries;

  /// A colour's nearest entry, by the six high bits of each channel —
  /// asked once each, of the middle of its cell; -1 until asked.
  final Int16List _nearest = Int16List(1 << 18)..fillRange(0, 1 << 18, -1);

  @override
  int getColorIndexRgb(int r, int g, int b) {
    final exact = _entries[_key(r, g, b)];
    if (exact != null) {
      return exact;
    }
    final cell = (r >> 2) << 12 | (g >> 2) << 6 | b >> 2;
    final known = _nearest[cell];
    if (known >= 0) {
      return known;
    }
    return _nearest[cell] = _nearestTo(
      (r & 0xFC) + 2,
      (g & 0xFC) + 2,
      (b & 0xFC) + 2,
    );
  }

  /// The entry nearest (r, g, b), straight across the colour cube.
  int _nearestTo(int r, int g, int b) {
    var best = 0;
    var bestDistance = 1 << 30;
    for (var index = 0; index < palette.numColors; index += 1) {
      final distance = _distance(
        (
          palette.getRed(index).toInt(),
          palette.getGreen(index).toInt(),
          palette.getBlue(index).toInt(),
        ),
        (r, g, b),
      );
      if (distance < bestDistance) {
        best = index;
        bestDistance = distance;
      }
    }
    return best;
  }

  @override
  int getColorIndex(img.Color c) =>
      getColorIndexRgb(c.r.toInt(), c.g.toInt(), c.b.toInt());

  @override
  img.Color getQuantizedColor(img.Color c) {
    final index = getColorIndex(c);
    return img.ColorRgb8(
      palette.getRed(index).toInt(),
      palette.getGreen(index).toInt(),
      palette.getBlue(index).toInt(),
    );
  }

  static int _key(int r, int g, int b) => r << 16 | g << 8 | b;

  static int _distance((int, int, int) a, (int, int, int) b) {
    final dr = a.$1 - b.$1;
    final dg = a.$2 - b.$2;
    final db = a.$3 - b.$3;
    return dr * dr + dg * dg + db * db;
  }

  /// How many pixels of [picture] are each colour it holds.
  static Map<int, int> _countsOf(img.Image picture) {
    final counts = <int, int>{};
    for (final pixel in picture) {
      final rgb = _key(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
      counts[rgb] = (counts[rgb] ?? 0) + 1;
    }
    return counts;
  }

  /// [leaves] down to [colors]: the thinnest, one at a time, into the leaf
  /// nearest it — where no whole fold fits the count.
  static void _mergeDownTo(List<_Branch> leaves, int colors) {
    while (leaves.length > colors) {
      final thinnest = leaves.reduce((a, b) => b.count < a.count ? b : a);
      leaves.remove(thinnest);
      final nearest = leaves.reduce(
        (a, b) => _distance(b.mean, thinnest.mean) <
                _distance(a.mean, thinnest.mean)
            ? b
            : a,
      );
      nearest.take(thinnest);
    }
  }
}

/// A branch of the octree: the colours under it, summed — a leaf while it
/// has no children.
class _Branch {
  _Branch(this.depth);

  final int depth;
  int count = 0;
  int red = 0;
  int green = 0;
  int blue = 0;
  List<_Branch?>? _children;

  /// The mean of the colours under it — black under none: a picture of no
  /// pixels (a frame left all clear) is a root alone, and its one entry is
  /// what the clear pixels stand in while they are dithered.
  (int, int, int) get mean => count == 0
      ? (0, 0, 0)
      : (
          (red / count).round(),
          (green / count).round(),
          (blue / count).round(),
        );

  /// Adds [pixels] of [rgb] to every branch down to its leaf, keeping each
  /// branch that grows children at its level in [branches].
  void add(int rgb, int pixels, List<List<_Branch>> branches) {
    final r = rgb >> 16 & 0xFF;
    final g = rgb >> 8 & 0xFF;
    final b = rgb & 0xFF;
    var at = this;
    while (true) {
      at
        ..count += pixels
        ..red += r * pixels
        ..green += g * pixels
        ..blue += b * pixels;
      if (at.depth == GifOctreeQuantizer._depth) {
        return;
      }
      final bit = 7 - at.depth;
      final slot = (r >> bit & 1) << 2 | (g >> bit & 1) << 1 | b >> bit & 1;
      var children = at._children;
      if (children == null) {
        children = at._children = List<_Branch?>.filled(8, null);
        branches[at.depth].add(at);
      }
      at = children[slot] ??= _Branch(at.depth + 1);
    }
  }

  /// Adds [other]'s colours to this one's.
  void take(_Branch other) {
    count += other.count;
    red += other.red;
    green += other.green;
    blue += other.blue;
  }

  /// How many leaves are under it — itself, while it is one.
  int get leavesUnder {
    final children = _children;
    return children == null
        ? 1
        : children.nonNulls.fold(0, (sum, child) => sum + child.leavesUnder);
  }

  /// Makes this branch a leaf of every colour under it.
  void fold() => _children = null;

  void collectLeaves(List<_Branch> into) {
    final children = _children;
    if (children == null) {
      into.add(this);
      return;
    }
    for (final child in children.nonNulls) {
      child.collectLeaves(into);
    }
  }
}
