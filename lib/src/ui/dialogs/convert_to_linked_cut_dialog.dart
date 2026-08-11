import 'package:flutter/material.dart';

import '../../models/cut_id.dart';
import '../../services/commands/convert_to_linked_cut_plan.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// 겸용 변경 dialog: pick a target cut, read the 안내문 (what links, what
/// gets replaced — 원본 승리 — and what appears where), then confirm.
/// Pops the chosen [CutId] to convert with, or null on cancel.
class ConvertToLinkedCutDialog extends StatefulWidget {
  const ConvertToLinkedCutDialog({
    super.key,
    required this.activeCutName,
    required this.candidates,
    required this.previewOf,
  });

  final String activeCutName;
  final List<({CutId id, String name})> candidates;
  final ConvertToLinkedCutPreviewData? Function(CutId targetCutId) previewOf;

  @override
  State<ConvertToLinkedCutDialog> createState() =>
      _ConvertToLinkedCutDialogState();
}

class _ConvertToLinkedCutDialogState extends State<ConvertToLinkedCutDialog> {
  CutId? _targetCutId;

  @override
  void initState() {
    super.initState();
    if (widget.candidates.length == 1) {
      _targetCutId = widget.candidates.single.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetCutId = _targetCutId;
    final preview = targetCutId == null ? null : widget.previewOf(targetCutId);
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('convert-linked-cut-dialog'),
      title: strings.convertLinkedCutTitle,
      titleIcon: Icons.link_outlined,
      onClose: () => Navigator.of(context).pop(null),
      width: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.convertLinkedCutBodyTemplate.replaceAll(
              '{cut}',
              widget.activeCutName,
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          AppWindowField(
            label: strings.convertLinkedCutTargetLabel,
            emphasized: true,
            child: DropdownButtonFormField<CutId>(
              key: const ValueKey<String>('convert-linked-cut-target'),
              initialValue: targetCutId,
              items: [
                for (final candidate in widget.candidates)
                  DropdownMenuItem(
                    value: candidate.id,
                    child: Text(candidate.name),
                  ),
              ],
              onChanged: (value) => setState(() => _targetCutId = value),
            ),
          ),
          if (preview != null) ...[
            const SizedBox(height: 12),
            _PreviewSummary(preview: preview),
          ],
        ],
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('convert-linked-cut-cancel-button'),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        AppWindowAction(
          label: strings.commonLink,
          actionKey: const ValueKey<String>(
            'convert-linked-cut-confirm-button',
          ),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: preview != null && preview.linksAnything
              ? () => Navigator.of(context).pop(targetCutId)
              : null,
        ),
      ],
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.preview});

  final ConvertToLinkedCutPreviewData preview;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final lines = <String>[
      if (preview.linkingLayerNames.isNotEmpty)
        strings.convertLinkedCutLinksTemplate.replaceAll(
          '{names}',
          preview.linkingLayerNames.join(', '),
        ),
      // 원본 승리, announced up front (user-confirmed rule): the origin's
      // picture wins each same-name conflict, exactly once, undoable.
      if (preview.replacedFrameCount > 0)
        strings.convertLinkedCutReplacedTemplate
            .replaceAll('{count}', '${preview.replacedFrameCount}')
            .replaceAll('{cut}', preview.targetCutName),
      if (preview.joiningFrameCount > 0)
        strings.convertLinkedCutJoiningTemplate.replaceAll(
          '{count}',
          '${preview.joiningFrameCount}',
        ),
      if (preview.layerNamesAppearingInTarget.isNotEmpty)
        strings.convertLinkedCutTargetGainsTemplate
            .replaceAll('{cut}', preview.targetCutName)
            .replaceAll(
              '{names}',
              preview.layerNamesAppearingInTarget.join(', '),
            ),
      if (preview.layerNamesAppearingInOrigin.isNotEmpty)
        strings.convertLinkedCutOriginGainsTemplate.replaceAll(
          '{names}',
          preview.layerNamesAppearingInOrigin.join(', '),
        ),
      if (!preview.linksAnything) strings.convertLinkedCutNothing,
      // Sizes first: linking makes the two show ONE picture, and the
      // origin's size wins — the target's artwork can land outside the
      // frame if they disagree.
      if (preview.linksAnything && preview.canvasSizesDiffer)
        strings.convertLinkedCutResizeFirst,
      if (preview.linksAnything) strings.convertLinkedCutUndoNote,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              line,
              key: ValueKey<String>('convert-linked-cut-line-$line'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
