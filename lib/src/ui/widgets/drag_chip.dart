import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One thing a drag carries, as its chip names it: what kind of thing, and
/// what it is called.
typedef DragChipItem = ({IconData icon, String label});

/// 🚨★★★THE CHIP A DRAG HANGS AT THE POINTER — one look for every drag that
/// does not show what it carries live (I-39).
///
/// 유저 (I-39, 2026-09-17): 「무언가를 드래그할때 커서에 생기는 그립ui,
/// 공용화가 안되있는거같음. 패널탭띠 움직여서 패널 위치 바꿀때 쓰는 패널띠
/// 드래그랑 풀에서 드래그하는거랑 ui가 미묘한게 다른게 보여서 … 이 그립ui를
/// 다른 드래그에서도 재사용할것임. 우선 레이어 선택범위로 선택/드래그할때
/// 사용. 프레임블록은 애초에 라이브로 보여주니 필요없음. 라이브로
/// 안보여주는것만 적용. 그리고 레이어는 여러개 선택해서 이동하기도하니
/// 그립ui 여러개 대응하도록 개편」.
///
/// ↩️Two copies came first — the panel tab's feedback and the pool's chip,
/// one thing (a kind and a name on a lifted well) written twice, drifted in
/// the fill, the edge, the padding, the glyph colours, the gap, and where
/// each hung off the pointer (the tab's sat centred on it). The pool's is
/// the one the user approved as a mockup (미디어 배치 라운드, 2026-09-11), so
/// its look and its place are the ones kept.
///
/// [items] is everything the drag carries — one chip each, stacked, so four
/// layers moving show four names rather than one standing in for them.
/// [refused] is an entrance's no (「불가능 = 칩의 금지 표시(커서는 그대로)」):
/// the edge turns danger and the ban follows the last name.
///
/// ⚠️Its TOP-LEFT is the pointer. A `Draggable` gets that from
/// `pointerDragAnchorStrategy` — which the drop targets depend on anyway
/// (`MediaAssetDropTarget` says why) — and a drag that is not a `Draggable`
/// places it there itself (`DragChipOverlay`).
class DragChip extends StatelessWidget {
  const DragChip({super.key, required this.items, this.refused = false});

  final List<DragChipItem> items;
  final bool refused;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey<String>('drag-chips'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 2,
    children: [
      for (final (index, item) in items.indexed)
        _chip(
          item,
          key: ValueKey<String>('drag-chip-$index'),
          banned: refused && index == items.length - 1,
        ),
    ],
  );

  Widget _chip(DragChipItem item, {required Key key, required bool banned}) =>
      Material(
    key: key,
    elevation: 4,
    // The fill a switched-on tab wears: a drag avatar is the one surface the
    // pointer is literally carrying, and on a dark UI its drop shadow is
    // nearly nothing, so the fill has to do the lifting.
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
          Icon(item.icon, size: 14, color: AppColors.text),
          const SizedBox(width: 5),
          Text(
            item.label,
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
          if (banned) ...[
            const SizedBox(width: 2),
            Container(
              key: const ValueKey<String>('drag-chip-ban'),
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
