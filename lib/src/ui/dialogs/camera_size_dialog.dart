import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'size_fields_row.dart';
import 'canvas_size_dialog.dart' show CanvasSizeDialog;

/// The project camera (shooting frame) size — W×H fields plus the common
/// production frames. Pops the entered [CanvasSize], or nothing on cancel.
///
/// No anchor grid: the camera is a lens spec, not pixels — poses stay put
/// and every cut re-frames through `CameraPose.zoom` against the new
/// width. Bounds reuse [CanvasSizeDialog]'s typing limits: both fields
/// answer "how big may a document dimension be typed", which is the one
/// of the app's two ceilings that is actually a limit.
///
/// [onAdjustOnCanvas] opens the camera's frame on the canvas instead
/// (I-80): the window closes, and the size is dragged where the frame
/// stands.
Future<CanvasSize?> showCameraSizeDialog(
  BuildContext context, {
  required CanvasSize initialSize,
  VoidCallback? onAdjustOnCanvas,
}) {
  return showDialog<CanvasSize>(
    context: context,
    builder: (context) => _CameraSizeDialog(
      initialSize: initialSize,
      onAdjustOnCanvas: onAdjustOnCanvas,
    ),
  );
}

class _CameraSizeDialog extends StatefulWidget {
  const _CameraSizeDialog({required this.initialSize, this.onAdjustOnCanvas});

  final CanvasSize initialSize;
  final VoidCallback? onAdjustOnCanvas;

  @override
  State<_CameraSizeDialog> createState() => _CameraSizeDialogState();
}

class _CameraSizeDialogState extends State<_CameraSizeDialog> {
  /// The common production frames: a quarter of FHD (qHD), then the
  /// screens' sizes ([videoSizePresets]).
  ///
  /// 🗣️I-80 (유저 2026-10-06): 「카메라 크기 창도 버튼들 이제
  /// 리스트팝오버로서 여러 프리셋 준비해서 거기서 선택하는방식으로. 선택하면
  /// 적용되서 숫자 바뀌는느낌」 — the list the canvas size window offers.
  /// ↩️They were three chips (960 × 540, HD, FHD).
  static const _presets = <SizePreset>[
    (name: 'qHD', size: CanvasSize(width: 960, height: 540)),
    ...videoSizePresets,
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

  CanvasSize? get _enteredSize {
    final width = CanvasSizeDialog.parseDimension(_widthController.text);
    final height = CanvasSizeDialog.parseDimension(_heightController.text);
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
      // The canvas size window's width: the two share their rows, and the
      // presets row with 「캔버스에서 조정」 overflowed 380.
      width: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizeFieldsRow(
            keyPrefix: 'camera-size',
            widthController: _widthController,
            heightController: _heightController,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          SizePresetsRow(
            keyPrefix: 'camera-size',
            groups: const [_presets],
            entered: enteredSize,
            onPicked: _applyPreset,
            onAdjustOnCanvas: widget.onAdjustOnCanvas,
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
