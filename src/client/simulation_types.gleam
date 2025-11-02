// Shared types for simulation - breaks circular dependency
// This module contains types used by both simulator and report_generator

// ============================================================================
// Simulation Configuration
// ============================================================================

pub type SimulationConfig {
  SimulationConfig(
    num_users: Int,
    num_subreddits: Int,
    zipf_skewness: Float,
    simulation_duration_seconds: Int,
    actions_per_user: Int,
    connection_cycle_seconds: Int,
  )
}

pub fn default_config() -> SimulationConfig {
  SimulationConfig(
    num_users: 50,
    num_subreddits: 10,
    zipf_skewness: 1.0,
    simulation_duration_seconds: 60,
    actions_per_user: 10,
    connection_cycle_seconds: 15,
  )
}

pub fn large_scale_config() -> SimulationConfig {
  SimulationConfig(
    num_users: 1000,
    num_subreddits: 50,
    zipf_skewness: 1.5,
    simulation_duration_seconds: 300,
    actions_per_user: 20,
    connection_cycle_seconds: 30,
  )
}

// ============================================================================
// Simulation Metrics
// ============================================================================

pub type SimulationMetrics {
  SimulationMetrics(
    users_registered: Int,
    subreddits_created: Int,
    posts_created: Int,
    reposts_created: Int,
    comments_created: Int,
    votes_cast: Int,
    messages_sent: Int,
    errors: Int,
  )
}

pub fn init_metrics() -> SimulationMetrics {
  SimulationMetrics(
    users_registered: 0,
    subreddits_created: 0,
    posts_created: 0,
    reposts_created: 0,
    comments_created: 0,
    votes_cast: 0,
    messages_sent: 0,
    errors: 0,
  )
}