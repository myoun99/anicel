import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../text/full_width_numerals.dart';
import '../widgets/app_window.dart';

/// The width × height pair every size window asks for: two emphasised
/// numeric fields on one row, the width focused first.
///
/// 🚨ONE row for the canvas size window and the camera size window (the
/// audit's clone scan, 2026-09-03); each used to spell the pair out.
class SizeFieldsRow extends StatelessWidget {
  const SizeFieldsRow({
    super.key,
    required this.keyPrefix,
    required this.widthController,
    required this.heightController,
    required this.onChanged,
  });

  final String keyPrefix;
  final TextEditingController widthController;
  final TextEditingController heightController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: AppWindowField(
            label: strings.canvasWidthLabel,
            emphasized: true,
            child: TextField(
              key: ValueKey<String>('$keyPrefix-width-field'),
              controller: widthController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: halfWidthDigitsOnly,
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 7),
          child: Text('×'),
        ),
        Expanded(
          child: AppWindowField(
            label: strings.canvasHeightLabel,
            emphasized: true,
            child: TextField(
              key: ValueKey<String>('$keyPrefix-height-field'),
              controller: heightController,
              keyboardType: TextInputType.number,
              inputFormatters: halfWidthDigitsOnly,
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
      ],
    );
  }
}
