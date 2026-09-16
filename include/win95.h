#ifndef WIN95_H
#define WIN95_H

/*
 * C ABI for the Win95 Swift UI library.
 *
 * Link against the Win95 dylib produced by `swift build`:
 *   -L .build/debug -lWin95
 *
 * Threading: every function MUST be called on the main thread, except
 * w95_dispatch_main, which is safe from any thread (it hops to main
 * before running the callback). Callbacks installed via *_new always
 * fire on the main thread. The `ud` pointer is passed through untouched;
 * its lifetime and any synchronization are the caller's problem.
 *
 * Handles returned by *_new are opaque retained pointers. Do not free
 * them with free(3). w95_textfield_get is the exception: it returns a
 * malloc'd C string that the caller must free.
 */

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *w95_handle;

typedef void (*w95_cell_cb)(void *ud, int32_t x, int32_t y, int32_t button);
typedef void (*w95_action_cb)(void *ud);

void w95_init(void);
void w95_run(void);
void w95_install_menus(const char *app_name);

/* Theme: dotfile-backed scheme shared by every linked app.
 * The file is created with stock 95 colors on first launch.
 * ControlTheme.app edits it; linked apps reload live. */
void w95_theme_reload(void);
void w95_theme_reset(void);
/* malloc'd UTF-8 path to the theme file; caller frees. */
char *w95_theme_path(void);

/* Hop `cb` onto the main thread. Safe from any thread. */
void w95_dispatch_main(w95_action_cb cb, void *ud);

/* Open `url` with the default handler. */
void w95_open_url(const char *url);

/* --- window ----------------------------------------------------------- */

w95_handle w95_window_new(const char *title, double x, double y, double w, double h);
void w95_window_client_size(w95_handle win, double *out_w, double *out_h);
void w95_window_set_status(w95_handle win, const char *text);
void w95_window_set_title(w95_handle win, const char *title);

/* --- controls --------------------------------------------------------- */

w95_handle w95_button_new(w95_handle win, const char *title,
                          double x, double y, double w, double h,
                          bool is_default, w95_action_cb cb, void *ud);

w95_handle w95_checkbox_new(w95_handle win, const char *title,
                            double x, double y, bool checked,
                            w95_action_cb cb, void *ud);

w95_handle w95_textfield_new(w95_handle win, double x, double y, double w, double h);
/* malloc'd UTF-8; caller frees. */
char *w95_textfield_get(w95_handle field);
void w95_textfield_set(w95_handle field, const char *s);

w95_handle w95_chatview_new(w95_handle win, double x, double y, double w, double h);
void w95_chatview_append(w95_handle view, const char *line);

w95_handle w95_progress_new(w95_handle win, double x, double y, double w, double h);
void w95_progress_set(w95_handle bar, double value);

w95_handle w95_listbox_new(w95_handle win, double x, double y, double w, double h,
                           w95_action_cb cb, void *ud);
void w95_listbox_add(w95_handle list, const char *item);
int32_t w95_listbox_selected(w95_handle list); /* -1 if none */

w95_handle w95_slider_new(w95_handle win, double x, double y, double w,
                          w95_action_cb cb, void *ud);
double w95_slider_get(w95_handle slider);

w95_handle w95_spinner_new(w95_handle win, double x, double y, double w,
                           int32_t min, int32_t max, int32_t initial,
                           w95_action_cb cb, void *ud);
int32_t w95_spinner_get(w95_handle spinner);

/* --- minesweeper board ------------------------------------------------ */

w95_handle w95_board_new(w95_handle win, int32_t cols, int32_t rows,
                         w95_cell_cb cell_cb, w95_action_cb face_cb, void *ud);
void w95_board_set_cell(w95_handle board, int32_t x, int32_t y, int32_t state);
void w95_board_set_number(w95_handle board, int32_t x, int32_t y, int32_t n);
void w95_board_set_face(w95_handle board, int32_t face);
void w95_board_set_counters(w95_handle board, int32_t left, int32_t right);

#ifdef __cplusplus
}
#endif

#endif /* WIN95_H */
