import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🚨THE VALUE PICKER MARKS THE CURRENT VALUE BY COLOUR.
///
/// Six flyouts used to spell this loop out, and all six marked the current
/// value `checked` — the trailing check glyph 「선택 표시는 색상만」 forbids.
/// [PanelFlyoutValueChoices.asFlyoutValueChoices] is the one place now (the
/// enum spelling rides on it), so the mark is pinned here;
/// `panel_flyout_test.dart` pins what `selected` paints (accent, no glyph).
void main() {
  test('one item per value, keyed by name, the current one selected and '
      'none of them a toggle', () {
    OnionSkinMode? picked;
    final items = OnionSkinMode.values.asFlyoutChoices(
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

  // F-230: a device's name, a cut, an instruction — values that are not an
  // enum's are picked from the same list.
  test('any value picks the same way: its own key, an icon when it has one, '
      'a null among them is a value like the rest', () {
    String? picked = 'unpicked';
    List<PanelFlyoutItem> choices(String? current) =>
        <String?>[null, 'a', 'b']
            .asFlyoutValueChoices(
              current: current,
              choiceOf: (value) => PanelFlyoutChoice(
                key: 'probe-${value ?? 'none'}',
                label: value ?? 'None',
                icon: value == 'b' ? Icons.star : null,
              ),
              onPicked: (value) => picked = value,
            )
            .cast<PanelFlyoutItem>();

    final items = choices(null);
    expect([for (final item in items) item.keyValue], [
      'probe-none',
      'probe-a',
      'probe-b',
    ]);
    expect([for (final item in items) item.label], ['None', 'a', 'b']);
    expect([for (final item in items) item.icon], [null, null, Icons.star]);
    expect(
      [for (final item in items) item.selected],
      [true, false, false],
      reason: 'null is the current value here, and it is in the list',
    );
    expect(
      [for (final item in choices('gone')) item.selected],
      everyElement(isFalse),
      reason: 'a current value the list does not hold marks no row',
    );

    items.first.onSelected!();
    expect(picked, isNull);
    items.last.onSelected!();
    expect(picked, 'b');
  });
}
