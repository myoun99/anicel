import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨A MODEL FREEZES A COLLECTION THROUGH ONE HELPER — `frozenList`,
/// `frozenSet` and `frozenMap` (`lib/src/core/frozen_collections.dart`).
///
/// 🔬Card a-track-copy-wraps-its-unchanged-lists-anew (11-11): 33 model
/// files froze with `List.unmodifiable` and its kin, which copy a list a
/// model froze itself as readily as one from outside — so every copy gave
/// each collection it did not change a new identity, and whatever kept
/// work by that identity did the work again. The helper hands its own back.
///
/// ⛔THIS SCANS SOURCE: a model that freezes by hand passes every
/// behaviour test there is, until something keeps work by its identity.
void main() {
  test('🚨no model freezes a collection by hand, outside the ledger', () {
    final found = <String, int>{};
    final hits = <String, List<int>>{};
    for (final file in dartFilesUnder('lib/src/models')) {
      final path = libPath(file);
      final lines = _freezesIn(file.readAsStringSync());
      if (lines.isNotEmpty) {
        found[path] = lines.length;
        hits[path] = lines;
      }
    }
    expectCountsMatchLedger(
      found,
      {for (final MapEntry(:key, :value) in _ledger.entries) key: value.count},
      grew:
          'freeze through `frozenList` · `frozenSet` · `frozenMap` '
          '(`frozenMapOrSame` where the constructor builds the map from the '
          'one it was given) — `List.unmodifiable` copies a list a model '
          'froze itself, and a copy of the model then hands back a new one',
      paidOff: 'these freeze through the helper now — take the line out',
      hits: hits,
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy({
      for (final MapEntry(:key, :value) in _ledger.entries) key: value.why,
    });
  });

  test('the scan sees a planted freeze, typed or not, and not one in a '
      'comment', () {
    const planted = '''
final a = List.unmodifiable(items);
// ↩️It was Set.unmodifiable(items).
final b = Map<int, String>.unmodifiable(entries);
final c = frozenList(items);
''';
    expect(_freezesIn(planted), [1, 3]);
  });

  // 🚨A mark is this isolate's own, and a file opens on a worker: a copy
  // falls back to its own field through `ownFrozen`, which marks it here —
  // without asking, so only for a field every constructor of its class
  // freezes (`frozen_collections.dart` has why).
  test('🚨a copy hands on as its own what its class froze, and only that', () {
    final found = {
      for (final file in dartFilesUnder('lib/src/models'))
        libPath(file): _handOnsIn(file.readAsStringSync()),
    };
    expect(
      {
        for (final MapEntry(:key, :value) in found.entries)
          if (value.unsaid.isNotEmpty) key: value.unsaid,
      },
      isEmpty,
      reason:
          'a copy falls back to a collection its class froze without '
          '`ownFrozen(this.…)` — a model opened from a file was made on a '
          'worker, so it comes unmarked, and its copy hands that one anew',
    );
    expect(
      {
        for (final MapEntry(:key, :value) in found.entries)
          if (value.unearned.isNotEmpty) key: value.unearned,
      },
      isEmpty,
      reason:
          '`ownFrozen` says it of a field its class does not freeze in '
          'every constructor (one takes `this.…` as handed) — a list its '
          'giver can still change would pass on as frozen',
    );
  });

  test('the hand-on scan sees a fallback left unsaid and one said of a '
      'field taken as handed — and takes no call for a constructor', () {
    const planted = '''
class Kept {
  Kept({required List<int> items, required List<int> more})
    : items = frozenList(items),
      more = frozenList(more);
  final List<int> items;
  final List<int> more;
  Kept copyWith({List<int>? items, List<int>? more}) => Kept(
    items: items ?? this.items,
    more: more ?? ownFrozen(this.more),
  );
}
class Both {
  Both(List<int> items) : items = frozenList(items);
  Both._adopting(this.items);
  final List<int> items;
  Both copyWith({List<int>? items}) => Both(items ?? ownFrozen(this.items));
  Both again({List<int>? items}) => Both(items ?? this.items);
}
class Loose {
  Loose(this.items);
  final List<int> items;
  Loose copyWith({List<int>? items}) => Loose(items ?? ownFrozen(this.items));
}
class Called {
  Called(List<int> items) : items = frozenList(items);
  final List<int> items;
  Called copyWith({List<int>? items}) =>
      Called(items ?? ownFrozen(this.items));
}
''';
    final (:unsaid, :unearned) = _handOnsIn(planted);
    expect(unsaid, ['Kept.items @8']);
    expect(unearned, ['Both.items @16', 'Loose.items @22']);
  });
}

/// The lines of [source] that freeze by hand, counted from 1.
List<int> _freezesIn(String source) => [
  for (final (index, line) in codeOfLines(source).split('\n').indexed)
    if (_freeze.hasMatch(line)) index + 1,
];

final _freeze = RegExp(r'\b(List|Set|Map)(<[^()=;]*>)?\.unmodifiable\(');

/// The copies in [source] that fall back to a collection their class froze
/// without saying it is their own, and the ones that say it of a field the
/// class does not freeze in every constructor — each `Class.field @line`.
({List<String> unsaid, List<String> unearned}) _handOnsIn(String source) {
  final lines = codeOfLines(source).split('\n');
  final classes = _ClassesRead(lines);
  return (
    unsaid: [
      for (final (index, line) in lines.indexed)
        for (final match in _fallback.allMatches(line))
          if (match.group(1) == match.group(2) &&
              classes.freezesAlways(index, match.group(1)!))
            classes.nameOf(index, match.group(1)!),
    ],
    unearned: [
      for (final (index, line) in lines.indexed)
        for (final match in _said.allMatches(line))
          if (!classes.freezesAlways(index, match.group(1)!))
            classes.nameOf(index, match.group(1)!),
    ],
  );
}

/// The class each line of a source stands in, and what each class freezes
/// and what its constructors take as handed (`this.field`).
final class _ClassesRead {
  _ClassesRead(List<String> lines) {
    var owner = '';
    for (final line in lines) {
      owner = _owner.firstMatch(line)?.group(1) ?? owner;
      _owners.add(owner);
      for (final match in _frozenAt.allMatches(line)) {
        (_frozen[owner] ??= {}).add(match.group(1)!);
      }
      _readParameters(owner, line);
    }
  }

  final _owners = <String>[];
  final _frozen = <String, Set<String>>{};
  final _handed = <String, Set<String>>{};

  /// How deep [_readParameters] stands in a constructor's parentheses.
  var _depth = 0;

  /// Whether the class of line [index] freezes [field] in every
  /// constructor.
  bool freezesAlways(int index, String field) {
    final owner = _owners[index];
    return (_frozen[owner]?.contains(field) ?? false) &&
        !(_handed[owner]?.contains(field) ?? false);
  }

  /// [field] of the class of line [index], and where.
  String nameOf(int index, String field) =>
      '${_owners[index]}.$field @${index + 1}';

  /// The fields [line] hands a constructor of [owner] as they are, while
  /// it stands in that constructor's parameters — a constructor DECLARED,
  /// at a member's indent: one called at the head of a line stands deeper.
  void _readParameters(String owner, String line) {
    final start = owner.isEmpty
        ? null
        : RegExp('^  (?:const )?$owner(?:\\.\\w+)?\\(').firstMatch(line);
    if (start == null && _depth == 0) {
      return;
    }
    final end = _closing(line, start == null ? 0 : start.end - 1);
    for (final match in _selfAt.allMatches(line.substring(0, end))) {
      (_handed[owner] ??= {}).add(match.group(1)!);
    }
  }

  /// Where on [line] the parentheses open at [from] close — its end while
  /// they go on.
  int _closing(String line, int from) {
    for (var i = from; i < line.length; i += 1) {
      _depth += switch (line[i]) {
        '(' => 1,
        ')' => -1,
        _ => 0,
      };
      if (_depth == 0) {
        return i + 1;
      }
    }
    return line.length;
  }
}

final _owner = RegExp(
  '^(?:abstract |final |sealed |base |interface |mixin )*'
  r'(?:class|enum|mixin) ([A-Za-z_]\w*)',
);
final _frozenAt = RegExp(
  r'(?:^|[\s,:])([a-z]\w*)\s*=\s*frozen(?:List|Set|Map|MapOrSame)\b',
);
final _selfAt = RegExp(r'\bthis\.([a-z]\w*)');
final _fallback = RegExp(r'\b([a-z]\w*) \?\? this\.([a-z]\w*)\b');
final _said = RegExp(r'\bownFrozen\(this\.([a-z]\w*)\)');

const _ledger = <String, ({int count, String why})>{
  'lib/src/models/composite_tree.dart': (
    count: 19,
    why:
        'on the transition list (관제 11-11: bitmap_tile · brush_stamp_image '
        '· composite_tree · layer_blend_mode) — another lane is moving it, '
        'and nothing here touches it until that lane lands.',
  ),
};
