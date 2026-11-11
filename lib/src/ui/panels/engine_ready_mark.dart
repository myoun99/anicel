import 'package:flutter/widgets.dart';

import '../../native/app_kernels_ahead.dart';
import '../media/viewer_page_loading.dart';

/// The app's ring at the middle of the place it stands in, while the app
/// gets its engine ready ([appEngineGetsReady]) — nothing once it is.
///
/// 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「애초에 타임라인같은거도
/// 포함해서 고리띄우고 모든 조작 막음」 — every panel's place stands one: a
/// docked panel's by the shell every dock is (`EditorPanelTabs`), the
/// floor's by the canvas panel lying there, at the middle of what the docks
/// leave of it to be seen (`FrameWaitMark`).
///
/// 🗣️관제 2026-11-11 08:25: 「고리는 지금 캔버스 자리의 「준비 중」 고리와 같은
/// 것을 같은 법으로 — 새 고리를 만들지 않는다. 자리는 늘 있는 패널 자리 안」
/// — the one ring ([ViewerPageLoading]), mounted only while the app is
/// held, so nothing of it turns once a hand is let at the app.
class EngineReadyMark extends StatelessWidget {
  const EngineReadyMark({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: appEngineGetsReady,
    builder: (context, getsReady, _) =>
        getsReady ? const ViewerPageLoading() : const SizedBox.shrink(),
  );
}
