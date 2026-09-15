import 'package:flutter/material.dart';

import '../theme/app_theme.dart' show AppShapes;

/// A brush preset's name as its row writes it — ONE label for a row with a
/// stroke preview and a row without one.
///
/// 🚨F-82 (유저 2026-09-11 19:28): 「스트로크 프리뷰에 있는 브러시 이름, 지금도
/// 보기힘드니까 그냥 예전처럼 텍스트 배경색으로 뭔가 두고, 그 위에 고정색 텍스트
/// 두도록. 그리고 스트로크 프리뷰 없앨때의 브러시 이름이랑 있을떄의 이름이랑
/// 텍스트 ui가 다른데 다르지않도록 통일」.
///
/// ↩️The history, so none of it comes back as a "fix": until 09-08 the name
/// sat `centerRight` on a 78%-alpha plate of the row's own colour; 09-08 took
/// the plate away so the name rode the stroke (「스트로크랑 겹치든 말든」);
/// 09-10 picked ONE ink for the whole name from the mean ink under it; H38
/// (the morning of 09-11) fixed the ink black and put the name dead centre
/// (「중앙아래가 아니라 완전중앙」 — that placement stands); H38 again wrote
/// it in the slider's column-by-column ink (「슬라이더 공용 텍스트ui 그대로
/// 재사용」). None of those made it readable over a stroke, and F-82 brings
/// the plate back — the same plate — with the row's fixed name colour on it.
///
/// ⚠️The row with no preview wrote its name at 12, the preview at 11; both
/// write 12 now, the larger of the two, because the complaint was reading it.
class BrushNameLabel extends StatelessWidget {
  const BrushNameLabel({super.key, required this.name, required this.selected});

  final String name;

  /// The row wears the highlight: plate and text take the row's selected
  /// colours, the same pair its own ground and name always used.
  final bool selected;

  static const double fontSize = 12;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: (selected ? scheme.surfaceContainerHigh : scheme.surface)
            .withValues(alpha: 0.78),
        shape: AppShapes.container(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          name,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: fontSize,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
