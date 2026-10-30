import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../../services/editing/default_cut_helpers.dart'
    show defaultCutCanvasSize;
import '../text/app_strings.dart';
import '../text/full_width_numerals.dart';
import '../text/pixel_size_label.dart';
import '../input/control_press_claim.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';

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

/// A size a size window offers, by its name.
typedef SizePreset = ({String name, CanvasSize size});

/// The screens' sizes — the canvas size window's after the paper's, and
/// the camera size window's.
///
/// 🗣️I-79-Q4 (유저 2026-10-08): 「용지 크기 + 영상 크기」 — these are the
/// video's. I-80 (유저 2026-10-06): 「카메라 크기 창도 버튼들 이제
/// 리스트팝오버로서 여러 프리셋 준비해서」 — the camera's window offers
/// the same.
const videoSizePresets = <SizePreset>[
  (name: 'HD', size: CanvasSize(width: 1280, height: 720)),
  (name: 'FHD', size: CanvasSize(width: 1920, height: 1080)),
  (name: '2K', size: CanvasSize(width: 2560, height: 1440)),
  (name: '4K', size: CanvasSize(width: 3840, height: 2160)),
];

/// The paper's sizes — a canvas window's first.
///
/// 🗣️I-79-Q4 (유저 2026-10-08): 「용지 크기 + 영상 크기」 — A4 across at
/// 150, 200 (a new cut's, [defaultCutCanvasSize]) and 300 dpi. 「현장마다
/// 용지 크기 다름 … 용지는 특히 홀수만 아니면됨」: a studio types its own,
/// and no size here is odd.
const paperSizePresets = <SizePreset>[
  (name: 'A4 150dpi', size: CanvasSize(width: 1754, height: 1240)),
  (name: 'A4 200dpi', size: defaultCutCanvasSize),
  (name: 'A4 300dpi', size: CanvasSize(width: 3508, height: 2480)),
];

/// What a cut's canvas is offered, in the canvas size window and the new
/// cut window alike: the paper's, a line, then the video's.
///
/// 🗣️I-79 (유저 2026-10-06): 「프리셋은 리스트팝오버로서 여러 프리셋
/// 준비하고」 — the app's one picking list ([SizePresetsButton]).
/// ↩️They were four chips in a row.
const canvasSizePresetGroups = [paperSizePresets, videoSizePresets];

/// Under a size window's fields: its presets ([SizePresetsButton]) and
/// 「캔버스에서 조정」, which closes the window and hands the size to the
/// canvas ([onAdjustOnCanvas]) — the canvas size window's (I-79) and the
/// camera size window's (I-80), keyed `<keyPrefix>-adjust-on-canvas`.
///
/// ⛔The button stands where a window has nothing to hand over, dead: a
/// control that came and went with its caller would be UI popping into
/// existence. A window that never hands a size to a canvas — the new cut
/// window, whose cut is not made yet — wears the list alone.
class SizePresetsRow extends StatelessWidget {
  const SizePresetsRow({
    super.key,
    required this.keyPrefix,
    required this.groups,
    required this.entered,
    required this.onPicked,
    this.onAdjustOnCanvas,
  });

  final String keyPrefix;
  final List<List<SizePreset>> groups;
  final CanvasSize? entered;
  final ValueChanged<CanvasSize> onPicked;
  final VoidCallback? onAdjustOnCanvas;

  @override
  Widget build(BuildContext context) {
    final open = onAdjustOnCanvas;
    final adjust = open == null
        ? null
        : () {
            Navigator.of(context).pop();
            open();
          };
    return Row(
      children: [
        SizePresetsButton(
          keyPrefix: keyPrefix,
          groups: groups,
          entered: entered,
          onPicked: onPicked,
        ),
        const SizedBox(width: 8),
        ControlPressClaim(
          onPressed: adjust,
          child: OutlinedButton(
            key: ValueKey<String>('$keyPrefix-adjust-on-canvas'),
            onPressed: silentPress(adjust),
            child: Text(AppText.strings.canvasAdjustOnCanvas),
          ),
        ),
      ],
    );
  }
}

/// A size window's presets as one list ([PanelFlyoutButton]), keyed
/// `<keyPrefix>-presets`.
class SizePresetsButton extends StatelessWidget {
  const SizePresetsButton({
    super.key,
    required this.keyPrefix,
    required this.groups,
    required this.entered,
    required this.onPicked,
  });

  final String keyPrefix;

  /// The sizes the list offers, a line between two groups; each row keyed
  /// `<keyPrefix>-preset-<width>x<height>`.
  final List<List<SizePreset>> groups;

  /// The size the fields hold — its row is marked.
  final CanvasSize? entered;

  /// A row picked: the fields take its size.
  final ValueChanged<CanvasSize> onPicked;

  List<PanelFlyoutEntry> _rows() => [
    for (final (index, group) in groups.indexed) ...[
      if (index > 0) const PanelFlyoutDivider(),
      ...group.asFlyoutValueChoices(
        current: group.where((preset) => preset.size == entered).firstOrNull,
        choiceOf: (preset) => PanelFlyoutChoice(
          key: '$keyPrefix-preset-${preset.size.width}x${preset.size.height}',
          label:
              '${preset.name} '
              '${pixelSizeLabel(preset.size.width, preset.size.height)}',
        ),
        onPicked: (preset) => onPicked(preset.size),
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) => PanelFlyoutButton(
    key: ValueKey<String>('$keyPrefix-presets'),
    label: AppText.strings.canvasSizePresets,
    entriesBuilder: _rows,
  );
}
