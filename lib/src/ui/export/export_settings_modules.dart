import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../text/full_width_numerals.dart';

import '../../models/canvas_size.dart';
import '../../models/export_cel_naming.dart';
import '../../models/export_format_selection.dart';
import '../../models/export_size_mode.dart';
import '../../models/export_spec.dart';
import '../../models/layer_mark.dart';
import '../theme/app_theme.dart';
import '../timeline/layer_label_controls.dart' show layerMarkChipText;
import '../widgets/app_window.dart';
import '../text/app_strings.dart';
import '../text/pixel_size_label.dart';
import '../text/text_measure.dart';
import '../input/control_press_claim.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';

/// Compact building blocks of the export window's settings column (v10):
/// one accordion grammar, pill strips, and the shared Format module.
/// Everything is stateless and callback-driven — the dialog owns the spec.

const exportModuleGap = 6.0;

/// A settings-column accordion: `Title — value summary` when collapsed,
/// title + optional Reset chip when open. Selection/emphasis is color
/// only (no checkmarks — house rule).
class ExportAccordion extends StatelessWidget {
  const ExportAccordion({
    super.key,
    required this.title,
    required this.summary,
    required this.expansion,
    required this.child,
    this.reset,
  });

  final String title;
  final String summary;

  /// Whether the module is open, and what opens or closes it — ONE value,
  /// because they are answered by one state key and the dialog used to
  /// write that key twice per accordion.
  final ({bool expanded, VoidCallback onToggle}) expansion;

  final Widget child;

  /// Non-null shows the header Reset chip (disabled while the module sits
  /// at its defaults — the v10 Reset grammar). Enabled-ness and the action
  /// travel together because neither means anything alone.
  final ({bool enabled, VoidCallback onTap})? reset;

  bool get expanded => expansion.expanded;
  VoidCallback get onToggle => expansion.onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return Container(
      decoration: ShapeDecoration(
        shape: AppShapes.container(
          5,
          side: BorderSide(color: theme.dividerColor),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ControlPressClaim(
            onPressed: onToggle,
            child: InkWell(
              mouseCursor: AppCursors.press,
              onTap: silentPress(onToggle),
              child: Container(
                color: AppColors.washUp.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        // A module holding nothing yet says only its name —
                        // not a dash with nothing after it.
                        expanded || summary.isEmpty
                            ? title
                            : '$title — $summary',
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
                    if (reset != null) ...[
                      ExportResetChip(
                        enabled: reset!.enabled,
                        onPressed: reset!.onTap,
                      ),
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

/// 「초기화」 at the head of a module, and of the Cels list's rules: off —
/// dim, taking no press — while there is nothing to put back.
class ExportResetChip extends StatelessWidget {
  const ExportResetChip({super.key, required this.enabled, this.onPressed});

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.onSurface
        : theme.disabledColor.withValues(alpha: 0.4);
    return ControlPressClaim(
      onPressed: enabled ? onPressed : null,
      child: InkWell(
        mouseCursor: AppCursors.press,
        onTap: silentPress(enabled ? onPressed : null),
        customBorder: AppShapes.container(AppShapes.wellRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: ShapeDecoration(
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: BorderSide(
                color: enabled ? theme.dividerColor : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            AppText.strings.commonReset,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}

/// A row name of the settings column — every name a row there can give, so
/// the column of names is as wide as the widest of them in the program's
/// language ([ExportModuleRow.captionWidthIn]): a row that shows only for
/// one format or inside a folded accordion counts as much as one that
/// shows, so no row moves another's control when it comes.
enum ExportCaption {
  format,
  codec,
  bitrate,
  quality,
  channels,
  background,
  image,
  paper,
  layerFx,
  target,
  folders,
  nameParts,
  prefix;

  String wordsIn(AppStrings strings) => switch (this) {
    format => strings.exFormat,
    codec => strings.exCodec,
    bitrate => strings.exBitrate,
    quality => strings.exQuality,
    channels => strings.exChannels,
    background => strings.exBackground,
    image => strings.exImage,
    paper => strings.exPaperLabel,
    layerFx => strings.exApplyLayerFx,
    target => strings.exTarget,
    folders => strings.exFolders,
    nameParts => strings.exNameParts,
    prefix => strings.exPrefix,
  };
}

class ExportModuleRow extends StatelessWidget {
  const ExportModuleRow({
    super.key,
    required this.caption,
    required this.child,
  }) : _strip = false;

  /// A row whose control is a strip of pills: beside its caption where the
  /// strip's words fit there, under it where they do not — every pill as
  /// wide as its word either way.
  ///
  /// 🗣️F-486 (유저 2026-10-27): 「출력창 버튼들 자동맞춤해서 글자에 맞게
  /// 되도록」 — beside 「Papier」 the cut envelope's 「Taille du plan · Feuille
  /// réelle」 both gave their words up.
  const ExportModuleRow.strip({
    super.key,
    required this.caption,
    required PillStrip strip,
  }) : child = strip,
       _strip = true;

  final ExportCaption caption;
  final Widget child;

  /// Whether [child] is a strip that goes under the caption when it does
  /// not fit beside it ([ExportModuleRow.strip]).
  final bool _strip;

  /// The column of row names: as wide as the widest name the column can
  /// give ([ExportCaption]) where this [context] lays text out, so every
  /// control starts at one x and every name is whole.
  ///
  /// 🗣️F-486-Q1 (유저 2026-10-27): 「칸 이름만 맞춘다」. ↩️54 in every
  /// language — the Korean's longest (「폴더 생성」, 「이름 지정」) — so
  /// 「ビットレート」 and 「Channels」 gave their ends up.
  static double captionWidthIn(BuildContext context) {
    final words = TextMeasure(
      context,
      DefaultTextStyle.of(context).style.merge(_wordStyleOf(Theme.of(context))),
    );
    final strings = AppText.strings;
    return ExportCaption.values
        .map((caption) => words.size(caption.wordsIn(strings)).width)
        .reduce(math.max);
  }

  static TextStyle? _wordStyleOf(ThemeData theme) =>
      theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );

  @override
  Widget build(BuildContext context) {
    final name = SizedBox(
      width: captionWidthIn(context),
      child: Text(
        caption.wordsIn(AppText.strings),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _wordStyleOf(Theme.of(context)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: _strip
          ? Wrap(
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [name, child],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [name, Expanded(child: child)],
            ),
    );
  }
}

/// How the export names a colour label in a button or a summary: the
/// plate's two abbreviations as one reading (「원화 작감」), 「라벨 없음」 for
/// none. The rail's plate writes the same two texts in its two columns.
String exportCelLabelText(LayerMark label) {
  if (label.isNone) {
    return AppText.strings.tlLayerMarkNone;
  }
  final chip = layerMarkChipText(label);
  return [chip.process, chip.revise].where((t) => t.isNotEmpty).join(' ');
}

/// The 선택 filters that are on, read as one line — 「기준 · 어태치」,
/// 「어태치 · 시트」 — for a preset's summary. A dash when none is on (the
/// export then writes only what 추가 adds).
String exportCelFilterSummary(CelsExportSpec spec) {
  final strings = AppText.strings;
  final on = [
    if (spec.base) strings.exSelBase,
    if (spec.attach) strings.exSelAttach,
    if (spec.sheetOnly) strings.exSelSheet,
  ];
  return on.isEmpty ? '—' : on.join(' · ');
}

/// A labelled row offering one pill per VALUE of a choice.
///
/// 🚨ONE LAW FOR EVERY PICKER ROW (the audit's clone scan, round 8): a
/// pill keyed `<keyPrefix>-<keyOf(value)>`, labelled from [labelOf],
/// shown selected by comparing the value with [selected], and selecting
/// it on tap. Seven rows across the export, import and text-cel windows
/// spelled that out by hand, and the key naming and selection-by-colour
/// were promises each of them kept on its own.
///
/// ⛔[enabledFor] refuses a VALUE, it does not hide it: the pill keeps its
/// place and loses its tap (「없다가 생기는 UI 금지」).
class ExportChoiceRow<T> extends StatelessWidget {
  const ExportChoiceRow({
    super.key,
    required this.caption,
    required this.keyPrefix,
    required this.values,
    required this.selected,
    required this.keyOf,
    required this.labelOf,
    required this.onSelect,
    this.enabledFor,
  });

  final ExportCaption caption;

  /// The pills are keyed `<keyPrefix>-<keyOf(value)>` — tests reach for
  /// those strings, so the prefix is part of the row's contract.
  final String keyPrefix;

  final List<T> values;
  final T selected;
  final String Function(T value) keyOf;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelect;

  /// Null offers every value.
  final bool Function(T value)? enabledFor;

  @override
  Widget build(BuildContext context) => ExportModuleRow.strip(
    caption: caption,
    strip: PillStrip(
      items: [
        for (final value in values)
          PillItem(
            keyValue: '$keyPrefix-${keyOf(value)}',
            label: labelOf(value),
            selected: value == selected,
            onTap: enabledFor?.call(value) == false
                ? null
                : () => onSelect(value),
          ),
      ],
    ),
  );
}


/// What the Format module offers in a tab: the LINEUP (v10 — every pill
/// shows), with per-pill enablement + reason from the machine's actual
/// encoders. A grayed pill says why on hover; nothing fails only at
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
  )?
  videoReason;

  bool get hasVideo => video.isNotEmpty;

  List<ExportVideoCodec> codecsFor(ExportVideoContainer container) =>
      video[container] ?? const [];

  bool isStillEnabled(ExportStillFormat format) =>
      stillEnabled?.call(format) ?? true;

  bool isVideoEnabled(ExportVideoContainer container, ExportVideoCodec codec) =>
      videoEnabled?.call(container, codec) ?? true;

  /// A container pill stays live while ANY of its codecs does.
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

  /// 형식: what the file is, picked from the app's one value list as the
  /// codec is — first 동영상 or 이미지 where the tab writes both, then the
  /// format beside it.
  ///
  /// 🗣️I-117 (유저 2026-10-21): 「형식 많아질테니 형식고르는건 기본적으로
  /// 출력창에서 코덱 고르듯이 리스트팝오버로. 동영상이랑 이미지 둘다있으면
  /// 먼저 둘중하나 리스트팝오버로 고르고, 그 옆에 해당에 맞는 팝오버 버튼
  /// 뜸」. ↩️Two pill rows, 「동영상」 MP4 · MOV and 「이미지」 PNG · JPG · PSD —
  /// seven still formats do not fit one.
  ///
  /// The format button stands whichever kind is chosen: what it lists is
  /// what changes.
  Widget _formatRow() => ExportModuleRow(
    caption: ExportCaption.format,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (capabilities.hasVideo) ...[
            _kindButton(),
            const SizedBox(width: 4),
          ],
          if (selection.isVideo) _containerButton() else _stillButton(),
        ],
      ),
    ),
  );

  static String _kindLabel(ExportMediaKind kind) => switch (kind) {
    ExportMediaKind.video => AppText.strings.exVideo,
    ExportMediaKind.still => AppText.strings.exImage,
  };

  /// Whether [kind] has a format this build can write.
  bool _kindWritable(ExportMediaKind kind) => switch (kind) {
    ExportMediaKind.video => capabilities.video.keys.any(
      capabilities.isContainerEnabled,
    ),
    ExportMediaKind.still => capabilities.stills.any(
      capabilities.isStillEnabled,
    ),
  };

  Widget _kindButton() => PanelFlyoutButton(
    key: const ValueKey<String>('export-format-kind'),
    label: _kindLabel(selection.kind),
    enabled: enabled,
    entriesBuilder: () => ExportMediaKind.values.asFlyoutValueChoices(
      current: selection.kind,
      choiceOf: (kind) => PanelFlyoutChoice(
        key: 'export-format-kind-${kind.jsonValue}',
        label: _kindLabel(kind),
        enabled: _kindWritable(kind),
        warning: _kindWritable(kind)
            ? null
            : AppText.strings.exNotInThisBuild,
      ),
      onPicked: (kind) => _change(_withKind(kind)),
    ),
  );

  /// [kind], landing on the format that kind last stood on — or, when that
  /// one is off in this build, the first one that is on.
  ExportFormatSelection _withKind(ExportMediaKind kind) {
    if (kind == ExportMediaKind.video) {
      final container = capabilities.isContainerEnabled(selection.container)
          ? selection.container
          : capabilities.video.keys.firstWhere(
              capabilities.isContainerEnabled,
              orElse: () => selection.container,
            );
      return _withContainer(container);
    }
    final still = capabilities.isStillEnabled(selection.stillFormat)
        ? selection.stillFormat
        : capabilities.stills.firstWhere(
            capabilities.isStillEnabled,
            orElse: () => selection.stillFormat,
          );
    return selection.copyWith(kind: kind, stillFormat: still);
  }

  /// The containers. Choosing one lands on that container's first WRITABLE
  /// codec when the current one is off there — picking MOV must not leave a
  /// codec selected that MOV cannot hold.
  Widget _containerButton() => PanelFlyoutButton(
    key: const ValueKey<String>('export-format-file'),
    label: selection.container.label,
    enabled: enabled,
    entriesBuilder: () => capabilities.video.keys.asFlyoutValueChoices(
      current: selection.container,
      choiceOf: (container) {
        final writable = capabilities.isContainerEnabled(container);
        return PanelFlyoutChoice(
          key: 'export-format-container-${container.jsonValue}',
          label: container.label,
          enabled: writable,
          warning: writable
              ? null
              : capabilities.reasonFor(
                  container,
                  capabilities.codecsFor(container).first,
                ),
        );
      },
      onPicked: (container) => _change(_withContainer(container)),
    ),
  );

  /// [container], with the codec moved to that container's first WRITABLE
  /// one when the selected codec is off there — picking MOV must not
  /// leave a codec selected that MOV cannot hold.
  ExportFormatSelection _withContainer(ExportVideoContainer container) {
    final next = selection.copyWith(
      kind: ExportMediaKind.video,
      container: container,
    );
    if (capabilities.isVideoEnabled(container, next.videoCodec)) {
      return next;
    }
    for (final codec in capabilities.codecsFor(container)) {
      if (capabilities.isVideoEnabled(container, codec)) {
        return next.copyWith(videoCodec: codec);
      }
    }
    return next;
  }

  Widget _stillButton() => PanelFlyoutButton(
    key: const ValueKey<String>('export-format-file'),
    label: selection.stillFormat.label,
    enabled: enabled,
    entriesBuilder: () => capabilities.stills.asFlyoutValueChoices(
      current: selection.stillFormat,
      choiceOf: (still) {
        final writable = capabilities.isStillEnabled(still);
        return PanelFlyoutChoice(
          key: 'export-format-still-${still.jsonValue}',
          label: still.label,
          enabled: writable,
          warning: writable ? null : AppText.strings.exNotInThisBuild,
        );
      },
      onPicked: (still) => _change(
        selection.copyWith(kind: ExportMediaKind.still, stillFormat: still),
      ),
    ),
  );

  /// The codec, picked from the app's one value list.
  ///
  /// 🗣️video-export-speed-Q1 (유저 2026-10-09): 「코덱을 팝오버로 보여서
  /// 그중에 고르게하도록」. ↩️It was a pill strip, and MOV's six shared the
  /// settings column's row at some 30px each — every name cut to an
  /// ellipsis (실측 10-05).
  Widget _codecRow(List<ExportVideoCodec> codecs) => ExportModuleRow(
    caption: ExportCaption.codec,
    child: Align(
      alignment: Alignment.centerLeft,
      child: PanelFlyoutButton(
        key: const ValueKey<String>('export-format-codec'),
        label: selection.videoCodec.label,
        enabled: enabled,
        entriesBuilder: () => codecs.asFlyoutValueChoices(
          current: selection.videoCodec,
          choiceOf: (codec) {
            final writable = capabilities.isVideoEnabled(
              selection.container,
              codec,
            );
            return PanelFlyoutChoice(
              key: 'export-format-codec-${codec.jsonValue}',
              label: codec.label,
              enabled: writable,
              warning: writable
                  ? null
                  : capabilities.reasonFor(selection.container, codec),
            );
          },
          onPicked: (codec) => _change(selection.copyWith(videoCodec: codec)),
        ),
      ),
    ),
  );

  /// Zero is AUTO — the encoder picks — so the bar's low end is a word,
  /// not a number.
  static String _bitrateText(double mbps, String derived) =>
      mbps <= 0 ? AppText.strings.exBitrateAuto : derived;

  Widget _bitrateRow() => ExportModuleRow(
    caption: ExportCaption.bitrate,
    child: FieldSlider(
      key: const ValueKey<String>('export-format-bitrate'),
      value: selection.videoBitrateMbps.clamp(0, 50).toDouble(),
      min: 0,
      max: 50,
      divisions: 50,
      unit: ' Mb',
      valueTextBuilder: _bitrateText,
      onChanged: enabled
          ? (next) =>
                _change(selection.copyWith(videoBitrateMbps: next.round()))
          : null,
    ),
  );

  Widget _qualityRow() => ExportJpgQualityRow(
    keyValue: 'export-format-quality',
    quality: selection.jpgQuality,
    onChanged: enabled
        ? (quality) => _change(selection.copyWith(jpgQuality: quality))
        : null,
  );

  Widget _channelsRow() => ExportChoiceRow<ExportChannels>(
    caption: ExportCaption.channels,
    keyPrefix: 'export-format-channels',
    values: ExportChannels.values,
    selected: selection.effectiveChannels,
    keyOf: (channels) => channels.jsonValue,
    labelOf: (channels) => channels.name.toUpperCase(),
    onSelect: (channels) => _change(selection.copyWith(channels: channels)),
    enabledFor: (_) => enabled,
  );

  Widget _backgroundRow() => ExportModuleRow.strip(
    caption: ExportCaption.background,
    strip: PillStrip(
      items: [
        PillItem(
          keyValue: 'export-format-bg-white',
          label: AppText.strings.exWhite,
          selected: selection.backgroundArgb == 0xFFFFFFFF,
          onTap: enabled
              ? () => _change(selection.copyWith(backgroundArgb: 0xFFFFFFFF))
              : null,
        ),
        PillItem(
          keyValue: 'export-format-bg-black',
          label: AppText.strings.exBlack,
          selected: selection.backgroundArgb == 0xFF000000,
          onTap: enabled
              ? () => _change(selection.copyWith(backgroundArgb: 0xFF000000))
              : null,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final codecs = selection.isVideo
        ? capabilities.codecsFor(selection.container)
        : const <ExportVideoCodec>[];
    final showChannels =
        selection.isStill && selection.stillFormat.supportsAlpha;
    final showBackground =
        selection.isStill && selection.effectiveChannels == ExportChannels.rgb;
    final showBitrate = selection.isVideo && !selection.videoCodec.isProRes;
    final showQuality =
        selection.isStill && selection.stillFormat == ExportStillFormat.jpg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formatRow(),
        if (selection.isVideo && codecs.length > 1) _codecRow(codecs),
        if (showBitrate) _bitrateRow(),
        if (showQuality) _qualityRow(),
        if (showChannels) _channelsRow(),
        if (showBackground) _backgroundRow(),
      ],
    );
  }
}

/// 품질: a JPG's quality, 1–100 — ONE row wherever a JPG is written, a cel
/// or a paper document.
class ExportJpgQualityRow extends StatelessWidget {
  const ExportJpgQualityRow({
    super.key,
    required this.keyValue,
    required this.quality,
    required this.onChanged,
  });

  final String keyValue;
  final int quality;

  /// Null while the window is busy.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    return ExportModuleRow(
      caption: ExportCaption.quality,
      child: FieldSlider(
        key: ValueKey<String>(keyValue),
        value: quality.clamp(1, 100).toDouble(),
        min: 1,
        max: 100,
        divisions: 99,
        onChanged: changed == null ? null : (next) => changed(next.round()),
      ),
    );
  }
}

/// What a PAPER DOCUMENT is written as — a timesheet's pages, a cut
/// envelope, the conte's page images: any still, JPG at a quality
/// ([paperDocumentFormat]; 유저 2026-10-05: 「시트 그리고 png말고 jpg도
/// 추가」 · I-117, 10-21: 「새 출력형식으로서 BMP TGA TIFF WEBP」, and a PSD
/// of its strata). A still this machine cannot write stays in the list,
/// off, saying why — the Format module's law ([stillEnabled]).
///
/// A document that has a format which is no picture — the timesheet's
/// digital sheet, the conte's PDF — offers it in the same list ([before] ·
/// [after]), and the picture formats are marked only while a picture is
/// what is written ([pictured]).
class ExportPaperFormatModule extends StatelessWidget {
  const ExportPaperFormatModule({
    super.key,
    required this.keyPrefix,
    required this.caption,
    required this.image,
    required this.onImageChanged,
    required this.stillEnabled,
    this.pictured = true,
    this.before = const [],
    this.after = const [],
  });

  /// Leads every key of the module: the list's button `<keyPrefix>-file`,
  /// its rows `-png`, `-jpg` …, and `-quality`.
  final String keyPrefix;
  final ExportCaption caption;
  final ExportFormatSelection image;

  /// A picture format, picked — or its quality, moved. Null while the
  /// window is busy.
  final ValueChanged<ExportFormatSelection>? onImageChanged;

  /// Whether this machine writes a still in a format — the answer the
  /// Format module's list is greyed by ([ExportFormatCapabilities]).
  final bool Function(ExportStillFormat format) stillEnabled;
  final bool pictured;
  final List<PillItem> before;
  final List<PillItem> after;

  static String summarize(ExportFormatSelection image) =>
      image.stillFormat == ExportStillFormat.jpg
      ? 'JPG · ${image.jpgQuality}'
      : image.stillFormat.label;

  /// The format the button names: the picture's while a picture is written,
  /// else the [before] or [after] format standing.
  String get _shown {
    if (pictured) {
      return image.stillFormat.label;
    }
    for (final item in [...before, ...after]) {
      if (item.selected) {
        return item.label;
      }
    }
    return image.stillFormat.label;
  }

  /// One list, as the Format module's is (I-117, 유저 2026-10-21: 「형식
  /// 고르는건 기본적으로 출력창에서 코덱 고르듯이 리스트팝오버로」) — the
  /// formats that are no picture where they stood, [before] and [after] the
  /// pictures. ↩️A pill strip: PNG · JPG between them.
  ///
  /// [before] and [after] come as the window's pills ([PillItem]), so they
  /// keep the window's law for a press while an export runs — their own
  /// dead [PillItem.onTap] — and are listed as they are. Every row is then
  /// one value of the app's one picker ([PanelFlyoutValueChoices]).
  List<PanelFlyoutEntry> _entries() {
    final changed = onImageChanged;
    ({
      String key,
      String label,
      bool current,
      VoidCallback? pick,
      bool writable,
    })
    listed(PillItem item) => (
      key: item.keyValue,
      label: item.label,
      current: item.selected,
      pick: item.onTap,
      writable: true,
    );
    final rows = [
      for (final item in before) listed(item),
      for (final format in ExportStillFormat.values)
        (
          key: '$keyPrefix-${format.jsonValue}',
          label: format.label,
          current: pictured && image.stillFormat == format,
          pick: changed == null
              ? null
              : () => changed(image.copyWith(stillFormat: format)),
          writable: stillEnabled(format),
        ),
      for (final item in after) listed(item),
    ];
    return rows.asFlyoutValueChoices(
      current: rows.where((row) => row.current).firstOrNull,
      choiceOf: (row) => PanelFlyoutChoice(
        key: row.key,
        label: row.label,
        enabled: row.writable && row.pick != null,
        warning: row.writable ? null : AppText.strings.exNotInThisBuild,
      ),
      onPicked: (row) => row.pick?.call(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final changed = onImageChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExportModuleRow(
          caption: caption,
          child: Align(
            alignment: Alignment.centerLeft,
            child: PanelFlyoutButton(
              key: ValueKey<String>('$keyPrefix-file'),
              label: _shown,
              enabled: changed != null,
              entriesBuilder: _entries,
            ),
          ),
        ),
        if (pictured && image.stillFormat == ExportStillFormat.jpg)
          ExportJpgQualityRow(
            keyValue: '$keyPrefix-quality',
            quality: image.jpgQuality,
            onChanged: changed == null
                ? null
                : (quality) => changed(image.copyWith(jpgQuality: quality)),
          ),
      ],
    );
  }
}

/// The Scope module: Cut/Project pills plus an optional tab-specific body
/// (Sequence's in/out fields, the Cels cut grid).
class ExportScopeModule extends StatelessWidget {
  const ExportScopeModule({
    super.key,
    required this.scope,
    required this.enabled,
    required this.onChanged,
    this.child,
  });

  final ExportScopeKind scope;
  final bool enabled;
  final ValueChanged<ExportScopeKind> onChanged;
  final Widget? child;

  static String summarize(ExportScopeKind scope) =>
      scope == ExportScopeKind.cut
      ? AppText.strings.exCut
      : AppText.strings.exProject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExportChoiceRow<ExportScopeKind>(
          caption: ExportCaption.target,
          keyPrefix: 'export-scope',
          values: ExportScopeKind.values,
          selected: scope,
          keyOf: (kind) => kind.jsonValue,
          labelOf: (kind) => kind == ExportScopeKind.cut
              ? AppText.strings.exCut
              : AppText.strings.exProject,
          onSelect: onChanged,
          enabledFor: (_) => enabled,
        ),
        if (child != null) ...[const SizedBox(height: 1), child!],
      ],
    );
  }
}

/// The Size module with the v10 coupling: a project scope forces the
/// camera frame (per-cut canvases cannot make one movie), so the canvas is
/// only offered under the cut scope.
///
/// Picked from the app's one value list, as the codec is
/// (video-export-speed-Q1, 유저 2026-10-09: 「이 방식은 다른곳에서도
/// 쓸수있으면 쓰게하고싶음」). ↩️It was a pill strip, and its two answers —
/// a word and a size each — were cut to an ellipsis in every language (실측
/// 10-09, the app's own faces).
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
      mode == ExportSizeMode.camera
      ? AppText.strings.exSizeCamera
      : AppText.strings.exSizeCanvas;

  /// What [mode] is called here: the frame it writes, and its size.
  String _labelOf(ExportSizeMode mode) {
    final strings = AppText.strings;
    return switch (mode) {
      ExportSizeMode.camera => strings.exCameraTemplate.replaceAll(
        '{size}',
        pixelSizeLabel(cameraSize.width, cameraSize.height),
      ),
      ExportSizeMode.canvas =>
        canvasSizes.length == 1
            ? strings.exCanvasTemplate.replaceAll(
                '{size}',
                pixelSizeLabel(
                  canvasSizes.first.width,
                  canvasSizes.first.height,
                ),
              )
            : strings.exCanvasPerCut,
    };
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: PanelFlyoutButton(
      key: const ValueKey<String>('export-size'),
      label: _labelOf(sizeMode),
      enabled: enabled,
      entriesBuilder: () =>
          [
            ExportSizeMode.camera,
            if (!projectScope) ExportSizeMode.canvas,
          ].asFlyoutValueChoices(
            current: sizeMode,
            choiceOf: (mode) => PanelFlyoutChoice(
              key: 'export-size-${mode.jsonValue}',
              label: _labelOf(mode),
            ),
            onPicked: onChanged,
          ),
    ),
  );
}

/// A lone file's name: typed alone, with the extension its format gives it
/// standing beside the field, fixed.
///
/// 🗣️F-221 (유저 2026-10-06): 「이름칸은 확장자랑 텍스트가 같이있는데 확장자는
/// 따로 나눠서 편집불가하게 그냥 띄우기만하고, 이름만 딱 있도록. 그렇게
/// 설정한대로 내보낼때 이름 지정되는 방식이지」.
///
/// 🗣️F-404 (유저 2026-10-19): the field opens EMPTY, and what the file is
/// called while it stays so shows faintly behind it — 「텍스트로 인식안되는데
/// 아무것도 안써져있으면 뒤에 흐리게 텍스트 보이게하는거」.
class ExportFileNameModule extends StatelessWidget {
  const ExportFileNameModule({
    super.key,
    required this.controller,
    required this.ghost,
    required this.extension,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;

  /// What the file is called while nothing is typed — the name the run
  /// writes then, shown behind the empty field.
  final String ghost;

  /// The format's own, without its dot.
  final String extension;
  final bool enabled;

  /// The name was typed on: what shows it elsewhere reads it again.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindowField(
      label: AppText.strings.exFileLabel,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey<String>('export-file-name-field'),
              controller: controller,
              enabled: enabled,
              decoration: InputDecoration(hintText: ghost),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '.$extension',
            key: const ValueKey<String>('export-file-extension'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sequence numbering: `<base>_0001.<ext>` — the base empty until one is
/// typed, and what the stills are called meanwhile behind it, as a lone
/// file's name is ([ExportFileNameModule], F-404).
class ExportSequenceNamingModule extends StatelessWidget {
  const ExportSequenceNamingModule({
    super.key,
    required this.naming,
    required this.ghost,
    required this.enabled,
    required this.onChanged,
    required this.baseNameController,
  });

  final ExportSequenceNaming naming;

  /// The base the stills are numbered under while none is typed.
  final String ghost;
  final bool enabled;
  final ValueChanged<ExportSequenceNaming> onChanged;
  final TextEditingController baseNameController;

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
              decoration: InputDecoration(hintText: ghost),
              onChanged: (value) =>
                  onChanged(naming.copyWith(baseName: value.trim())),
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
        inputFormatters: halfWidthDigitsOnly,
        onChanged: (value) {
          final parsed = halfWidthInt(value);
          if (parsed != null) {
            widget.onChanged(parsed);
          }
        },
      ),
    );
  }
}

/// What a kind is called wherever the window names it — its pill in
/// 「내보낼 종류」 and its prefix field in the naming module.
String exportCelKindLabel(ExportCelKind kind) => switch (kind) {
  ExportCelKind.cel => AppText.strings.exCels,
  // The conte ROW's word (콘티), not the sheet panel's (콘티 용지): the kind
  // is the row's drawings, written as cels are.
  ExportCelKind.conte => AppText.strings.tlKindStoryboard,
  ExportCelKind.art => AppText.strings.exArtLabel,
  ExportCelKind.direction => AppText.strings.exSelDirection,
  ExportCelKind.timesheet => AppText.strings.panelTimesheet,
  ExportCelKind.envelope => AppText.strings.panelEnvelope,
};

/// Cel-file naming: the CSP-style options ported into the module grammar.
class ExportCelNamingModule extends StatelessWidget {
  const ExportCelNamingModule({
    super.key,
    required this.naming,
    required this.enabled,
    required this.onChanged,
    required this.suffixController,
    required this.prefixControllers,
  });

  final ExportCelNaming naming;
  final bool enabled;
  final ValueChanged<ExportCelNaming> onChanged;
  final TextEditingController suffixController;

  /// One field a kind ([ExportCelNaming.prefixOf]) — the window's, as the
  /// suffix's is, so a preset or a reset can write them.
  final Map<ExportCelKind, TextEditingController> prefixControllers;

  /// How many prefix fields share a line of the settings column.
  static const int _prefixesPerLine = 3;

  /// 접두사: a field for every kind, empty for none. ⚠️Not trimmed: a
  /// prefix is whatever was typed, and what leads a file's name is usually
  /// one character.
  Widget _prefixFields() {
    Widget field(ExportCelKind kind) => Expanded(
      child: AppWindowField(
        label: exportCelKindLabel(kind),
        child: TextField(
          key: ValueKey<String>('export-cel-prefix-${kind.jsonValue}'),
          controller: prefixControllers[kind],
          enabled: enabled,
          onChanged: (value) => onChanged(naming.withPrefix(kind, value)),
        ),
      ),
    );
    const kinds = ExportCelKind.values;
    return Column(
      children: [
        for (var first = 0; first < kinds.length; first += _prefixesPerLine)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var at = first; at < first + _prefixesPerLine; at += 1) ...[
                if (at > first) const SizedBox(width: 8),
                // A short last line keeps the fields' width: an empty seat
                // where a kind would be.
                if (at < kinds.length)
                  field(kinds[at])
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
      ],
    );
  }

  /// Three names the file can carry and the same three the folders can, as
  /// two multi-select strips.
  PillStrip _names({
    required String keyPrefix,
    required bool project,
    required bool cut,
    required bool layer,
    required ExportCelNaming Function(String which) toggled,
  }) {
    final strings = AppText.strings;
    PillItem item(String which, String label, bool selected) =>
        PillItem(
          keyValue: '$keyPrefix-$which',
          label: label,
          selected: selected,
          onTap: enabled ? () => onChanged(toggled(which)) : null,
        );
    return PillStrip(
      items: [
        item('project', strings.exProject, project),
        item('cut', strings.exCut, cut),
        item('layer', strings.exLayer, layer),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Top to bottom the way the file is built: the folder it lands in, the
    // name it gets, what each kind's name starts with, then the digits and
    // suffix (유저 2026-09-09: 「젤 위에 폴더 생성, 이름 지정, 자릿수/접미사」).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExportModuleRow(
          caption: ExportCaption.folders,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _names(
              keyPrefix: 'export-cel-folder',
              project: naming.projectFolder,
              cut: naming.cutFolder,
              layer: naming.layerFolder,
              toggled: (which) => switch (which) {
                'project' =>
                  naming.copyWith(projectFolder: !naming.projectFolder),
                'cut' => naming.copyWith(cutFolder: !naming.cutFolder),
                _ => naming.copyWith(layerFolder: !naming.layerFolder),
              },
            ),
          ),
        ),
        ExportModuleRow(
          caption: ExportCaption.nameParts,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _names(
              keyPrefix: 'export-cel-include',
              project: naming.includeProjectName,
              cut: naming.includeCutName,
              layer: naming.includeLayerName,
              toggled: (which) => switch (which) {
                'project' => naming.copyWith(
                  includeProjectName: !naming.includeProjectName,
                ),
                'cut' => naming.copyWith(includeCutName: !naming.includeCutName),
                _ => naming.copyWith(
                  includeLayerName: !naming.includeLayerName,
                ),
              },
            ),
          ),
        ),
        ExportModuleRow(
          caption: ExportCaption.prefix,
          child: _prefixFields(),
        ),
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
      ],
    );
  }
}
