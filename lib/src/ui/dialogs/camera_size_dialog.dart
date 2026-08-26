import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../text/app_strings.dart';
import '../text/full_width_numerals.dart';
import '../widgets/app_window.dart';
import 'canvas_size_dialog.dart' show CanvasSizeDialog;

/// The project camera (shooting frame) size — W×H fields plus the common
/// production frames. Pops the entered [CanvasSize], or nothing on cancel.
///
/// No anchor grid: the camera is a lens spec, not pixels — poses stay put
/// and every cut re-frames through `CameraPose.zoom` against the new
/// width. Bounds reuse [CanvasSizeDialog]'s typing limits: both fields
/// answer "how big may a document dimension be typed", which is the one
/// of the app's two ceilings that is actually a limit.
Future<CanvasSize?> showCameraSizeDialog(
  BuildContext context, {
  required CanvasSize initialSize,
}) {
  return showDialog<CanvasSize>(
    context: context,
    builder: (context) => _CameraSizeDialog(initialSize: initialSize),
  );
}

class _CameraSizeDialog extends StatefulWidget {
  const _CameraSizeDialog({required this.initialSize});

  final CanvasSize initialSize;

  @override
  State<_CameraSizeDialog> createState() => _CameraSizeDialogState();
}

class _CameraSizeDialogState extends State<_CameraSizeDialog> {
  static const _presets = <CanvasSize>[
    CanvasSize(width: 960, height: 540),
    CanvasSize(width: 1280, height: 720),
    CanvasSize(width: 1920, height: 1080),
  ];

  late final TextEditingController _widthController = TextEditingController(
    text: '${widget.initialSize.width}',
  );
  late final TextEditingController _heightController = TextEditingController(
    text: '${widget.initialSize.height}',
  );

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  int? _parseDimension(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    if (value == null ||
        value < CanvasSizeDialog.minDimension ||
        value > CanvasSizeDialog.maxDimension) {
      return null;
    }
    return value;
  }

  CanvasSize? get _enteredSize {
    final width = _parseDimension(_widthController);
    final height = _parseDimension(_heightController);
    if (width == null || height == null) {
      return null;
    }
    return CanvasSize(width: width, height: height);
  }

  void _applyPreset(CanvasSize size) {
    setState(() {
      _widthController.text = '${size.width}';
      _heightController.text = '${size.height}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final enteredSize = _enteredSize;
    final strings = AppText.strings;

    return AppWindow(
      windowKey: const ValueKey<String>('camera-size-dialog'),
      title: strings.cameraSizeTitle,
      titleIcon: Icons.videocam_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 380,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppWindowField(
                  label: strings.canvasWidthLabel,
                  emphasized: true,
                  child: TextField(
                    key: const ValueKey<String>('camera-size-width-field'),
                    controller: _widthController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: halfWidthDigitsOnly,
                    onChanged: (_) => setState(() {}),
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
                    key: const ValueKey<String>('camera-size-height-field'),
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    inputFormatters: halfWidthDigitsOnly,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final size in _presets)
                ActionChip(
                  key: ValueKey<String>(
                    'camera-size-preset-${size.width}x${size.height}',
                  ),
                  label: Text('${size.width}×${size.height}'),
                  onPressed: () => _applyPreset(size),
                ),
            ],
          ),
        ],
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('camera-size-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonApply,
          actionKey: const ValueKey<String>('camera-size-apply-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: enteredSize == null
              ? null
              : () => Navigator.of(context).pop(enteredSize),
        ),
      ],
    );
  }
}
