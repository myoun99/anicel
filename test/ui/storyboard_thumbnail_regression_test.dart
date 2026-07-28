import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'storyboard_cut_block_probe.dart';

/// R4-⑩ regression probe: storyboard cut blocks must show their rendered
/// thumbnail (the real render pipeline, not a fake) — the painted block's
/// picture replaces the pending placeholder once the async render lands.
void main() {
  testWidgets('storyboard cut blocks show a rendered thumbnail end-to-end', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: createDefaultProject())),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
      );
      await tester.pumpAndSettle();

      // Let the async thumbnail render land (real ui.Image work needs
      // runAsync), then rebuild.
      for (var attempt = 0; attempt < 20; attempt += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (cutBlocks(tester).first.thumbnails.first != null) {
          break;
        }
      }

      expect(
        cutBlocks(tester).first.thumbnails.first,
        isNotNull,
        reason: 'the placeholder must give way to the rendered thumbnail',
      );
    });
  });
}
