use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

const MAX_CLIPS: usize = 30;
const MAX_CLIP_BYTES: usize = 64 * 1024;

#[derive(Serialize, Deserialize, Default, Debug, PartialEq)]
struct Data {
    clips: Vec<String>,
    shelf: Vec<String>,
}

/// Clipboard history and file shelf, persisted as JSON after every change.
pub struct Store {
    path: Option<PathBuf>,
    data: Data,
}

impl Store {
    pub fn in_memory() -> Self {
        Self { path: None, data: Data::default() }
    }

    pub fn open(dir: PathBuf) -> Self {
        let _ = fs::create_dir_all(&dir);
        let path = dir.join("state.json");
        let data = fs::read(&path)
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        Self { path: Some(path), data }
    }

    fn save(&self) {
        let Some(path) = &self.path else { return };
        if let Ok(json) = serde_json::to_vec(&self.data) {
            let tmp = path.with_extension("json.tmp");
            if fs::write(&tmp, json).is_ok() {
                let _ = fs::rename(tmp, path);
            }
        }
    }

    pub fn clips(&self) -> &[String] {
        &self.data.clips
    }

    /// Moves `text` to the front, de-duplicating. Ignores blank or huge text.
    pub fn push_clip(&mut self, text: &str) -> bool {
        if text.trim().is_empty() || text.len() > MAX_CLIP_BYTES {
            return false;
        }
        if self.data.clips.first().is_some_and(|c| c == text) {
            return false;
        }
        self.data.clips.retain(|c| c != text);
        self.data.clips.insert(0, text.to_owned());
        self.data.clips.truncate(MAX_CLIPS);
        self.save();
        true
    }

    pub fn remove_clip(&mut self, index: usize) {
        if index < self.data.clips.len() {
            self.data.clips.remove(index);
            self.save();
        }
    }

    pub fn clear_clips(&mut self) {
        self.data.clips.clear();
        self.save();
    }

    pub fn shelf(&self) -> &[String] {
        &self.data.shelf
    }

    pub fn add_shelf(&mut self, path: &str) -> bool {
        if self.data.shelf.iter().any(|p| p == path) {
            return false;
        }
        self.data.shelf.push(path.to_owned());
        self.save();
        true
    }

    pub fn remove_shelf(&mut self, path: &str) {
        self.data.shelf.retain(|p| p != path);
        self.save();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clips_dedupe_and_cap() {
        let mut s = Store::in_memory();
        assert!(s.push_clip("a"));
        assert!(s.push_clip("b"));
        assert!(!s.push_clip("b"));
        assert!(s.push_clip("a"));
        assert_eq!(s.clips(), ["a", "b"]);
        assert!(!s.push_clip("   "));
        for i in 0..100 {
            s.push_clip(&i.to_string());
        }
        assert_eq!(s.clips().len(), MAX_CLIPS);
        assert_eq!(s.clips()[0], "99");
    }

    #[test]
    fn shelf_ignores_duplicates() {
        let mut s = Store::in_memory();
        assert!(s.add_shelf("/tmp/x"));
        assert!(!s.add_shelf("/tmp/x"));
        s.remove_shelf("/tmp/x");
        assert!(s.shelf().is_empty());
    }

    #[test]
    fn persists_round_trip() {
        let dir = std::env::temp_dir().join(format!("notchdeck-test-{}", std::process::id()));
        let mut s = Store::open(dir.clone());
        s.push_clip("hello");
        s.add_shelf("/tmp/file.txt");
        let reopened = Store::open(dir.clone());
        assert_eq!(reopened.data, s.data);
        let _ = fs::remove_dir_all(dir);
    }
}
