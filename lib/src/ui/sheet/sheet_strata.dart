import 'package:flutter/widgets.dart';

import '../../models/sheet_paint_layer.dart';
import '../widgets/static_raster.dart';

export '../../models/sheet_paint_layer.dart' show SheetStratum;

/// A sheet's strata, each baked on its own ([StaticRaster]) and re-recorded
/// only when what IT prints changes — the one shell the three canvas-base
/// sheets print through (유저 2026-09-25: 「그림 수정하거나 텍스트 바뀌거나
/// 하는데 용지 리빌드하면 너무 비효율적이잖아」 · 「캔버스베이스패널은 다
/// 통일해줘」).
///
/// Each painter is the sheet's own, drawing its stratum's layers
/// ([SheetStratum.layers]) and comparing only what those layers read. A
/// stratum the sheet does not have is absent from [painters].
///
/// ⛔One bake for the whole page re-recorded the form for a typed letter,
/// a landed thumbnail and every stroke (the conte and the envelope); two
/// bakes whose form compared the whole document did the same for letters
/// (the timesheet).
class SheetStrata extends StatelessWidget {
  const SheetStrata({
    super.key,
    required this.sheet,
    required this.painters,
    this.liveNow,
    this.liveChanges,
  });

  /// The sheet's name in the strata's keys and bake labels:
  /// `<sheet>-<stratum>` and `<sheet>-<stratum>-paint`.
  final String sheet;

  /// Each stratum's painter.
  final Map<SheetStratum, CustomPainter> painters;

  /// Whether [stratum] changes on every step right now — the ink under a
  /// pen that is down, the values under a drag they follow — so its bake
  /// stands down meanwhile: a capture per step costs a full paint and a
  /// full copy, and saves nothing. Read again when [liveChanges] notifies.
  final bool Function(SheetStratum stratum)? liveNow;
  final Listenable? liveChanges;

  @override
  Widget build(BuildContext context) {
    final changes = liveChanges;
    if (changes == null) {
      return _strata();
    }
    return ListenableBuilder(
      listenable: changes,
      builder: (context, _) => _strata(),
    );
  }

  Widget _strata() {
    final live = liveNow;
    return Stack(
      children: [
        for (final stratum in SheetStratum.values)
          if (painters[stratum] case final painter?)
            Positioned.fill(
              child: StaticRaster(
                debugLabel: '$sheet-${stratum.name}',
                enabled: !(live?.call(stratum) ?? false),
                child: CustomPaint(
                  key: ValueKey<String>('$sheet-${stratum.name}-paint'),
                  painter: painter,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
      ],
    );
  }
}
