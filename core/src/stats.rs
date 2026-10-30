use std::time::Instant;

use serde::Serialize;
use sysinfo::{Networks, System};

pub struct Stats {
    system: System,
    networks: Networks,
    last: Instant,
}

#[derive(Serialize, Debug)]
pub struct Snapshot {
    pub cpu_percent: f32,
    pub mem_used: u64,
    pub mem_total: u64,
    /// Bytes per second since the previous sample.
    pub net_down: u64,
    pub net_up: u64,
}

impl Stats {
    /// `None` when the platform refuses to expose system info.
    pub fn new() -> Option<Self> {
        let mut system = System::new().ok()?;
        system.refresh_cpu_usage();
        let networks = Networks::new_with_refreshed_list().ok()?;
        Some(Self { system, networks, last: Instant::now() })
    }

    pub fn sample(&mut self) -> Snapshot {
        self.system.refresh_cpu_usage();
        self.system.refresh_memory();
        self.networks.refresh(true);

        let elapsed = self.last.elapsed().as_secs_f64().max(0.001);
        self.last = Instant::now();
        let (down, up) = self
            .networks
            .iter()
            .filter(|(name, _)| !name.as_encoded_bytes().starts_with(b"lo"))
            .fold((0, 0), |(d, u), (_, n)| (d + n.received(), u + n.transmitted()));

        Snapshot {
            cpu_percent: self.system.global_cpu_usage(),
            mem_used: self.system.used_memory(),
            mem_total: self.system.total_memory(),
            net_down: (down as f64 / elapsed) as u64,
            net_up: (up as f64 / elapsed) as u64,
        }
    }
}
