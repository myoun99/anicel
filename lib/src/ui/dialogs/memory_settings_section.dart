import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../diagnostics/memory_census.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
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
class MemorySettingsSection extends StatefulWidget {
  const MemorySettingsSection({super.key, required this.session});

  final EditorSessionManager session;

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
  /// bar's ceiling.
  ///
  /// ⛔A bar scaled to the CURRENT total can only ever be full, so it would
  /// never move; scaled to the device's RAM it would never leave the
  /// bottom. A high-water mark is the only scale on which the thing the
  /// user asked to watch — growing and shrinking — is visible.
  int _peakBytes = 1;

  /// The allowance under the thumb while the slider is dragged — the tier
  /// bar previews it; the setting only changes on release.
  int? _draggedBytes;

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
    final census = collectMemoryCensus(widget.session);
    setState(() {
      _census = census;
      if (census.footprintBytes > _peakBytes) {
        _peakBytes = census.footprintBytes;
      }
    });
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';

  String _labelFor(String id) {
    final strings = AppText.strings;
    return switch (id) {
      'drawings' => strings.memoryItemDrawings,
      'sheetInk' => strings.memoryItemSheetInk,
      'undo' => strings.memoryItemUndo,
      'playbackFrames' => strings.memoryItemPlaybackFrames,
      'layerImages' => strings.memoryItemLayerImages,
      'brushTips' => strings.memoryItemBrushTips,
      'panelRasters' => strings.memoryItemPanelRasters,
      'viewerPages' => strings.memoryItemViewerPages,
      'imageCache' => strings.memoryItemImageCache,
      'storyboardThumbnails' => strings.memoryItemStoryboardThumbnails,
      'moviePictures' => strings.memoryItemMoviePictures,
      'tileImages' => strings.memoryItemTileImages,
      'engineBuffers' => strings.memoryItemEngineBuffers,
      _ => id,
    };
  }

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
    final available = census?.availableBytes;
    final device = census?.deviceBytes;
    final items = census?.items ?? const <MemoryCensusItem>[];
    final automatic = widget.session.deviceCacheBudgets.total;

    return ValueListenableBuilder<AppMemorySettings>(
      valueListenable: AppMemory.settings,
      builder: (context, memory, _) {
        final chosen = memory.allowanceBytes;
        final allowance = _draggedBytes ?? chosen ?? automatic;
        return SingleChildScrollView(
          key: const ValueKey<String>('memory-settings-section'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🗣️THREE TIERS (유저 2026-09-11): 「디바이스의 메모리를 제일
              // 큰 기준으로 보여주고, 그 안에 앱이 사용하기로 허가된
              // 메모리 … 그러고 실제 사용하는 메모리」 — the device, the
              // allowance inside it, what is used inside that.
              _TotalRow(
                label: strings.memoryDeviceTotal,
                value: device == null ? '—' : _mb(device),
                emphasis: true,
              ),
              _AllowanceRow(
                label: strings.memoryAllowance,
                automaticTooltip: strings.memoryAllowanceAutomatic,
                allowanceBytes: allowance,
                minBytes: CacheBudgets.floors.total,
                maxBytes: device ?? automatic * 2,
                chosen: chosen != null,
                onDragged: (bytes) => setState(() => _draggedBytes = bytes),
                onChosen: (bytes) {
                  setState(() => _draggedBytes = null);
                  widget.session.setMemorySettings(
                    AppMemorySettings(allowanceBytes: bytes),
                  );
                },
                onAutomatic: () => widget.session.setMemorySettings(
                  const AppMemorySettings(),
                ),
              ),
              const SizedBox(height: 4),
              _TierBar(
                deviceBytes: device,
                allowanceBytes: allowance,
                totalBytes: footprint,
                trackedBytes: tracked,
              ),
              const SizedBox(height: 10),
              _TotalRow(
                label: strings.memoryProcessTotal,
                value: _mb(footprint),
                emphasis: true,
              ),
              const SizedBox(height: 6),
              _LiveBar(
                trackedBytes: tracked,
                totalBytes: footprint,
                peakBytes: _peakBytes,
              ),
              const SizedBox(height: 6),
              // The legend both bars share: the accent is what we can
              // name, the grey is the rest of the process (memory-usage-
              // panel ④ — 「회색바는 뭐지?」).
              _TotalRow(
                label: strings.memoryTracked,
                value: _mb(tracked),
                mark: const _Mark.fill(_MarkColor.accent),
                markKey: 'memory-legend-tracked',
              ),
              _TotalRow(
                label: strings.memoryUntracked,
                value: _mb(untracked),
                mark: const _Mark.fill(_MarkColor.grey),
                markKey: 'memory-legend-untracked',
              ),
              _TotalRow(
                label: strings.memoryAvailable,
                value: available == null ? '—' : _mb(available),
              ),
              const SizedBox(height: 12),
              for (final item in items)
                _ItemRow(
                  label: _labelFor(item.id),
                  bytes: item.bytes,
                  pinned: item.detail,
                  ofBytes: tracked,
                  pinnedLabel: strings.memoryPinned,
                  format: _mb,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Which colour a legend mark takes — the same two the bars fill with.
enum _MarkColor { accent, grey, allowance }

/// A legend mark before a row's label: a filled dot for a fill in the
/// bars, a ring for the allowance's outline.
class _Mark {
  const _Mark.fill(this.color) : ring = false;
  const _Mark.ring(this.color) : ring = true;

  final _MarkColor color;
  final bool ring;

  Color get resolved => switch (color) {
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

  /// The legend mark that ties this row to a colour in the bars.
  final _Mark? mark;
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
              mark: mark,
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

class _MarkDot extends StatelessWidget {
  const _MarkDot({super.key, required this.mark});

  final _Mark mark;

  @override
  Widget build(BuildContext context) {
    final color = mark.resolved;
    return SizedBox(
      width: 8,
      height: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: mark.ring ? null : color,
          border: mark.ring ? Border.all(color: color, width: 1.5) : null,
        ),
      ),
    );
  }
}

/// The allowance: what the app's caches may hold between them, set on a
/// slider and moved back to automatic with the button beside it.
///
/// ⛔The value lands on RELEASE, not on every tick of the drag: a new
/// allowance re-budgets every cache, and dragging down would cool cels to
/// disk once per frame. While the thumb moves, the tier bar previews it.
///
/// ⛔The button is always there and goes inert at the automatic allowance
/// rather than appearing when a value is chosen — no UI that pops into
/// existence.
class _AllowanceRow extends StatelessWidget {
  const _AllowanceRow({
    required this.label,
    required this.automaticTooltip,
    required this.allowanceBytes,
    required this.minBytes,
    required this.maxBytes,
    required this.chosen,
    required this.onDragged,
    required this.onChosen,
    required this.onAutomatic,
  });

  final String label;
  final String automaticTooltip;
  final int allowanceBytes;
  final int minBytes;
  final int maxBytes;
  final bool chosen;
  final ValueChanged<int> onDragged;
  final ValueChanged<int> onChosen;
  final VoidCallback onAutomatic;

  static const double _mb = 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    final min = minBytes / _mb;
    final max = maxBytes > minBytes ? maxBytes / _mb : min * 2;
    final value = (allowanceBytes / _mb).clamp(min, max).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const _MarkDot(
            key: ValueKey<String>('memory-legend-allowance'),
            mark: _Mark.ring(_MarkColor.allowance),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textDim),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FieldSlider(
              key: const ValueKey<String>('memory-allowance-slider'),
              min: min,
              max: max,
              value: value,
              scale: FieldSliderScale.exponential,
              // The bar writes its own digits (F-34); in megabytes they
              // read the way the rows beside it do.
              unit: 'MB',
              onChanged: (mb) => onDragged((mb * _mb).round()),
              onChangeEnd: (mb) => onChosen((mb * _mb).round()),
            ),
          ),
          AppIconButton(
            keyValue: 'memory-allowance-automatic',
            tooltip: automaticTooltip,
            size: AppIconButtonSize.dense,
            icon: const Icon(Icons.settings_backup_restore),
            onPressed: chosen ? onAutomatic : null,
          ),
        ],
      ),
    );
  }
}

/// The three tiers on one scale — the DEVICE's memory is the bar, the
/// allowance an outline inside it, and what the process uses the fill
/// inside that (grey the whole process, accent the part we can name).
///
/// ⚠️On a desktop the fill is a sliver of the bar — which is the answer to
/// "where does this app stand on this machine", and the reason the live
/// bar below keeps its own high-water scale: this one could never show a
/// cache filling.
class _TierBar extends StatelessWidget {
  const _TierBar({
    required this.deviceBytes,
    required this.allowanceBytes,
    required this.totalBytes,
    required this.trackedBytes,
  });

  final int? deviceBytes;
  final int allowanceBytes;
  final int totalBytes;
  final int trackedBytes;

  @override
  Widget build(BuildContext context) {
    // An unknown device (no engine: tests, host runs) scales to the
    // largest thing drawn, so nothing runs off the end.
    final scale = math.max(
      deviceBytes ?? math.max(allowanceBytes, totalBytes),
      1,
    );
    double fraction(int bytes) => (bytes / scale).clamp(0.0, 1.0);
    return SizedBox(
      key: const ValueKey<String>('memory-tier-bar'),
      height: 12,
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
                width: width * fraction(totalBytes),
                child: const ColoredBox(color: AppColors.hairline),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: width * fraction(trackedBytes),
                child: ColoredBox(color: AppColors.accent),
              ),
              Positioned(
                key: const ValueKey<String>('memory-tier-allowance'),
                left: 0,
                top: 0,
                bottom: 0,
                width: width * fraction(allowanceBytes),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.textDim, width: 1.5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The bar 유저 asked to watch: the whole process against the high-water
/// mark, with the accounted-for part filled in the accent.
class _LiveBar extends StatelessWidget {
  const _LiveBar({
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
      key: const ValueKey<String>('memory-live-bar'),
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
                child: const ColoredBox(color: AppColors.hairline),
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

/// One accounted-for holding, with its share of the tracked total.
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
  final int bytes;
  final int pinned;
  final int ofBytes;
  final String pinnedLabel;
  final String Function(int) format;

  @override
  Widget build(BuildContext context) {
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
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
              Text(
                // ⛔The pinned figure rides the SAME line rather than
                // appearing on its own when non-zero: a row that grows a
                // second line when playback starts is UI that pops into
                // existence.
                pinned > 0
                    ? '${format(bytes)}  (${format(pinned)} $pinnedLabel)'
                    : format(bytes),
                style: const TextStyle(fontSize: 12, color: AppColors.textDim),
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
