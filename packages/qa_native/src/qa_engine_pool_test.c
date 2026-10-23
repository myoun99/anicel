// Several callers at once on the engine (card
// clip-import-hangs-on-three-samples, 2026-10-23).
//
// Every isolate that loads the engine calls it from a thread of its own,
// and the clip import draws vector layers on several at once. The pool was
// one job slot and one set of wake-ups for the process: two callers at once
// overwrote each other's job, one waited for a wake-up nobody would send,
// and three .clip samples never finished opening. Everything else that runs
// the engine here — the parity suites, the canvas — calls it from one
// thread, so nothing else can see two callers at once.
//
// It includes the translation unit rather than linking it, because the pool
// is static.

#include "qa_engine.c"

#include <stdio.h>

#if defined(_WIN32)
typedef volatile LONG pool_test_count;

static void pool_test_add(pool_test_count* count) {
  InterlockedIncrement(count);
}

static int32_t pool_test_read(pool_test_count* count) {
  return (int32_t)InterlockedCompareExchange(count, 0, 0);
}

static void pool_test_nap(void) {
  Sleep(10);
}
#else
typedef int32_t pool_test_count;

static void pool_test_add(pool_test_count* count) {
  __atomic_fetch_add(count, 1, __ATOMIC_SEQ_CST);
}

static int32_t pool_test_read(pool_test_count* count) {
  return __atomic_load_n(count, __ATOMIC_SEQ_CST);
}

static void pool_test_nap(void) {
  usleep(10000);
}
#endif

enum {
  CALLERS = 6,
  ROUNDS = 200,
  // Enough items that every worker takes some.
  ITEMS = 48,
  // 8 x 4 compose tiles of 32, under one layer tile of 256.
  RASTER_W = 256,
  RASTER_H = 128,
  COMPOSE_TILE = 32,
  COMPOSE_ITEMS = (RASTER_W / COMPOSE_TILE) * (RASTER_H / COMPOSE_TILE),
  LAYER_TILE = 256,
  // 5 x 3 fill tiles of 128, so one wave spans the pool.
  FILL_W = 600,
  FILL_H = 300,
  FILL_SHIFT = 7,
  FILL_TILES_X = 5,
  FILL_TILES_Y = 3,
  FILL_CANDIDATES = 16,
  // A hang fails the run instead of stalling it: 60 s, in naps of 10 ms.
  DEADLINE_NAPS = 6000,
};

typedef struct {
  pool_test_count hits[ITEMS];
} pool_test_board;

static void pool_test_hit(int32_t item, void* context) {
  pool_test_board* board = (pool_test_board*)context;
  // Long enough that the callers' calls overlap.
  volatile uint32_t spin = 0;
  for (uint32_t i = 0; i < 4000; i += 1) {
    spin += i;
  }
  pool_test_add(&board->hits[item]);
}

static pool_test_count g_started;
static pool_test_count g_in_company;

// Waits, up to 2 s, for the other item to start beside this one.
static void pool_test_wait_for_company(int32_t item, void* context) {
  (void)item;
  (void)context;
  pool_test_add(&g_started);
  for (int nap = 0; nap < 200 && pool_test_read(&g_started) < 2; nap += 1) {
    pool_test_nap();
  }
  if (pool_test_read(&g_started) == 2) {
    pool_test_add(&g_in_company);
  }
}

// Whether this machine should spread a call: it has the processors, and
// nobody set the thread count. Asked of the machine rather than of the
// pool, because a pool that never started has no workers to report.
static int pool_test_should_spread(void) {
  if (getenv("QA_ENGINE_THREADS") != NULL) {
    return 0;
  }
#if defined(_WIN32)
  SYSTEM_INFO info;
  GetSystemInfo(&info);
  return info.dwNumberOfProcessors >= 2;
#else
  return sysconf(_SC_NPROCESSORS_ONLN) >= 2;
#endif
}

// Whether a call alone is spread across the workers: on one thread the
// first of two items waits out its 2 s alone, and only the second finds
// company. Results are the same either way — this is the pool's one job.
static int pool_test_spreads(void) {
  g_started = 0;
  g_in_company = 0;
  qa_pool_run(pool_test_wait_for_company, NULL, 2);
  return pool_test_read(&g_in_company) == 2;
}

// Each of this call's items ran, once, with this call's context.
static int pool_test_own_items(void) {
  pool_test_board board;
  memset((void*)&board, 0, sizeof(board));
  qa_pool_run(pool_test_hit, &board, ITEMS);
  for (int32_t i = 0; i < ITEMS; i += 1) {
    if (pool_test_read(&board.hits[i]) != 1) {
      return 0;
    }
  }
  return 1;
}

typedef struct {
  uint8_t layer[LAYER_TILE * LAYER_TILE * 4];
  qa_compose_tile_item items[COMPOSE_ITEMS];
  qa_compose_blend blends[COMPOSE_ITEMS * 2];
  int32_t paper_r, paper_g, paper_b;
  uint8_t alone[RASTER_W * RASTER_H * 4];
  uint8_t raster[RASTER_W * RASTER_H * 4];
} pool_test_compose;

typedef struct {
  uint8_t rgb[FILL_W * FILL_H * 4];
  uint8_t composed[FILL_TILES_X * FILL_TILES_Y];
  uint8_t alone[FILL_W * FILL_H];
  int32_t alone_bounds[4];
  uint8_t filled[FILL_W * FILL_H];
  int32_t bounds[4];
} pool_test_fill;

static pool_test_compose g_composes[CALLERS];
static pool_test_fill g_fills[CALLERS];

static uint32_t pool_test_next_byte(uint32_t* state) {
  *state = *state * 1664525u + 1013904223u;
  return *state >> 24;
}

// A layer tile of noise, two blends of it on every compose tile, and a
// paper of the caller's own: no two callers compose the same raster.
static void pool_test_set_compose(int caller) {
  pool_test_compose* c = &g_composes[caller];
  uint32_t state = 7u + (uint32_t)caller;
  for (int32_t i = 0; i < LAYER_TILE * LAYER_TILE * 4; i += 1) {
    c->layer[i] = (uint8_t)pool_test_next_byte(&state);
  }
  c->paper_r = 10 * caller;
  c->paper_g = 200 - caller;
  c->paper_b = 50;
  int32_t item = 0;
  for (int32_t top = 0; top < RASTER_H; top += COMPOSE_TILE) {
    for (int32_t left = 0; left < RASTER_W; left += COMPOSE_TILE) {
      const qa_compose_tile_item tile = {
          left, top, left + COMPOSE_TILE, top + COMPOSE_TILE, item * 2, 2};
      c->items[item] = tile;
      for (int32_t b = 0; b < 2; b += 1) {
        const qa_compose_blend blend = {
            c->layer, LAYER_TILE, 0, 0, left, top,
            left + COMPOSE_TILE, top + COMPOSE_TILE,
            b == 0 ? 255 : 100 + 20 * caller, 0};
        c->blends[item * 2 + b] = blend;
      }
      item += 1;
    }
  }
}

static void pool_test_compose_into(pool_test_compose* c, uint8_t* raster) {
  memset(raster, 0x5A, RASTER_W * RASTER_H * 4);
  qa_fill_compose_batch(raster, RASTER_W, c->paper_r, c->paper_g, c->paper_b,
                        c->items, COMPOSE_ITEMS, c->blends);
}

// White paper with a wall of the caller's own — a vertical line with one
// gap, at a place no other caller's is — so the fills differ, and each
// crosses tiles through the gap.
static void pool_test_set_fill(int caller) {
  pool_test_fill* f = &g_fills[caller];
  memset(f->rgb, 255, sizeof(f->rgb));
  for (int32_t i = 0; i < FILL_W * FILL_H; i += 1) {
    f->rgb[i * 4 + 3] = 0;
  }
  const int32_t wall_x = 90 + 60 * caller;
  const int32_t gap_top = 20 + 40 * caller;
  for (int32_t y = 0; y < FILL_H; y += 1) {
    if (y >= gap_top && y < gap_top + 10) {
      continue;
    }
    uint8_t* px = &f->rgb[(y * FILL_W + wall_x) * 4];
    px[0] = px[1] = px[2] = 0;
  }
  for (int32_t x = wall_x; x < FILL_W; x += 1) {
    uint8_t* px = &f->rgb[((gap_top + 30) * FILL_W + x) * 4];
    px[0] = px[1] = px[2] = 0;
  }
  memset(f->composed, 1, sizeof(f->composed));
}

// One fill from (1, 1), as the Dart driver starts one: the seed marked, on
// the stack, and the bounds at it. Every tile is composed, so one round
// floods it all and returns no candidates — or -1, while another fill
// holds the arena.
static int32_t pool_test_fill_once(pool_test_fill* f, uint8_t* filled,
                                   int32_t* bounds) {
  int32_t stack[1];
  int32_t stack_size = 1;
  int32_t candidates[FILL_CANDIDATES];
  const int32_t seed = 1 * FILL_W + 1;
  memset(filled, 0, FILL_W * FILL_H);
  filled[seed] = 255;
  stack[0] = seed;
  bounds[0] = bounds[1] = 1;
  bounds[2] = bounds[3] = 1;
  return qa_flood_fill_wave(f->rgb, filled, f->composed, FILL_W, FILL_H,
                            FILL_SHIFT, FILL_TILES_X, 255, 255, 255, 0, stack,
                            &stack_size, candidates, FILL_CANDIDATES, bounds);
}

static int pool_test_fill_matches(pool_test_fill* f) {
  return memcmp(f->filled, f->alone, sizeof(f->alone)) == 0 &&
         memcmp(f->bounds, f->alone_bounds, sizeof(f->bounds)) == 0;
}

typedef struct {
  int index;
  int failures;
  int held;
  pool_test_count* finished;
} pool_test_caller;

static void pool_test_fail(pool_test_caller* caller, int32_t round,
                           const char* what) {
  if (caller->failures < 3) {
    printf("FAIL caller %d, round %d: %s\n", caller->index, round, what);
  }
  caller->failures += 1;
}

static void pool_test_run_caller(pool_test_caller* caller) {
  pool_test_compose* c = &g_composes[caller->index];
  pool_test_fill* f = &g_fills[caller->index];
  for (int32_t round = 0; round < ROUNDS; round += 1) {
    if (!pool_test_own_items()) {
      pool_test_fail(caller, round, "its pool items did not each run once");
    }
    pool_test_compose_into(c, c->raster);
    if (memcmp(c->raster, c->alone, sizeof(c->alone)) != 0) {
      pool_test_fail(caller, round, "its raster is not the one composed alone");
    }
    const int32_t candidates = pool_test_fill_once(f, f->filled, f->bounds);
    if (candidates == -1) {
      caller->held += 1;
    } else if (candidates != 0 || !pool_test_fill_matches(f)) {
      pool_test_fail(caller, round, "its fill is not the one filled alone");
    }
  }
  pool_test_add(caller->finished);
}

#if defined(_WIN32)
static unsigned __stdcall pool_test_thread(void* argument) {
  pool_test_run_caller((pool_test_caller*)argument);
  return 0;
}
#else
static void* pool_test_thread(void* argument) {
  pool_test_run_caller((pool_test_caller*)argument);
  return NULL;
}
#endif

int main(void) {
  int failures = 0;

  // Alone first: what each caller must get when nobody else is running.
  const int should_spread = pool_test_should_spread();
  if (should_spread && !pool_test_spreads()) {
    printf("FAIL: a call alone ran on one thread, with %d workers\n",
           g_pool.worker_count);
    failures += 1;
  }
  for (int caller = 0; caller < CALLERS; caller += 1) {
    pool_test_set_compose(caller);
    pool_test_compose_into(&g_composes[caller], g_composes[caller].alone);
    pool_test_set_fill(caller);
    pool_test_fill* f = &g_fills[caller];
    if (pool_test_fill_once(f, f->alone, f->alone_bounds) != 0) {
      printf("FAIL caller %d: its fill alone did not finish in one round\n",
             caller);
      failures += 1;
    }
  }

  pool_test_count finished = 0;
  pool_test_caller callers[CALLERS];
#if defined(_WIN32)
  HANDLE threads[CALLERS];
#else
  pthread_t threads[CALLERS];
#endif
  for (int i = 0; i < CALLERS; i += 1) {
    const pool_test_caller caller = {i, 0, 0, &finished};
    callers[i] = caller;
#if defined(_WIN32)
    threads[i] = (HANDLE)_beginthreadex(NULL, 0, pool_test_thread,
                                        &callers[i], 0, NULL);
#else
    pthread_create(&threads[i], NULL, pool_test_thread, &callers[i]);
#endif
  }
  for (int nap = 0; pool_test_read(&finished) < CALLERS; nap += 1) {
    if (nap == DEADLINE_NAPS) {
      printf("FAIL: %d of %d callers at once never finished\n",
             CALLERS - pool_test_read(&finished), CALLERS);
      fflush(stdout);
      exit(1);
    }
    pool_test_nap();
  }
  int held = 0;
  for (int i = 0; i < CALLERS; i += 1) {
#if defined(_WIN32)
    WaitForSingleObject(threads[i], INFINITE);
    CloseHandle(threads[i]);
#else
    pthread_join(threads[i], NULL);
#endif
    failures += callers[i].failures;
    held += callers[i].held;
  }

  // Given back: the next caller has the pool and the arena to itself.
  if (should_spread && !pool_test_spreads()) {
    printf("FAIL: a call alone, after the callers, ran on one thread\n");
    failures += 1;
  }
  pool_test_fill* f = &g_fills[0];
  if (pool_test_fill_once(f, f->filled, f->bounds) != 0 ||
      !pool_test_fill_matches(f)) {
    printf("FAIL: a fill alone, after the callers, is not the one before\n");
    failures += 1;
  }

  if (failures == 0) {
    printf("qa_engine_pool: all passed (%d workers; %d of %d fills found "
           "the arena held)\n",
           g_pool.worker_count, held, CALLERS * ROUNDS);
  }
  return failures == 0 ? 0 : 1;
}
