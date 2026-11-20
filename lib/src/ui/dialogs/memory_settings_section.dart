import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../native/app_gpu_engine.dart';
import '../diagnostics/memory_census.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../text/text_measure.dart';
import '../theme/app_theme.dart';
import '../widgets/field_slider.dart';
import '../widgets/app_icon_button.dart';
import '../session/cache_budgets.dart';
import '../../services/persistence/app_memory_settings.dart';

/// Preferences ▸ Memory: what this app is holding in RAM, live.
///
/// 유저 2026-08-28: 「이 앱이 쓰는 메모리의 총합. 그리고 추가적으로 거기서
/// 어떤항목이 얼만큼 차지하는지도 보여주고」 and 「라이브로(위아래 봉이
/// 늘어나고 줄어드는 실시간)」.
///
/// ⚠️THE TWO TOTALS ARE DIFFERENT ON PURPOSE, and that was the user's own
/// question: 「os합이랑 우리가 쓰는 합이랑 다르다면 os합 보여주고 우리가쓰는
/// 합 보여주고 그 합 안에서 항목 나눠서 보여줌」. They cannot be made equal —
/// the process holds the Flutter engine, Skia, the Dart heap, the binary
/// and the embedded typefaces, none of which this app allocates. So the
/// bar shows the WHOLE process, splits it into what we can account for and
/// what we cannot, and breaks items out inside ours.
///
/// 🗣️TWO COLUMNS WHERE THE GPU HAS MEMORY OF ITS OWN (유저 2026-11-16,
/// vram-in-use-shown-in-the-memory-tab, on a screenshot: 「막대가 vram막대
/// 표시되는거맞나? … 외장gpu면 영역 제대로 나눠서 왼쪽에 RAM, 오른쪽에 VRAM
/// … 기기 메모리는 그리고 RAM 설정이니까 제대로 RAM 항목안에」 — Q3 「C · 칸마다
/// 내역, 허용치로 묶음」, Q5 「C-1 · 이름 옆에 막대」, drawn before it was built
/// and built as drawn). The RAM and the VRAM are ONE column shape, row for
/// row — 「ram의 앱 허용치랑 vram의 os 예산 중 … 행/열 느낌이라던가 막대의
/// ui라던가 너무 다르잖아 … 최대한 통일감」: the device's whole, the ceiling on
/// a bar of that scale, what this app uses, the live bar, its legend, what
/// is left, and the holdings in the two groups the allowance draws
/// ([_MemoryColumn]). One column where the GPU shares the RAM
/// ([MemoryCensus.gpuMemoryIsRam]); Q4: where the OS says nothing of the
/// GPU's memory (Android, Linux) the VRAM column stands all the same, its
/// OS figures 「—」.
class MemorySettingsSection extends StatefulWidget {
  const MemorySettingsSection({
    super.key,
    required this.session,
    required this.openSessions,
  });

  final EditorSessionManager session;

  /// Every open project — the census adds them all up (I-7).
  final Iterable<EditorSessionManager> openSessions;

  @override
  State<MemorySettingsSection> createState() => _MemorySettingsSectionState();
}

class _MemorySettingsSectionState extends State<MemorySettingsSection> {
  /// Slow enough to read, fast enough to watch a cache fill. The audio
  /// monitor's 33ms is for a meter you play against; this is a number you
  /// look at.
  static const Duration _interval = Duration(milliseconds: 500);

  Timer? _timer;
  MemoryCensus? _census;

  /// The largest process total seen while this panel has been open — the
  /// RAM's live bar's ceiling.
  ///
  /// ⛔A bar scaled to the CURRENT total can only ever be full, so it would
  /// never move; scaled to the device's RAM it would never leave the
  /// bottom. A high-water mark is the only scale on which the thing the
  /// user asked to watch — growing and shrinking — is visible.
  int _peakBytes = 1;

  /// The same for the VRAM's live bar: the most of the GPU's own memory
  /// this app was seen to use — or to hold in the rows that name it, where
  /// the OS says no use.
  int _videoPeakBytes = 1;

  @override
  void initState() {
    super.initState();
    _sample();
    _timer = Timer.periodic(_interval, (_) => _sample());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sample() {
    if (!mounted) {
      return;
    }
    final census = collectMemoryCensus(widget.openSessions);
    setState(() {
      _census = census;
      _peakBytes = math.max(_peakBytes, census.footprintBytes);
      _videoPeakBytes = math.max(
        _videoPeakBytes,
        census.videoMemory?.used ?? census.videoTrackedBytes,
      );
    });
  }

  /// [bytes] in megabytes, 「—」 where nothing says it.
  static String _mb(int? bytes) => bytes == null
      ? '—'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';

  String _labelFor(String id) {
    final strings = AppText.strings;
    return switch (id) {
      'drawings' => strings.memoryItemDrawings,
      'sheetInk' => strings.memoryItemSheetInk,
      'undo' => strings.memoryItemUndo,
      'framePictures' => strings.memoryItemFramePictures,
      'brushTips' => strings.memoryItemBrushTips,
      'panelRasters' => strings.memoryItemPanelRasters,
      'viewerPages' => strings.memoryItemViewerPages,
      'imageCache' => strings.memoryItemImageCache,
      'storyboardThumbnails' => strings.memoryItemStoryboardThumbnails,
      'sheetImages' => strings.memoryItemSheetImages,
      'textImages' => strings.memoryItemTextImages,
      'strokePreviews' => strings.memoryItemStrokePreviews,
      'timelineTiles' => strings.memoryItemTimelineTiles,
      'moviePictures' => strings.memoryItemMoviePictures,
      'tileImages' => strings.memoryItemTileImages,
      'engineScratch' => strings.memoryItemEngineScratch,
      'gpuInSystem' => strings.memoryItemGpuInSystem,
      _ => id,
    };
  }

  /// A column's holdings as its rows, and [rest] — what no row names — last
  /// among them.
  List<_Holding> _holdings(
    List<MemoryCensusItem> items,
    String restLabel,
    int? rest,
  ) => [
    for (final item in items)
      (
        id: item.id,
        label: _labelFor(item.id),
        bytes: item.bytes,
        pinned: item.detail,
      ),
    (id: null, label: restLabel, bytes: rest, pinned: 0),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final census = _census;
    // ⛔The layout is the same whether or not a sample has landed: the
    // space is reserved and only the numbers change (the app's no-UI-that-
    // pops-into-existence rule).
    final footprint = census?.footprintBytes ?? 0;
    final tracked = census?.trackedBytes ?? 0;
    final untracked = census?.untrackedBytes ?? 0;
    final device = census?.deviceBytes;
    final automatic = widget.session.automaticAllowance;
    final shared =
        census?.gpuMemoryIsRam ??
        texturesAreInTheRamFigure(appGpuVideoMemory);
    // ONE label width for the ceilings of both columns, so their bars start
    // and end where each other's do.
    final ceilingLabels = TextStyle(fontSize: 12, color: AppColors.textDim);
    final ceilingLabelWidth = TextMeasure(
      context,
      DefaultTextStyle.of(context).style.merge(ceilingLabels),
    ).widest([
      strings.memoryAllowance,
      if (!shared) strings.memoryBudget,
    ]).ceilToDouble();

    return ValueListenableBuilder<AppMemorySettings>(
      valueListenable: AppMemory.settings,
      builder: (context, memory, _) {
        final chosen = memory.allowanceBytes;
        final ram = _MemoryColumn(
          column: 'memory-ram',
          keyPrefix: 'memory',
          heading: strings.memoryRam,
          subheading: shared ? strings.memoryRamSharedWithGpu : null,
          totalLabel: strings.memoryDeviceTotal,
          totalBytes: device,
          ceiling: _CeilingRow(
            label: strings.memoryAllowance,
            labelStyle: ceilingLabels,
            labelWidth: ceilingLabelWidth,
            bar: _AllowanceBar(
              allowanceBytes: chosen ?? automatic,
              floorBytes: CacheBudgets.floors.total,
              // An unknown device (no engine: tests, host runs) scales to
              // twice the automatic allowance.
              scaleBytes: device ?? automatic * 2,
              totalBytes: footprint,
              trackedBytes: tracked,
              onChosen: (bytes) => widget.session.setMemorySettings(
                AppMemorySettings(allowanceBytes: bytes),
              ),
            ),
            // ⛔The button is always there and goes inert at the automatic
            // allowance rather than appearing when a value is chosen — no
            // UI that pops into existence.
            button: AppIconButton(
              keyValue: 'memory-allowance-automatic',
              tooltip: strings.memoryAllowanceAutomatic,
              size: AppIconButtonSize.dense,
              icon: const Icon(Icons.settings_backup_restore),
              onPressed: chosen != null
                  ? () => widget.session.setMemorySettings(
                      const AppMemorySettings(),
                    )
                  : null,
              resets: true,
            ),
          ),
          usedLabel: strings.memoryProcessTotal,
          usedBytes: footprint,
          trackedBytes: tracked,
          peakBytes: _peakBytes,
          restLabel: strings.memoryUntracked,
          restBytes: untracked,
          availableBytes: census?.availableBytes,
          holdings: _holdings(
            census?.items ?? const [],
            strings.memoryUntracked,
            untracked,
          ),
          format: _mb,
        );
        final Widget body;
        if (shared) {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: ram.cells(),
          );
        } else {
          final video = census?.videoMemory;
          final videoTracked = census?.videoTrackedBytes ?? 0;
          final videoUntracked = census?.videoUntrackedBytes;
          final budget = video?.budget;
          final used = video?.used;
          final vram = _MemoryColumn(
            column: 'memory-vram',
            keyPrefix: 'memory-vram',
            heading: strings.memoryVram,
            totalLabel: strings.memoryDeviceVram,
            totalBytes: video?.total,
            ceiling: _CeilingRow(
              label: strings.memoryBudget,
              labelStyle: ceilingLabels,
              labelWidth: ceilingLabelWidth,
              bar: _BudgetBar(
                budgetBytes: budget,
                scaleBytes: video?.total ?? budget ?? _videoPeakBytes,
                totalBytes: used ?? videoTracked,
                trackedBytes: videoTracked,
              ),
            ),
            usedLabel: strings.memoryGpuTotal,
            usedBytes: used,
            trackedBytes: videoTracked,
            peakBytes: _videoPeakBytes,
            restLabel: strings.memoryVramUntracked,
            restBytes: videoUntracked,
            availableBytes: budget == null || used == null
                ? null
                : math.max(0, budget - used),
            holdings: _holdings(
              census?.videoItems ?? const [],
              strings.memoryVramUntracked,
              videoUntracked,
            ),
            format: _mb,
          );
          // 🗣️ROWS, NOT TWO COLUMNS SIDE BY SIDE (유저 2026-11-16: 「행/열
          // 느낌」): a row of the RAM's and the VRAM's stand in one table
          // row, as tall as the taller — a label that wraps on one side
          // moves both, and the rows stay level all the way down.
          final left = ram.cells();
          final right = vram.cells();
          assert(left.length == right.length, 'the columns are one shape');
          body = Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: FixedColumnWidth(_columnGap * 2 + 1),
              2: FlexColumnWidth(),
            },
            children: [
              for (var row = 0; row < left.length; row++)
                TableRow(children: [left[row], const _Rule(), right[row]]),
            ],
          );
        }
        return SingleChildScrollView(
          key: const ValueKey<String>('memory-settings-section'),
          child: body,
        );
      },
    );
  }
}

/// The room on each side of the rule between the RAM and the VRAM.
const double _columnGap = 28;

/// The rule between the RAM and the VRAM, a row's height each — one line
/// down the table.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => TableCell(
    verticalAlignment: TableCellVerticalAlignment.fill,
    child: Center(
      child: SizedBox(
        width: 1,
        height: double.infinity,
        child: ColoredBox(color: AppColors.hairline),
      ),
    ),
  );
}

/// The room a column keeps at its right for the ceiling's button — the
/// allowance's back-to-automatic; the budget's, none — so every figure and
/// both bars end where the ceiling's bar does.
final double _buttonSlot = AppIconButtonSize.dense.maxWidth;

/// One row of a column's holdings: a census row, or what no row names
/// (`id` null), its bytes null where nothing says them.
typedef _Holding = ({String? id, String label, int? bytes, int pinned});

/// ONE MEMORY'S COLUMN — the RAM's or the VRAM's, the same shape row for
/// row (see [MemorySettingsSection]): its cells, which the section stands
/// beside the other column's, one table row each.
class _MemoryColumn {
  const _MemoryColumn({
    required this.column,
    required this.keyPrefix,
    required this.heading,
    this.subheading,
    required this.totalLabel,
    required this.totalBytes,
    required this.ceiling,
    required this.usedLabel,
    required this.usedBytes,
    required this.trackedBytes,
    required this.peakBytes,
    required this.restLabel,
    required this.restBytes,
    required this.availableBytes,
    required this.holdings,
    required this.format,
  });

  /// What its cells' keys begin with: `<column>-cell-<row>`.
  final String column;

  /// What the keys of the bars and the marks in it begin with.
  final String keyPrefix;

  final String heading;
  final String? subheading;

  /// The device's whole of this memory.
  final String totalLabel;
  final int? totalBytes;

  final _CeilingRow ceiling;

  /// What this app uses of it, and the part of that the rows name.
  final String usedLabel;
  final int? usedBytes;
  final int trackedBytes;
  final int peakBytes;

  /// What no row names.
  final String restLabel;
  final int? restBytes;

  final int? availableBytes;
  final List<_Holding> holdings;
  final String Function(int?) format;

  /// The column's rows, top to bottom, the holdings last — each keyed
  /// `<column>-cell-<row>`.
  List<Widget> cells() {
    final strings = AppText.strings;
    Widget slotted(Widget row) => Padding(
      padding: EdgeInsets.only(right: _buttonSlot),
      child: row,
    );
    final under = [
      for (final holding in holdings)
        if (holding.id != null && CacheBudgetLine.covers(holding.id!))
          holding,
    ];
    final outside = [
      for (final holding in holdings)
        if (holding.id == null || !CacheBudgetLine.covers(holding.id!))
          holding,
    ];
    final rows = <Widget>[
      _ColumnHeading(heading: heading, subheading: subheading),
      slotted(
        _TotalRow(
          label: totalLabel,
          value: format(totalBytes),
          emphasis: true,
        ),
      ),
      ceiling,
      const SizedBox(height: 10),
      slotted(
        _TotalRow(label: usedLabel, value: format(usedBytes), emphasis: true),
      ),
      const SizedBox(height: 6),
      slotted(
        _LiveBar(
          key: ValueKey<String>('$keyPrefix-live-bar'),
          trackedBytes: trackedBytes,
          // Where the OS says no use, what the rows name is all the bar
          // knows (Q4: 「아는 만큼만」).
          totalBytes: usedBytes ?? trackedBytes,
          peakBytes: peakBytes,
        ),
      ),
      const SizedBox(height: 6),
      // The legend both bars share: the accent is what we can name, the
      // grey is the rest (memory-usage-panel ④ — 「회색바는 뭐지?」).
      slotted(
        _TotalRow(
          label: strings.memoryTracked,
          value: format(trackedBytes),
          mark: _MarkColor.accent,
          markKey: '$keyPrefix-legend-tracked',
        ),
      ),
      slotted(
        _TotalRow(
          label: restLabel,
          value: format(restBytes),
          mark: _MarkColor.grey,
          markKey: '$keyPrefix-legend-untracked',
        ),
      ),
      slotted(
        _TotalRow(
          label: strings.memoryAvailable,
          value: format(availableBytes),
        ),
      ),
      // ↩️What sits outside the allowance was ONE SENTENCE under the
      // legend (유저 2026-09-16, memory-allowance-Q2: 「셀 수 없는게 밖에
      // 있으니 그 부분을 문장으로 제대로 알기쉽게 간략하게 설명해두기」)
      // till the holdings were grouped by it (Q3 「C · 칸마다 내역,
      // 허용치로 묶음」, 2026-11-16): the names stand in the group they
      // head. ⛔Still read off [CacheBudgetLine.covers], never written by
      // hand (유저 09-16: 「낡지않을구조로」) — a holder that gains a ceiling
      // moves group on its own. In the VRAM's column too: the allowance
      // ceilings its pictures as well.
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoldingGroup(
            keyValue: '$keyPrefix-under-allowance',
            title: strings.memoryUnderAllowance,
            holdings: under,
            ofBytes: trackedBytes,
            format: format,
          ),
          _HoldingGroup(
            keyValue: '$keyPrefix-outside-allowance',
            title: strings.memoryOutsideAllowance,
            holdings: outside,
            ofBytes: trackedBytes,
            format: format,
          ),
        ],
      ),
    ];
    return [
      for (final (row, cell) in rows.indexed)
        KeyedSubtree(key: ValueKey<String>('$column-cell-$row'), child: cell),
    ];
  }
}

/// A column's name — RAM, VRAM — and, where the GPU shares the RAM, that
/// it does.
class _ColumnHeading extends StatelessWidget {
  const _ColumnHeading({required this.heading, this.subheading});

  final String heading;
  final String? subheading;

  @override
  Widget build(BuildContext context) {
    final subheading = this.subheading;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            heading,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.75,
              color: AppColors.text,
            ),
          ),
          if (subheading != null) ...[
            const SizedBox(width: 8),
            Text(
              subheading,
              style: TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
          ],
        ],
      ),
    );
  }
}

/// Which colour a legend mark takes — the same ones the bars draw with.
enum _MarkColor {
  accent,
  grey,
  allowance;

  Color get resolved => switch (this) {
    _MarkColor.accent => AppColors.accent,
    _MarkColor.grey => AppColors.hairline,
    _MarkColor.allowance => AppColors.textDim,
  };
}

/// One total line: a label, its figure, and — for the rows the bars fill —
/// the legend mark that ties it to a colour there.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.mark,
    this.markKey,
  });

  final String label;
  final String value;
  final bool emphasis;

  /// The colour in the bars this row is the legend of.
  final _MarkColor? mark;
  final String? markKey;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasis ? 13 : 12,
      color: emphasis ? AppColors.text : AppColors.textDim,
      fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
    );
    final mark = this.mark;
    final markKey = this.markKey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (mark != null) ...[
            _MarkDot(
              key: markKey == null ? null : ValueKey<String>(markKey),
              color: mark,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// A legend mark before a row's label: a dot of the colour it names in the
/// bars. ↩️The allowance's ring stood before its name too, the outline's
/// legend, till the two columns were made one shape (유저 2026-11-16:
/// 「앱 허용치앞엔 동그라미있고」 — Q5 「C-1」 has none).
class _MarkDot extends StatelessWidget {
  const _MarkDot({super.key, required this.color});

  final _MarkColor color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 8,
    height: 8,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.resolved,
      ),
    ),
  );
}

/// A ceiling's row, the same in both columns: its name in a column as wide
/// as the widest of the two, its bar, and the slot for its button — kept
/// where it has none, so the bars end together.
class _CeilingRow extends StatelessWidget {
  const _CeilingRow({
    required this.label,
    required this.labelStyle,
    required this.labelWidth,
    required this.bar,
    this.button,
  });

  final String label;
  final TextStyle labelStyle;
  final double labelWidth;
  final Widget bar;
  final Widget? button;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(label, style: labelStyle),
        ),
        const SizedBox(width: 8),
        Expanded(child: bar),
        SizedBox(
          width: _buttonSlot,
          child: button == null ? null : Center(child: button),
        ),
      ],
    ),
  );
}

/// The allowance — what the app's caches may hold between them — on the
/// device's own scale: the bar is the device's memory, what the process
/// uses fills it (grey the whole process, accent the part we can name),
/// and the allowance is the outline over that, set by dragging it
/// ([FieldSlider.ceiling]). The button beside it moves it back to
/// automatic ([_CeilingRow]).
///
/// 🗣️THREE TIERS (유저 2026-09-11): 「디바이스의 메모리를 제일 큰 기준으로
/// 보여주고, 그 안에 앱이 사용하기로 허가된 메모리 … 그러고 실제 사용하는
/// 메모리」 — the device, the allowance inside it, what is used inside that.
///
/// 🗣️F-480 (유저 2026-10-27): 「비율이 고정슬라이더가 아니라 변동슬라이더 …
/// 고정값으로. 그렇게 하고 밑, 두번째 슬라이더랑 내용적으로 같아지니 내용
/// 서로 합쳐서 통합」. ↩️The allowance had a slider of its own, on a scale
/// whose middle was about a quarter of the device (exponential), with the
/// three tiers on a bar under it.
///
/// ⚠️On a desktop the fill is a sliver of the bar — which is the answer to
/// "where does this app stand on this machine", and the reason the live
/// bar below keeps its own high-water scale: this one could never show a
/// cache filling.
///
/// ⛔The value lands on RELEASE, not on every tick of the drag: a new
/// allowance re-budgets every cache, and dragging down would cool cels to
/// disk once per frame. The bar follows the hand on its own until then.
class _AllowanceBar extends StatelessWidget {
  const _AllowanceBar({
    required this.allowanceBytes,
    required this.floorBytes,
    required this.scaleBytes,
    required this.totalBytes,
    required this.trackedBytes,
    required this.onChosen,
  });

  final int allowanceBytes;

  /// The least the allowance can be set to — every budget line's floor.
  final int floorBytes;

  /// The whole bar: the device's memory.
  final int scaleBytes;

  /// What the whole process uses, and the part of it we can name.
  final int totalBytes;
  final int trackedBytes;

  final ValueChanged<int> onChosen;

  static const double _mb = 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    final floor = floorBytes / _mb;
    final max = scaleBytes > floorBytes ? scaleBytes / _mb : floor * 2;
    final value = (allowanceBytes / _mb).clamp(floor, max).toDouble();
    return FieldSlider.ceiling(
      key: const ValueKey<String>('memory-allowance-slider'),
      max: max,
      floor: floor,
      value: value,
      levels: _levels(totalBytes, trackedBytes),
      color: _MarkColor.allowance.resolved,
      // The bar writes its own digits (F-34); in megabytes they read the
      // way the rows beside it do.
      unit: 'MB',
      // Nothing previews the drag but the bar itself (see above).
      onChanged: (_) {},
      onChangeEnd: (mb) => onChosen((mb * _mb).round()),
    );
  }
}

/// What a ceiling's bar fills, in megabytes: the whole use in grey, the
/// part the rows name in the accent over it.
List<FieldSliderLevel> _levels(int totalBytes, int trackedBytes) => [
  (value: totalBytes / _AllowanceBar._mb, color: _MarkColor.grey.resolved),
  (value: trackedBytes / _AllowanceBar._mb, color: _MarkColor.accent.resolved),
];

/// The VRAM's ceiling — the budget the OS gives this process in the GPU's
/// own memory, past which it moves the process's pictures out to the RAM
/// (F-569) — as the allowance is drawn ([_AllowanceBar]): the bar is the
/// adapter's own memory, the use fills it, the budget is the outline. Set
/// by the OS, not by the hand ([FieldSlider.setElsewhere]); 「—」 where the
/// OS says none (Q4).
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({
    required this.budgetBytes,
    required this.scaleBytes,
    required this.totalBytes,
    required this.trackedBytes,
  });

  final int? budgetBytes;

  /// The whole bar: the adapter's own memory, where the OS says it.
  final int scaleBytes;

  final int totalBytes;
  final int trackedBytes;

  @override
  Widget build(BuildContext context) {
    const mb = _AllowanceBar._mb;
    final budget = budgetBytes;
    final max = math.max(scaleBytes, 1) / mb;
    return FieldSlider.ceiling(
      key: const ValueKey<String>('memory-budget-bar'),
      max: max,
      floor: 0,
      value: budget == null ? 0 : math.min(budget / mb, max),
      levels: _levels(totalBytes, trackedBytes),
      color: _MarkColor.allowance.resolved,
      unit: 'MB',
      restingText: budget == null ? '—' : null,
      setElsewhere: true,
      onChanged: null,
    );
  }
}

/// The bar 유저 asked to watch: the whole use against the high-water mark,
/// with the accounted-for part filled in the accent.
class _LiveBar extends StatelessWidget {
  const _LiveBar({
    super.key,
    required this.trackedBytes,
    required this.totalBytes,
    required this.peakBytes,
  });

  final int trackedBytes;
  final int totalBytes;
  final int peakBytes;

  @override
  Widget build(BuildContext context) {
    final ceiling = peakBytes <= 0 ? 1 : peakBytes;
    final wholeFraction = (totalBytes / ceiling).clamp(0.0, 1.0);
    final trackedFraction = (trackedBytes / ceiling).clamp(0.0, 1.0);
    return SizedBox(
      height: 18,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.hairline),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: width * wholeFraction,
                child: ColoredBox(color: AppColors.hairline),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: width * trackedFraction,
                child: ColoredBox(color: AppColors.accent),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One group of a column's holdings — those the allowance ceilings, or
/// those outside it — under its name and its sum, largest first.
class _HoldingGroup extends StatelessWidget {
  const _HoldingGroup({
    required this.keyValue,
    required this.title,
    required this.holdings,
    required this.ofBytes,
    required this.format,
  });

  final String keyValue;
  final String title;
  final List<_Holding> holdings;
  final int ofBytes;
  final String Function(int?) format;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11.5, color: AppColors.textDim);
    var sum = 0;
    for (final holding in holdings) {
      sum += holding.bytes ?? 0;
    }
    final rows = [...holdings]
      ..sort((a, b) => (b.bytes ?? -1).compareTo(a.bytes ?? -1));
    return Column(
      key: ValueKey<String>(keyValue),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.hairline)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: style)),
                  Text(format(sum), style: style),
                ],
              ),
            ),
          ),
        ),
        for (final holding in rows)
          _ItemRow(
            label: holding.label,
            bytes: holding.bytes,
            pinned: holding.pinned,
            ofBytes: ofBytes,
            pinnedLabel: AppText.strings.memoryPinned,
            format: format,
          ),
      ],
    );
  }
}

/// One holding, with its share of the tracked total.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.label,
    required this.bytes,
    required this.pinned,
    required this.ofBytes,
    required this.pinnedLabel,
    required this.format,
  });

  final String label;
  final int? bytes;
  final int pinned;
  final int ofBytes;
  final String pinnedLabel;
  final String Function(int?) format;

  @override
  Widget build(BuildContext context) {
    final bytes = this.bytes ?? 0;
    final share = ofBytes <= 0 ? 0.0 : (bytes / ofBytes).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
              Text(
                // ⛔The pinned figure rides the SAME line rather than
                // appearing on its own when non-zero: a row that grows a
                // second line when playback starts is UI that pops into
                // existence.
                pinned > 0
                    ? '${format(this.bytes)}  (${format(pinned)} $pinnedLabel)'
                    : format(this.bytes),
                style: TextStyle(fontSize: 12, color: AppColors.textDim),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 3,
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: constraints.maxWidth * share,
                  child: ColoredBox(color: AppColors.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
