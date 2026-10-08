import 'package:flutter/material.dart';

/// What a surface showing a document's pages stands at its middle while a
/// page it shows has no picture yet — the file still opening, or the page
/// not drawn yet.
///
/// 🗣️F-315 (유저 2026-10-08): 「준비안된상태면 지금 이전그림 보여주는데
/// 그게아니라 해당 패널의 중앙에? 중앙이든 뭐든 로딩창같은거 해당패널중앙에
/// 위젯 띄우도록. 지금 특히 셀 출력에서 다음버튼눌럿는데 이전그림 보인다던가
/// 콘티용지 출력탭에서 준비안된장이 그냥 흰색장인채로 보인다던가」 — and of
/// the three surfaces it names, 「다 똑같은데」: ONE widget for the viewer, the
/// export window's preview and the import window's, as their pages are one
/// cache ([PageRasters]).
///
/// The app's spinner, as its progress window has it, and no words. It
/// takes no press — what the hand does goes to the page under it — and
/// turns on a layer of its own, so the page beside it is not painted again
/// for every turn.
class ViewerPageLoading extends StatelessWidget {
  const ViewerPageLoading({super.key});

  static const double _box = 24;

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: Center(
      child: RepaintBoundary(
        child: SizedBox(
          width: _box,
          height: _box,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}
