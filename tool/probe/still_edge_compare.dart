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
// A cell of the app's own way says, last, whether its region drew from its
// image — one that painted live measured nothing.
//
// And of `still_dock_probe_main.dart` — the app itself, two screenshots of
// one state, its images on and off:
//
//   dart run tool/probe/still_edge_compare.dart <image.png> <live.png> \
//     <now.json>
//
// Compares the two shots pixel for pixel and prints, per region the parted
// pixels stand in (the innermost that holds each), the same four numbers and
// what the image shot drew the region from.
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.length == 3) {
    _compareShots(args[0], args[1], args[2]);
    return;
  }
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/probe/still_edge_compare.dart '
      '<screenshot.png> <layout.json>\n'
      '       dart run tool/probe/still_edge_compare.dart '
      '<image.png> <live.png> <now.json>',
    );
    exit(64);
  }
  final shot = _decode(args[0]);
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
    'variant  shape        worst  parted  >2     >8     worst at   image',
  );
  for (final cell in layout['cells']! as List<Object?>) {
    final map = cell! as Map<String, Object?>;
    final live = _rect(map['live']);
    final image = _rect(map['image']);
    final parted = _part(shot, origin, live, image);
    stdout.writeln(
      '${(map['variant']! as String).padRight(8)} '
      '${(map['shape']! as String).padRight(12)} '
      '${parted.columns} '
      '${_imageOf(map)}',
    );
  }
}

/// The dock probe's two shots, parted region by region.
void _compareShots(String imagePath, String livePath, String nowPath) {
  final image = _decode(imagePath);
  final live = _decode(livePath);
  if (image.width != live.width || image.height != live.height) {
    stderr.writeln(
      'the shots differ in size: ${image.width}x${image.height} and '
      '${live.width}x${live.height}',
    );
    exit(65);
  }
  final now =
      jsonDecode(File(nowPath).readAsStringSync()) as Map<String, Object?>;
  final mark = now['mark']! as int;
  final origin = _findMark(image, mark);
  final liveOrigin = _findMark(live, mark);
  if (origin == null || origin != liveOrigin) {
    stderr.writeln('the ${mark}px magenta mark: $origin and $liveOrigin');
    exit(66);
  }
  final regions = [
    for (final region in now['regions']! as List<Object?>)
      region! as Map<String, Object?>,
  ];
  final rects = [for (final region in regions) _rect(region['rect'])];
  final tallies = <int, _Tally>{};
  final whole = _Tally();
  final (ox, oy) = origin;
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      final most = _most(image.getPixel(x, y), live.getPixel(x, y));
      final at = (x - ox, y - oy);
      whole.add(most, at);
      if (most > 0) {
        tallies.putIfAbsent(_innermost(rects, at), _Tally.new).add(most, at);
      }
    }
  }
  stdout.writeln(
    'shots ${image.width}x${image.height}, mark at $origin, '
    'devicePixelRatio ${now['devicePixelRatio']}, phase ${now['phase']}, '
    'still ${now['still']} s, ${regions.length} regions',
  );
  stdout.writeln(
    'worst  parted  >2     >8     worst at     drawn from          region',
  );
  stdout.writeln('${whole.columns}  ${''.padRight(19)} whole screen');
  final parted = tallies.entries.toList()
    ..sort((a, b) => b.value.worst.compareTo(a.value.worst));
  for (final MapEntry(key: index, value: tally) in parted) {
    if (index < 0) {
      stdout.writeln('${tally.columns}  ${''.padRight(19)} in no region');
      continue;
    }
    final region = regions[index];
    final from = '${region['from'] ?? 'live'}';
    stdout.writeln(
      '${tally.columns}  ${from.padRight(19)} '
      '${region['label']} · ${region['name']} · ${region['rect']} · '
      '${region['standDown']}',
    );
  }
}

img.Image _decode(String path) {
  final shot = img.decodeImage(File(path).readAsBytesSync());
  if (shot == null) {
    stderr.writeln('not an image: $path');
    exit(65);
  }
  return shot;
}

/// The index of the smallest of [rects] that holds [at], or -1.
int _innermost(List<List<int>> rects, (int, int) at) {
  final (x, y) = at;
  var best = -1;
  var bestArea = 0;
  for (var i = 0; i < rects.length; i += 1) {
    final [left, top, width, height] = rects[i];
    if (x < left || y < top || x >= left + width || y >= top + height) {
      continue;
    }
    final area = width * height;
    if (best < 0 || area < bestArea) {
      best = i;
      bestArea = area;
    }
  }
  return best;
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
_Tally _part(
  img.Image shot,
  (int, int) origin,
  List<int> live,
  List<int> image,
) {
  final (ox, oy) = origin;
  final tally = _Tally();
  for (var y = 0; y < live[3]; y += 1) {
    for (var x = 0; x < live[2]; x += 1) {
      tally.add(
        _most(
          shot.getPixel(ox + live[0] + x, oy + live[1] + y),
          shot.getPixel(ox + image[0] + x, oy + image[1] + y),
        ),
        (x, y),
      );
    }
  }
  return tally;
}

/// The widest of two pixels' channel differences.
int _most(img.Pixel a, img.Pixel b) {
  var most = 0;
  for (final d in [(a.r - b.r).abs(), (a.g - b.g).abs(), (a.b - b.b).abs()]) {
    if (d > most) {
      most = d.toInt();
    }
  }
  return most;
}

/// Pixels' differences, counted: the worst and where it stands, how many
/// part at all, and by more than 2 and 8.
final class _Tally {
  int worst = 0;
  int any = 0;
  int overTwo = 0;
  int overEight = 0;
  (int, int)? at;

  void add(int most, (int, int) where) {
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
      at = where;
    }
  }

  /// worst · parted · >2 · >8 · worst at, padded to the header.
  String get columns =>
      '${'$worst'.padRight(6)} '
      '${'$any'.padRight(7)} '
      '${'$overTwo'.padRight(6)} '
      '${'$overEight'.padRight(6)} '
      '${'$at'.padRight(10)}';
}

/// What a cell of the app's own way says of its region: the bytes its image
/// held, or why it painted live — empty for the other ways' cells.
String _imageOf(Map<String, Object?> cell) {
  final bytes = cell['imageBytes'];
  if (bytes == null) {
    return '';
  }
  return bytes == 0 ? 'LIVE (${cell['standDown']})' : '$bytes B';
}
