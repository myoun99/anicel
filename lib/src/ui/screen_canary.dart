import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../native/lost_screen.dart';
import 'present_pacing.dart' show aClockRuns;
import 'raster_watch.dart';

/// A pixel the screen's context did not say back: the colour asked, as the
/// four bytes it is read as (red first, in hex), what came instead — the
/// bytes read, or why none were — and when it was asked.
typedef PixelNotSaid = ({String asked, String instead, DateTime askedAt});

/// 🚨WHILE THE SCREEN RESTS, ITS OWN CONTEXT IS ASKED TO DRAW ONE PIXEL AND
/// SAY IT BACK — WHERE IT DOES NOT, THE APP WRITES WHAT IT WAS DOING.
/// Evidence only (`LostScreenEvidence.noteThePixelNotSaidOnce`).
///
/// 🗣️a-real-gpu-reset-went-unheard-on-the-main-pc-Q1 (유저 2026-11-22):
/// 「앱이 화면용 컨텍스트로 1픽셀을 그려 되읽는다 — 처음엔 기록만」.
///
/// WHY: where a driver takes the screen's device alone, the window stands
/// on its last picture and nothing says so (11-22 16:47, NVIDIA). The
/// runner's watch asks a device of its own, which stood; and Flutter
/// 3.47.4's Windows embedder gives out no device of the screen's, tells a
/// present that failed to no one, and says a frame it could not put up
/// drawn as any is ([RasterWatch] has where each was read). A context
/// whose device went draws nothing, so a pixel drawn through it and read
/// back is the one question that reaches the screen's own device.
///
/// - ONLY WHILE THE SCREEN RESTS — no clock running ([aClockRuns]) and no
///   frame handed over for [rest]: a pixel is drawn on the thread that
///   draws the frames, and no frame is to wait behind one, a playback's
///   least of all (the option chosen, its third cost: 「재생 중에는
///   프레임을 밀까 봐 안 묻는다」).
///   ⚠️THE CLOCK IS ASKED OF ITSELF: a playback holding one picture draws
///   no frame (`LookOnlyFrames`), and the frame watch counts the frames
///   drawn (board a-frame-handed-over-after-the-loss-word-is-not-said-
///   drawn, 2026-11-23). ↩️Till then it counted every frame begun, a
///   playback's looks with them, and that alone kept the pixel out of one
///   — a value answering whether the screen rests and whether the raster
///   thread was handed a frame, which part.
/// - 🚨THE RUNNER'S WATCH IS ASKED FIRST, and the pixel drawn only where
///   it says, asked just then, that its device stands
///   ([LostScreen.stands]). On the Surface (Intel, 11-18 15:08) the first
///   thing drawn after a reset of the whole adapter ended the process, and
///   what the watch last said may be a tenth of a second old. Where no
///   runner watches nothing is asked at all: what Flutter tells of a lost
///   screen was read for Windows.
/// - ONCE: after a pixel not said back, no other is asked this run.
///
/// 🚨A PIXEL NOT SAID BACK IS A WORD OF A LOSS
/// ([LostScreen.sayThePixelNotSaid]): written, and said to the runner,
/// which takes it through the door the watch's word goes through — the
/// window to save and start again, or the engine told where it restores. ↩️「처음엔 기록만」 (the option chosen)
/// wrote it and asked nothing, till 「실제 사고 한 번이 그 기록으로 맞다고
/// 확인되면 저장 · 다시 시작 창에 잇는다」: 2026-11-23 20:40 (검증, main PC),
/// two nvlddmkm 153s, the watch and the app's engine silent, and this
/// pixel failing to bind the screen's context — the screen stood still.
abstract final class ScreenCanary {
  /// How long no frame was handed over before the screen is said to rest —
  /// the answer's 「새 프레임이 1초 넘게 없을 때」.
  static const Duration rest = Duration(seconds: 1);

  /// How often a pixel is asked while the screen rests.
  // ⏳My number (the answer says 「몇 초에 한 번」): a screen that stopped
  // is written within seconds of it, for one pixel drawn each.
  static const Duration every = Duration(seconds: 5);

  /// The pixel the screen's context did not say back, once one was not
  /// this run — null till then.
  static ValueListenable<PixelNotSaid?> get notSaid => _notSaid;
  static final ValueNotifier<PixelNotSaid?> _notSaid = ValueNotifier(null);

  /// What asks every [every], once installed; one asking at a time; and
  /// how many pixels were asked, which says each one's colour.
  static Timer? _asks;
  static bool _asking = false;
  static int _asked = 0;

  /// Asks for the app's lifetime: `main`, once.
  static void install() {
    _asks ??= Timer.periodic(every, (_) => unawaited(ask()));
  }

  /// Test seam: the clock the screen's rest and a late timer are told by.
  @visibleForTesting
  static DateTime Function()? debugClockOverride;

  static DateTime _now() => (debugClockOverride ?? DateTime.now)();

  /// Test seam: what draws a pixel in place of [readBack] — a context
  /// whose device went is not one a test has.
  @visibleForTesting
  static Future<Uint8List> Function(int argb)? debugDrawOverride;

  /// One asking: nothing where a pixel was not said back or the screen
  /// said gone this run, nor while a clock runs or frames are handed over;
  /// else the runner's watch, and a pixel where it says its device stands.
  @visibleForTesting
  static Future<void> ask() async {
    if (_asking || _notSaid.value != null || LostScreen.hasGone) {
      return;
    }
    if (aClockRuns() || _now().difference(RasterWatch.handedOverAt) <= rest) {
      return;
    }
    _asking = true;
    try {
      final stands = await LostScreen.stands();
      if (stands == null) {
        // No runner watches here, and none will.
        _asks?.cancel();
      } else if (stands) {
        await _askAPixel();
      }
    } finally {
      _asking = false;
    }
  }

  static Future<void> _askAPixel() async {
    final askedAt = _now();
    _asked += 1;
    final argb = colorOf(_asked);
    final asked = bytesOf(argb);
    String? instead;
    try {
      final draw = debugDrawOverride ?? readBack;
      final read = await draw(argb).timeout(RasterWatch.patience);
      if (!listEquals(read, asked)) {
        instead = 'read ${_hex(read)}';
      }
    } on TimeoutException {
      // ⛔Not the machine standing still ([RasterWatch] says the same of
      // its own wait): a timer far later than it was set for waited on no
      // context.
      if (_now().difference(askedAt) <= RasterWatch.patience * 2) {
        instead = 'nothing in ${RasterWatch.patience.inSeconds} s';
      }
    } on Object catch (error) {
      instead = 'failed: $error';
    }
    if (instead != null) {
      _notSaid.value = (
        asked: _hex(asked),
        instead: instead,
        askedAt: askedAt,
      );
      await LostScreen.sayThePixelNotSaid(askedAt);
    }
  }

  /// The colour of the [asking]th pixel, as 0xAARRGGBB — opaque, and
  /// another each time: a pixel read back as asked was drawn for that
  /// asking.
  @visibleForTesting
  static int colorOf(int asking) =>
      0xFF000000 | ((asking * 0x9E3779B1) & 0x00FFFFFF);

  /// [argb] as the four bytes a pixel of it is read as: red first.
  @visibleForTesting
  static Uint8List bytesOf(int argb) => Uint8List.fromList([
    (argb >> 16) & 0xFF,
    (argb >> 8) & 0xFF,
    argb & 0xFF,
    (argb >> 24) & 0xFF,
  ]);

  static String _hex(List<int> bytes) => [
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join();

  /// One pixel of [argb] drawn through the context the screen is drawn
  /// with, read back as its four bytes, red first.
  static Future<Uint8List> readBack(int argb) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(ui.Color(argb), ui.BlendMode.src);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(1, 1);
      try {
        // No bytes fails as any failure of the draw does.
        final bytes = (await image.toByteData())!;
        return bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// Test seam: a run that asked no pixel, and asks none till installed.
  @visibleForTesting
  static void debugForget() {
    _asks?.cancel();
    _asks = null;
    _asking = false;
    _asked = 0;
    _notSaid.value = null;
  }
}
