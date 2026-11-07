// STILL EDGE COMPARE — the other half of `still_edge_probe_main.dart`: how
// far each cell's image half parts from its live half, read off a
// screenshot of the probe's window.
//
//   dart run tool/probe/still_edge_compare.dart <screenshot.png> <layout.json>
//
// Finds the probe's magenta mark in the screenshot, then for every cell
// compares the two halves pixel for pixel and prints, per variant and shape,
// the worst channel difference, how many pixels part at all and by more than
// 2 and 8, and where the worst one stands in the cell. A variant whose row
// reads 0 everywhere takes its image the way the screen draws.
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/probe/still_edge_compare.dart '
      '<screenshot.png> <layout.json>',
    );
    exit(64);
  }
  final shot = img.decodeImage(File(args[0]).readAsBytesSync());
  if (shot == null) {
    stderr.writeln('not an image: ${args[0]}');
    exit(65);
  }
  final layout =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, Object?>;
  final mark = layout['mark']! as int;
  final origin = _findMark(shot, mark);
  if (origin == null) {
    stderr.writeln('no ${mark}px magenta mark in ${args[0]}');
    exit(66);
  }
  stdout.writeln(
    'screenshot ${shot.width}x${shot.height}, mark at $origin, '
    'devicePixelRatio ${layout['devicePixelRatio']}',
  );
  stdout.writeln(
    'variant  shape        worst  parted  >2     >8     worst at',
  );
  for (final cell in layout['cells']! as List<Object?>) {
    final map = cell! as Map<String, Object?>;
    final live = _rect(map['live']);
    final image = _rect(map['image']);
    final parted = _part(shot, origin, live, image);
    stdout.writeln(
      '${(map['variant']! as String).padRight(8)} '
      '${(map['shape']! as String).padRight(12)} '
      '${'${parted.worst}'.padRight(6)} '
      '${'${parted.any}'.padRight(7)} '
      '${'${parted.overTwo}'.padRight(6)} '
      '${'${parted.overEight}'.padRight(6)} '
      '${parted.at}',
    );
  }
}

/// `[x, y, w, h]` as written by the probe.
List<int> _rect(Object? value) => [
  for (final n in value! as List<Object?>) n! as int,
];

/// The top-left corner of the first [side]-pixel square of pure magenta.
(int, int)? _findMark(img.Image shot, int side) {
  bool magenta(int x, int y) {
    final p = shot.getPixel(x, y);
    return p.r == 255 && p.g == 0 && p.b == 255;
  }

  for (var y = 0; y + side <= shot.height; y += 1) {
    for (var x = 0; x + side <= shot.width; x += 1) {
      if (!magenta(x, y)) {
        continue;
      }
      var whole = true;
      for (var dy = 0; dy < side && whole; dy += 1) {
        for (var dx = 0; dx < side && whole; dx += 1) {
          whole = magenta(x + dx, y + dy);
        }
      }
      if (whole) {
        return (x, y);
      }
    }
  }
  return null;
}

/// How the [image] half parts from the [live] half.
({int worst, int any, int overTwo, int overEight, (int, int)? at}) _part(
  img.Image shot,
  (int, int) origin,
  List<int> live,
  List<int> image,
) {
  final (ox, oy) = origin;
  var worst = 0;
  var any = 0;
  var overTwo = 0;
  var overEight = 0;
  (int, int)? at;
  for (var y = 0; y < live[3]; y += 1) {
    for (var x = 0; x < live[2]; x += 1) {
      final a = shot.getPixel(ox + live[0] + x, oy + live[1] + y);
      final b = shot.getPixel(ox + image[0] + x, oy + image[1] + y);
      var most = 0;
      for (final d in [
        (a.r - b.r).abs(),
        (a.g - b.g).abs(),
        (a.b - b.b).abs(),
      ]) {
        if (d > most) {
          most = d.toInt();
        }
      }
      if (most > 0) {
        any += 1;
      }
      if (most > 2) {
        overTwo += 1;
      }
      if (most > 8) {
        overEight += 1;
      }
      if (most > worst) {
        worst = most;
        at = (x, y);
      }
    }
  }
  return (
    worst: worst,
    any: any,
    overTwo: overTwo,
    overEight: overEight,
    at: at,
  );
}
