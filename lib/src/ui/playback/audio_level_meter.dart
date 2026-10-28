import 'package:flutter/material.dart';

import 'canvas_playback_controller.dart';
import '../text/app_strings.dart' show AppText;
import '../repaint_props.dart';
import '../theme/app_theme.dart' show AppColors;
import '../widgets/field_slider.dart';
import '../widgets/tick_layer.dart';

/// The playback level meter (AUDIO-PRO R2): two thin bars fed by the
/// device transport's PRE-CLIP bus peaks. Green through the working
/// range, amber approaching full scale, red at/over 1.0 — the moment the
/// output stage starts clipping, which until now only ears could catch.
///
/// Repaints ride the playback frame notifier (the tick cadence playback
/// already broadcasts); an inactive or fallback run meters silence.
///
/// 🗣️F-463 ③ (유저 2026-10-25): 「마이크버튼 옆 게인 표시하는거, 이런식으로
/// 뭔지모르겟는데 공간차지하는 느낌 싫으니 처음부터 뭔지 알도록. 뭔가
/// 외곽선안에 바탕색 깔아서 지금 게인 0이다 라는거 보여주는식」 — the bars
/// stand in a WELL, a settings bar's frame ([FieldSlider.frameOf]) on the
/// fill a well cut into a panel wears ([AppColors.backdrop]), there at rest
/// and empty while there is no level. ↩️T29 (유저 2026-08-13: 「드롭율 왼쪽에
/// 이상한 바탕색? 배경? 사각형 패딩같은거 있는데 삭제」) took the grey
/// trough away, and a silent meter painted nothing: an empty seat beside the
/// mic. That trough had no edge and stood against the drop readout, which
/// is a glyph's overlay now (F-463 ②).
class AudioLevelMeter extends StatelessWidget {
  const AudioLevelMeter({
    super.key,
    required this.controller,
    required this.resolvePeaks,
    this.metering = true,
    this.refused = false,
  });

  final CanvasPlaybackController controller;

  /// The transport's [AudioDeviceTransport.meterPeaks] (injected so the
  /// widget stays testable without a device).
  final ({double left, double right}) Function() resolvePeaks;

  /// Whether this meter reads the peaks at all. A transport row keeps the
  /// meter's seat while another scope plays (F-111), and it must not light
  /// up with that scope's sound.
  final bool metering;

  /// Whether the output would not open: the well is red
  /// (playback-waits-for-its-sound-Q1, 유저 2026-10-17 — said on the
  /// meter's own seat, so nothing beside it moves).
  final bool refused;

  /// The well's size, its frame included.
  static const double width = 10;
  static const double height = 24;

  /// Between the frame's edge and the bars.
  static const double _inset = 2;

  /// 🚨THE METER IS A TICK LAYER OF ITS OWN
  /// (playback-making-pictures-shakes-the-frames, 10-11). It is built again
  /// on every frame played, and built bare it was built in the scope of the
  /// tab strip's tick layer above it: every frame laid out and repainted the
  /// whole strip, tabs and all — 🔬90 render objects a frame in the strip of
  /// the panel playing, 52 in a strip whose meter was only saying silence.
  /// Its seat is fixed (F-111), so its own layer keeps the tick to its bars;
  /// and a meter that is not metering hears no frame at all. The well is
  /// outside the layer: a tick paints the bars alone.
  @override
  Widget build(BuildContext context) {
    final frame = FieldSlider.frameOf(height, enabled: true);
    return SizedBox(
      key: const ValueKey<String>('audio-level-meter'),
      width: width,
      height: height,
      child: DecoratedBox(
        key: refused
            ? const ValueKey<String>('playback-output-refused')
            : null,
        decoration: ShapeDecoration(
          color: refused ? AppColors.danger : AppColors.backdrop,
          shape: frame.shape,
        ),
        child: Padding(
          padding: const EdgeInsets.all(_inset),
          child: TickLayer(
            child: Semantics(
              label: AppText.strings.audioLevelMeter,
              child: metering
                  ? ValueListenableBuilder<int?>(
                      valueListenable: controller.globalFrameIndexListenable,
                      builder: (context, frame, _) {
                        final peaks = frame == null
                            ? (left: 0.0, right: 0.0)
                            : resolvePeaks();
                        return CustomPaint(
                          painter: _MeterPainter(
                            left: peaks.left,
                            right: peaks.right,
                          ),
                        );
                      },
                    )
                  : const CustomPaint(
                      painter: _MeterPainter(left: 0, right: 0),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
class _MeterPainter extends CustomPainter with RepaintOnProps {
  const _MeterPainter({required this.left, required this.right});

  final double left;
  final double right;

  static Color _colorFor(double peak) {
    if (peak >= 1.0) {
      return const Color(0xFFE53935); // clipping
    }
    if (peak >= 0.7) {
      return const Color(0xFFFFB300); // hot
    }
    return const Color(0xFF43A047);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = (size.width - 1) / 2;
    void bar(double peak, double x) {
      final clamped = peak > 1.0 ? 1.0 : (peak < 0.0 ? 0.0 : peak);
      final height = size.height * clamped;
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - height, barWidth, height),
        Paint()..color = _colorFor(peak),
      );
    }

    bar(left, 0);
    bar(right, barWidth + 1);
  }

  @override
  Object get props => (left, right);
}
