import 'package:flutter/material.dart';

import '../../models/app_frame_count_settings.dart' show FrameCountEntry;
import '../../models/project_frame_rate.dart';
import '../text/app_strings.dart';
import '../text/full_width_numerals.dart';
import 'app_window.dart';
import 'pill_strip.dart';
import 'selected_text_controller.dart';

/// A count of frames, typed either way — the entry switch above, the field
/// or fields under it.
///
/// 🗣️I-24 (유저 2026-09-14): 「코마 수 설정창에서 기존처럼 프레임수로 정하는거랑
/// 추가로 초수+코마로 조절하는거 신설. 버튼으로 각각 옵션 변경가능. 초수+코마는
/// 특히 +를 텍스트로 쓰게한다거나 하지말고 초수랑 코마랑 제대로 칸 나눠서
/// 입력하게하고 사이에 + 텍스트만 넣기. 그리고 이 창은 알겠지만 숫자만
/// 입력가능하도록. 그리고 초수+코마 변경은 특히 여러곳에서 쓰일테니 공용화」 —
/// so this is the field, and a window that asks for a count of frames asks
/// with it.
///
/// Switching the entry carries what was typed across: 30 frames at 24 fps
/// read `1` + `6`, and back.
class FrameCountField extends StatefulWidget {
  const FrameCountField({
    super.key,
    required this.keyPrefix,
    required this.framesPerSecond,
    required this.onChanged,
    this.label,
    this.onSubmitted,
    this.initialEntry = FrameCountEntry.frames,
    this.initialCount,
    this.onEntryChanged,
    this.beside,
  });

  /// `<keyPrefix>-field` (frames), `-seconds-field` and `-koma-field`
  /// (seconds+frames), `-entry-frames` and `-entry-seconds` (the switch).
  final String keyPrefix;

  /// The cap over the field; null where the window's title already says
  /// what the count is of (I-24-open-entry: 「프레임이든 초+코마든 노출
  /// 프레임수라는 텍스트 필요없어보임. 안써도 이미 헤더랑 버튼에서
  /// 설명됨」).
  final String? label;

  /// The COUNTING base (`ProjectFrameRate.countingBase`).
  final int framesPerSecond;

  /// The count typed so far — null while nothing countable is typed.
  final ValueChanged<int?> onChanged;
  final VoidCallback? onSubmitted;
  final FrameCountEntry initialEntry;

  /// The count the field opens on, selected either way it is typed — the
  /// length already there (I-24-open-entry: 「길이 설정도 기존 길이
  /// 띄워둔다」). Null opens it empty.
  final int? initialCount;

  /// The entry the switch was just moved to — what a window remembers to
  /// open on next time (I-24-open-entry).
  final ValueChanged<FrameCountEntry>? onEntryChanged;

  /// What stands beside the number, either way it is typed — the mark the
  /// mark-every window lays: 🗣️I-130-Q2 (유저 2026-10-25 「간격 숫자 옆에
  /// ○ / ● 고르기」). Null on every other count window.
  final Widget? beside;

  @override
  State<FrameCountField> createState() => _FrameCountFieldState();
}

class _FrameCountFieldState extends State<FrameCountField> {
  late FrameCountEntry _entry = widget.initialEntry;
  late final _split = switch (widget.initialCount) {
    null => null,
    final count => durationSecondsAndFrames(count, widget.framesPerSecond),
  };
  late final _frames = selectedTextController(
    widget.initialCount?.toString() ?? '',
  );
  late final _seconds = selectedTextController(
    _split?.seconds.toString() ?? '',
  );
  late final _koma = selectedTextController(_split?.frames.toString() ?? '');

  @override
  void dispose() {
    _frames.dispose();
    _seconds.dispose();
    _koma.dispose();
    super.dispose();
  }

  int? get _count => switch (_entry) {
    FrameCountEntry.frames => halfWidthInt(_frames.text),
    FrameCountEntry.secondsPlusFrames =>
      _seconds.text.isEmpty && _koma.text.isEmpty
          ? null
          : framesOfSecondsAndFrames(
              halfWidthInt(_seconds.text) ?? 0,
              halfWidthInt(_koma.text) ?? 0,
              widget.framesPerSecond,
            ),
  };

  void _changed() => widget.onChanged(_count);

  void _switchTo(FrameCountEntry entry) {
    if (entry == _entry) {
      return;
    }
    final count = _count;
    setState(() {
      _entry = entry;
      if (count == null) {
        return;
      }
      switch (entry) {
        case FrameCountEntry.frames:
          _frames.text = '$count';
        case FrameCountEntry.secondsPlusFrames:
          final split = durationSecondsAndFrames(count, widget.framesPerSecond);
          _seconds.text = '${split.seconds}';
          _koma.text = '${split.frames}';
      }
    });
    widget.onEntryChanged?.call(entry);
    _changed();
  }

  TextField _numberField(
    String key,
    TextEditingController controller, {
    bool autofocus = false,
  }) => TextField(
    key: ValueKey<String>(key),
    controller: controller,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: halfWidthDigitsOnly,
    onChanged: (_) => _changed(),
    onSubmitted: (_) => widget.onSubmitted?.call(),
  );

  /// The field or fields the count is typed in, as the entry has it.
  Widget _number(String prefix) => switch (_entry) {
    FrameCountEntry.frames => _numberField(
      '$prefix-field',
      _frames,
      autofocus: true,
    ),
    FrameCountEntry.secondsPlusFrames => Row(
      children: [
        Expanded(
          child: _numberField(
            '$prefix-seconds-field',
            _seconds,
            autofocus: true,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('+'),
        ),
        Expanded(child: _numberField('$prefix-koma-field', _koma)),
      ],
    ),
  };

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
