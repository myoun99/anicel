import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiMode, rootBundle;

import 'src/services/input/pen_sidecars.dart';
import 'src/services/pdf/pdf_render_service.dart';
import 'src/services/persistence/app_documents.dart' show AppStorage;
import 'src/ui/debug/measurement_mode.dart';
import 'src/ui/home_page.dart';
import 'src/ui/input/app_input_settings.dart' show AppInput;
import 'src/ui/theme/app_scroll_behavior.dart';
import 'src/ui/theme/app_theme.dart';

void main() {
  // FIRST, before anything reaches for a platform channel. The pen
  // sidecars do: PencilInteractionService installs a handler on
  // `qa_pen/ios`, and a MethodChannel needs the binding's messenger to
  // exist. That call is iOS-ONLY — every other platform returns before
  // touching the channel — so binding late cost nothing on Windows,
  // Android, macOS or Linux, and stopped the app dead at a white screen
  // on iPad and iPhone. CI could not see it either: it builds for iOS,
  // it does not launch there.
  WidgetsFlutterBinding.ensureInitialized();
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
  // The bundled conte-PDF fonts are OFL: their license must SHIP with the
  // binary that redistributes them, not just sit in the repo — the About
  // dialog's license page surfaces these entries (THIRD_PARTY.md).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'M PLUS 1p',
    ], await rootBundle.loadString('assets/fonts/OFL-MPLUS1p.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'IBM Plex Sans KR',
    ], await rootBundle.loadString('assets/fonts/OFL-IBMPlexSansKR.txt'));
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
  runApp(const AnicelApp());
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
        home: const HomePage(),
      ),
    );
  }
}
