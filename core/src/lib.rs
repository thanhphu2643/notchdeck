//! C ABI for the Swift app. Every function returning `*mut c_char` hands over
//! an owned, NUL-terminated JSON string that must be released with
//! `nd_string_free`.

mod stats;
mod store;
mod timer;

use std::ffi::{CStr, CString, c_char};
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard, OnceLock};

use serde::Serialize;

use stats::Stats;
use store::Store;
use timer::FocusTimer;

struct Core {
    stats: Option<Stats>,
    store: Store,
    timer: FocusTimer,
}

static CORE: OnceLock<Mutex<Core>> = OnceLock::new();

fn core() -> MutexGuard<'static, Core> {
    CORE.get_or_init(|| {
        Mutex::new(Core {
            stats: Stats::new(),
            store: Store::in_memory(),
            timer: FocusTimer::default(),
        })
    })
    .lock()
    .unwrap_or_else(|e| e.into_inner())
}

fn str_arg<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: caller passes a valid NUL-terminated string that outlives the call.
    unsafe { CStr::from_ptr(ptr) }.to_str().ok()
}

fn json_out<T: Serialize>(value: &T) -> *mut c_char {
    let json = serde_json::to_string(value).unwrap_or_else(|_| "null".into());
    CString::new(json).map_or(std::ptr::null_mut(), CString::into_raw)
}

/// Loads persisted state from `data_dir/state.json`. Safe to call once at launch.
#[unsafe(no_mangle)]
pub extern "C" fn nd_init(data_dir: *const c_char) -> bool {
    let Some(dir) = str_arg(data_dir) else { return false };
    core().store = Store::open(PathBuf::from(dir));
    true
}

/// # Safety
/// `s` must be null or a pointer returned by one of the `nd_*` JSON functions,
/// freed at most once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nd_string_free(s: *mut c_char) {
    if !s.is_null() {
        // SAFETY: `s` was produced by `CString::into_raw` in `json_out`.
        drop(unsafe { CString::from_raw(s) });
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_stats() -> *mut c_char {
    let snapshot = core().stats.as_mut().map(Stats::sample);
    json_out(&snapshot)
}

/// Returns true when the history changed.
#[unsafe(no_mangle)]
pub extern "C" fn nd_clip_push(text: *const c_char) -> bool {
    str_arg(text).is_some_and(|t| core().store.push_clip(t))
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_clip_list() -> *mut c_char {
    json_out(&core().store.clips())
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_clip_remove(index: u32) {
    core().store.remove_clip(index as usize);
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_clip_clear() {
    core().store.clear_clips();
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_shelf_add(path: *const c_char) -> bool {
    str_arg(path).is_some_and(|p| core().store.add_shelf(p))
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_shelf_remove(path: *const c_char) {
    if let Some(p) = str_arg(path) {
        core().store.remove_shelf(p);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_shelf_list() -> *mut c_char {
    json_out(&core().store.shelf())
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_timer_start(seconds: u32) {
    core().timer.start(seconds);
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_timer_toggle_pause() {
    core().timer.toggle_pause();
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_timer_stop() {
    core().timer.stop();
}

#[unsafe(no_mangle)]
pub extern "C" fn nd_timer_state() -> *mut c_char {
    json_out(&core().timer.state())
}
