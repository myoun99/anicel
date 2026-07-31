import 'package:flutter/material.dart';
import '../text/full_width_numerals.dart';

/// One position axis for the nav bar's scrub: how many stops, where the
/// boundary ticks sit, and what a stop is called. The tab defines the
/// domain (Sequence/Image = frames, Cels = cels, Timesheet = pages) —
/// the bar only knows positions.
class ExportNavAxis {
  const ExportNavAxis({
    required this.length,
    this.ticks = const [],
    this.captionOf,
  });

  final int length;

  /// Positions that start a new group (cut boundaries, cel-label
  /// boundaries) — drawn as small ticks.
  final List<int> ticks;

  /// The playhead caption for a position (`F58`, `A-3`); null = 1-based
  /// number.
  final String Function(int position)? captionOf;

  String caption(int position) =>
      captionOf?.call(position) ?? '${position + 1}';

  int clamp(int position) =>
      length <= 0 ? 0 : position.clamp(0, length - 1);
}

/// The v10 nav bar (전 탭 공통): optional in/out number fields at the very
/// ends, ◀▶ inside them, the scrub bar center. In/out marks paint as a
/// fill band; the playhead carries its caption.
class ExportNavBar extends StatelessWidget {
  const ExportNavBar({
    super.key,
    required this.axis,
    required this.position,
    required this.onChanged,
    required this.enabled,
    this.inController,
    this.outController,
    this.onInOutEdited,
    this.inMark,
    this.outMark,
  });

  final ExportNavAxis axis;
  final int position;
  final ValueChanged<int> onChanged;
  final bool enabled;

  /// Present on the Sequence tab: 1-based in/out fields, two-way with the
  /// scrub marks.
  final TextEditingController? inController;
  final TextEditingController? outController;
  final VoidCallback? onInOutEdited;

  /// 0-based marks on the axis (null = unclipped end).
  final int? inMark;
  final int? outMark;

  void _step(int delta) {
    if (axis.length > 0) {
      onChanged(axis.clamp(position + delta));
    }
  }

  Widget _endField(
    BuildContext context,
    TextEditingController controller,
    String key,
  ) {
    return SizedBox(
      width: 44,
      child: TextField(
        key: ValueKey<String>(key),
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: halfWidthDigitsOnly,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => onInOutEdited?.call(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stepButton(String glyph, int delta, String key) => InkWell(
      key: ValueKey<String>(key),
      onTap: enabled && axis.length > 0 ? () => _step(delta) : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(glyph, style: theme.textTheme.labelSmall),
      ),
    );

    return Row(
      children: [
        if (inController != null) ...[
          _endField(context, inController!, 'export-range-start-field'),
          const SizedBox(width: 6),
        ],
        stepButton('◀', -1, 'export-nav-prev'),
        const SizedBox(width: 6),
        Expanded(
          child: _ExportScrubBar(
            key: const ValueKey<String>('export-nav-scrub'),
            axis: axis,
            position: position,
            inMark: inMark,
            outMark: outMark,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 6),
        stepButton('▶', 1, 'export-nav-next'),
        if (outController != null) ...[
          const SizedBox(width: 6),
          _endField(context, outController!, 'export-range-end-field'),
        ],
      ],
    );
  }
}

class _ExportScrubBar extends StatelessWidget {
  const _ExportScrubBar({
    super.key,
    required this.axis,
    required this.position,
    required this.inMark,
    required this.outMark,
    required this.enabled,
    required this.onChanged,
  });

  final ExportNavAxis axis;
  final int position;
  final int? inMark;
  final int? outMark;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seekTo(double dx) {
          if (!enabled || axis.length <= 0 || width <= 0) {
            return;
          }
          final fraction = (dx / width).clamp(0.0, 1.0);
          onChanged(axis.clamp((fraction * axis.length).floor()));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekTo(details.localPosition.dx),
          onHorizontalDragStart: (details) =>
              seekTo(details.localPosition.dx),
          onHorizontalDragUpdate: (details) =>
              seekTo(details.localPosition.dx),
          child: SizedBox(
            height: 26,
            child: CustomPaint(
              painter: _ExportScrubPainter(
                axis: axis,
                position: position,
                inMark: inMark,
                outMark: outMark,
                trackColor: theme.dividerColor,
                accent: theme.colorScheme.primary,
                dimColor: theme.colorScheme.onSurfaceVariant,
                captionStyle: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExportScrubPainter extends CustomPainter {
  _ExportScrubPainter({
    required this.axis,
    required this.position,
    required this.inMark,
    required this.outMark,
    required this.trackColor,
    required this.accent,
    required this.dimColor,
    required this.captionStyle,
  });

  final ExportNavAxis axis;
  final int position;
  final int? inMark;
  final int? outMark;
  final Color trackColor;
  final Color accent;
  final Color dimColor;
  final TextStyle? captionStyle;

  double _x(Size size, int position) => axis.length <= 1
      ? 0
      : position / (axis.length - 1) * size.width;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height * 0.62;
    final track = Paint()
      ..color = trackColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      track,
    );
    if (axis.length <= 0) {
      return;
    }

    final start = inMark ?? 0;
    final end = outMark ?? axis.length - 1;
    if (end >= start && (inMark != null || outMark != null)) {
      canvas.drawLine(
        Offset(_x(size, start), centerY),
        Offset(_x(size, end), centerY),
        Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }

    final tickPaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.2;
    for (final tick in axis.ticks) {
      if (tick <= 0 || tick >= axis.length) {
        continue;
      }
      final x = _x(size, tick);
      canvas.drawLine(
        Offset(x, centerY - 6),
        Offset(x, centerY + 6),
        tickPaint,
      );
    }

    final playheadX = _x(size, axis.clamp(position));
    canvas.drawLine(
      Offset(playheadX, centerY - 9),
      Offset(playheadX, centerY + 8),
      Paint()
        ..color = accent
        ..strokeWidth = 2,
    );
    final style = captionStyle;
    if (style != null) {
      final painter = TextPainter(
        text: TextSpan(text: axis.caption(axis.clamp(position)), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      // A caption wider than the bar (squeezed layouts) just skips —
      // clamp with an inverted range throws.
      final maxLeft = size.width - painter.width;
      if (maxLeft >= 0) {
        painter.paint(
          canvas,
          Offset((playheadX + 4).clamp(0.0, maxLeft), 0),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ExportScrubPainter oldDelegate) =>
      oldDelegate.axis.length != axis.length ||
      !identical(oldDelegate.axis.ticks, axis.ticks) ||
      oldDelegate.position != position ||
      oldDelegate.inMark != inMark ||
      oldDelegate.outMark != outMark ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.accent != accent;
}
