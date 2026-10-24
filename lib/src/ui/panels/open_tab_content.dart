import 'package:flutter/widgets.dart';

import '../text/app_strings.dart';
import '../timeline/memo_token.dart' show ByIdentity, Kept, keptWhileSame;

/// An open tab's content, built when the tab opens and handed back as the
/// IDENTICAL instance every time its holder is built again while the tab
/// stays open (R12-①): the panel's subtree is then skipped wholesale by a
/// tab switch elsewhere, a lock toggle, a fold or any layout notify.
///
/// 🚨★EVERY TAB, the light ones too (2026-10-24). ↩️It was a tab's opt-in
/// (`cachesContent`) and only the tabs once kept alive offstage had it — the
/// flag outlived the keep-alive it was born with (R12, 07-13) when panels
/// stopped being kept (10-14). The rest were rebuilt whole by every layout
/// notify: 🔬on the user's layout a bottom-dock tab switch or fold rebuilt
/// the tool library, the tool settings, the colour and the onion panels
/// with it, about 2ms of a fold's 10.
///
/// The content is built again only when it is no longer built for the same
/// thing:
/// - another tab ([tabId]);
/// - another [identity] — 🚨the session stopped being stable with a project
///   per tab (I-7): a cached canvas went on showing the project that was
///   switched away from, because nothing here ran its builder again;
/// - another LANGUAGE, program or notation (the notation reprints a sheet,
///   UI-R10 #7) — every keep's fact ([keptWhileSame]), heard here: 🚨four
///   panels subscribed to it for themselves, and the rest were reached
///   only by the app's root rebuild, which a handed-back instance stops.
///
/// CONTRACT for [build]: it closes over stable objects only (the session,
/// long-lived notifiers) and subscribes to what it shows itself.
class OpenTabContent extends StatefulWidget {
  const OpenTabContent({
    super.key,
    required this.tabId,
    required this.identity,
    required this.build,
  });

  final String tabId;
  final Object? identity;
  final Widget Function() build;

  @override
  State<OpenTabContent> createState() => _OpenTabContentState();
}

class _OpenTabContentState extends State<OpenTabContent> {
  final Map<Type, Kept<(String, ByIdentity<Object?>)>> _held = {};

  @override
  void initState() {
    super.initState();
    AppText.settings.addListener(_languageChanged);
  }

  @override
  void dispose() {
    AppText.settings.removeListener(_languageChanged);
    super.dispose();
  }

  void _languageChanged() => setState(() {});

  @override
  Widget build(BuildContext context) => keptWhileSame(
    _held,
    OpenTabContent,
    (widget.tabId, ByIdentity(widget.identity)),
    widget.build,
  );
}
