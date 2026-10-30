import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/app_frame_count_settings.dart' show FrameCountEntry;
import '../../models/project_frame_rate.dart';
import '../text/app_strings.dart';
import 'app_window.dart';
import 'pill_strip.dart';
import 'window_number.dart';

/// A count of frames, given either way — the entry switch above, the number
/// or numbers under it.
///
/// 🗣️I-24 (유저 2026-09-14): 「코마 수 설정창에서 기존처럼 프레임수로 정하는거랑
/// 추가로 초수+코마로 조절하는거 신설. 버튼으로 각각 옵션 변경가능. 초수+코마는
/// 특히 +를 텍스트로 쓰게한다거나 하지말고 초수랑 코마랑 제대로 칸 나눠서
/// 입력하게하고 사이에 + 텍스트만 넣기. 그리고 이 창은 알겠지만 숫자만
/// 입력가능하도록. 그리고 초수+코마 변경은 특히 여러곳에서 쓰일테니 공용화」 —
/// so this is the field, and a window that asks for a count of frames asks
/// with it.
///
/// Each number is the window number ([WindowNumber]) — dragged, stepped or
/// typed: 🗣️F-507-Q1 (유저 2026-10-30 「칸마다 드래그 숫자 — 전환은
/// 그대로」). The koma counts on past the rate into the seconds and back,
/// since both are one count; the count stops at zero, as digits alone
/// leave typing no sign.
///
/// Switching the entry shows the same count the other way: 30 frames at 24
/// fps read `1` + `6`, and back.
class FrameCountField extends StatefulWidget {
  const FrameCountField({
    super.key,
    required this.keyPrefix,
    required this.framesPerSecond,
    required this.count,
    required this.onChanged,
    this.label,
    this.initialEntry = FrameCountEntry.frames,
    this.onEntryChanged,
    this.beside,
  });

  /// `<keyPrefix>-field` (frames), `-seconds-field` and `-koma-field`
  /// (seconds+frames) — each a [WindowNumber]'s key base —
  /// `-entry-frames` and `-entry-seconds` (the switch).
  final String keyPrefix;

  /// The cap over the field; null where the window's title already says
  /// what the count is of (I-24-open-entry: 「프레임이든 초+코마든 노출
  /// 프레임수라는 텍스트 필요없어보임. 안써도 이미 헤더랑 버튼에서
  /// 설명됨」).
  final String? label;

  /// The COUNTING base (`ProjectFrameRate.countingBase`).
  final int framesPerSecond;

  /// The count shown — its host's, built again with what [onChanged] gave;
  /// null where there is none to show ([WindowNumber.value]).
  final int? count;

  /// The count a number was just moved or typed to, never below zero.
  final ValueChanged<int> onChanged;
  final FrameCountEntry initialEntry;

  /// The entry the switch was just moved to — what a window remembers to
  /// open on next time (I-24-open-entry).
  final ValueChanged<FrameCountEntry>? onEntryChanged;

  /// What stands beside the number, either way it is given — the mark the
  /// mark-every window lays: 🗣️I-130-Q2 (유저 2026-10-25 「간격 숫자 옆에
  /// ○ / ● 고르기」). Null on every other count window.
  final Widget? beside;

  @override
  State<FrameCountField> createState() => _FrameCountFieldState();
}

class _FrameCountFieldState extends State<FrameCountField> {
  late FrameCountEntry _entry = widget.initialEntry;

  void _set(int count) => widget.onChanged(math.max(0, count));

  void _switchTo(FrameCountEntry entry) {
    if (entry == _entry) {
      return;
    }
    setState(() => _entry = entry);
    widget.onEntryChanged?.call(entry);
  }

  /// The number or numbers the count is given in, as the entry has it.
  Widget _number(String prefix) {
    final fps = widget.framesPerSecond;
    final count = widget.count;
    if (_entry == FrameCountEntry.frames) {
      return WindowNumber(
        keyValue: '$prefix-field',
        value: count,
        onChanged: _set,
      );
    }
    final split = count == null ? null : durationSecondsAndFrames(count, fps);
    final seconds = split?.seconds ?? 0;
    final koma = split?.frames ?? 0;
    return Row(
      children: [
        Expanded(
          child: WindowNumber(
            keyValue: '$prefix-seconds-field',
            value: split?.seconds,
            width: _splitWidth,
            onChanged: (to) => _set(
              framesOfSecondsAndFrames(math.max(0, to), koma, fps),
            ),
          ),
        ),
        const Text('+'),
        Expanded(
          child: WindowNumber(
            keyValue: '$prefix-koma-field',
            value: split?.frames,
            width: _splitWidth,
            onChanged: (to) => _set(framesOfSecondsAndFrames(seconds, to, fps)),
          ),
        ),
      ],
    );
  }

  /// A seconds or koma number's face: two numbers and their hands share the
  /// row one stands in.
  static const double _splitWidth = 48;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final prefix = widget.keyPrefix;
    final number = _number(prefix);
    final beside = widget.beside;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PillStrip(
            items: [
              PillItem(
                keyValue: '$prefix-entry-frames',
                label: strings.frameCountEntryFrames,
                selected: _entry == FrameCountEntry.frames,
                onTap: () => _switchTo(FrameCountEntry.frames),
              ),
              PillItem(
                keyValue: '$prefix-entry-seconds',
                label: strings.frameCountEntrySecondsPlusFrames,
                selected: _entry == FrameCountEntry.secondsPlusFrames,
                onTap: () => _switchTo(FrameCountEntry.secondsPlusFrames),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AppWindowField(
          label: widget.label,
          emphasized: true,
          child: beside == null
              ? number
              : Row(
                  children: [
                    Expanded(child: number),
                    const SizedBox(width: 8),
                    beside,
                  ],
                ),
        ),
      ],
    );
  }
}
