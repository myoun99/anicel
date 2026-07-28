import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'src/services/input/pen_sidecars.dart';
import 'src/services/persistence/app_documents.dart' show AppStorage;
import 'src/ui/debug/measurement_mode.dart';
import 'src/ui/home_page.dart';
import 'src/ui/input/app_input_settings.dart' show AppInput;
import 'src/ui/theme/app_theme.dart';

void main() {
  // The pen sidecars (PEN-2/PEN-4): Wintab follows the input settings;
  // the macOS/Linux channel streams start on their platform. Absent
  // drivers/handlers stay permanently idle.
  PenSidecars.bind();
  // SAVE-1c: resolve the mobile app-documents home once (desktop no-op).
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled conte-PDF fonts are OFL: their license must SHIP with the
  // binary that redistributes them, not just sit in the repo — the About
  // dialog's license page surfaces these entries (THIRD_PARTY.md).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['M PLUS 1p'],
      await rootBundle.loadString('assets/fonts/OFL-MPLUS1p.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['IBM Plex Sans KR'],
      await rootBundle.loadString('assets/fonts/OFL-IBMPlexSansKR.txt'),
    );
  });
  unawaited(AppStorage.ensureInitialized());
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
        // Edit ▸ Frame Timing Overlay: a MaterialApp property, so the
        // toggle has to reach this build — that is what makes it usable
        // on a tablet, where a --dart-define costs a rebuild and an
        // install.
        MeasurementMode.frameTimingOverlay,
      ]),
      builder: (context, _) => MaterialApp(
        title: 'Anicel',
        theme: buildAppTheme(),
        showPerformanceOverlay: MeasurementMode.frameTimingOverlay.value,
        home: const HomePage(),
      ),
    );
  }
}
