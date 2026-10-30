use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

/// One report from the now-playing watcher (see `NowPlaying.swift`).
/// Unknown fields such as `artwork` are ignored here; Swift handles images.
#[derive(Deserialize, Default, Debug)]
struct Report {
    #[serde(default)]
    active: bool,
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    app_name: Option<String>,
    bundle_id: Option<String>,
    duration: Option<f64>,
    elapsed: Option<f64>,
    rate: Option<f64>,
    /// Epoch seconds at which `elapsed` was measured.
    timestamp: Option<f64>,
    playing: Option<bool>,
}

#[derive(Debug, Clone, PartialEq)]
struct Track {
    title: String,
    artist: String,
    album: String,
    app_name: String,
    bundle_id: String,
    duration: f64,
    elapsed: f64,
    rate: f64,
    timestamp: f64,
    playing: bool,
}

impl Track {
    fn same_item(&self, other: &Track) -> bool {
        self.title == other.title && self.artist == other.artist && self.bundle_id == other.bundle_id
    }

    fn position_at(&self, now: f64) -> f64 {
        let drift = if self.playing { self.rate * (now - self.timestamp).max(0.0) } else { 0.0 };
        let pos = (self.elapsed + drift).max(0.0);
        if self.duration > 0.0 { pos.min(self.duration) } else { pos }
    }
}

#[derive(Serialize, Debug, PartialEq)]
pub struct MediaState {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub app_name: String,
    pub bundle_id: String,
    pub duration: f64,
    /// Interpolated playback position in seconds.
    pub position: f64,
    pub playing: bool,
}

#[derive(Default)]
pub struct Media {
    track: Option<Track>,
}

pub fn now_epoch() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0.0, |d| d.as_secs_f64())
}

impl Media {
    /// Applies a watcher report. Returns true when the item itself changed
    /// (new track, new source, or playback stopped), so the UI can swap artwork.
    pub fn update(&mut self, json: &str, now: f64) -> bool {
        let Ok(report) = serde_json::from_str::<Report>(json) else { return false };
        let next = report.active.then(|| {
            let rate = report.rate.unwrap_or(0.0);
            Track {
                title: report.title.unwrap_or_default(),
                artist: report.artist.unwrap_or_default(),
                album: report.album.unwrap_or_default(),
                app_name: report.app_name.unwrap_or_default(),
                bundle_id: report.bundle_id.unwrap_or_default(),
                duration: report.duration.unwrap_or(0.0),
                elapsed: report.elapsed.unwrap_or(0.0),
                rate: if rate > 0.0 { rate } else { 1.0 },
                timestamp: report.timestamp.unwrap_or(now),
                playing: report.playing.unwrap_or(false) || rate > 0.0,
            }
        });
        let changed = match (&self.track, &next) {
            (Some(a), Some(b)) => !a.same_item(b),
            (None, None) => false,
            _ => true,
        };
        self.track = next;
        changed
    }

    /// Optimistic update after the user taps play/pause, before the watcher reports back.
    pub fn set_playing(&mut self, playing: bool, now: f64) {
        if let Some(t) = &mut self.track {
            t.elapsed = t.position_at(now);
            t.timestamp = now;
            t.playing = playing;
        }
    }

    pub fn state(&self, now: f64) -> Option<MediaState> {
        self.track.as_ref().map(|t| MediaState {
            title: t.title.clone(),
            artist: t.artist.clone(),
            album: t.album.clone(),
            app_name: t.app_name.clone(),
            bundle_id: t.bundle_id.clone(),
            duration: t.duration,
            position: t.position_at(now),
            playing: t.playing,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SONG: &str = r#"{"active":true,"title":"Song","artist":"A","bundle_id":"com.spotify.client",
        "duration":200,"elapsed":10,"rate":1,"timestamp":1000,"playing":true,"artwork":"aGk="}"#;

    #[test]
    fn interpolates_position_while_playing() {
        let mut m = Media::default();
        assert!(m.update(SONG, 1000.0));
        assert_eq!(m.state(1005.0).unwrap().position, 15.0);
        assert_eq!(m.state(5000.0).unwrap().position, 200.0, "clamped to duration");
    }

    #[test]
    fn pause_freezes_position() {
        let mut m = Media::default();
        m.update(SONG, 1000.0);
        m.set_playing(false, 1004.0);
        let s = m.state(1100.0).unwrap();
        assert!(!s.playing);
        assert_eq!(s.position, 14.0);
    }

    #[test]
    fn reports_item_changes_only() {
        let mut m = Media::default();
        assert!(m.update(SONG, 1000.0));
        assert!(!m.update(&SONG.replace("\"elapsed\":10", "\"elapsed\":11"), 1001.0));
        assert!(m.update(&SONG.replace("Song", "Other"), 1002.0));
        assert!(m.update(r#"{"active":false}"#, 1003.0));
        assert!(m.state(1003.0).is_none());
        assert!(!m.update("not json", 1004.0));
    }
}
