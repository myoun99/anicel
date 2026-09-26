import 'dart:async' show unawaited;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiMode, rootBundle;

import 'src/services/persistence/app_support_path.dart';
import 'src/services/input/pen_sidecars.dart';
import 'src/services/pdf/pdf_render_service.dart';
import 'src/services/persistence/app_documents.dart' show AppStorage;
import 'src/services/persistence/app_ui_scale_store.dart';
import 'src/ui/canvas/colour_key_shader.dart';
import 'src/ui/debug/frame_stats.dart';
import 'src/ui/debug/frame_stats_readout.dart';
import 'src/ui/debug/repaint_cause.dart';
import 'src/ui/debug/measurement_mode.dart';
import 'src/ui/effective_device_pixel_ratio.dart';
import 'src/ui/home_page.dart';
import 'src/ui/layout/device_grid_audit.dart';
import 'src/ui/shortcuts/keyboard_ime_switch.dart';
import 'src/models/app_input_settings.dart' show AppInput;
import 'src/services/diagnostics/memory_black_box.dart';
import 'src/ui/theme/app_scroll_behavior.dart';
import 'src/ui/text/app_strings.dart';
import 'src/ui/theme/app_theme.dart';
import 'src/ui/ui_scale.dart';
import 'src/ui/ui_scale_binding.dart';

Future<void> main() async {
  // FIRST, before anything reaches for a platform channel. The pen
  // sidecars do: PencilInteractionService installs a handler on
  // `qa_pen/ios`, and a MethodChannel needs the binding's messenger to
  // exist. That call is iOS-ONLY — every other platform returns before
  // touching the channel — so binding late cost nothing on Windows,
  // Android, macOS or Linux, and stopped the app dead at a white screen
  // on iPad and iPhone. CI could not see it either: it builds for iOS,
  // it does not launch there.
  //
  // [AnicelBinding] rather than [WidgetsFlutterBinding]: it is the same
  // binding plus the UI scale in the root device matrix.
  AnicelBinding.ensureInitialized();
  // 🚨★★★**BEFORE ANY STORE READS ANYTHING.** The settings moved into a
  // room of their own (`<container>/Settings/`), and a store that resolved
  // its path first would find nothing, write a default, and hand the user
  // a factory-fresh app whose real settings were sitting one folder up.
  // ⛔The migration never deletes and never overwrites — every step is a
  // rename into a name that does not exist yet — so the worst a failure
  // here can do is leave an entry at the old address for the next launch
  // to try again. See [migrateSettingsIntoTheirRoom].
  migrateSettingsIntoTheirRoom();
  // Full screen on the platforms that have an OS strip to give up (유저
  // 확정, 프로크리·카리페그처럼): the clock and the battery cost a band of
  // canvas across the top, and a drawing app is the case the immersive
  // modes exist for. Sticky, so an edge swipe still brings the bars back
  // for a moment instead of stranding the user.
  //
  // Android hides the status AND navigation bars; iOS hides the status bar
  // (its home indicator is not ours to remove — that needs
  // `prefersHomeIndicatorAutoHidden` natively, and even then it only
  // fades). Desktop has no system overlays, so this is a no-op there.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  // The pen sidecars (PEN-2/PEN-4): Wintab follows the input settings;
  // the macOS/Linux channel streams start on their platform. Absent
  // drivers/handlers stay permanently idle.
  PenSidecars.bind();
  // I-19 ④: on Windows the IME listens only while a text field holds the
  // keyboard, so a Japanese or Korean input mode cannot swallow a shortcut.
  // Once, for the app's lifetime — see the class.
  KeyboardImeSwitch.install();
  // 🚨AWAITED, BEFORE THE FIRST FRAME. The colour key on a folder is a
  // fragment shader, and a `Paint` is built inside a paint — which cannot
  // wait for an asset. A composite that reached a key with no program would
  // have to drop the effect, and a dropped effect is the screen lying about
  // the file. Loading it here is what lets the paint-time guard stay a
  // guard rather than a case.
  await ColourKeyShader.load();
  // The bundled fonts are OFL: their license must SHIP with the binary that
  // redistributes them, not just sit in the repo — the About dialog's license
  // page surfaces these entries (THIRD_PARTY.md).
  //
  // ⚠️The two families are the APP's (BIZ UDPGothic · 나눔고딕, 유저 확정
  // 2026-08-28) — the UI's, and since 2026-09-25 the conte PDF's too, which
  // embeds the same files.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'BIZ UDPGothic',
    ], await rootBundle.loadString('assets/fonts/OFL-BIZUDPGothic.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Nanum Gothic',
    ], await rootBundle.loadString('assets/fonts/OFL-NanumGothic.txt'));
    // PDFium binaries bundle at build time (pdfrx native assets); their
    // license requires the notice to ship with binary redistributions —
    // pub's automatic NOTICES only covers the Dart packages, not the
    // downloaded engine itself.
    yield LicenseEntryWithLineBreaks(const [
      'PDFium',
    ], await rootBundle.loadString('assets/licenses/LICENSE-PDFium.txt'));
  });
  unawaited(AppStorage.ensureInitialized());
  // Probe PDFium once at startup (loads the bundled library, ~ms): the
  // import window and Preferences > System then have a settled answer
  // instead of probing mid-flow. Absence is a reported state, not an
  // error.
  unawaited(PdfRenderService.ensureAvailable());
  // Settings ▸ Frame Stats. HERE and not inside the `ListenableBuilder`
  // below: that builder re-runs on every accent change, and registering
  // a timings callback there would stack a duplicate each time. The
  // recorder is inert until the switch is on — it costs one bool per
  // frame batch.
  FrameStats.install();
  RepaintCause.install();
  // Inert until `DeviceGridAudit.strict` is set — the per-frame cost while
  // it is off is one bool. HERE for the same reason as the two above: a
  // persistent frame callback cannot be removed, so registering it
  // anywhere that re-runs would stack duplicates.
  DeviceGridAudit.install();
  // AWAITED, unlike every other settings restore. The rest land late and
  // the app repaints; this one decides how large the window's contents are
  // laid out, so restoring it after the first frame would show 100% and
  // then jump. One small file read, before a frame that costs far more.
  //
  // A failure here is a default, not a crash: `load` swallows a missing or
  // corrupt file and returns null.
  final storedScale = await AppUiScaleStore().load();
  if (storedScale != null) {
    AppUiScale.value.value = storedScale;
  } else {
    // ⛔FIRST RUN ONLY (유저 2026-08-31, I-11: 「초기값은 첫 실행 때만
    // 정해짐」). `load` returns null exactly when no settings file exists,
    // so a stored scale — even one equal to the default — is never
    // reconsidered. The branch structure IS the guarantee: there is no path
    // from here that can overwrite a value the user chose.
    AppUiScale.value.value = AppUiScale.firstRunScaleFor(
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0,
    );
  }
  // Read BEFORE this launch starts writing its own: an entry with no END
  // means the app died in the middle of that work, and a memory kill
  // leaves nothing else behind — no exception, no crash report, nothing
  // in App Store Connect. Read once, then the page is turned, so a kill
  // is reported at the next launch and not at every launch after it.
  MemoryBlackBox.lastUnfinished = MemoryBlackBox.unfinishedEntry();
  MemoryBlackBox.reset();
  runApp(const AnicelApp());
  // 🗣️F-178 (유저 2026-09-24): 「ios에서 녹음누르면 권한묻는데 그게아니라 앱
  // 실행시로 못하나? 한번 권한 얻으면 심플하잖아」. Once, at launch, after the
  // first frame so the system dialog lands on the app rather than on an empty
  // window. The record button still awaits the same ask, so no take rolls
  // before the answer is in — and an answer already given comes back at
  // once, which is what makes this cheap on every later launch.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(AppStorage.ensureMicrophoneAccess()),
  );
}

class AnicelApp extends StatelessWidget {
  const AnicelApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The theme rides the LIVE accent settings (UI-R22 #5) and the
    // pointer-input policy (UI-R22 #6): changing either rebuilds the app
    // so gesture device sets and scroll behaviors re-derive.
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppColors.accentSettings,
        AppInput.settings,
        // Settings ▸ Frame Timing Overlay: a MaterialApp property, so the
        // toggle has to reach this build — that is what makes it usable
        // on a tablet, where a --dart-define costs a rebuild and an
        // install.
        MeasurementMode.frameTimingOverlay,
        // The UI scale has TWO halves and this is the widget one: the
        // binding rescales the root matrix, and this rebuild carries the
        // matching MediaQuery down (see
        // [EffectiveDevicePixelRatioScope]). Both hang off the same
        // notifier so they cannot land a frame apart.
        AppUiScale.value,
        // 🚨THE PROGRAM LANGUAGE, because the FONT depends on it
        // ([AppTypography.familyFor]): 한자는 일본과 중국이 코드포인트를
        // 공유하면서 자형이 다르므로, 언어가 바뀌면 얼굴도 바뀌어야 한다.
        // ⛔Without this the theme would keep the face it was built with and
        // the setting would look like it did nothing.
        AppText.settings,
      ]),
      builder: (context, _) => MaterialApp(
        title: 'Anicel',
        theme: buildAppTheme(),
        // ONE scrollbar in the app, and this is where it is installed.
        // It has to be the App's and not a wrapper below it: dialogs,
        // popup menus and dropdown routes are children of the Navigator's
        // overlay rather than of [HomePage], and most of the surfaces that
        // had no bar of their own live exactly there.
        scrollBehavior: const AppScrollBehavior(),
        showPerformanceOverlay: MeasurementMode.frameTimingOverlay.value,
        // Above every route and below the Navigator: the measurement
        // readouts have to outrank dialogs and popovers, which are the
        // Navigator's children.
        // Inside the builder so the scope sits ABOVE the Navigator:
        // dialogs and popup routes are the Navigator's children, not
        // [HomePage]'s, and a route built outside the scope would fall
        // back to MediaQuery — the exact wrong grid this source exists to
        // replace.
        // ⛔NOT because "MaterialApp is what inserts MediaQuery": it is
        // not. `MaterialApp` never introduces its own — the `View` widget
        // does — so mounting above `MaterialApp` would have worked too,
        // and that is where a live UI scale will want to live (inside the
        // `ListenableBuilder` above). Moving it there is fine; moving it
        // BELOW the Navigator is not.
        builder: (context, child) => EffectiveDevicePixelRatioScope(
          uiScale: AppUiScale.value.value,
          child: MeasurementReadoutHost(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
