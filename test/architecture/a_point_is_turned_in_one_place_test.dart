import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨A POINT IS TURNED IN ONE PLACE — [PlaneTurn], beside the one table its
/// cosine and sine come from.
///
/// `x·cos − y·sin, x·sin + y·cos` and its way back were written out by hand
/// wherever something turned — the viewport, the transform box, its fold
/// and its scale solve, a text and its frame, a guide's symmetry — and half
/// of them read `math.cos` instead of the table, so a text turned 90° kept
/// a 6e-17 that the box's affine did not (board
/// `a-point-turned-by-an-angle-is-spelled-in-many-places`, 2026-10-18).
///
/// A turn is TWO crossed sums, one for each coordinate, a few lines apart
/// at most. One alone is a point read along a direction
/// (`projectOntoAxis`), which is not a turn.
///
/// ↩️It was a RATCHET until 2026-10-23: the files that still turned a point
/// by hand stood on a ledger that only shrank. The last two — a brush
/// dab's pixel turned into tip space, in the coverage law and again in the
/// tile kernel's loop — turn by the home's formula now (`turnedX`, board
/// `the-brush-kernel-turns-a-pixel-into-tip-space-in-two-places`), so it is
/// a ban.
void main() {
  const home = 'lib/src/core/turn_trig.dart';

  /// A cosine or a sine as the code names one — `cos`, `turn.sin`,
  /// `tipCos`, `affine.cosTheta`, `math.cos(radians)` — and not `cosine`,
  /// `cos2` or `sinAbs`, which are other things (a hue's weights, a
  /// reflection's doubled angle, a turned box's reach).
  const cosine = r'\b[\w.]*(?:cos|Cos)(?:Theta)?\b(?:\([^()]*\))?';
  const sine = r'\b[\w.]*(?:sin|Sin)(?:Theta)?\b(?:\([^()]*\))?';

  /// What a file must name, a cosine and a sine both, before it is read
  /// closely — the close read costs forty seconds over `lib/` without it.
  final namesACosine = RegExp(r'(?:cos|Cos)(?:Theta)?\b');
  final namesASine = RegExp(r'(?:sin|Sin)(?:Theta)?\b');

  /// A coordinate: a name, a field, or one bracket — `dx`, `point.dx`,
  /// `(ux - px)`.
  const factor = r'(?:\([^()]*\)|\b[\w.]+)';

  /// A coordinate times [trig], either side of the `*`: `dx * cos`,
  /// `(ux - px) * -sin`, `cos * origin.x`.
  String timesBy(String trig) =>
      '(?:$factor\\s*\\*\\s*-?\\s*$trig|-?\\s*$trig\\s*\\*\\s*$factor)';

  /// One coordinate of a turned point: `dx * cos - dy * sin`.
  final crossedSum = RegExp(
    '${timesBy(cosine)}\\s*[-+]\\s*${timesBy(sine)}'
    '|${timesBy(sine)}\\s*[-+]\\s*${timesBy(cosine)}',
  );

  /// Where [source] turns a point by hand: the first line of each place
  /// two crossed sums stand within three lines of each other — its
  /// comments aside, so a decision that quotes the old spelling is not one.
  List<int> turnsIn(String source) {
    final code = codeOfLines(source);
    if (!namesACosine.hasMatch(code) || !namesASine.hasMatch(code)) {
      return const [];
    }
    final sums = [
      for (final m in crossedSum.allMatches(code))
        '\n'.allMatches(code.substring(0, m.start)).length + 1,
    ];
    final turns = <int>[];
    int? start;
    var last = 0;
    var count = 0;
    void close() {
      if (count >= 2) turns.add(start!);
    }

    for (final line in sums) {
      if (start != null && line - last <= 3) {
        count += 1;
      } else {
        close();
        start = line;
        count = 1;
      }
      last = line;
    }
    close();
    return turns;
  }

  test('premise: the home turns a point once', () {
    expect(turnsIn(File(home).readAsStringSync()), hasLength(1));
  });

  test('premise: the scan sees every spelling the card took out', () {
    // In the shapes they stood in on 2026-10-18, a pair of each.
    const spelled = [
      // The viewport's way in, and its way back.
      'x: (x * cos - y * sin) * zoom,\n'
          'y: (x * sin + y * cos) * zoom,',
      'final rx = ux * cos + uy * sin;\n'
          'final ry = -ux * sin + uy * cos;',
      // The box's anchor, by its own getters, a getter apart.
      'double get appliedTx =>\n'
          '    tx + anchorX - (anchorX * cosTheta - anchorY * sinTheta);\n'
          '\n'
          'double get appliedTy =>\n'
          '    ty + anchorY - (anchorX * sinTheta + anchorY * cosTheta);',
      // The fold, three entries apart.
      'c: (offsetX * cos + offsetY * sin) * invSx,\n'
          'd: -sin * invSy,\n'
          'e: cos * invSy,\n'
          'f: (offsetX * -sin + offsetY * cos) * invSy,',
      // A text's turn about its cross.
      'x: centre.x + dx * cos - dy * sin,\n'
          'y: centre.y + dx * sin + dy * cos,',
      // A guide's, its turn on the left and its bracket opened.
      'origin.x - cos * origin.x + sin * origin.y,\n'
          'origin.y - sin * origin.x - cos * origin.y,',
      // The CLIP STUDIO frame's corner, both sums cosine first.
      'x: (ax * cos + ay * sin).round(),\n'
          'y: (ay * cos - ax * sin).round(),',
      // A dab's pixel in tip space.
      'final tipU = dx * tip.tipCos - dy * tip.tipSin;\n'
          'final tipV = (dx * tip.tipSin + dy * tip.tipCos) * inverse;',
      // The library's, inline.
      'x * math.cos(r) - y * math.sin(r),\n'
          'x * math.sin(r) + y * math.cos(r),',
    ];
    for (final pair in spelled) {
      expect(turnsIn(pair), hasLength(1), reason: pair);
    }
  });

  test('premise: what is not a turn is not one', () {
    const notTurns = [
      // A point read along a direction: one sum.
      'final along =\n'
          '    (point.x - axis.origin.x) * math.cos(radians) +\n'
          '    (point.y - axis.origin.y) * math.sin(radians);',
      // A reflection's doubled angle.
      'origin.x - cos2 * origin.x - sin2 * origin.y,\n'
          'origin.y - sin2 * origin.x + cos2 * origin.y,',
      // A turned box's reach.
      'halfExtentX = radius * cosAbs + minorRadius * sinAbs;\n'
          'halfExtentY = radius * sinAbs + minorRadius * cosAbs;',
      // A hue's weights.
      'weight + cosine * cosineWeight + sine * sineWeight;',
      // Two directions' reads, far apart.
      'a * cos + b * sin;\n\n\n\nc * cos + d * sin;',
    ];
    for (final source in notTurns) {
      expect(turnsIn(source), isEmpty, reason: source);
    }
  });

  test('no file but the home turns a point by hand', () {
    final offenders = <String>[
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != home)
          for (final line in turnsIn(file.readAsStringSync()))
            '${libPath(file)}:$line',
    ];
    expect(offenders, isEmpty, reason: 'reach for PlaneTurn');
  });
}
