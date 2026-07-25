import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../timeline/instruction_icon_palette.dart';
import 'instance_edit_dialog.dart';
import 'instance_edit_preview.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';

/// What the instruction event dialog resolved to: an event to apply, a
/// deletion, or (when the user edited the vocabulary meanwhile) the edited
/// instruction set rides along so the caller commits both.
class InstructionEventDialogResult {
  const InstructionEventDialogResult({
    this.instructionId,
    this.text,
    this.valueA,
    this.valueB,
    this.memo,
    this.delete = false,
  });

  final String? instructionId;

  /// Free per-event text (independent of the mark); empty → vocabulary
  /// name fallback.
  final String? text;
  final String? valueA;
  final String? valueB;

  /// Free memo, printed into the timesheet's memo band.
  final String? memo;
  final bool delete;
}

/// The instruction layer's instance editor in the shared shell: the sheet's
/// start/end instance names (A/B), the mark (vocabulary pick — the def
/// carries bar/O.L), the free instruction name, the timesheet memo and the
/// live paper-block preview. New events are created ONE frame long like
/// drawing cels — the grips own the length afterwards (the R3 length input
/// is retired). Blank fields simply don't display. Editing an existing
/// event offers Delete.
class InstructionEventDialog extends StatefulWidget {
  const InstructionEventDialog({
    super.key,
    required this.instructionSet,
    this.initialInstructionId,
    this.initialText,
    this.initialValueA,
    this.initialValueB,
    this.initialMemo,
    this.editing = false,
    this.onEditInstructionSet,
    this.previewAxis = Axis.horizontal,
  });

  final CameraInstructionSet instructionSet;
  final String? initialInstructionId;
  final String? initialText;
  final String? initialValueA;
  final String? initialValueB;
  final String? initialMemo;

  /// Whether an existing event is being edited (shows Delete).
  final bool editing;

  /// Opens the vocabulary editor; the host owns the flow so the edited set
  /// commits through the session even when this dialog is cancelled.
  final VoidCallback? onEditInstructionSet;

  /// Follows the timeline orientation so the preview matches what the
  /// user is looking at.
  final Axis previewAxis;

  @override
  State<InstructionEventDialog> createState() => _InstructionEventDialogState();
}

class _InstructionEventDialogState extends State<InstructionEventDialog> {
  late String? _instructionId =
      widget.initialInstructionId ??
      (widget.instructionSet.defs.isEmpty
          ? null
          : widget.instructionSet.defs.first.id);
  late final TextEditingController _textController = TextEditingController(
    text: widget.initialText ?? '',
  );
  late final TextEditingController _valueAController = TextEditingController(
    text: widget.initialValueA ?? '',
  );
  late final TextEditingController _valueBController = TextEditingController(
    text: widget.initialValueB ?? '',
  );
  late final TextEditingController _memoController = TextEditingController(
    text: widget.initialMemo ?? '',
  );

  @override
  void initState() {
    super.initState();
    // Live preview: repaint on every keystroke.
    _textController.addListener(_onFieldsChanged);
    _valueAController.addListener(_onFieldsChanged);
    _valueBController.addListener(_onFieldsChanged);
  }

  void _onFieldsChanged() => setState(() {});

  @override
  void dispose() {
    _textController.dispose();
    _valueAController.dispose();
    _valueBController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  String? _trimmedOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  void _submit() {
    final instructionId = _instructionId;
    if (instructionId == null) {
      return;
    }
    Navigator.of(context).pop(
      InstructionEventDialogResult(
        instructionId: instructionId,
        text: _trimmedOrNull(_textController),
        valueA: _trimmedOrNull(_valueAController),
        valueB: _trimmedOrNull(_valueBController),
        memo: _trimmedOrNull(_memoController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final instructionId = _instructionId;
    final strings = AppText.strings;
    return InstanceEditDialogShell(
      title: widget.editing
          ? strings.instructionEventEditTitle
          : strings.instructionEventAddTitle,
      titleIcon: Icons.videocam_outlined,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppWindowField(
            label: strings.instructionMarkLabel,
            emphasized: true,
            child: DropdownButtonFormField<String>(
              key: const ValueKey<String>('instruction-def-dropdown'),
              initialValue: _instructionId,
              items: [
                for (final def in widget.instructionSet.defs)
                  DropdownMenuItem<String>(
                    key: ValueKey<String>('instruction-option-${def.id}'),
                    value: def.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(instructionIconFor(def.iconKey), size: 16),
                        const SizedBox(width: 8),
                        Text(def.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _instructionId = value),
            ),
          ),
          const SizedBox(height: 12),
          AppWindowField(
            label: strings.instructionNameLabel,
            child: TextField(
              key: const ValueKey<String>('instruction-text-field'),
              controller: _textController,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppWindowField(
                  label: strings.instructionStartLabel,
                  child: TextField(
                    key: const ValueKey<String>('instruction-value-a-field'),
                    controller: _valueAController,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppWindowField(
                  label: strings.instructionEndLabel,
                  child: TextField(
                    key: const ValueKey<String>('instruction-value-b-field'),
                    controller: _valueBController,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppWindowField(
            label: strings.instructionMemoLabel,
            child: TextField(
              key: const ValueKey<String>('instruction-memo-field'),
              controller: _memoController,
            ),
          ),
          if (widget.onEditInstructionSet != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey<String>('instruction-edit-set-button'),
                onPressed: widget.onEditInstructionSet,
                icon: const Icon(Icons.tune, size: 16),
                label: Text(strings.instructionEditSetButton),
              ),
            ),
          ],
        ],
      ),
      preview: instructionId == null
          ? null
          : InstanceEditPreview.instruction(
              axis: widget.previewAxis,
              event: InstructionEvent(
                instructionId: instructionId,
                length: InstanceEditPreview.maxKoma,
                text: _trimmedOrNull(_textController),
                valueA: _trimmedOrNull(_valueAController),
                valueB: _trimmedOrNull(_valueBController),
              ),
              defById: widget.instructionSet.defById,
            ),
      onSubmit: instructionId == null ? null : _submit,
      onDelete: widget.editing
          ? () => Navigator.of(
              context,
            ).pop(const InstructionEventDialogResult(delete: true))
          : null,
    );
  }
}
