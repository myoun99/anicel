import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🚨THE VALUE PICKER MARKS THE CURRENT VALUE BY COLOUR.
///
/// Six flyouts used to spell this loop out, and all six marked the current
/// value `checked` — the trailing check glyph 「선택 표시는 색상만」 forbids.
/// [panelFlyoutChoices] is the one place now, so the mark is pinned here;
/// `panel_flyout_test.dart` pins what `selected` paints (accent, no glyph).
void main() {
  test('one item per value, keyed by name, the current one selected and '
      'none of them a toggle', () {
    OnionSkinMode? picked;
    final items = panelFlyoutChoices(
      values: OnionSkinMode.values,
      current: OnionSkinMode.values.last,
      keyPrefix: 'probe-',
      labelOf: (mode) => 'label ${mode.name}',
      onPicked: (mode) => picked = mode,
    ).cast<PanelFlyoutItem>();

    expect(
      [for (final item in items) item.keyValue],
      [for (final mode in OnionSkinMode.values) 'probe-${mode.name}'],
    );
    expect(
      [for (final item in items) item.label],
      [for (final mode in OnionSkinMode.values) 'label ${mode.name}'],
    );
    expect(
      [for (final item in items) item.selected],
      [
        for (final mode in OnionSkinMode.values)
          mode == OnionSkinMode.values.last,
      ],
      reason: 'the current value is the SELECTED row — colour, not a glyph',
    );
    expect(
      [for (final item in items) item.checked],
      everyElement(isNull),
      reason: '`checked` is a toggle\'s field; a value picker has none',
    );

    items.first.onSelected!();
    expect(picked, OnionSkinMode.values.first);
  });
}
