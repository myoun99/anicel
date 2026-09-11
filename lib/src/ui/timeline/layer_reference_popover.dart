import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../editor_session_manager.dart';
import '../input/control_press_claim.dart';
import '../media/media_asset_pool_state.dart';
import '../text/app_strings.dart';
import '../widgets/anchored_popup.dart';
import 'rasterize_reference_rows.dart';

/// The reference button's popover (유저 2026-09-11, 미디어 배치 라운드 3~6):
/// the button does not bake — it opens this, and the bake is the one button
/// inside it, 「래스터라이즈 · N장」.
///
/// The first line names the file beside its POOL state (`bg_street.png ·
/// 품음`), because 「참조」 means two things and the popover says which one
/// the file is (round 5). When the press acts on several rows it says so
/// instead — the mockup's 「선택한 레이어」.
const double layerReferencePopoverWidth = 236;
const double layerReferencePopoverHeight = 72;

Future<void> showLayerReferencePopover(
  BuildContext anchorContext, {
  required EditorSessionManager session,
  required LayerId layerId,
}) {
  return showAnchoredPopup<void>(
    anchorContext,
    label: 'layer-reference',
    width: layerReferencePopoverWidth,
    height: layerReferencePopoverHeight,
    builder: (context, close) => _LayerReferencePopover(
      session: session,
      layerId: layerId,
      close: close,
    ),
  );
}

/// The REFERENCE rows a press on [pressedId] bakes, in stack order: the rows
/// the press acts on (`RowSelection.rowsActedOnBy` — 「선택 안에서 누르면
/// 선택 전체, 밖에서 누르면 그것만」) that still point at a file.
List<Layer> layerReferenceTargets(
  EditorSessionManager session,
  LayerId pressedId,
) {
  final ids = session.rowSelectionVerbs.rowsActedOnBy(pressedId);
  return [
    for (final layer in session.layers)
      if (ids.contains(layer.id) && layer.mediaReference != null) layer,
  ];
}

class _LayerReferencePopover extends StatelessWidget {
  const _LayerReferencePopover({
    required this.session,
    required this.layerId,
    required this.close,
  });

  final EditorSessionManager session;
  final LayerId layerId;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    // Listening keeps the window honest while it is open: an undo, or the
    // menu's rasterize, can change what it would bake.
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final targets = layerReferenceTargets(session, layerId);
        if (targets.isEmpty) {
          return const SizedBox.shrink();
        }
        return _body(context, targets);
      },
    );
  }

  Widget _body(BuildContext context, List<Layer> targets) {
    final strings = AppText.strings;
    // What the bake would LEAVE: a still's cels are already its own, a
    // movie's are one per position of its block ([rasterizeCelCount]).
    final cels = targets.fold<int>(
      0,
      (sum, layer) => sum + rasterizeCelCount(layer),
    );
    // ⛔No `Material` of its own — the anchored popup carries the window.
    return Padding(
      key: const ValueKey<String>('layer-reference-popover'),
      padding: AnchoredPopupText.bodyPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sourceLine(targets),
            key: const ValueKey<String>('layer-reference-source'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AnchoredPopupText.caption,
          ),
          const SizedBox(height: 6),
          _RasterizeButton(
            label:
                '${strings.layerRasterizeLabel} · '
                '${strings.exCelCount(cels)}',
            onPressed: () {
              close();
              // A movie is decoded frame by frame behind the wait window;
              // rows whose pixels are already cels land at once.
              unawaited(rasterizeReferenceRows(context, session, targets));
            },
          ),
        ],
      ),
    );
  }

  String _sourceLine(List<Layer> targets) {
    if (targets.length > 1) {
      return AppText.strings.tlSelectedLayers;
    }
    final layer = targets.single;
    final path = layer.mediaReference!.assetPath;
    final asset = session.mediaPool.mediaAssets
        .where((candidate) => candidate.path == path)
        .firstOrNull;
    return asset == null
        ? layer.name
        : '${asset.name} · ${mediaAssetPoolState(asset)}';
  }
}

/// The popover's one action, as the mockup drew it: the window's accent
/// fill. Pressed inside and released inside — a popover is not a rail row.
class _RasterizeButton extends StatelessWidget {
  const _RasterizeButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ControlPressClaim(
      onPressed: onPressed,
      child: FilledButton(
        key: const ValueKey<String>('layer-reference-rasterize'),
        onPressed: silentPress(onPressed),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
