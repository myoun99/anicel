import 'package:flutter/material.dart';

import '../../models/canvas_resize_anchor.dart';
import '../../models/canvas_size.dart';
import '../../services/editing/default_cut_helpers.dart'
    show defaultCutCanvasSize;
import '../widgets/app_window.dart';
import 'size_fields_row.dart';
import '../text/app_strings.dart';
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart' show AppShapes;
import 'app_confirm_dialog.dart';

/// What the canvas-size dialog confirms: the new size plus the anchor the
/// existing artwork stays pinned to.
class CanvasResizeRequest {
  const CanvasResizeRequest({required this.size, required this.anchor});

  final CanvasSize size;
  final CanvasResizeAnchor anchor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasResizeRequest &&
          other.size == size &&
          other.anchor == anchor;

  @override
  int get hashCode => Object.hash(size, anchor);

  @override
  String toString() => 'CanvasResizeRequest(size: $size, anchor: $anchor)';
}

/// Canvas-size dialog for a cut. Pops a [CanvasResizeRequest], or nothing on
/// cancel. The 9-way anchor grid (center by default, like Photoshop/Clip
/// Studio) chooses where existing artwork stays pinned; cropped strokes are
/// kept and reappear if the canvas grows again.
class CanvasSizeDialog extends StatefulWidget {
  const CanvasSizeDialog({
    super.key,
    required this.initialSize,
    this.onAdjustOnCanvas,
  });

  static const int minDimension = 1;

  /// User decision 2026-08-25 (D4): raised from 8192 to 16384.
  ///
  /// Two different 8192s lived in this app and only one of them was ever a
  /// limit. THIS one validates what may be typed, so it decides how big a
  /// document can be. The other -- `_maxBufferSide` in
  /// canvas_layer_stack_view.dart -- caps the DISPLAY buffer, and crossing
  /// it falls back to a direct walk, which is always correct and only costs
  /// more. The model itself never had a ceiling; the dialog did.
  /// Do not "unify" the two constants: they answer different questions.
  static const int maxDimension = 16384;

  /// The typed dimension in [text], or null when it is not a whole number
  /// inside [minDimension]..[maxDimension].
  ///
  /// Lives here because the bounds do: the camera-size dialog reads the
  /// same two constants, so one parser is the only way the two can answer
  /// "how big may a document dimension be typed" with one voice.
  static int? parseDimension(String text) {
    final value = int.tryParse(text.trim());
    if (value == null || value < minDimension || value > maxDimension) {
      return null;
    }
    return value;
  }

  final CanvasSize initialSize;

  /// Opens the canvas's adjust ON the canvas, the window closing to show
  /// it (I-79-Q3, 유저 2026-10-08: 「캔버스에서 조정」). Null greys the
  /// button out.
  final VoidCallback? onAdjustOnCanvas;

  @override
  State<CanvasSizeDialog> createState() => _CanvasSizeDialogState();
}

class _CanvasSizeDialogState extends State<CanvasSizeDialog> {
  /// The sizes the presets list offers, each with its name: the paper's,
  /// a line, then the video's ([videoSizePresets]).
  ///
  /// 🗣️I-79 (유저 2026-10-06): 「프리셋은 리스트팝오버로서 여러 프리셋
  /// 준비하고」 — the app's one picking list ([SizePresetsRow]).
  /// ↩️They were four chips in a row.
  ///
  /// 🗣️I-79-Q4 (유저 2026-10-08): 「용지 크기 + 영상 크기」 — A4 across at
  /// 150, 200 (a new cut's, [defaultCutCanvasSize]) and 300 dpi, then
  /// HD · FHD · 2K · 4K. 「현장마다 용지 크기 다름 … 용지는 특히 홀수만
  /// 아니면됨」: a studio types its own, and no size here is odd.
  static const _paperPresets = <SizePreset>[
    (name: 'A4 150dpi', size: CanvasSize(width: 1754, height: 1240)),
    (name: 'A4 200dpi', size: defaultCutCanvasSize),
    (name: 'A4 300dpi', size: CanvasSize(width: 3508, height: 2480)),
  ];

  late final TextEditingController _widthController = TextEditingController(
    text: '${widget.initialSize.width}',
  );
  late final TextEditingController _heightController = TextEditingController(
    text: '${widget.initialSize.height}',
  );
  CanvasResizeAnchor _anchor = CanvasResizeAnchor.center;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  CanvasResizeRequest? get _enteredRequest {
    final width = CanvasSizeDialog.parseDimension(_widthController.text);
    final height = CanvasSizeDialog.parseDimension(_heightController.text);
    if (width == null || height == null) {
      return null;
    }
    return CanvasResizeRequest(
      size: CanvasSize(width: width, height: height),
      anchor: _anchor,
    );
  }

  void _applyPreset(CanvasSize size) {
    setState(() {
      _widthController.text = '${size.width}';
      _heightController.text = '${size.height}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final keys = confirmDialogKeys('canvas-size');
    final enteredRequest = _enteredRequest;
    final strings = AppText.strings;

    return AppWindow(
      windowKey: keys.window,
      title: strings.canvasSizeTitle,
      titleIcon: Icons.crop_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizeFieldsRow(
            keyPrefix: 'canvas-size',
            widthController: _widthController,
            heightController: _heightController,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          SizePresetsRow(
            keyPrefix: 'canvas-size',
            groups: const [_paperPresets, videoSizePresets],
            entered: enteredRequest?.size,
            onPicked: _applyPreset,
            onAdjustOnCanvas: widget.onAdjustOnCanvas,
          ),
          const SizedBox(height: 12),
          // ⛔No caption beside the grid: the rule against explaining a
          // control under it (no-explanatory-ui-copy). ↩️It said what an
          // anchor is, that cropped strokes come back, and the size range —
          // which the fields already enforce by refusing what is outside it.
          _AnchorGrid(
            selected: _anchor,
            onSelected: (anchor) => setState(() => _anchor = anchor),
          ),
        ],
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: keys.decline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonResize,
          actionKey: keys.accept,
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: enteredRequest == null
              ? null
              : () => Navigator.of(context).pop(enteredRequest),
        ),
      ],
    );
  }
}

/// The Photoshop-style 3×3 anchor picker.
class _AnchorGrid extends StatelessWidget {
  const _AnchorGrid({required this.selected, required this.onSelected});

  static const _rows = <List<CanvasResizeAnchor>>[
    [
      CanvasResizeAnchor.topLeft,
      CanvasResizeAnchor.topCenter,
      CanvasResizeAnchor.topRight,
    ],
    [
      CanvasResizeAnchor.centerLeft,
      CanvasResizeAnchor.center,
      CanvasResizeAnchor.centerRight,
    ],
    [
      CanvasResizeAnchor.bottomLeft,
      CanvasResizeAnchor.bottomCenter,
      CanvasResizeAnchor.bottomRight,
    ],
  ];

  final CanvasResizeAnchor selected;
  final ValueChanged<CanvasResizeAnchor> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: AppShapes.container(
          AppShapes.wellRadius,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final anchor in row)
                  ControlPressClaim(
                    onPressed: () => onSelected(anchor),
                    child: InkWell(
                      key: ValueKey<String>(
                        'canvas-size-anchor-${anchor.name}',
                      ),
                      onTap: silentPress(() => onSelected(anchor)),
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: anchor == selected
                                  ? colorScheme.primary
                                  : Colors.transparent,
                              border: Border.all(
                                color: anchor == selected
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
