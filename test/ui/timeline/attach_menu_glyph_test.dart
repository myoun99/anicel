import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// ① (유저 확정): 「어태치 레이어 생성 항목의 화살표 아이콘이 실제 어태치
/// 아이콘과 다르다 ⇒ 통일」.
///
/// The four attach entries drew `north_east`/`south_east` — a second
/// vocabulary for attachment, so the menu that MAKES an attached row and the
/// row it makes did not look like the same idea. The rail already
/// distinguishes above from below by FLIPPING one glyph
/// ([LayerAttachArrowCell]), so the menu does the same thing rather than
/// inventing a pair.
void main() {
  Future<void> openAddLayerMenu(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-menu')),
    );
    await tester.pumpAndSettle();
  }

  PanelFlyoutItem itemNamed(WidgetTester tester, String keyValue) {
    final menuItem = tester.widget<PopupMenuItem<PanelFlyoutItem>>(
      find.byKey(ValueKey<String>(keyValue)),
    );
    return menuItem.value!;
  }

  testWidgets('every attach entry wears the rail\'s own attach glyph', (
    tester,
  ) async {
    await openAddLayerMenu(tester);

    for (final keyValue in const [
      'add-layer-attach-free-above',
      'add-layer-attach-free-below',
      'add-layer-attach-above',
      'add-layer-attach-below',
    ]) {
      expect(
        itemNamed(tester, keyValue).icon,
        Icons.subdirectory_arrow_right,
        reason: '$keyValue should speak the rail\'s vocabulary',
      );
    }
  });

  testWidgets('above is that glyph FLIPPED, exactly as the rail flips it — '
      'not a different arrow', (tester) async {
    await openAddLayerMenu(tester);

    expect(itemNamed(tester, 'add-layer-attach-free-above').iconFlipY, isTrue);
    expect(itemNamed(tester, 'add-layer-attach-above').iconFlipY, isTrue);
    expect(itemNamed(tester, 'add-layer-attach-free-below').iconFlipY, isFalse);
    expect(itemNamed(tester, 'add-layer-attach-below').iconFlipY, isFalse);
  });
}
