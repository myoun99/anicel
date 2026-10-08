import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/superellipse_clip.dart';

/// One floating control surface on the canvas: opaque, superellipse,
/// ringed in the backdrop — the view pill, the page strip, the panbars,
/// the transport, and the pill a canvas verb wears (`CanvasTargetPill`).
///
/// ↩️It was the canvas panel's own (`_capsule`) until the transform box's
/// 확정/취소 had to wear it too (I-79, 유저 2026-10-06: 「캔버스 내부 알약은
/// 다른곳에서도 쓰니 공용화. 예를들어 변형도구 체크버튼도 이 공용화된거
/// 쓰도록」).
///
/// ↩️Opaque on a docked panel too. Its capsules were see-through for a
/// day (F-209, 유저 2026-09-28), and the user took that back (09-30:
/// 「알약 반투명하지말자. 원복. 대신 판정을 알약까지 포함해서 판정」),
/// leaving a see-through pill to us only if it costs nothing
/// (「굽기가능하거나 성능변화없으면」). It does not: the pill faded WHOLE is
/// a group opacity, one more offscreen pass on every frame the canvas
/// under it moves (Impeller keeps no raster cache) — and with the framing
/// out from under the pill (`pillBandIn`) nothing framed lies under it.
///
/// The ring is not decoration. What lies beside a capsule is the
/// PASTEBOARD, a colour the user chooses, so no fill of ours can be
/// relied on to contrast with it — the same reason the panbar lane has
/// carried a hairline since the palette collapsed to three fills.
class CanvasCapsule extends StatelessWidget {
  const CanvasCapsule({
    super.key,
    required this.keyValue,
    required this.child,
    this.width,
    this.height,
  });

  /// A pill of bar buttons (`AppIconButtonSize.bar`): its height, and the
  /// room its row leaves at each end — the view pill's, and the one a
  /// canvas verb wears, so the two are one thing to the eye.
  static const double barPillHeight = 28;
  static const double barPillEnd = 4;

  final String keyValue;
  final Widget child;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    // The corner follows the SHORT axis, the way every control's does. A
    // capsule with neither axis stated would ask for an infinite radius, so
    // the fallback is the app's smallest corner rather than a crash.
    final short = math.min(width ?? double.infinity, height ?? double.infinity);
    final shape = short.isFinite
        ? AppShapes.control(short)
        : AppShapes.container(AppShapes.wellRadius);
    return DecoratedBox(
      key: ValueKey<String>(keyValue),
      decoration: ShapeDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: shape.copyWith(
          side: const BorderSide(color: AppColors.backdrop),
        ),
      ),
      child: SuperellipseClip(
        shape: shape,
        child: SizedBox(width: width, height: height, child: child),
      ),
    );
  }
}
