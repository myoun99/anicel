import 'dart:async';

import 'package:flutter/material.dart';

import '../diagnostics/memory_census.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';

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
      if (census.rssBytes > _peakBytes) {
        _peakBytes = census.rssBytes;
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
    final rss = census?.rssBytes ?? 0;
    final tracked = census?.trackedBytes ?? 0;
    final untracked = census?.untrackedBytes ?? 0;
    final available = census?.availableBytes;
    final items = census?.items ?? const <MemoryCensusItem>[];

    return SingleChildScrollView(
      key: const ValueKey<String>('memory-settings-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _TotalRow(
            label: strings.memoryProcessTotal,
            value: _mb(rss),
            emphasis: true,
          ),
          const SizedBox(height: 6),
          _LiveBar(
            trackedBytes: tracked,
            totalBytes: rss,
            peakBytes: _peakBytes,
          ),
          const SizedBox(height: 6),
          _TotalRow(label: strings.memoryTracked, value: _mb(tracked)),
          _TotalRow(label: strings.memoryUntracked, value: _mb(untracked)),
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
  }
}

/// One of the three totals under the bar.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasis ? 13 : 12,
      color: emphasis ? AppColors.text : AppColors.textDim,
      fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
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
