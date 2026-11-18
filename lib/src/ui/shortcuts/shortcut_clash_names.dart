import 'package:flutter/material.dart';

import '../input/control_press_claim.dart' show ControlPressClaim, silentPress;
import '../text/app_strings.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/ellipsis_text.dart';
import '../widgets/panel_flyout.dart';
import 'editor_shortcut_bindings.dart';
import 'editor_shortcut_scope.dart';
import 'shortcut_activator_codec.dart';

/// Who holds the keys that clash, beside the shortcut window's warning —
/// 「올가미 채우기 (Y) : 펜 (Y)」, each name a button that leaves the key on it
/// alone ([EditorShortcutBindings.giveKeyTo]).
///
/// 🗣️I-158 (유저 2026-11-04): 「키 충돌하면 같은키를 쓰는 동작 있습니다 옆에
/// 대상 텍스트로 보여주게. 예를들어 올가미 채우기(Y) : 펜(Y) 이런식. 여러개
/// 충돌하면 해당 영역 버튼눌러서 리스트팝오버로 여러개 보여주게. 그리고
/// 추가로 펜(Y)이런식으로 이 텍스트를 버튼으로 만들어서, 이걸로 할당하는
/// 기능. 호버하면 설명 말한대로 툴팁으로 보여주고」.
/// ⚠️MY READINGS: 「여러개」 is more than one pair — two keys, or one key on
/// three actions — and the list's button is named by the keys that clash.
class ShortcutClashNames extends StatelessWidget {
  const ShortcutClashNames({super.key, required this.bindings});

  final EditorShortcutBindings bindings;

  @override
  Widget build(BuildContext context) {
    final clashes = bindings.keyClashes;
    return switch (clashes) {
      [] => const SizedBox.shrink(),
      [final clash] when clash.holders.length == 2 => _ClashLine(
        bindings: bindings,
        clash: clash,
      ),
      _ => PanelFlyoutButton(
        key: const ValueKey<String>('shortcut-clash-list'),
        label: [
          for (final clash in clashes)
            _keyLabel(bindings, clash.holders.first, clash.key),
        ].join(', '),
        labelColor: Theme.of(context).colorScheme.error,
        entriesBuilder: () => [
          for (final clash in clashes)
            PanelFlyoutRow(
              keyValue: 'shortcut-clash-${activatorKey(clash.key)}',
              listenable: bindings,
              builder: (_) => _ClashLine(bindings: bindings, clash: clash),
            ),
        ],
      ),
    };
  }
}

/// [key] as [actionId]'s row shows it.
String _keyLabel(
  EditorShortcutBindings bindings,
  String actionId,
  SingleActivator key,
) => singleActivatorLabel(bindings.shownActivatorFor(actionId, key));

/// One clash's holders, a button each, the user's 「 : 」 between them.
class _ClashLine extends StatelessWidget {
  const _ClashLine({required this.bindings, required this.clash});

  final EditorShortcutBindings bindings;
  final KeyClash clash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = activatorKey(clash.key);
    // Read live: a row of the list stays up after one of its names is
    // pressed, and shows where the key went.
    final holding = {
      for (final id in clash.holders)
        if (bindings.holds(id, clash.key)) id,
    };
    Color inkOf(String id) => holding.length > 1
        ? theme.colorScheme.error
        : holding.contains(id)
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodySmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, id) in clash.holders.indexed) ...[
          if (index > 0) Text(' : ', style: style),
          Flexible(
            child: _KeepButton(
              keyValue: 'shortcut-clash-keep-$id-$at',
              label: labelWithKeys(
                _nameOf(id),
                _keyLabel(bindings, id, clash.key),
              ),
              tooltip: AppText.strings.shortcutClashKeep(
                _keyLabel(bindings, id, clash.key),
                _nameOf(id),
                [
                  for (final other in clash.holders)
                    if (other != id) _nameOf(other),
                ].join(', '),
              ),
              color: inkOf(id),
              style: style,
              onPressed: () => bindings.giveKeyTo(id, clash.key),
            ),
          ),
        ],
      ],
    );
  }

  String _nameOf(String actionId) => switch (bindings.definitionFor(actionId)) {
    final definition? => actionLabelOf(definition),
    null => actionId,
  };
}

/// A name in the clash, pressed to keep the key on it alone.
class _KeepButton extends StatelessWidget {
  const _KeepButton({
    required this.keyValue,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.style,
    required this.onPressed,
  });

  final String keyValue;
  final String label;
  final String tooltip;
  final Color color;
  final TextStyle? style;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: tooltip,
    child: ControlPressClaim(
      onPressed: onPressed,
      child: TextButton(
        key: ValueKey<String>(keyValue),
        onPressed: silentPress(onPressed),
        style: TextButton.styleFrom(
          foregroundColor: color,
          textStyle: style,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: EllipsisText(label, maxLines: 1),
      ),
    ),
  );
}
