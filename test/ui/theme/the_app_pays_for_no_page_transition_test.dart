import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🚨★★★**THE EDITOR SITS UNDER NO PAGE TRANSITION.**
///
/// `MaterialApp(home:)` puts the whole editor inside a `PageRoute`, and the
/// route asks the theme how to animate itself in. Whatever that builds
/// STAYS in the tree when the animation is over, and Flutter's defaults are
/// not free at rest:
///
///  * android — the tablet target — builds four `FadeTransition`s, and a
///    `FadeTransition` keeps a full-window `OpacityLayer` at ANY alpha
///    above zero (`RenderAnimatedOpacityMixin.isRepaintBoundary`), 255
///    included. Four offscreens over the whole window, every frame.
///  * windows/linux build `SnapshotWidget`s, one more boundary in the
///    chain.
///
/// 🔬F-130 layer census, one cursor move with nothing else on screen
/// (2026-09-22): **13 layers re-added on android · 9 on windows → 9 on
/// both.** Nothing else moved: rebuilt 0, painted 0, pictures re-recorded 0
/// in every reading.
///
/// ⛔Nothing is lost. `Navigator.push`, `MaterialPageRoute` and
/// `PageRouteBuilder` appear nowhere in `lib/` — the editor is the one
/// route there is, so the only transition ever built is the one nobody
/// sees, on the frame the app starts. Dialogs are `PopupRoute`s and keep
/// their own fades.
void main() {
  testWidgets('🚨every platform gets the child back, unwrapped', (
    tester,
  ) async {
    final builders = buildAppTheme().pageTransitionsTheme.builders;
    expect(
      builders.keys.toSet(),
      TargetPlatform.values.toSet(),
      reason: 'a platform with no entry falls through to Flutter\'s default, '
          'which is exactly the thing being refused',
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final context = tester.element(find.byType(SizedBox));
    final route = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );
    const child = SizedBox.shrink();
    for (final platform in TargetPlatform.values) {
      expect(
        builders[platform]!.buildTransitions<void>(
          route,
          context,
          kAlwaysCompleteAnimation,
          kAlwaysDismissedAnimation,
          child,
        ),
        same(child),
        reason: '$platform wraps the editor in something',
      );
    }
  });

  for (final platform in TargetPlatform.values) {
    testWidgets('⛔nothing of the route\'s own stands over the app on '
        '${platform.name}', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const SizedBox.expand(key: ValueKey<String>('the-app')),
        ),
      );
      await tester.pumpAndSettle();

      final app = find.byKey(const ValueKey<String>('the-app'));
      expect(app, findsOneWidget, reason: 'fixture');
      for (final wrapper in <Type>[FadeTransition, SnapshotWidget]) {
        expect(
          find.ancestor(of: app, matching: find.byType(wrapper)),
          findsNothing,
          reason: 'a $wrapper over the whole app is a full-window layer the '
              'engine composites on every frame, for an animation that '
              'finished on the first one',
        );
      }
      // ⚠️In the body: the harness checks the foundation debug variables
      // between the body and the tear-downs.
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
