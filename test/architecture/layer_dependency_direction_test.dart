// THE APP HAS ONE DEPENDENCY DIRECTION, AND THIS IS WHAT MAKES THAT TRUE.
//
// The inner layers describe what the app IS — cuts, layers, frames, brushes,
// the rules that move them. `lib/src/ui` describes what the app LOOKS LIKE.
// A dependency that runs inward is a layer being used; one that runs outward
// is a layer being owned, and the owned one can no longer be reasoned about,
// tested, or moved without dragging a widget tree along.
//
// Nothing enforced this before and the direction held anyway — 197 of 198
// service files, and zero of them import the widget framework. That is
// exactly why it is worth pinning NOW: the cost of the pin is smallest while
// the ledger below is short, and a ledger nobody checks grows by one file at
// a time with nobody noticing.
//
// WHAT THIS IS NOT: it does not say the entries below are wrong. Most of them
// are a TYPE IN THE WRONG FOLDER rather than a layer reaching for a widget —
// `app_input_settings`, `app_accents`, `ui_scale` and friends are settings the
// app has opinions about, and their persistence lives in services, so services
// must reach up to name them. Moving those files inward is audit work, and the
// ledger is what makes that work finite and checkable. Until then this holds
// the line where it currently stands.
//
// It is an instrument, so here is what it looks like when it lies:
//   - it reads import LINES textually, so an import written inside a block
//     comment counts as an import -> a violation nobody can execute
//   - it does not follow `export` chains: a `ui/` type re-exported by an inner
//     barrel file passes unseen -> the direction is broken and this is silent
//   - `part` files carry their parent's imports and are not read here
//   - a conditional import is counted once, by its text
//
// Adding a new outward edge is not forbidden — it is forbidden SILENTLY. Put
// the pair in `_ledger` with the reason you could not avoid it, and the next
// reader gets your argument instead of a mystery.
//
// 2026-09-03 (audit, Round 4): the inner layers are also ORDERED. core sits
// inside models, models inside services, services inside controllers, and a
// file may import only the layers inside its own. This was MEASURED before
// it was pinned: zero edges ran outward except eight services files
// importing a helper cluster (`editing_session_state`, `default_cut_helpers`
// and five more) that held no controller at all — a type in the wrong
// folder, the same shape as the ledger below — and that cluster moved to
// `services/editing/` in the commit that added the test. So the ordering has
// no ledger: the debt was zero on the day it was counted.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/import_graph.dart';

/// The layers that must not know what the app looks like.
///
/// ⚠️IN ORDER, innermost first: the ordering test reads the index.
///
/// `native` is deliberately absent: it is the platform adapter, the outermost
/// ring on that side, and nobody has ever stated a direction for it. Inventing
/// one here would be this test asserting a rule the app never agreed to.
const _innerLayers = <String>['core', 'models', 'services', 'controllers'];

/// Importing one of these IS importing the widget framework.
///
/// `foundation`, `services` and `gestures` are not here on purpose — they are
/// `ChangeNotifier`, `Offset`, key codes and pointer kinds, none of which draw
/// anything. 14 service files use `foundation` today and that is not a leak.
const _widgetFrameworkImports = <String>[
  'package:flutter/material.dart',
  'package:flutter/widgets.dart',
  'package:flutter/cupertino.dart',
];

const _settingsStore =
    'The store persists a settings VALUE whose type is declared under ui/. '
    'Moving the value type inward would take this edge with it.';

/// Every outward dependency that exists TODAY, with the reason it exists.
///
/// Keyed by the importing file, valued by the import target exactly as it is
/// written. An entry that no longer matches anything FAILS: a ledger that
/// keeps paid debts on it stops being read.
///
/// 2026-09-07 (audit, Round 8): `brush_group_icon.dart` came off. Its excuse
/// was that `IconData` must be a const literal or the icon font ships whole —
/// true, and it never required the LITERAL to sit in the enum. The faces moved
/// to a const switch in `ui/brush/brush_group_icon_glyph.dart`, still const,
/// still tree-shaken, and the enum went back to being data.
const _ledger = <String, List<_Debt>>{
  'lib/src/services/persistence/audio_sync_settings_store.dart': [
    _Debt('../../ui/playback/audio_sync_settings.dart', _settingsStore),
  ],
};

class _Debt {
  const _Debt(this.target, this.reason);

  final String target;
  final String reason;
}

void main() {
  group('layer dependency direction', () {
    test('inner layers do not import ui/ or the widget framework', () {
      final unledgered = <String>[];

      for (final file in _innerDartFiles()) {
        final path = _normalise(file.path);
        final allowed = _ledger[path] ?? const <_Debt>[];

        for (final target in _importsOf(file)) {
          if (!_isOutward(target)) {
            continue;
          }
          if (allowed.any((debt) => debt.target == target)) {
            continue;
          }
          unledgered.add('$path -> $target');
        }
      }

      expect(
        unledgered,
        isEmpty,
        reason:
            'These inner-layer files reach outward and are not on the ledger. '
            'Either move the type inward, or add the pair to `_ledger` in this '
            'file with the reason it cannot move:\n  '
            '${unledgered.join('\n  ')}',
      );
    });

    test('each inner layer imports only the layers inside it', () {
      final outward = <String>[];

      for (final file in _innerDartFiles()) {
        final path = _normalise(file.path);
        final ring = _innerLayers.indexOf(_layerOf(path)!);

        for (final target in _importsOf(file)) {
          final targetLayer = _layerOf(_resolvedTarget(path, target));
          if (targetLayer == null) {
            continue;
          }
          if (_innerLayers.indexOf(targetLayer) <= ring) {
            continue;
          }
          outward.add('$path -> $target');
        }
      }

      expect(
        outward,
        isEmpty,
        reason:
            'These files import a layer OUTSIDE their own (core < models < '
            'services < controllers). The fix that has always worked is to '
            'move the imported piece inward — it is a type in the wrong '
            'folder, not a layer that needs the outer one:\n  '
            '${outward.join('\n  ')}',
      );
    });
    test('the ledger has no entries that were already paid off', () {
      final stale = <String>[];

      for (final entry in _ledger.entries) {
        final file = File(entry.key);
        if (!file.existsSync()) {
          stale.add('${entry.key} (file is gone)');
          continue;
        }
        final imports = _importsOf(file).toSet();
        for (final debt in entry.value) {
          if (!imports.contains(debt.target)) {
            stale.add('${entry.key} -> ${debt.target}');
          }
        }
      }

      expect(
        stale,
        isEmpty,
        reason:
            'These ledger entries no longer describe anything. Delete them — a '
            'ledger nobody can trust is a ledger nobody reads:\n  '
            '${stale.join('\n  ')}',
      );
    });

    test('the ledger is the whole debt, counted', () {
      // The number lives in one place so a PR that adds three edges and three
      // excuses still shows up as a number moving the wrong way in the diff.
      final edges = _ledger.values.fold<int>(0, (sum, l) => sum + l.length);
      expect(
        edges,
        1,
        reason:
            'The outward-edge count changed. Going DOWN is the point — update '
            'this number and say so in the commit. Going UP needs an argument.',
      );
    });
  });
}

bool _isOutward(String target) {
  if (_widgetFrameworkImports.contains(target)) {
    return true;
  }
  // Relative hops into the ui tree: '../ui/x.dart', '../../ui/y/z.dart'.
  return RegExp(r'^(\.\./)+ui/').hasMatch(target) ||
      target.startsWith('package:anicel/src/ui/');
}

Iterable<File> _innerDartFiles() sync* {
  for (final layer in _innerLayers) {
    final dir = Directory('lib/src/$layer');
    if (!dir.existsSync()) {
      continue;
    }
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        yield entity;
      }
    }
  }
}

final _importLine = RegExp(
  '''^\\s*import\\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

Iterable<String> _importsOf(File file) =>
    _importLine.allMatches(file.readAsStringSync()).map((m) => m.group(1)!);

String _normalise(String path) => path.replaceAll('\\', '/');

/// Which inner layer [path] (repo-relative, `/`-separated) lives in, or null.
String? _layerOf(String path) {
  const prefix = 'lib/src/';
  if (!path.startsWith(prefix)) {
    return null;
  }
  final layer = path.substring(prefix.length).split('/').first;
  return _innerLayers.contains(layer) ? layer : null;
}

/// [target] as written in [path]'s import line, as a repo-relative path.
///
/// `dart:` and third-party `package:` targets come back as written; they are
/// in no layer of ours and [_layerOf] says so.
String _resolvedTarget(String path, String target) {
  const own = 'package:anicel/';
  if (target.startsWith(own)) {
    return 'lib/${target.substring(own.length)}';
  }
  if (target.contains(':')) {
    return target;
  }
  return normalisePath('${dirOf(path)}/$target');
}
