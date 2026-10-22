import 'package:flutter/material.dart';

import '../../models/pasteboard_bounds.dart';
import '../text/app_strings.dart';
import '../widgets/pill_strip.dart';

/// The pasteboard's own row in its colour window (I-109, 유저 2026-10-18:
/// 「캔버스패널의 페이스트보드 색 고르는 창 안에 크기 지정이랑 사용 불리언
/// 버튼 두도록」): whether it is there, as one toggle pill, and its size, as
/// the steps the user chose (I-109-Q3: 1.5x · 2x · 3x).
///
/// A pill row, so its yes/no is a pill of one (board
/// `pill-group-booleans-Q1`: 「알약 줄 안은 한 알 토글」). The size keeps its
/// pills, live, while the pasteboard is off — the size is kept for when it
/// is on again, as a colour is while its plane is none.
///
/// The window was built with the values it opened on, so the row keeps its
/// own as it hands each change on — the window's opacity row does the same
/// with its 「없음」.
class PasteboardReachRow extends StatefulWidget {
  const PasteboardReachRow({
    super.key,
    required this.size,
    required this.inUse,
    required this.onSize,
    required this.onInUse,
  });

  final PasteboardSize size;
  final bool inUse;
  final ValueChanged<PasteboardSize> onSize;
  final ValueChanged<bool> onInUse;

  @override
  State<PasteboardReachRow> createState() => _PasteboardReachRowState();
}

class _PasteboardReachRowState extends State<PasteboardReachRow> {
  late PasteboardSize _size = widget.size;
  late bool _inUse = widget.inUse;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return Row(
      children: [
        TogglePill(
          keyValue: 'pasteboard-in-use',
          on: _inUse,
          words: (
            on: strings.pasteboardInUse,
            off: strings.pasteboardNotInUse,
          ),
          onChanged: (inUse) {
            setState(() => _inUse = inUse);
            widget.onInUse(inUse);
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PillStrip.even(
            key: const ValueKey<String>('pasteboard-size'),
            items: [
              for (final size in PasteboardSize.values)
                PillItem(
                  keyValue: 'pasteboard-size-${size.name}',
                  label: size.label,
                  selected: size == _size,
                  onTap: () {
                    setState(() => _size = size);
                    widget.onSize(size);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
