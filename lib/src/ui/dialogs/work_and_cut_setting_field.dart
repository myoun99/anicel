import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/ellipsis_text.dart';
import '../widgets/panel_flyout.dart';

/// A format window's setting the whole work has and a cut may say otherwise
/// of: [work], and under it the cut's own beside the words that say which
/// cuts — the format's (null) or one of its own, the one picked lit.
///
/// 🗣️I-82 (유저 2026-10-31): 「카메라 움직임항목에서 전체 설정이랑 컷 설정
/// 두고, 컷 설정은 현재컷(컷이름) 이런식으로 텍스트 보여주고 해당 항목안에
/// 버튼」 · F-542 (유저 2026-11-02): 「타임시트용지나 콘티용지든 고정텍스트를
/// 카메라 움직임처럼 전체설정이랑 현재컷 설정 두개로 나눔」. ↩️The camera's
/// room spelled this out for itself until the fixed text made it three.
class WorkAndCutSettingField<T extends Object> extends StatelessWidget {
  const WorkAndCutSettingField({
    super.key,
    required this.label,
    required this.work,
    required this.cutWords,
    required this.keyValue,
    required this.choices,
    required this.picked,
    required this.stands,
    required this.nameOf,
    required this.choiceKeyOf,
    required this.onPicked,
  });

  final String label;

  /// What sets the whole work's.
  final Widget work;

  /// The words that say which cuts the row is about; null in the gap, where
  /// there is none to set it for, so the row refuses.
  final String? cutWords;

  final String keyValue;

  /// What a cut may keep of its own, beside the format's.
  final List<T> choices;

  /// What was picked for the cuts — null until one is, so saving leaves them
  /// as they [stands].
  final ({T? to})? picked;

  /// What the cut keeps as it stands: null for the format's.
  final T? stands;

  T? get _shown => switch (picked) {
    (:final to) => to,
    null => stands,
  };

  final String Function(T? value) nameOf;
  final String Function(T? value) choiceKeyOf;
  final ValueChanged<T?> onPicked;

  /// One row of the field: [label], and what sets it.
  static Widget _row(String label, Widget child) => AppWindowField(
    label: label,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  Widget _cutRow() => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 12,
    children: [
      Flexible(
        child: EllipsisText(
          cutWords ?? AppText.strings.noCutSelected,
          maxLines: 1,
        ),
      ),
      PanelFlyoutButton(
        key: ValueKey<String>(keyValue),
        label: nameOf(_shown),
        enabled: cutWords != null,
        entriesBuilder: () => <T?>[null, ...choices].asFlyoutValueChoices(
          current: _shown,
          choiceOf: (value) => PanelFlyoutChoice(
            key: '$keyValue-${choiceKeyOf(value)}',
            label: nameOf(value),
          ),
          onPicked: onPicked,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindowField(
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          _row(strings.conteCameraRoomAll, work),
          _row(strings.cutSettingsTitle, _cutRow()),
        ],
      ),
    );
  }
}

/// Whether a paper writes its fixed lines: [work], and the cut's own — the
/// format's (null), or written or not. The one field the two format windows
/// have for it (F-542).
class FixedTextSettingField extends StatelessWidget {
  const FixedTextSettingField({
    super.key,
    required this.work,
    required this.keyValue,
    required this.cutWords,
    required this.picked,
    required this.stands,
    required this.onPicked,
  });

  final Widget work;
  final String keyValue;
  final String? cutWords;
  final ({bool? to})? picked;
  final bool? stands;
  final ValueChanged<bool?> onPicked;

  static String _nameOf(bool? on) {
    final strings = AppText.strings;
    return switch (on) {
      true => strings.conteOutlineOn,
      false => strings.conteOutlineOff,
      null => strings.conteCameraRoomAsSheet,
    };
  }

  static String _keyOf(bool? on) => switch (on) {
    true => 'on',
    false => 'off',
    null => 'format',
  };

  @override
  Widget build(BuildContext context) => WorkAndCutSettingField<bool>(
    label: AppText.strings.conteFixedText,
    work: work,
    cutWords: cutWords,
    keyValue: keyValue,
    choices: const [true, false],
    picked: picked,
    stands: stands,
    nameOf: _nameOf,
    choiceKeyOf: _keyOf,
    onPicked: onPicked,
  );
}
