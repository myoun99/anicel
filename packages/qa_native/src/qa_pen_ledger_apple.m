// THE PEN LEDGER (H43) — what the platform said about each pen sample,
// written down BEFORE Flutter hears of it, and read by the brush
// synchronously, by the sample's own timestamp.
//
// Why a ledger and not a channel: a channel message and a pointer event
// travel two queues with no order between them, and the brush has to know
// about THIS sample while it handles THIS sample. A write that happens
// before the event reaches Flutter, read through FFI while the event is
// being handled, cannot arrive late.
//
// iOS — UIKit's word on Apple Pencil force and altitude. Either can be an
// ESTIMATE when a sample is taken (`estimatedProperties`), one UIKit will
// correct (`estimatedPropertiesExpectingUpdates`) or one it calls final,
// and a correction comes later through
// `touchesEstimatedPropertiesUpdated`, which Flutter's engine does not
// implement. The Runner's view controller hands both to
// +[QaPenLedger noteTouches:] and +[QaPenLedger updateTouches:] ahead of its
// super calls. (Location can be estimated too; the brush does not wait on
// position, so it is not kept.)
//
// macOS — the tablet pressure and tilt Flutter's embedder drops. A local
// event monitor (qa_pen_ledger_start) sees every left-mouse event before
// the window does and writes both, or that it is not a tablet event.
//
// Compiled for Apple only, through the ios/ and macos/ Classes forwarders.

#import <TargetConditionals.h>
#import <Foundation/Foundation.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

#include <os/lock.h>
#include <stdint.h>

#define QA_EXPORT __attribute__((visibility("default")))

enum {
  QA_PEN_MEASURED = 0,
  QA_PEN_ESTIMATED = 1,
  QA_PEN_NO_PRESSURE = 2,
  QA_PEN_UNREPORTED = 3,  // The platform never reports this property.
  // UIKit's estimate that no update will correct: `estimatedProperties`
  // names it and `estimatedPropertiesExpectingUpdates` does not, which
  // Apple calls final. Final, but nothing measured it (H43, build 1065).
  QA_PEN_ESTIMATED_FINAL = 4,
};

typedef struct {
  int64_t micros;
  int64_t update_index;  // UIKit's estimationUpdateIndex; -1 when none.
  double value;          // Force (iOS) or pressure (macOS).
  double altitude;       // Radians from the surface (iOS only).
  double tilt_x;         // AppKit's scaled tilt, -1..1 (macOS only).
  double tilt_y;
  int32_t state;
  int32_t altitude_state;
  int32_t tilt_state;
  int32_t used;
} QaPenSample;

// Far more samples than one stroke's wait can span: the brush asks about a
// sample within milliseconds of recording it.
#define QA_PEN_RING 512

static QaPenSample qa_pen_ring[QA_PEN_RING];
static int qa_pen_next = 0;
static os_unfair_lock qa_pen_lock = OS_UNFAIR_LOCK_INIT;

// The key Flutter itself stamps the pointer event with: the platform
// timestamp times 1000000, truncated into an integer (iOS:
// FlutterViewController's dispatchTouches; macOS: the embedder's mouse
// events). The same arithmetic here makes the two keys equal.
static int64_t qa_pen_micros(NSTimeInterval timestamp) {
  return (int64_t)(timestamp * 1000000);
}

static void qa_pen_record(int64_t micros, double value, int32_t state,
                          double altitude, int32_t altitude_state,
                          double tilt_x, double tilt_y, int32_t tilt_state,
                          int64_t update_index) {
  os_unfair_lock_lock(&qa_pen_lock);
  QaPenSample *slot = &qa_pen_ring[qa_pen_next];
  qa_pen_next = (qa_pen_next + 1) % QA_PEN_RING;
  slot->micros = micros;
  slot->update_index = update_index;
  slot->value = value;
  slot->altitude = altitude;
  slot->tilt_x = tilt_x;
  slot->tilt_y = tilt_y;
  slot->state = state;
  slot->altitude_state = altitude_state;
  slot->tilt_state = tilt_state;
  slot->used = 1;
  os_unfair_lock_unlock(&qa_pen_lock);
}

// The newest record Flutter stamped [micros], or NULL. Call with the lock
// held.
static const QaPenSample *qa_pen_find(int64_t micros) {
  for (int n = 0; n < QA_PEN_RING; n++) {
    const int i = (qa_pen_next - 1 - n + QA_PEN_RING) % QA_PEN_RING;
    const QaPenSample *slot = &qa_pen_ring[i];
    if (slot->used && slot->micros == micros) {
      return slot;
    }
  }
  return NULL;
}

#if TARGET_OS_IOS

// What UIKit says of [property] on one sample: an estimate it will send
// the measured value for, an estimate it never will, or a measurement.
//
// 🚨H43, build 1065: the ledger asked `estimatedPropertiesExpectingUpdates`
// alone, so an estimate with no update coming read as MEASURED — and the
// constant 0.33 the Pencil's first samples carry was painted as it always
// had been. `estimatedProperties` is the set that says a value is an
// estimate at all.
static int32_t qa_pen_state_of(UITouchProperties estimated,
                               UITouchProperties awaited,
                               UITouchProperties property) {
  if ((awaited & property) != 0) {
    return QA_PEN_ESTIMATED;
  }
  if ((estimated & property) != 0) {
    return QA_PEN_ESTIMATED_FINAL;
  }
  return QA_PEN_MEASURED;
}

@interface QaPenLedger : NSObject
+ (void)noteTouches:(NSSet<UITouch *> *)touches;
+ (void)updateTouches:(NSSet<UITouch *> *)touches;
@end

@implementation QaPenLedger

+ (void)noteTouches:(NSSet<UITouch *> *)touches {
  for (UITouch *touch in touches) {
    if (touch.type != UITouchTypePencil) {
      continue;
    }
    const UITouchProperties estimated = touch.estimatedProperties;
    const UITouchProperties awaited = touch.estimatedPropertiesExpectingUpdates;
    NSNumber *index = touch.estimationUpdateIndex;
    qa_pen_record(
        qa_pen_micros(touch.timestamp), touch.force,
        qa_pen_state_of(estimated, awaited, UITouchPropertyForce),
        touch.altitudeAngle,
        qa_pen_state_of(estimated, awaited, UITouchPropertyAltitude),
        // The lean's direction rides the pointer on iOS.
        0, 0, QA_PEN_UNREPORTED, index != nil ? index.longLongValue : -1);
  }
}

+ (void)updateTouches:(NSSet<UITouch *> *)touches {
  for (UITouch *touch in touches) {
    NSNumber *index = touch.estimationUpdateIndex;
    if (index == nil) {
      continue;
    }
    // Only a property UIKit no longer means to update replaces an estimate.
    const UITouchProperties awaited = touch.estimatedPropertiesExpectingUpdates;
    const BOOL force = (awaited & UITouchPropertyForce) == 0;
    const BOOL altitude = (awaited & UITouchPropertyAltitude) == 0;
    const int64_t key = index.longLongValue;
    os_unfair_lock_lock(&qa_pen_lock);
    for (int i = 0; i < QA_PEN_RING; i++) {
      QaPenSample *slot = &qa_pen_ring[i];
      if (!slot->used || slot->update_index != key) {
        continue;
      }
      if (force && slot->state == QA_PEN_ESTIMATED) {
        slot->value = touch.force;
        slot->state = QA_PEN_MEASURED;
      }
      if (altitude && slot->altitude_state == QA_PEN_ESTIMATED) {
        slot->altitude = touch.altitudeAngle;
        slot->altitude_state = QA_PEN_MEASURED;
      }
    }
    os_unfair_lock_unlock(&qa_pen_lock);
  }
}

@end

#elif TARGET_OS_OSX

static id qa_pen_monitor = nil;

static void qa_pen_note_event(NSEvent *event) {
  const BOOL tablet = event.type == NSEventTypeTabletPoint ||
                      event.subtype == NSEventSubtypeTabletPoint;
  // `tilt` is valid for exactly these events (AppKit's own words).
  const NSPoint tilt = tablet ? event.tilt : NSZeroPoint;
  qa_pen_record(qa_pen_micros(event.timestamp), tablet ? event.pressure : 0,
                tablet ? QA_PEN_MEASURED : QA_PEN_NO_PRESSURE, 0,
                QA_PEN_UNREPORTED, tilt.x, tilt.y,
                tablet ? QA_PEN_MEASURED : QA_PEN_UNREPORTED, -1);
}

static void qa_pen_install_monitor(void) {
  if (qa_pen_monitor != nil) {
    return;
  }
  const NSEventMask mask = NSEventMaskLeftMouseDown |
                           NSEventMaskLeftMouseDragged |
                           NSEventMaskLeftMouseUp | NSEventMaskTabletPoint;
  qa_pen_monitor =
      [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                            handler:^NSEvent *(NSEvent *e) {
                                              qa_pen_note_event(e);
                                              return e;
                                            }];
}

#endif

// Starts whatever the platform needs to keep the ledger: the event monitor
// on macOS (installed on the main thread, where AppKit calls it); nothing
// on iOS, where the Runner writes. Safe to call again.
QA_EXPORT void qa_pen_ledger_start(void) {
#if TARGET_OS_OSX
  if ([NSThread isMainThread]) {
    qa_pen_install_monitor();
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      qa_pen_install_monitor();
    });
  }
#endif
}

// What the ledger holds for the sample Flutter stamped [micros], newest
// record first: -1 when it has none, -2 while UIKit's force is still an
// estimate, -4 when it is an estimate UIKit will never correct, -3 when
// the sample carries no pressure at all (a mouse on
// macOS); otherwise the value the platform reported — UIKit force on iOS,
// NSEvent pressure (0..1) on macOS.
QA_EXPORT double qa_pen_ledger_value(int64_t micros) {
  double result = -1;
  os_unfair_lock_lock(&qa_pen_lock);
  const QaPenSample *slot = qa_pen_find(micros);
  if (slot != NULL) {
    switch (slot->state) {
      case QA_PEN_ESTIMATED:
        result = -2;
        break;
      case QA_PEN_NO_PRESSURE:
        result = -3;
        break;
      case QA_PEN_ESTIMATED_FINAL:
        result = -4;
        break;
      default:
        result = slot->value;
        break;
    }
  }
  os_unfair_lock_unlock(&qa_pen_lock);
  return result;
}

// The pen's altitude for the sample Flutter stamped [micros], in radians
// from the surface (UIKit's altitudeAngle): -1 when the ledger has no
// record or the platform reports none, -2 while it is still UIKit's
// estimate, -4 when it is an estimate UIKit will never correct.
QA_EXPORT double qa_pen_ledger_altitude(int64_t micros) {
  double result = -1;
  os_unfair_lock_lock(&qa_pen_lock);
  const QaPenSample *slot = qa_pen_find(micros);
  if (slot != NULL) {
    switch (slot->altitude_state) {
      case QA_PEN_ESTIMATED:
        result = -2;
        break;
      case QA_PEN_ESTIMATED_FINAL:
        result = -4;
        break;
      case QA_PEN_MEASURED:
        result = slot->altitude;
        break;
      default:
        break;
    }
  }
  os_unfair_lock_unlock(&qa_pen_lock);
  return result;
}

// The pen's tilt for the sample Flutter stamped [micros], as AppKit scaled
// it (NSEvent.tilt: -1..1 each way): 1 with [xy] filled when the record is
// a tablet event's, 0 when the ledger holds none — no record, a mouse, or
// iOS, where the lean rides the pointer itself.
QA_EXPORT int32_t qa_pen_ledger_tilt(int64_t micros, double *xy) {
  int32_t found = 0;
  os_unfair_lock_lock(&qa_pen_lock);
  const QaPenSample *slot = qa_pen_find(micros);
  if (slot != NULL && slot->tilt_state == QA_PEN_MEASURED) {
    xy[0] = slot->tilt_x;
    xy[1] = slot->tilt_y;
    found = 1;
  }
  os_unfair_lock_unlock(&qa_pen_lock);
  return found;
}
