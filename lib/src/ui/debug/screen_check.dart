import 'dart:async' show unawaited;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../core/red_and_blue_swapped.dart';
import '../../native/screen_texture.dart';
import '../text/pixel_size_label.dart';
import 'frame_stats.dart';

/// 🔬WHETHER FLUTTER SHOWS THE BYTES THE ENGINE WROTE, read off this
/// device: a surface made as a screen's are ([ScreenTexture.surfaceOf]),
/// filled with a pattern, shown through a texture of its own as a screen's
/// is ([SharedTexture]), and what Flutter drew of it read back
/// ([RenderRepaintBoundary.toImage]) against the surface's own bytes read
/// back by the engine ([GpuSurface.fingerprint]) — the stage-0 probe's own
/// comparison (packages/gpu_engine/example). Run once for each way a
/// screen was opened by ([ScreenTexture.path]), while the frame statistics
/// are up.
///
/// 🗣️유저 2026-11-23 (card the-galaxy-tab-canvas-went-slow-on-build-1095
/// ⓑ): 「모든가능성 철저하게 검사해서 디버그화면 만들면되지」 — on Android the
/// engine's Vulkan device writes an AHardwareBuffer and Flutter's own reads
/// it, with no release of the image between the two
/// (rust/src/platform/android.rs): a layout or a compression the other
/// device does not see shows here as `differs`, where the canvas would
/// only look wrong.
///
/// ⚖️The fill and the read-back wait for the GPU on the thread that builds
/// the app's frames — once a way, a [side]² surface, and only while the
/// frame statistics are up (공통 2026-11-24): the canvas's own screens
/// never do.
class ScreenCheck extends StatefulWidget {
  const ScreenCheck({super.key});

  /// The surface's side in texels: big enough that a driver lays it out as
  /// it lays a screen's — whether it compresses an image depends on its
  /// size —, small enough to read back at once.
  static const int side = 256;

  /// What the newest check said: `—` till one has run, `checking`, then
  /// `same`, `differs` with both fingerprints, or `failed:` and why.
  static final ValueNotifier<String> said = ValueNotifier('—');

  /// The way the check last ran for ([ScreenTexture.path]): run again
  /// once a screen opens another way.
  static String? _ranFor;

  /// What a check says of the fingerprint of what Flutter [shown] against
  /// the one the engine [written]: `same` and it, else `differs` and both.
  static String verdict({required int shown, required int written}) =>
      shown == written
      ? 'same ${_hex(written)}'
      : 'differs  shown ${_hex(shown)}  written ${_hex(written)}';

  static String _hex(int value) => value.toRadixString(16).padLeft(8, '0');

  /// Test seam: no check run yet.
  @visibleForTesting
  static void debugForget() {
    _ranFor = null;
    said.value = '—';
  }

  @override
  State<ScreenCheck> createState() => _ScreenCheckState();
}

class _ScreenCheckState extends State<ScreenCheck> {
  final GlobalKey _boundary = GlobalKey();
  int? _shown;

  // Asked again as the statistics publish: a screen opened another way
  // since is checked then.
  @override
  void initState() {
    super.initState();
    FrameStats.latest.addListener(_askAgain);
    _askAgain();
  }

  @override
  void dispose() {
    FrameStats.latest.removeListener(_askAgain);
    super.dispose();
  }

  void _askAgain() {
    final engine = ScreenTexture.engineOfThePath;
    final path = ScreenTexture.path;
    if (engine == null || path == ScreenCheck._ranFor) {
      return;
    }
    ScreenCheck._ranFor = path;
    unawaited(_check(engine));
  }

  Future<void> _check(GpuEngine engine) async {
    ScreenCheck.said.value = 'checking';
    const side = ScreenCheck.side;
    GpuSurface? surface;
    SharedTexture? texture;
    try {
      final made = surface = ScreenTexture.surfaceOf(engine, side, side);
      made
        ..fill(_seed)
        ..settle();
      await engine.done();
      final written = made.fingerprint();
      texture = await SharedTexture.register(made);
      texture.show(0);
      ScreenCheck.said.value = ScreenCheck.verdict(
        shown: await _seen(texture.id),
        written: written,
      );
    } on Object catch (error) {
      ScreenCheck.said.value = 'failed: $error';
    } finally {
      texture?.unregister();
      if (mounted) {
        setState(() => _shown = null);
      }
      await SchedulerBinding.instance.endOfFrame;
      surface?.free();
    }
  }

  /// The fingerprint of what Flutter drew of texture [id], one texel a
  /// pixel, in the surface's own order.
  Future<int> _seen(int id) async {
    if (!mounted) {
      throw StateError('the frame statistics were closed');
    }
    final ratio = View.of(context).devicePixelRatio;
    setState(() => _shown = id);
    for (var i = 0; i < 3; i++) {
      await SchedulerBinding.instance.endOfFrame;
    }
    final boundary = _boundary.currentContext?.findRenderObject();
    if (!mounted || boundary is! RenderRepaintBoundary) {
      throw StateError('the frame statistics were closed');
    }
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      if (image.width != ScreenCheck.side || image.height != ScreenCheck.side) {
        throw StateError('read ${pixelSizeLabel(image.width, image.height)}');
      }
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return fingerprintBytes(
        ScreenTexture.bgra
            ? redAndBlueSwapped(bytes!)
            : bytes!.buffer.asUint8List(),
      );
    } finally {
      image.dispose();
    }
  }

  static const int _seed = 7;

  @override
  Widget build(BuildContext context) {
    final logical = ScreenCheck.side / View.of(context).devicePixelRatio;
    return SizedBox.square(
      dimension: logical,
      child: RepaintBoundary(
        key: _boundary,
        child: switch (_shown) {
          null => const SizedBox.expand(),
          final id => Texture(textureId: id),
        },
      ),
    );
  }
}
