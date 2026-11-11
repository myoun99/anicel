import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/cut_id.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/layer_effect.dart';
import '../../models/string_id.dart';

/// A plugin's effect as its header names it: [effect] of [owner]'s chain
/// ([FxPluginWorn]).
typedef FxPluginPlace = ({StringId owner, EffectId effect});

/// Who a run was worn by: the row whose picture it ran over, in the cut it
/// was drawn in ([FxPluginWorn.wearer]).
typedef FxPluginWearer = ({CutId cut, StringId row});

/// WHICH PLUGIN EFFECTS FAILED TO DRAW, AND AT WHICH FRAME — what a plugin
/// effect's fx row header shows: 🗣️a-failed-plugin-shows-the-cel-silently-Q1
/// (유저 2026-11-08): 「원래 셀 + 머리를 회색으로, 이름 뒤 ⚠ 칸은 늘 잡아
/// 둔다」 — the picture stays the cel as if the effect were off, and the
/// header greys with a ⚠ while the frame it stands on failed.
///
/// Every route that shows a plugin's picture tells it through the run
/// ([FxPluginRun.told]) — kept or made, each time — by where the effect is
/// worn ([ResolvedLayerEffect.worn]): a header asks of its effect at a frame
/// whether any row that wears it failed there — an attach row runs its
/// base's chain over its own picture, and may fail where the base draws.
///
/// 🚨A RUN BOUND IS TOLD AT ONCE HOW ITS SAMPLE WENT WHERE IT RAN BEFORE
/// ([toldFor]) — card a-cached-failed-picture-loses-its-mark (2026-11-08):
/// a picture comes back from a cache with no run, and a frame's picture
/// holds its plugin's steps run, so an undo that gives a chain back the
/// value it failed at, or a switch that puts it back on, ran nothing to
/// tell it (🔬the V row's switch, Surface Pro 11, 2/2). What is bound is
/// the chain as it is shown now, and a run of the same sample at the same
/// frame over the same row goes as it went.
final class FxPluginOutcomes extends ChangeNotifier {
  final Map<FxPluginPlace, Map<int, Map<FxPluginWearer, _Worn>>> _places =
      {};

  /// ⚖️The tellers [toldFor] handed out, the newest [_tellersKept]: the same
  /// one for the same sample of the same effect, worn alike at the same
  /// frame — so a picture that tells again what its steps told
  /// (`EngineFramePicture.hold`) keeps one of each, however often its
  /// chain is bound anew.
  final LinkedHashMap<_Teller, FxPluginTold> _tellers = LinkedHashMap();
  static const int _tellersKept = 256;
  bool _announcing = false;
  bool _disposed = false;

  /// What [sample]'s run — worn as [worn] says, in [cut], at [frame] —
  /// tells how it went ([FxPluginRun.told]); and, as it is bound, how the
  /// same sample went there before, where it ran.
  void Function({required bool failed}) toldFor(
    FxPluginWorn worn,
    ResolvedLayerEffect sample, {
    required CutId cut,
    required int frame,
  }) {
    final place = (owner: worn.owner, effect: worn.effect);
    final wearer = (cut: cut, row: worn.wearer);
    final before = _places[place]?[frame]?[wearer];
    if (before?.went[sample] case final failed?) {
      _set(before!, failed: failed);
    }
    void told({required bool failed}) {
      final kept = ((_places[place] ??= {})[frame] ??= {})[wearer] ??=
          _Worn();
      kept.remember(sample, failed: failed);
      _set(kept, failed: failed);
    }

    final teller = (place: place, wearer: wearer, frame: frame, sample: sample);
    final handed = _tellers.remove(teller) ?? told;
    _tellers[teller] = handed;
    if (_tellers.length > _tellersKept) {
      _tellers.remove(_tellers.keys.first);
    }
    return handed;
  }

  /// Whether a run of [place] at [frame] last failed, worn by any row.
  bool failedAt(FxPluginPlace place, int frame) =>
      _places[place]?[frame]?.values.any((worn) => worn.failed) ?? false;

  /// Lets go of what plugin [pluginId]'s runs told: a build of it let go
  /// of — replaced or taken off — tells nothing of the next.
  void forget(String pluginId) {
    _tellers.removeWhere((teller, _) => teller.sample.plugin?.id == pluginId);
    var failedGone = false;
    for (final frames in _places.values) {
      for (final wearers in frames.values) {
        wearers.removeWhere((_, worn) {
          final gone = worn.went.keys.any(
            (sample) => sample.plugin?.id == pluginId,
          );
          failedGone |= gone && worn.failed;
          return gone;
        });
      }
    }
    if (failedGone) {
      _announce();
    }
  }

  void _set(_Worn worn, {required bool failed}) {
    if (worn.failed == failed) {
      return;
    }
    worn.failed = failed;
    _announce();
  }

  /// ⚠️A run is told while a picture is made — in a build, a paint, a
  /// recording — where a listener may not build: so listeners hear it once
  /// that work is done, in a microtask, once for every tell before it.
  void _announce() {
    if (_announcing) {
      return;
    }
    _announcing = true;
    scheduleMicrotask(() {
      _announcing = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A teller [FxPluginOutcomes.toldFor] hands out, as it is asked for.
typedef _Teller = ({
  FxPluginPlace place,
  FxPluginWearer wearer,
  int frame,
  ResolvedLayerEffect sample,
});

/// One row's runs of an effect at a frame: whether the last failed, and
/// how the last samples run went.
final class _Worn {
  bool failed = false;

  /// The samples run, the newest last.
  final LinkedHashMap<ResolvedLayerEffect, bool> went = LinkedHashMap();

  /// ⚖️As many as an undo is likely to walk back through, at a few numbers
  /// each.
  static const int _kept = 16;

  void remember(ResolvedLayerEffect sample, {required bool failed}) {
    went
      ..remove(sample)
      ..[sample] = failed;
    if (went.length > _kept) {
      went.remove(went.keys.first);
    }
  }
}
