import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';

/// The GPU engine's grid pass refuses a stream holding a corner past 64
/// pixels or below square, whole, rather than draw a smaller corner
/// (`kernels/timeline/grid/mod.rs`, `MOST_RADIUS_Q9`) — and asks the writer
/// to refuse first. The corner is the one the box takes: its radius, or
/// half its narrower side where that is less.
void main() {
  void fill(double width, double height, double radius) =>
      TimelineGridTileOpWriter().rrectFill(0, 0, width, height, radius, 15, 0);
  void ring(double width, double height, double radius) =>
      TimelineGridTileOpWriter().rrectRing(
        (
          x: 0,
          y: 0,
          width: width,
          height: height,
          radius: radius,
          cornerMask: 15,
        ),
        lineWidth: 1,
        openMask: 0,
        rgba: 0,
      );

  for (final (name, write) in [('fill', fill), ('ring', ring)]) {
    test('a $name\'s corner of 64 px is written, one past it is refused', () {
      write(128, 128, 64);
      expect(() => write(129, 129, 64 + 1 / 256), throwsArgumentError);
    });

    test('a $name\'s corner is the one its box takes', () {
      write(16, 16, 100);
      write(128, 300, 100);
      expect(() => write(129, 300, 100), throwsArgumentError);
      expect(() => write(300, 129, 100), throwsArgumentError);
    });

    test('a $name\'s corner below square is refused', () {
      write(16, 16, 0);
      expect(() => write(16, 16, -1 / 256), throwsArgumentError);
    });
  }
}
