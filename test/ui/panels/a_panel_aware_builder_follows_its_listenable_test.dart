import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/panels/panel_visibility_scope.dart';

/// A [PanelAwareListenableBuilder] rebuilt around ANOTHER listenable hears
/// that one — the workspace hands its panel hosts a fresh
/// `Listenable.merge` on every build, and the builder's gate is re-pointed
/// rather than kept on the first.
void main() {
  testWidgets('a panel-aware builder handed a new listenable hears it, and '
      'not the one it had', (tester) async {
    final first = ValueNotifier(0);
    final second = ValueNotifier(0);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var builds = 0;
    Widget host(Listenable listenable) => Directionality(
      textDirection: TextDirection.ltr,
      child: PanelAwareListenableBuilder(
        listenable: listenable,
        builder: (context) {
          builds += 1;
          return const SizedBox();
        },
      ),
    );

    await tester.pumpWidget(host(first));
    await tester.pumpWidget(host(second));
    builds = 0;

    first.value += 1;
    await tester.pump();
    expect(builds, 0, reason: 'the old listenable is no longer heard');

    second.value += 1;
    await tester.pump();
    expect(builds, 1, reason: 'the new one is');
  });
}
