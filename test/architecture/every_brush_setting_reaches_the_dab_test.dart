import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**A SETTING THAT NEVER REACHES A DAB IS A CONTROL THAT DOES
/// NOTHING** — and the pixel tests cannot see the hop, because they all
/// build their dabs by hand.
///
/// Measured 2026-09-09, and it had been true for a while: the brush's
/// アンチエイリアス step and the dual mask's density were written by the
/// panel, stored on `BrushShape`, forwarded by every settings bag — and
/// then dropped. Neither live builder passed them. The pin that was
/// supposed to catch exactly this watched `BrushDab.fromInputSample`, an
/// offline factory NOTHING in the app called, so it stayed green while the
/// canvas ignored the setting.
///
/// ⇒ The rule is the INTERSECTION, not a list somebody remembers to
/// extend: every field `BrushShape` and `BrushDab` both declare must be
/// passed by name where a dab is built for the screen. What it is set to is
/// the builder's business (F-12 deliberately passes `opacity: 1`, and the
/// preview picks its own colour); that the parameter is there at all is
/// this test's.
void main() {
  /// Every value a model exposes by name — stored (`final … name;`) AND
  /// derived (`… get name`).
  ///
  /// ⚠️THE GETTERS COUNT. `BrushShape.textureMask` is derived (the picked
  /// texture with its levels baked in) and a stored-fields-only scan lost
  /// it the moment it stopped being a field — silently widening the hole
  /// this test exists to close.
  /// ⚠️`@override` members are skipped: `hashCode` is declared by both
  /// models and is not a brush setting — it is the object protocol.
  Set<String> namesIn(String path) {
    final names = <String>{};
    var overridden = false;
    for (final line in File(path).readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('///')) {
        continue;
      }
      if (trimmed == '@override') {
        overridden = true;
        continue;
      }
      final field = RegExp(
        r'^\s*final\s+[\w<>,?\s]+\s+(\w+);\s*$',
      ).firstMatch(line);
      final getter = RegExp(
        r'^\s*[\w<>,?\s]+\s+get\s+(\w+)\s*[={]',
      ).firstMatch(line);
      if (!overridden) {
        if (field != null) {
          names.add(field.group(1)!);
        } else if (getter != null) {
          names.add(getter.group(1)!);
        }
      }
      overridden = false;
    }
    return names;
  }

  /// The argument text of the first `BrushDab(` in [path], by paren depth.
  String dabArguments(String path) {
    final source = File(path).readAsStringSync();
    final start = source.indexOf('BrushDab(');
    expect(start, isNot(-1), reason: '$path builds no BrushDab any more');
    var depth = 0;
    for (var i = start + 'BrushDab'.length; i < source.length; i += 1) {
      if (source[i] == '(') {
        depth += 1;
      } else if (source[i] == ')') {
        depth -= 1;
        if (depth == 0) {
          return source.substring(start, i);
        }
      }
    }
    fail('$path has an unbalanced BrushDab( — cannot read its arguments');
  }

  test('🚨every setting a dab can carry is passed where one is built', () {
    final shared =
        namesIn('lib/src/models/brush_shape.dart')
          ..retainAll(namesIn('lib/src/models/brush_dab.dart'));
    expect(
      shared,
      containsAll(['antiAlias', 'textureMask']),
      reason: 'fixture premise: the two models really do share fields',
    );

    // Where a dab is built for the SCREEN. Both are UI, and both are the
    // reason this is a source scan: one is private to a widget state.
    const builders = [
      'lib/src/ui/canvas/interactive_brush_edit_canvas_view.dart',
      'lib/src/ui/brush/brush_stroke_preview_cache.dart',
    ];

    final missing = <String>[];
    for (final builder in builders) {
      final arguments = dabArguments(builder);
      for (final field in shared) {
        if (!arguments.contains('$field:')) {
          missing.add('$builder: $field');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'these are brush settings the panel can change and the canvas '
          'never sees. Pass them where the dab is built — and if one is '
          'deliberately not a dab\'s business, take it off BrushDab.',
    );
  });
}
