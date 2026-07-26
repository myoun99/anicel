import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/canvas_size.dart';
import '../../models/export_cel_naming.dart';
import '../../models/export_format_selection.dart';
import '../../models/export_size_mode.dart';
import '../../models/export_spec.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';

/// Compact building blocks of the export window's settings column (v10):
/// one accordion grammar, chip pickers, and the shared Format module.
/// Everything is stateless and callback-driven — the dialog owns the spec.

const exportModuleGap = 6.0;
const _chipPadding = EdgeInsets.symmetric(horizontal: 7, vertical: 2);

/// A settings-column accordion: `Title — value summary` when collapsed,
/// title + optional Reset chip when open. Selection/emphasis is color
/// only (no checkmarks — house rule).
class ExportAccordion extends StatelessWidget {
  const ExportAccordion({
    super.key,
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.resetEnabled,
    this.onReset,
  });

  final String title;
  final String summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  /// Non-null shows the header Reset chip (disabled while the module sits
  /// at its defaults — the v10 Reset grammar).
  final bool? resetEnabled;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      expanded ? title : '$title — $summary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: expanded ? null : dim,
                        fontWeight: expanded
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (resetEnabled != null) ...[
                    _ResetChip(enabled: resetEnabled!, onPressed: onReset),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: dim,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _ResetChip extends StatelessWidget {
  const _ResetChip({required this.enabled, this.onPressed});

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.onSurface
        : theme.disabledColor.withValues(alpha: 0.4);
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled ? theme.dividerColor : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Reset',
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

/// One compact selectable chip (the picker unit). Selection = accent
/// border + soft fill, color only.
class ExportChip extends StatelessWidget {
  const ExportChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: _chipPadding,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : null,
          border: Border.all(
            color: selected ? accent : theme.dividerColor,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: disabled
                ? theme.disabledColor
                : selected
                ? accent
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class ExportModuleRow extends StatelessWidget {
  const ExportModuleRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

Widget exportModuleNote(BuildContext context, String text) => Text(
  text,
  style: Theme.of(context).textTheme.bodySmall?.copyWith(
    fontSize: 10.5,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
);

/// What the Format module offers in a tab: the LINEUP (v10 — every chip
/// shows), with per-chip enablement + reason from the machine's actual
/// encoders. A grayed chip says why on hover; nothing fails only at
/// Export.
class ExportFormatCapabilities {
  const ExportFormatCapabilities({
    required this.stills,
    this.video = const {},
    this.stillEnabled,
    this.videoEnabled,
    this.videoReason,
  });

  final List<ExportStillFormat> stills;
  final Map<ExportVideoContainer, List<ExportVideoCodec>> video;

  /// Null = everything in the lineup is writable (the EX2 behavior).
  final bool Function(ExportStillFormat format)? stillEnabled;
  final bool Function(ExportVideoContainer container, ExportVideoCodec codec)?
      videoEnabled;
  final String? Function(
    ExportVideoContainer container,
    ExportVideoCodec codec,
  )? videoReason;

  bool get hasVideo => video.isNotEmpty;

  List<ExportVideoCodec> codecsFor(ExportVideoContainer container) =>
      video[container] ?? const [];

  bool isStillEnabled(ExportStillFormat format) =>
      stillEnabled?.call(format) ?? true;

  bool isVideoEnabled(ExportVideoContainer container, ExportVideoCodec codec) =>
      videoEnabled?.call(container, codec) ?? true;

  /// A container chip stays live while ANY of its codecs does.
  bool isContainerEnabled(ExportVideoContainer container) {
    for (final codec in codecsFor(container)) {
      if (isVideoEnabled(container, codec)) {
        return true;
      }
    }
    return false;
  }

  String? reasonFor(ExportVideoContainer container, ExportVideoCodec codec) =>
      videoReason?.call(container, codec);
}

/// The shared Format module (v10: 포맷·코덱·세부가 한 몸). Renders the
/// grouped Video/Image picker plus the detail rows the current choice
/// needs; [capabilities] filters what the build can actually write.
class ExportFormatModule extends StatelessWidget {
  const ExportFormatModule({
    super.key,
    required this.selection,
    required this.capabilities,
    required this.enabled,
    required this.onChanged,
  });

  final ExportFormatSelection selection;
  final ExportFormatCapabilities capabilities;
  final bool enabled;
  final ValueChanged<ExportFormatSelection> onChanged;

  static String summarize(ExportFormatSelection selection) {
    if (selection.isVideo) {
      return '${selection.container.label} · ${selection.videoCodec.label}';
    }
    final channels = selection.effectiveChannels == ExportChannels.rgba
        ? 'RGBA'
        : 'RGB';
    if (selection.stillFormat == ExportStillFormat.jpg) {
      return 'JPG · ${selection.jpgQuality}';
    }
    return '${selection.stillFormat.label} · $channels';
  }

  void _change(ExportFormatSelection next) {
    if (enabled) {
      onChanged(next);
    }
  }

  Widget _maybeTooltip(String? reason, Widget chip) =>
      reason == null ? chip : Tooltip(message: reason, child: chip);

  @override
  Widget build(BuildContext context) {
    final containers = capabilities.video.keys.toList();
    final codecs = selection.isVideo
        ? capabilities.codecsFor(selection.container)
        : const <ExportVideoCodec>[];
    final showChannels =
        selection.isStill && selection.stillFormat.supportsAlpha;
    final showBackground =
        selection.isStill &&
        selection.effectiveChannels == ExportChannels.rgb;
    final showBitrate = selection.isVideo && !selection.videoCodec.isProRes;
    final showQuality =
        selection.isStill && selection.stillFormat == ExportStillFormat.jpg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (capabilities.hasVideo)
          ExportModuleRow(
            label: AppText.strings.exVideo,
            child: Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                for (final container in containers)
                  _maybeTooltip(
                    capabilities.isContainerEnabled(container)
                        ? null
                        : capabilities.reasonFor(
                            container,
                            capabilities.codecsFor(container).first,
                          ),
                    ExportChip(
                      key: ValueKey<String>(
                        'export-format-container-${container.jsonValue}',
                      ),
                      label: container.label,
                      selected: selection.isVideo &&
                          selection.container == container,
                      onTap: enabled &&
                              capabilities.isContainerEnabled(container)
                          ? () {
                              // Land on that container's first WRITABLE
                              // codec when the current one is off there.
                              var next = selection.copyWith(
                                kind: ExportMediaKind.video,
                                container: container,
                              );
                              if (!capabilities.isVideoEnabled(
                                container,
                                next.videoCodec,
                              )) {
                                for (final codec
                                    in capabilities.codecsFor(container)) {
                                  if (capabilities.isVideoEnabled(
                                    container,
                                    codec,
                                  )) {
                                    next =
                                        next.copyWith(videoCodec: codec);
                                    break;
                                  }
                                }
                              }
                              _change(next);
                            }
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ExportModuleRow(
          label: AppText.strings.exImage,
          child: Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              for (final still in capabilities.stills)
                _maybeTooltip(
                  capabilities.isStillEnabled(still)
                      ? null
                      : 'Not available in this build yet.',
                  ExportChip(
                    key: ValueKey<String>(
                      'export-format-still-${still.jsonValue}',
                    ),
                    label: still.label,
                    selected: selection.isStill &&
                        selection.stillFormat == still,
                    onTap: enabled && capabilities.isStillEnabled(still)
                        ? () => _change(
                            selection.copyWith(
                              kind: ExportMediaKind.still,
                              stillFormat: still,
                            ),
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (selection.isVideo && codecs.length > 1)
          ExportModuleRow(
            label: AppText.strings.exCodec,
            child: Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                for (final codec in codecs)
                  _maybeTooltip(
                    capabilities.isVideoEnabled(selection.container, codec)
                        ? null
                        : capabilities.reasonFor(selection.container, codec),
                    ExportChip(
                      key: ValueKey<String>(
                        'export-format-codec-${codec.jsonValue}',
                      ),
                      label: codec.label,
                      selected: selection.videoCodec == codec,
                      onTap: enabled &&
                              capabilities.isVideoEnabled(
                                selection.container,
                                codec,
                              )
                          ? () =>
                              _change(selection.copyWith(videoCodec: codec))
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        if (showBitrate)
          ExportModuleRow(
            label: AppText.strings.exBitrate,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const ValueKey<String>('export-format-bitrate'),
                    value: selection.videoBitrateMbps
                        .clamp(0, 50)
                        .toDouble(),
                    max: 50,
                    divisions: 50,
                    onChanged: enabled
                        ? (value) => _change(
                            selection.copyWith(
                              videoBitrateMbps: value.round(),
                            ),
                          )
                        : null,
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    selection.videoBitrateMbps <= 0
                        ? 'Auto'
                        : '${selection.videoBitrateMbps} Mb',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        if (showQuality)
          ExportModuleRow(
            label: AppText.strings.exQuality,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const ValueKey<String>('export-format-quality'),
                    value: selection.jpgQuality.clamp(1, 100).toDouble(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    onChanged: enabled
                        ? (value) => _change(
                            selection.copyWith(jpgQuality: value.round()),
                          )
                        : null,
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${selection.jpgQuality}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        if (showChannels)
          ExportModuleRow(
            label: AppText.strings.exChannels,
            child: Wrap(
              spacing: 5,
              children: [
                ExportChip(
                  key: const ValueKey<String>('export-format-channels-rgba'),
                  label: 'RGBA',
                  selected:
                      selection.effectiveChannels == ExportChannels.rgba,
                  onTap: enabled
                      ? () => _change(
                          selection.copyWith(channels: ExportChannels.rgba),
                        )
                      : null,
                ),
                ExportChip(
                  key: const ValueKey<String>('export-format-channels-rgb'),
                  label: 'RGB',
                  selected: selection.effectiveChannels == ExportChannels.rgb,
                  onTap: enabled
                      ? () => _change(
                          selection.copyWith(channels: ExportChannels.rgb),
                        )
                      : null,
                ),
              ],
            ),
          ),
        if (showBackground)
          ExportModuleRow(
            label: 'BG',
            child: Wrap(
              spacing: 5,
              children: [
                ExportChip(
                  key: const ValueKey<String>('export-format-bg-white'),
                  label: AppText.strings.exWhite,
                  selected: selection.backgroundArgb == 0xFFFFFFFF,
                  onTap: enabled
                      ? () =>
                          _change(selection.copyWith(backgroundArgb: 0xFFFFFFFF))
                      : null,
                ),
                ExportChip(
                  key: const ValueKey<String>('export-format-bg-black'),
                  label: AppText.strings.exBlack,
                  selected: selection.backgroundArgb == 0xFF000000,
                  onTap: enabled
                      ? () =>
                          _change(selection.copyWith(backgroundArgb: 0xFF000000))
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The Scope module: Cut/Project chips plus an optional tab-specific body
/// (Sequence's in/out fields, the Cels/Timesheet cut grid later).
class ExportScopeModule extends StatelessWidget {
  const ExportScopeModule({
    super.key,
    required this.scope,
    required this.enabled,
    required this.onChanged,
    this.note,
    this.child,
  });

  final ExportScopeKind scope;
  final bool enabled;
  final ValueChanged<ExportScopeKind> onChanged;
  final String? note;
  final Widget? child;

  static String summarize(ExportScopeKind scope) =>
      scope == ExportScopeKind.cut ? 'Cut' : 'Project';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          children: [
            ExportChip(
              key: const ValueKey<String>('export-scope-cut'),
              label: AppText.strings.exCut,
              selected: scope == ExportScopeKind.cut,
              onTap: enabled ? () => onChanged(ExportScopeKind.cut) : null,
            ),
            ExportChip(
              key: const ValueKey<String>('export-scope-project'),
              label: AppText.strings.exProject,
              selected: scope == ExportScopeKind.project,
              onTap: enabled ? () => onChanged(ExportScopeKind.project) : null,
            ),
          ],
        ),
        if (child != null) ...[const SizedBox(height: 6), child!],
        if (note != null) ...[
          const SizedBox(height: 5),
          exportModuleNote(context, note!),
        ],
      ],
    );
  }
}

/// The Size module with the v10 coupling: a project scope forces the
/// camera frame (per-cut canvases cannot make one movie), so the Canvas
/// chip only exists under the cut scope.
class ExportSizeModule extends StatelessWidget {
  const ExportSizeModule({
    super.key,
    required this.sizeMode,
    required this.cameraSize,
    required this.canvasSizes,
    required this.projectScope,
    required this.enabled,
    required this.onChanged,
  });

  final ExportSizeMode sizeMode;
  final CanvasSize cameraSize;
  final Set<CanvasSize> canvasSizes;
  final bool projectScope;
  final bool enabled;
  final ValueChanged<ExportSizeMode> onChanged;

  static String summarize(ExportSizeMode mode) =>
      mode == ExportSizeMode.camera ? 'Camera' : 'Canvas';

  @override
  Widget build(BuildContext context) {
    final canvasLabel = canvasSizes.length == 1
        ? 'Canvas ${canvasSizes.first.width}×${canvasSizes.first.height}'
        : 'Canvas (per cut)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: [
            ExportChip(
              key: const ValueKey<String>('export-size-camera'),
              label: 'Camera ${cameraSize.width}×${cameraSize.height}',
              selected: sizeMode == ExportSizeMode.camera,
              onTap: enabled ? () => onChanged(ExportSizeMode.camera) : null,
            ),
            if (!projectScope)
              ExportChip(
                key: const ValueKey<String>('export-size-canvas'),
                label: canvasLabel,
                selected: sizeMode == ExportSizeMode.canvas,
                onTap: enabled
                    ? () => onChanged(ExportSizeMode.canvas)
                    : null,
              ),
          ],
        ),
        if (projectScope) ...[
          const SizedBox(height: 5),
          exportModuleNote(
            context,
            'Canvas is cut-scope only (cuts size their canvases freely).',
          ),
        ],
      ],
    );
  }
}

/// A compact labelled switch row (the module toggle grammar).
class ExportToggleRow extends StatelessWidget {
  const ExportToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.widgetKey,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? widgetKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            height: 24,
            child: FittedBox(
              child: Switch(
                key: widgetKey,
                value: value,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, style: theme.textTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

/// Sequence numbering: `<base>_0001.<ext>`.
class ExportSequenceNamingModule extends StatelessWidget {
  const ExportSequenceNamingModule({
    super.key,
    required this.naming,
    required this.enabled,
    required this.onChanged,
    required this.baseNameController,
  });

  final ExportSequenceNaming naming;
  final bool enabled;
  final ValueChanged<ExportSequenceNaming> onChanged;
  final TextEditingController baseNameController;

  static String summarize(ExportSequenceNaming naming, String extension) =>
      '${naming.baseName}_${'1'.padLeft(naming.digits, '0')}.$extension';

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: AppWindowField(
            label: AppText.strings.exBaseName,
            child: TextField(
              key: const ValueKey<String>('export-naming-base-field'),
              controller: baseNameController,
              enabled: enabled,
              onChanged: (value) => onChanged(
                naming.copyWith(
                  baseName: value.trim().isEmpty ? 'frame' : value.trim(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: _DigitsField(
            widgetKey: const ValueKey<String>('export-naming-digits-field'),
            digits: naming.digits,
            enabled: enabled,
            onChanged: (digits) => onChanged(naming.copyWith(digits: digits)),
          ),
        ),
      ],
    );
  }
}

class _DigitsField extends StatefulWidget {
  const _DigitsField({
    required this.digits,
    required this.enabled,
    required this.onChanged,
    this.widgetKey,
  });

  final int digits;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final Key? widgetKey;

  @override
  State<_DigitsField> createState() => _DigitsFieldState();
}

class _DigitsFieldState extends State<_DigitsField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.digits}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppWindowField(
      label: AppText.strings.exDigits,
      child: TextField(
        key: widget.widgetKey,
        controller: _controller,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (value) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null) {
            widget.onChanged(parsed);
          }
        },
      ),
    );
  }
}

/// Cel-file naming: the CSP-style options ported into the module grammar.
class ExportCelNamingModule extends StatelessWidget {
  const ExportCelNamingModule({
    super.key,
    required this.naming,
    required this.enabled,
    required this.onChanged,
    required this.suffixController,
  });

  final ExportCelNaming naming;
  final bool enabled;
  final ValueChanged<ExportCelNaming> onChanged;
  final TextEditingController suffixController;

  static String summarize(ExportCelNaming naming) {
    final parts = <String>[
      if (naming.includeProjectName) 'proj',
      if (naming.includeCutName) 'cut',
      if (naming.includeLayerName) 'layer',
    ];
    final folders = <String>[
      if (naming.cutFolder) 'cut/',
      if (naming.layerFolder) 'layer/',
    ];
    return [
      parts.isEmpty ? 'frame' : parts.join('_'),
      if (naming.frameDigits > 0) '${naming.frameDigits}d',
      if (folders.isNotEmpty) folders.join(''),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: [
            ExportChip(
              key: const ValueKey<String>('export-cel-include-project'),
              label: AppText.strings.exProjectName,
              selected: naming.includeProjectName,
              onTap: enabled
                  ? () => onChanged(
                      naming.copyWith(
                        includeProjectName: !naming.includeProjectName,
                      ),
                    )
                  : null,
            ),
            ExportChip(
              key: const ValueKey<String>('export-cel-include-cut'),
              label: AppText.strings.renameCutField,
              selected: naming.includeCutName,
              onTap: enabled
                  ? () => onChanged(
                      naming.copyWith(includeCutName: !naming.includeCutName),
                    )
                  : null,
            ),
            ExportChip(
              key: const ValueKey<String>('export-cel-include-layer'),
              label: AppText.strings.renameLayerField,
              selected: naming.includeLayerName,
              onTap: enabled
                  ? () => onChanged(
                      naming.copyWith(
                        includeLayerName: !naming.includeLayerName,
                      ),
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 64,
              child: _DigitsField(
                widgetKey: const ValueKey<String>('export-cel-digits-field'),
                digits: naming.frameDigits,
                enabled: enabled,
                onChanged: (digits) =>
                    onChanged(naming.copyWith(frameDigits: digits)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppWindowField(
                label: AppText.strings.exSuffix,
                child: TextField(
                  key: const ValueKey<String>('export-cel-suffix-field'),
                  controller: suffixController,
                  enabled: enabled,
                  onChanged: (value) =>
                      onChanged(naming.copyWith(suffix: value.trim())),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 5,
          children: [
            ExportChip(
              key: const ValueKey<String>('export-cel-cut-folder'),
              label: AppText.strings.exCutFolder,
              selected: naming.cutFolder,
              onTap: enabled
                  ? () => onChanged(
                      naming.copyWith(cutFolder: !naming.cutFolder),
                    )
                  : null,
            ),
            ExportChip(
              key: const ValueKey<String>('export-cel-layer-folder'),
              label: AppText.strings.exLayerFolder,
              selected: naming.layerFolder,
              onTap: enabled
                  ? () => onChanged(
                      naming.copyWith(layerFolder: !naming.layerFolder),
                    )
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
