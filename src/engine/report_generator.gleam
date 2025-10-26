// Report Generator - Exports performance metrics to file
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/string
import gleam/float
import gleam/result
import engine/metrics_collector
import client/simulation_types  // CHANGED: Import shared types instead of simulator

// Use type aliases for clarity
pub type SimulationMetrics = simulation_types.SimulationMetrics
pub type SimulationConfig = simulation_types.SimulationConfig

// ============================================================================
// Report Generation
// ============================================================================

/// Generate a comprehensive performance report
pub fn generate_report(
  snapshot: metrics_collector.MetricsSnapshot,
  sim_metrics: SimulationMetrics,
  config: SimulationConfig,
) -> String {
  let header = generate_header()
  let summary = generate_summary_section(snapshot, sim_metrics, config)
  let operations = generate_operations_section(snapshot)
  let latency = generate_latency_section(snapshot)
  let errors = generate_errors_section(snapshot)
  let zipf = generate_zipf_section(config)
  let conclusions = generate_conclusions(snapshot, sim_metrics)
  
  header <> "\n\n" <>
  summary <> "\n\n" <>
  operations <> "\n\n" <>
  latency <> "\n\n" <>
  errors <> "\n\n" <>
  zipf <> "\n\n" <>
  conclusions
}

// ============================================================================
// Report Sections
// ============================================================================

fn generate_header() -> String {
  "# Reddit Clone - Performance Report\n" <>
  "\n" <>
  "**Project**: Distributed Reddit Clone Simulator\n" <>
  "**Language**: Gleam (Erlang VM)\n" <>
  "**Architecture**: Actor-based concurrent system\n" <>
  "**Date**: " <> get_current_date() <> "\n" <>
  "\n" <>
  "---\n"
}

fn generate_summary_section(
  snapshot: metrics_collector.MetricsSnapshot,
  sim_metrics: SimulationMetrics,
  config: SimulationConfig,
) -> String {
  "## Executive Summary\n" <>
  "\n" <>
  "This report presents the performance characteristics of a distributed Reddit clone\n" <>
  "implementation built using the Gleam programming language on the Erlang VM. The system\n" <>
  "uses the Actor model for concurrency and simulates realistic user behavior with\n" <>
  "Zipf distribution for subreddit popularity.\n" <>
  "\n" <>
  "### Configuration\n" <>
  "\n" <>
  "| Parameter | Value |\n" <>
  "|-----------|-------|\n" <>
  "| Simulated Users | " <> int.to_string(config.num_users) <> " |\n" <>
  "| Subreddits | " <> int.to_string(config.num_subreddits) <> " |\n" <>
  "| Zipf Skewness | " <> float_to_string(config.zipf_skewness) <> " |\n" <>
  "| Actions per User | " <> int.to_string(config.actions_per_user) <> " |\n" <>
  "| Simulation Duration | " <> int.to_string(config.simulation_duration_seconds) <> "s |\n" <>
  "\n" <>
  "### Key Metrics\n" <>
  "\n" <>
  "| Metric | Value |\n" <>
  "|--------|-------|\n" <>
  "| Total Operations | " <> int.to_string(snapshot.total_operations) <> " |\n" <>
  "| Duration | " <> format_float(snapshot.total_duration_seconds, 2) <> "s |\n" <>
  "| Throughput | " <> format_float(snapshot.operations_per_second, 2) <> " ops/sec |\n" <>
  "| Error Rate | " <> format_float(snapshot.error_rate *. 100.0, 2) <> "% |\n" <>
  "| Users Registered | " <> int.to_string(sim_metrics.users_registered) <> " |\n" <>
  "| Posts Created | " <> int.to_string(sim_metrics.posts_created) <> " |\n" <>
  "| Comments Created | " <> int.to_string(sim_metrics.comments_created) <> " |\n" <>
  "| Votes Cast | " <> int.to_string(sim_metrics.votes_cast) <> " |\n" <>
  "| Direct Messages | " <> int.to_string(sim_metrics.messages_sent) <> " |\n"
}

fn generate_operations_section(snapshot: metrics_collector.MetricsSnapshot) -> String {
  "## Operations Breakdown\n" <>
  "\n" <>
  "Distribution of operations performed during the simulation:\n" <>
  "\n" <>
  "| Operation | Count | Percentage |\n" <>
  "|-----------|-------|------------|\n" <>
  generate_operation_rows(snapshot) <>
  "\n" <>
  "### Analysis\n" <>
  "\n" <>
  "The operation distribution reflects realistic Reddit usage patterns:\n" <>
  "- **Content Creation** (posts + comments): Core activity\n" <>
  "- **Voting**: High engagement feature\n" <>
  "- **Feed Viewing**: Primary consumption activity\n" <>
  "- **Direct Messages**: Lower frequency communication\n"
}

fn generate_operation_rows(snapshot: metrics_collector.MetricsSnapshot) -> String {
  dict.fold(snapshot.operations_by_type, "", fn(acc, op_type, count) {
    let percentage = case snapshot.total_operations > 0 {
      True -> { int.to_float(count) /. int.to_float(snapshot.total_operations) } *. 100.0
      False -> 0.0
    }
    acc <> "| " <> op_type <> " | " <> int.to_string(count) <> " | " <> format_float(percentage, 1) <> "% |\n"
  })
}

fn generate_latency_section(snapshot: metrics_collector.MetricsSnapshot) -> String {
  "## Latency Analysis\n" <>
  "\n" <>
  "**Note**: In asynchronous actor-based systems, message passing is non-blocking.\n" <>
  "The latencies shown represent message send times, not end-to-end processing times.\n" <>
  "This is the expected behavior for distributed actor systems on the Erlang VM.\n" <>
  "\n" <>
  "| Operation | Count | Min (ms) | Avg (ms) | P50 (ms) | P95 (ms) | P99 (ms) | Max (ms) |\n" <>
  "|-----------|-------|----------|----------|----------|----------|----------|----------|\n" <>
  generate_latency_rows(snapshot) <>
  "\n" <>
  "### Actor Model Benefits\n" <>
  "\n" <>
  "- **Non-blocking**: Operations don't wait for responses\n" <>
  "- **Concurrent**: Thousands of operations processed simultaneously\n" <>
  "- **Fault-tolerant**: Actor crashes don't affect other actors\n" <>
  "- **Scalable**: Can distribute across multiple machines\n"
}

fn generate_latency_rows(snapshot: metrics_collector.MetricsSnapshot) -> String {
  dict.fold(snapshot.latency_stats, "", fn(acc, _key, stats) {
    acc <> "| " <> stats.operation <>
    " | " <> int.to_string(stats.count) <>
    " | " <> format_float(stats.min_ms, 3) <>
    " | " <> format_float(stats.avg_ms, 3) <>
    " | " <> format_float(stats.p50_ms, 3) <>
    " | " <> format_float(stats.p95_ms, 3) <>
    " | " <> format_float(stats.p99_ms, 3) <>
    " | " <> format_float(stats.max_ms, 3) <> " |\n"
  })
}

fn generate_errors_section(snapshot: metrics_collector.MetricsSnapshot) -> String {
  case dict.size(snapshot.errors_by_type) > 0 {
    True -> {
      "## Error Analysis\n" <>
      "\n" <>
      "| Error Type | Count |\n" <>
      "|------------|-------|\n" <>
      generate_error_rows(snapshot) <>
      "\n"
    }
    False -> {
      "## Error Analysis\n" <>
      "\n" <>
      "✅ **No errors occurred during the simulation.**\n" <>
      "\n" <>
      "This demonstrates the robustness of the actor-based architecture and\n" <>
      "proper error handling throughout the system.\n"
    }
  }
}

fn generate_error_rows(snapshot: metrics_collector.MetricsSnapshot) -> String {
  dict.fold(snapshot.errors_by_type, "", fn(acc, error_type, count) {
    acc <> "| " <> error_type <> " | " <> int.to_string(count) <> " |\n"
  })
}

fn generate_zipf_section(config: SimulationConfig) -> String {
  "## Zipf Distribution Implementation\n" <>
  "\n" <>
  "The simulation implements Zipf distribution (skewness = " <> float_to_string(config.zipf_skewness) <> ") for subreddit popularity:\n" <>
  "\n" <>
  "### Theory\n" <>
  "\n" <>
  "Zipf's law states that in many real-world phenomena, the frequency of an item is\n" <>
  "inversely proportional to its rank. In our simulation:\n" <>
  "\n" <>
  "```\n" <>
  "P(rank k) = 1 / (k^s * H(N,s))\n" <>
  "where s = " <> float_to_string(config.zipf_skewness) <> " (skewness parameter)\n" <>
  "```\n" <>
  "\n" <>
  "### Implementation Details\n" <>
  "\n" <>
  "1. **Subreddit Membership**: Popular subreddits get exponentially more members\n" <>
  "2. **Content Creation**: Users in popular subreddits generate more posts\n" <>
  "3. **Activity Scaling**: Bonus actions (0-10) based on total subscriber count\n" <>
  "\n" <>
  "### Real-World Analogy\n" <>
  "\n" <>
  "Just like Reddit where r/funny has millions of subscribers while niche\n" <>
  "communities have thousands, our simulation creates realistic popularity\n" <>
  "distributions that mirror actual social media platforms.\n"
}

fn generate_conclusions(
  snapshot: metrics_collector.MetricsSnapshot,
  sim_metrics: SimulationMetrics,
) -> String {
  "## Conclusions\n" <>
  "\n" <>
  "### System Performance\n" <>
  "\n" <>
  "The Reddit clone successfully demonstrates:\n" <>
  "\n" <>
  "1. **High Concurrency**: " <> int.to_string(snapshot.total_operations) <> " operations processed concurrently\n" <>
  "2. **Scalability**: Actor model enables thousands of concurrent users\n" <>
  "3. **Reliability**: " <> format_float({1.0 -. snapshot.error_rate} *. 100.0, 1) <> "% success rate\n" <>
  "4. **Realistic Simulation**: Zipf distribution creates authentic usage patterns\n" <>
  "\n" <>
  "### Architecture Strengths\n" <>
  "\n" <>
  "- **Actor Model**: Isolated state, message passing, fault tolerance\n" <>
  "- **Erlang VM**: Proven platform for distributed, concurrent systems\n" <>
  "- **Gleam**: Type-safe functional programming with Erlang interop\n" <>
  "\n" <>
  "### Future Enhancements\n" <>
  "\n" <>
  "- Add persistence layer (ETS/PostgreSQL)\n" <>
  "- Implement connection/disconnection cycles\n" <>
  "- Add repost detection and handling\n" <>
  "- Scale to 10,000+ concurrent users\n" <>
  "- Add WebSocket/REST API layer (Part II)\n" <>
  "\n" <>
  "---\n" <>
  "\n" <>
  "**Report generated automatically by the Reddit Clone simulator**\n"
}

// ============================================================================
// Helper Functions
// ============================================================================

fn format_float(f: Float, decimals: Int) -> String {
  let multiplier = case decimals {
    1 -> 10.0
    2 -> 100.0
    3 -> 1000.0
    _ -> 1.0
  }
  
  let rounded = float.round(f *. multiplier)
  let multiplier_int = float.round(multiplier)
  let int_part = rounded / multiplier_int
  let decimal_part = rounded - int_part * multiplier_int
  let decimal_int = float.round(float.absolute_value(int.to_float(decimal_part)))
  
  int.to_string(int_part) <> "." <> pad_zeros(int.to_string(decimal_int), decimals)
}

fn pad_zeros(s: String, width: Int) -> String {
  let len = string.length(s)
  case width > len {
    True -> s <> string.repeat("0", width - len)
    False -> s
  }
}

fn float_to_string(f: Float) -> String {
  case f {
    1.0 -> "1.0"
    1.5 -> "1.5"
    2.0 -> "2.0"
    _ -> format_float(f, 1)
  }
}

fn get_current_date() -> String {
  "2024"
}