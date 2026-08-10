import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// THE app's grip band: a thin rule along an edge saying "there is a handle
/// here", plus the one colour ladder every grip climbs.
///
/// It was born on the panel tab (R2 #9 / R3 #9), where a band's THICKNESS
/// says which thing it is saying — 2px for a state you read, 6px for a
/// handle you can reach — and its COLOUR says how close your hand is. Both
/// halves are here rather than in that widget because a second surface now
/// wears the same band: the command pill's `＋`, whose top edge opens the
/// list of kinds ([StrapIconButton]).
///
/// ★The TARGET is a constant [hitExtent] and the band inside it grows toward
/// the edge, so a pointer resting on a grip never finds the thing it is over
/// moving out from under it.
abstract final class GripBand {
  /// The lift/menu zone's extent along the edge. The band is thinner than
  /// this; the target may not move because the band grew.
  static const double hitExtent = 8;

  /// What the band is when it is saying a STATE, and when it is offering a
  /// HANDLE.
  static const double rest = 2;
  static const double reach = 6;

  /// Three rungs, on the three things a hand does: something is NEARBY
  /// (기본색) → the band itself is under the pointer (호버색) → it is being
  /// used (클릭색).
  ///
  /// [idle] is what the band is when nothing is near. The tab's is
  /// transparent — a strip of them would be noise — and the pill's `＋` is
  /// [AppColors.hairlineStrong], because a menu nobody can see is a menu
  /// nobody opens, and a tablet has no pointer to hover with.
  static Color ink({
    required bool nearby,
    required bool hovered,
    required bool active,
    Color idle = Colors.transparent,
  }) {
    if (active) {
      return AppColors.accent;
    }
    if (hovered) {
      return AppColors.gripHover;
    }
    return nearby ? AppColors.hairlineStrong : idle;
  }
}
