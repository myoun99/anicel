import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../theme/app_theme.dart';
import 'media_asset_kind_icon.dart';

/// The chip a dragged pool file hangs at the pointer: the file's kind and
/// name — and, over a place the file cannot land, the ban (유저 2026-09-11,
/// 미디어 배치 라운드: 「불가능 = 칩의 금지 표시(커서는 그대로)」, the
/// mockup's drag chip).
///
/// [verdict] is the entrance's answer ([MediaDropVerdictScope]); `false`
/// rings the chip in danger and adds the ban after the name. `true` and
/// `null` are the same chip — the answer is only ever said when it is no.
class MediaAssetDragChip extends StatelessWidget {
  const MediaAssetDragChip({
    super.key,
    required this.kind,
    required this.name,
    this.verdict,
  });

  final MediaAssetKind kind;
  final String name;
  final ValueListenable<bool?>? verdict;

  @override
  Widget build(BuildContext context) {
    final channel = verdict;
    return channel == null
        ? _chip(refused: false)
        : ValueListenableBuilder<bool?>(
            valueListenable: channel,
            builder: (context, answer, _) => _chip(refused: answer == false),
          );
  }

  Widget _chip({required bool refused}) => Material(
    key: const ValueKey<String>('media-drag-chip'),
    elevation: 4,
    color: AppColors.surfaceHigh,
    shape: AppShapes.container(
      AppShapes.wellRadius,
      side: BorderSide(
        color: refused ? AppColors.danger : AppColors.hairlineStrong,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mediaAssetKindIcon(kind), size: 14),
          const SizedBox(width: 5),
          Text(name, style: const TextStyle(fontSize: 12)),
          if (refused) ...[
            const SizedBox(width: 2),
            Container(
              key: const ValueKey<String>('media-drag-chip-ban'),
              width: 16,
              height: 16,
              decoration: const ShapeDecoration(
                color: AppColors.danger,
                shape: CircleBorder(),
              ),
              child: const Icon(Icons.block, size: 12, color: Color(0xFF1B0F0F)),
            ),
          ],
        ],
      ),
    ),
  );
}
