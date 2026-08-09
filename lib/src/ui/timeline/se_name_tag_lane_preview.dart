import 'package:flutter/material.dart';

import '../../models/se_name_tag.dart';

/// The name tag's live PREVIEW on its group header (R5 #7): the box, and
/// the dialogue beside it, in miniature.
///
/// It shows the LOOK, never the content — the strings are fixed (`名前` /
/// `セリフ`, localized), so the preview says the same thing wherever the
/// playhead parks and never asks what a block happens to contain. The user
/// settled that: "프리뷰는 그냥 어떤식으로 될지 확인만 하는거니까".
class SeNameTagLanePreview extends StatelessWidget {
  const SeNameTagLanePreview({
    super.key,
    required this.name,
    required this.line,
    this.tag = const SeNameTag(),
  });

  final String name;

  /// The dialogue sample; empty draws none, which is what the Show
  /// Dialogue member turning off looks like.
  final String line;

  /// The RESOLVED tag whose look is being previewed.
  final SeNameTag tag;

  @override
  Widget build(BuildContext context) {
    final box = tag.style.backgroundColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // The box keeps its shape at every size: the rail row is 24px tall
        // and the tag's real fontSize is 34, so this is a SILHOUETTE, not a
        // scaled render — matching the on-canvas metrics here would just
        // clip.
        DecoratedBox(
          decoration: BoxDecoration(
            color: box == null ? null : Color(box),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: tag.style.bold ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: tag.style.letterSpacing == 0
                    ? null
                    : tag.style.letterSpacing / 4,
                color: Color(tag.style.color),
              ),
            ),
          ),
        ),
        if (line.isNotEmpty) ...[
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: tag.lineStyle.bold
                    ? FontWeight.w700
                    : FontWeight.w400,
                letterSpacing: tag.lineStyle.letterSpacing == 0
                    ? null
                    : tag.lineStyle.letterSpacing / 4,
                color: Color(tag.lineStyle.color),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
