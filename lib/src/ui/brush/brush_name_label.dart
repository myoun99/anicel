import 'package:flutter/material.dart';

/// A brush preset's name as its row writes it — ONE label for a row with a
/// stroke preview and a row without one.
///
/// 🚨★★★F-82 (유저 2026-09-16): 「그냥 **이름 공간 따로 할당**해서 두는게
/// 좋아보임 … 아래를 브러시 이름으로 위아래 영역 나눠서 두도록. 브러시 이름 …
/// 글자크기는 지금보다 **더 작아도될듯**. 이렇게 하고 **글자 뒤에 바탕넣은건
/// 삭제**」.
///
/// ↩️The history, so none of it comes back as a "fix": until 09-08 the name
/// sat `centerRight` on a 78%-alpha plate of the row's own colour; 09-08 took
/// the plate away so the name rode the stroke (「스트로크랑 겹치든 말든」);
/// 09-10 picked ONE ink for the whole name from the mean ink under it; H38
/// (09-11) fixed that ink and put the name dead centre over the stroke
/// (「중앙아래가 아니라 완전중앙」); 09-11 19:28 brought the PLATE back because
/// none of it had made the name readable.
/// ⛔**Every one of those answered 「스트로크 위에서 안 읽힌다」, and the name
/// is not over the stroke any more** — F-82 gave it a band of its own, so
/// there is no stroke behind it to be read against and the plate goes.
///
/// ⛔What SURVIVES is the unification 유저 asked for in the same breath as the
/// plate: 「스트로크 프리뷰 없앨때의 브러시 이름이랑 있을떄의 이름이랑 텍스트
/// ui가 다른데 다르지않도록 통일」. One widget, one size, one ink pair,
/// whichever view the row is drawn in.
class BrushNameLabel extends StatelessWidget {
  const BrushNameLabel({super.key, required this.name, required this.selected});

  final String name;

  /// The row wears the highlight: the name takes the row's selected ink, the
  /// pair its own ground always used.
  final bool selected;

  /// ⚠️12 until F-82 — 「글자크기는 지금보다 더 작아도될듯」.
  static const double fontSize = 10;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Align(
        // ⛔LEFT, which is where the bare-name row has always written it.
        // Centring it under the stroke would read better in that one view
        // and would be a placement nobody asked for in the other — 「편의
        // 규칙을 발명하지 말 것」. One band, one alignment.
        alignment: Alignment.centerLeft,
        child: Text(
          name,
          maxLines: 1,
          textAlign: TextAlign.left,
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
