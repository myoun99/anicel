// CocoaPods compiles Classes/ only; the real source lives in src/ shared
// with every other platform. Same pattern as the sibling forwarders.
//
// Where the display's vblanks are and a precise wait — Windows' own; on an
// Apple platform both answer that there is nothing to say (the engine's
// vsync IS the display's there), but the symbols are the engine's on every
// platform, as the Dart side looks them up on every platform.
#include "../../src/qa_display.c"
