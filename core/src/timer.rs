use std::time::{Duration, Instant};

use serde::Serialize;

#[derive(Default)]
pub struct FocusTimer {
    total: Duration,
    /// Time banked before the current run segment (pauses split segments).
    banked: Duration,
    running_since: Option<Instant>,
}

#[derive(Serialize, Debug, PartialEq)]
pub struct TimerState {
    pub active: bool,
    pub paused: bool,
    pub total_secs: u64,
    pub remaining_secs: u64,
    pub finished: bool,
}

impl FocusTimer {
    pub fn start(&mut self, seconds: u32) {
        self.start_at(seconds, Instant::now());
    }

    fn start_at(&mut self, seconds: u32, now: Instant) {
        self.total = Duration::from_secs(seconds.into());
        self.banked = Duration::ZERO;
        self.running_since = Some(now);
    }

    pub fn toggle_pause(&mut self) {
        self.toggle_pause_at(Instant::now());
    }

    fn toggle_pause_at(&mut self, now: Instant) {
        if self.total.is_zero() {
            return;
        }
        match self.running_since.take() {
            Some(since) => self.banked += now - since,
            None => self.running_since = Some(now),
        }
    }

    pub fn stop(&mut self) {
        *self = Self::default();
    }

    pub fn state(&self) -> TimerState {
        self.state_at(Instant::now())
    }

    fn state_at(&self, now: Instant) -> TimerState {
        let elapsed = self.banked + self.running_since.map_or(Duration::ZERO, |s| now - s);
        let remaining = self.total.saturating_sub(elapsed);
        let active = !self.total.is_zero();
        TimerState {
            active,
            paused: active && self.running_since.is_none(),
            total_secs: self.total.as_secs(),
            // Round up so the display hits 0 exactly when the timer finishes.
            remaining_secs: remaining.as_millis().div_ceil(1000) as u64,
            finished: active && remaining.is_zero(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_down_pauses_and_finishes() {
        let t0 = Instant::now();
        let mut t = FocusTimer::default();
        assert!(!t.state_at(t0).active);

        t.start_at(10, t0);
        assert_eq!(t.state_at(t0 + Duration::from_secs(3)).remaining_secs, 7);

        t.toggle_pause_at(t0 + Duration::from_secs(4));
        let paused = t.state_at(t0 + Duration::from_secs(100));
        assert!(paused.paused);
        assert_eq!(paused.remaining_secs, 6);

        t.toggle_pause_at(t0 + Duration::from_secs(100));
        let done = t.state_at(t0 + Duration::from_secs(106));
        assert!(done.finished);
        assert_eq!(done.remaining_secs, 0);

        t.stop();
        assert!(!t.state().active);
    }
}
