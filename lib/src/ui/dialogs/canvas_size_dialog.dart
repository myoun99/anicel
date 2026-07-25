import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/canvas_resize_anchor.dart';
import '../../models/canvas_size.dart';
import '../widgets/app_window.dart';

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
  const CanvasSizeDialog({super.key, required this.initialSize});

  static const int minDimension = 1;
  static const int maxDimension = 8192;

  final CanvasSize initialSize;

  @override
  State<CanvasSizeDialog> createState() => _CanvasSizeDialogState();
}

class _CanvasSizeDialogState extends State<CanvasSizeDialog> {
  static const _presets = <(String, CanvasSize)>[
    ('Default', CanvasSize(width: 2340, height: 1654)),
    ('HD', CanvasSize(width: 1280, height: 720)),
    ('FHD', CanvasSize(width: 1920, height: 1080)),
    ('4K', CanvasSize(width: 3840, height: 2160)),
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

  int? _parseDimension(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    if (value == null ||
        value < CanvasSizeDialog.minDimension ||
        value > CanvasSizeDialog.maxDimension) {
      return null;
    }
    return value;
  }

  CanvasResizeRequest? get _enteredRequest {
    final width = _parseDimension(_widthController);
    final height = _parseDimension(_heightController);
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
    final enteredRequest = _enteredRequest;

    return AppWindow(
      windowKey: const ValueKey<String>('canvas-size-dialog'),
      title: 'Canvas size',
      titleIcon: Icons.crop_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('canvas-size-width-field'),
                  controller: _widthController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Width (px)'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('×'),
              ),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('canvas-size-height-field'),
                  controller: _heightController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Height (px)'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, size) in _presets)
                ActionChip(
                  key: ValueKey<String>(
                    'canvas-size-preset-${size.width}x${size.height}',
                  ),
                  label: Text('$label ${size.width}×${size.height}'),
                  onPressed: () => _applyPreset(size),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AnchorGrid(
                selected: _anchor,
                onSelected: (anchor) => setState(() => _anchor = anchor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Anchor: existing artwork stays pinned here. '
                  'Cropped strokes are kept and reappear if the canvas '
                  'grows again. '
                  '(${CanvasSizeDialog.minDimension}–${CanvasSizeDialog.maxDimension} px)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        AppWindowAction(
          label: 'Cancel',
          actionKey: const ValueKey<String>('canvas-size-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: 'Resize',
          actionKey: const ValueKey<String>('canvas-size-confirm-button'),
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
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final anchor in row)
                  InkWell(
                    key: ValueKey<String>('canvas-size-anchor-${anchor.name}'),
                    onTap: () => onSelected(anchor),
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
              ],
            ),
        ],
      ),
    );
  }
}
