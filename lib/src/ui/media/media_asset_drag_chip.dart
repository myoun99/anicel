import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../widgets/drag_chip.dart';
import 'media_asset_kind_icon.dart';

/// The chip a dragged pool file hangs at the pointer: the file's kind and
/// name — and, over a place the file cannot land, the ban (유저 2026-09-11,
/// 미디어 배치 라운드: 「불가능 = 칩의 금지 표시(커서는 그대로)」, the
/// mockup's drag chip). The chip is every drag's ([DragChip], I-39); what is
/// the pool's own is the answer it wears.
///
/// [verdict] is the entrance's answer ([MediaDropVerdictScope]); anything
/// but `true` rings the chip in danger and adds the ban after the name —
/// `null`, over no entrance at all, as much as `false`: let go there, the
/// file does nothing either way.
///
/// 🗣️F-372 (유저 2026-10-17): 「빈공간에 끌면 금지마크도 안떠서 가능한건가
/// 싶은데 … 드롭해도 아무 반응없음 … 금지마크가 제대로 금지인상황에 안뜬다
/// 는 사건이 있었으니 그 부분도 확인」. ↩️`null` was the plain chip — the
/// answer was only ever said when an entrance said no, so a place with no
/// entrance looked like a yes.
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
            builder: (context, answer, _) => _chip(refused: answer != true),
          );
  }

  Widget _chip({required bool refused}) => DragChip(
    items: [(icon: mediaAssetKindIcon(kind), label: name)],
    refused: refused,
  );
}
