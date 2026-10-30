// C ABI of the Rust core (core/src/lib.rs). Strings returned as `char *` are
// owned JSON and must be released with nd_string_free.
#pragma once
#include <stdbool.h>
#include <stdint.h>

bool nd_init(const char *data_dir);
void nd_string_free(char *s);

char *nd_stats(void);

bool nd_clip_push(const char *text);
char *nd_clip_list(void);
void nd_clip_remove(uint32_t index);
void nd_clip_clear(void);

bool nd_shelf_add(const char *path);
void nd_shelf_remove(const char *path);
char *nd_shelf_list(void);

bool nd_media_update(const char *json);
void nd_media_set_playing(bool playing);
char *nd_media_state(void);

void nd_timer_start(uint32_t seconds);
void nd_timer_toggle_pause(void);
void nd_timer_stop(void);
char *nd_timer_state(void);
