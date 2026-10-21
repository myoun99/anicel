import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart' show matchingClose;
import '../helpers/dart_sources.dart';

/// 🚨A HAND A VIEW HOLDS UP WHILE IT IS MOUNTED GOES THROUGH A `ViewHand`
/// (`lib/src/ui/canvas/view_hand.dart`) — not a callback its `dispose`
/// hands null.
///
/// 🗣️F-419 (유저 2026-10-21: 「선 레이어 불투명도 100에서 80정도로
/// 내렷다가 100으로 올리니 안그려지기 시작했어」): a view built anew comes up
/// before the one it replaces goes down, so a keeper handed a callback took
/// the old view's null as the last word, and the shape tool laid nothing
/// for the rest of the session. A behaviour test sees that only where
/// something builds the view anew within one frame, so this SCANS SOURCE:
/// a `dispose` that hands a widget's callback null.
void main() {
  test('no dispose in lib hands a widget\'s callback null', () {
    final hits = [
      for (final file in dartFilesUnder('lib'))
        ..._hitsIn(libPath(file), file.readAsStringSync()),
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'hold the hand up in a ViewHand the keeper owns — a view built '
          'anew says hello before the old one says goodbye. One that must '
          'keep a callback goes in the ledger, with why',
    );
  });

  test('every ledger entry still hands null, and says why', () {
    final sources = {
      for (final file in dartFilesUnder('lib'))
        libPath(file): file.readAsStringSync(),
    };
    for (final MapEntry(key: (path, name), value: why) in _ledger.entries) {
      expect(why.length, greaterThan(20), reason: '$path needs a reason');
      expect(
        _nullGoodbyes(sources[path] ?? ''),
        contains(name),
        reason: '$path no longer hands `$name` null — take it off the ledger',
      );
    }
  });

  test('the scan sees a planted goodbye, and none outside a dispose', () {
    const planted = '''
  @override
  void initState() {
    super.initState();
    widget.onHand?.call(null);
  }

  @override
  void dispose() {
    if (ready) {
      widget.onShapeShowChanged?.call(null);
    }
    widget.onLander(null);
    widget.hand?.call(_hand);
    super.dispose();
  }

  void _drop() => widget.onGone?.call(null);
''';
    expect(_nullGoodbyes(planted), ['onShapeShowChanged', 'onLander']);
  });

  test('the ledger lets through only its own callback in its own file', () {
    const planted = '''
  @override
  void dispose() {
    widget.onLegendMenus?.call(null);
    widget.onShapeShowChanged?.call(null);
  }
''';
    expect(_hitsIn('lib/src/ui/storyboard_panel.dart', planted), [
      'lib/src/ui/storyboard_panel.dart: widget.onShapeShowChanged(null)',
    ]);
    expect(
      _hitsIn('lib/src/ui/other_panel.dart', planted),
      hasLength(2),
      reason: 'another file\'s goodbye is not the ledger\'s',
    );
  });
}

/// What the scan says of the file at [path] holding [source]: each
/// goodbye the ledger does not keep.
List<String> _hitsIn(String path, String source) => [
  for (final name in _nullGoodbyes(source))
    if (!_ledger.containsKey((path, name))) '$path: widget.$name(null)',
];

/// The names of the widget callbacks each `dispose` in [source] hands null.
List<String> _nullGoodbyes(String source) => [
  for (final body in _disposeBodies(source))
    for (final goodbye in _nullGoodbye.allMatches(body)) goodbye.group(1)!,
];

final _nullGoodbye = RegExp(r'widget\.(\w+)(?:\?\.call|\.call)?\(null\)');

/// Each `dispose` body in [source], from its opening brace to the one
/// that closes it ([matchingClose]).
Iterable<String> _disposeBodies(String source) sync* {
  for (final start in RegExp(r'void dispose\(\) \{').allMatches(source)) {
    final close = matchingClose(source, start.end - 1);
    if (close != null) yield source.substring(start.end, close);
  }
}

/// The goodbyes that keep a callback, keyed by file and callback, with why.
const _ledger = <(String, String), String>{
  ('lib/src/ui/storyboard_panel.dart', 'onLegendMenus'):
      'the rail legend\'s menus are handed over again on every build, a '
      'promise no count can keep; a panel built anew heals the null at its '
      'next build (card rail-legend-menus-lost-to-an-old-goodbye)',
  ('lib/src/ui/timeline/timeline_panel.dart', 'onLegendMenus'):
      'the rail legend\'s menus, as the storyboard panel\'s are',
};
