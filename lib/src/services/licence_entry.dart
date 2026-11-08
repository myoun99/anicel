import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks;

/// [text], a licence the about screen shows under [packages].
///
/// 🚨ITS LINES END IN LF, WHEREVER THE TEXT CAME FROM (서피스 검증
/// 2026-11-08 10:35: a box at the end of every line of RNNoise's and
/// PDFium's). Flutter's parser breaks a paragraph's line at `\n` only, so
/// the `\r` before it stays in the line and is drawn as a letter. A text
/// reaches here in CRLF two ways: a checkout under `core.autocrlf` hands
/// every bundled `.txt` back so (the blobs are LF), and five crates'
/// licence files are CRLF as they ship — rust_crates.json carries them as
/// tool/crate_notices.dart read them. ⛔Not a `.gitattributes` rule: no
/// checkout rule reaches the crates', and one place every entry is made
/// through cannot miss a text added later.
LicenseEntry licenceEntry(List<String> packages, String text) =>
    LicenseEntryWithLineBreaks(packages, text.replaceAll(_lineEnd, '\n'));

final _lineEnd = RegExp('\r\n?');
