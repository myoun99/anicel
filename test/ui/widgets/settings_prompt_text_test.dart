// THE SETTINGS PANELS' MUTED PROMPT LINE IS ONE WIDGET: top-left, the
// small body style, the muted surface colour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/settings_prompt_text.dart';

void main() {
  testWidgets('renders the text muted, small and top-left', (tester) async {
    final theme = ThemeData();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: SizedBox(
            width: 200,
            height: 100,
            child: SettingsPromptText('Pick a guide'),
          ),
        ),
      ),
    );

    final align = tester.widget<Align>(
      find.ancestor(
        of: find.text('Pick a guide'),
        matching: find.byType(Align),
      ),
    );
    expect(align.alignment, Alignment.topLeft);

    final text = tester.widget<Text>(find.text('Pick a guide'));
    final resolved = Theme.of(tester.element(find.text('Pick a guide')));
    expect(text.style?.fontSize, resolved.textTheme.bodySmall?.fontSize);
    expect(text.style?.color, resolved.colorScheme.onSurfaceVariant);
  });
}
