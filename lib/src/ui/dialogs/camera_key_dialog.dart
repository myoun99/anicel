import 'package:flutter/material.dart';

import '../timeline/camera_key_edit.dart';
import 'instance_edit_dialog.dart';

/// The camera layer's instance editor — per-lane (Position/Scale/Rotation)
/// key toggle + value + interpolation at one frame, in the shared shell.
/// Pops the edited lane states (the host folds them into ONE track edit),
/// or nothing on cancel.
class CameraKeyDialog extends StatefulWidget {
  const CameraKeyDialog({
    super.key,
    required this.frameIndex,
    required this.lanes,
  });

  final int frameIndex;
  final List<CameraKeyLaneState> lanes;

  @override
  State<CameraKeyDialog> createState() => _CameraKeyDialogState();
}

class _CameraKeyDialogState extends State<CameraKeyDialog> {
  late final List<CameraKeyLaneState> _lanes = List.of(widget.lanes);
  late final List<TextEditingController> _valueControllers = [
    for (final lane in widget.lanes)
      TextEditingController(text: lane.valueText),
  ];

  @override
  void dispose() {
    for (final controller in _valueControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop([
      for (var i = 0; i < _lanes.length; i += 1)
        _lanes[i].copyWith(valueText: _valueControllers[i].text.trim()),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InstanceEditDialogShell(
      title: 'Camera keys — frame ${widget.frameIndex + 1}',
      titleIcon: Icons.videocam_outlined,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _lanes.length; i += 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Checkbox(
                    key: ValueKey<String>(
                      'camera-key-toggle-${_lanes[i].laneId}',
                    ),
                    value: _lanes[i].keyed,
                    onChanged: (value) => setState(
                      () =>
                          _lanes[i] = _lanes[i].copyWith(keyed: value ?? false),
                    ),
                  ),
                  SizedBox(
                    width: 68,
                    child: Text(
                      _lanes[i].label,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: ValueKey<String>(
                        'camera-key-value-${_lanes[i].laneId}',
                      ),
                      controller: _valueControllers[i],
                      enabled: _lanes[i].keyed,
                      decoration: const InputDecoration(isDense: true),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<bool>(
                    key: ValueKey<String>(
                      'camera-key-interp-${_lanes[i].laneId}',
                    ),
                    value: _lanes[i].hold,
                    onChanged: _lanes[i].keyed
                        ? (value) => setState(
                            () => _lanes[i] = _lanes[i].copyWith(
                              hold: value ?? false,
                            ),
                          )
                        : null,
                    items: const [
                      DropdownMenuItem(value: false, child: Text('Linear')),
                      DropdownMenuItem(value: true, child: Text('Hold')),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
      onSubmit: _submit,
    );
  }
}
