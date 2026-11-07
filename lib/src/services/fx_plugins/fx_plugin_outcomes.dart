import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/layer_effect.dart';

/// WHICH PLUGIN EFFECTS FAILED TO DRAW, AND AT WHICH FRAME — what a plugin
/// effect's fx row header shows: 🗣️a-failed-plugin-shows-the-cel-silently-Q1
/// (유저 2026-11-08): 「원래 셀 + 머리를 회색으로, 이름 뒤 ⚠ 칸은 늘 잡아
/// 둔다」 — the picture stays the cel as if the effect were off, and the
/// header greys with a ⚠ while the frame it stands on failed.
///
/// Every route that shows a plugin's picture tells it through the run
/// ([FxPluginRun.told]) — kept or made, each time — so the frame a header
/// reads is the last word of whatever showed that frame. An effect is its
/// instance ([ResolvedLayerEffect.instance]), held weakly: an edited effect
/// is another object, and the record of the old one goes with it.
final class FxPluginOutcomes extends ChangeNotifier {
  final Expando<Set<int>> _failed = Expando('fxPluginFailedFrames');
  bool _announcing = false;
  bool _disposed = false;

  /// [effect]'s run at [frame] [failed], or drew.
  void tell(LayerEffect effect, int frame, {required bool failed}) {
    final frames = _failed[effect];
    if ((frames?.contains(frame) ?? false) == failed) {
      return;
    }
    if (failed) {
      (_failed[effect] ??= {}).add(frame);
    } else {
      frames!.remove(frame);
    }
    _announce();
  }

  /// Whether [effect]'s run at [frame] last failed.
  bool failedAt(LayerEffect effect, int frame) =>
      _failed[effect]?.contains(frame) ?? false;

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
