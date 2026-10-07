import 'package:flutter/material.dart';

import '../../models/cut_id.dart';
import '../../services/commands/convert_to_linked_cut_plan.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import 'app_confirm_dialog.dart';

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
    final keys = confirmDialogKeys('convert-linked-cut');
    final targetCutId = _targetCutId;
    final target = widget.candidates
        .where((candidate) => candidate.id == targetCutId)
        .firstOrNull;
    final preview = targetCutId == null ? null : widget.previewOf(targetCutId);
    final strings = AppText.strings;
    return AppWindow(
      windowKey: keys.window,
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
            child: PanelFlyoutButton(
              key: const ValueKey<String>('convert-linked-cut-target'),
              label: target?.name ?? '',
              expand: true,
              entriesBuilder: () => widget.candidates.asFlyoutValueChoices(
                current: target,
                choiceOf: (candidate) => PanelFlyoutChoice(
                  key: 'convert-linked-cut-target-${candidate.id.value}',
                  label: candidate.name,
                ),
                onPicked: (candidate) =>
                    setState(() => _targetCutId = candidate.id),
              ),
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
          actionKey: keys.decline,
          onPressed: () => Navigator.of(context).pop(null),
        ),
        AppWindowAction(
          label: strings.commonLink,
          actionKey: keys.accept,
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

  /// One line of the 안내문.
  Widget _line(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      key: ValueKey<String>('convert-linked-cut-line-$text'),
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );

  /// Names the 안내문 is about, in the notices' own fold under the heading
  /// that says what they are — open, as [_replaced]'s are.
  ///
  /// 🗣️F-303 (유저 2026-10-06): 「ui 공용 리스트화 사용안하는거 연결」.
  /// ↩️Three lines of this window joined their names into a sentence
  /// (「Links A, B.」, 「"2" gains: …」, 「This cut gains: …」) beside the one
  /// list I-18 had already made of the drawings it replaces.
  Widget _listed(String heading, List<String> names) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: DetailsDisclosure(heading: heading, lines: names, startsOpen: true),
  );

  /// 원본 승리, announced up front (user-confirmed rule): the origin's
  /// picture wins each same-name conflict, exactly once, undoable.
  ///
  /// 🗣️I-18 link-notice-Q1 (유저): 「겸용 변환 안내문을 목록으로」 — the
  /// drawings it replaces are LISTED under the sentence, in the notices' own
  /// fold, open: which ones is what the line is about.
  List<Widget> _replaced(BuildContext context) => [
    if (preview.replacedDrawings.isNotEmpty) ...[
      _line(
        context,
        AppText.strings.convertLinkedCutReplacedTemplate.replaceAll(
          '{cut}',
          preview.targetCutName,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: DetailsDisclosure(
          heading: AppText.strings.convertLinkedCutReplacedHeading,
          lines: preview.replacedDrawings,
          startsOpen: true,
        ),
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    Widget line(String text) => _line(context, text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview.linkingLayerNames.isNotEmpty)
          _listed(
            strings.convertLinkedCutLinksHeading,
            preview.linkingLayerNames,
          ),
        ..._replaced(context),
        if (preview.joiningFrameCount > 0)
          line(
            strings.convertLinkedCutJoiningTemplate.replaceAll(
              '{count}',
              '${preview.joiningFrameCount}',
            ),
          ),
        if (preview.layerNamesAppearingInTarget.isNotEmpty)
          _listed(
            strings.convertLinkedCutTargetGainsHeadingTemplate.replaceAll(
              '{cut}',
              preview.targetCutName,
            ),
            preview.layerNamesAppearingInTarget,
          ),
        if (preview.layerNamesAppearingInOrigin.isNotEmpty)
          _listed(
            strings.convertLinkedCutOriginGainsHeading,
            preview.layerNamesAppearingInOrigin,
          ),
        if (!preview.linksAnything) line(strings.convertLinkedCutNothing),
        // Sizes first: linking makes the two show ONE picture, and the
        // origin's size wins — the target's artwork can land outside the
        // frame if they disagree.
        if (preview.linksAnything && preview.canvasSizesDiffer)
          line(strings.convertLinkedCutResizeFirst),
        if (preview.linksAnything) line(strings.convertLinkedCutUndoNote),
      ],
    );
  }
}
