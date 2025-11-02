// Report Generator - FIXED: Remove conclusions, fix latency display
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/string
import gleam/float
import gleam/result
import engine/metrics_collector
import client/simulation_types

// ============================================================================
// Report Generation
// ============================================================================

/// Generate a comprehensive performance report
pub fn generate_report(
  snapshot: metrics_collector.MetricsSnapshot,
  sim_metrics: simulation_types.SimulationMetrics,
  config: simulation_types.SimulationConfig,
) -> String {
  let header = generate_header()
  let summary = generate_summary_section(snapshot, sim_metrics, config)
  let operations = generate_operations_section(snapshot)
  let latency = generate_latency_section(snapshot)
  let errors = generate_errors_section(snapshot)
  let zipf = generate_zipf_section(config)
  
  // REMOVED: conclusions section
  header <> "\n\n" <>
  summary <> "\n\n" <>
  operations <> "\n\n" <>
  latency <> "\n\n" <>
  errors <> "\n\n" <>
  zipf <> "\n\n" <>
  "---\n\n**Report generated automatically by the Reddit Clone simulator**\n"
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
  sim_metrics: simulation_types.SimulationMetrics,
  config: simulation_types.SimulationConfig,
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
  "| Connection Cycle | " <> int.to_string(config.connection_cycle_seconds) <> "s |\n" <>
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
  "| Reposts Created | " <> int.to_string(sim_metrics.reposts_created) <> " |\n" <>
  "| Repost Rate | " <> calculate_repost_rate(sim_metrics) <> "% |\n" <>
  "| Comments Created | " <> int.to_string(sim_metrics.comments_created) <> " |\n" <>
  "| Votes Cast | " <> int.to_string(sim_metrics.votes_cast) <> " |\n" <>
  "| Direct Messages | " <> int.to_string(sim_metrics.messages_sent) <> " |\n"
}

fn calculate_repost_rate(metrics: simulation_types.SimulationMetrics) -> String {
  case metrics.posts_created > 0 {
    True -> {
      let rate = int.to_float(metrics.reposts_created) /. int.to_float(metrics.posts_created) *. 100.0
      format_float(rate, 1)
    }
    False -> "0.0"
  }
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

// FIXED: Show latencies in microseconds with actual data
fn generate_latency_section(snapshot: metrics_collector.MetricsSnapshot) -> String {
  let has_latency_data = dict.size(snapshot.latency_stats) > 0
  
  case has_latency_data {
    True -> {
      "## Latency Analysis (Microseconds)\n" <>
      "\n" <>
      "**Note**: All latencies are measured in **microseconds (μs)**.\n" <>
      "- 1,000 μs = 1 millisecond (ms)\n" <>
      "- Sub-millisecond latencies indicate excellent performance\n" <>
      "- These represent message-passing times in the actor system\n" <>
      "\n" <>
      "| Operation | Count | Min (μs) | Avg (μs) | P50 (μs) | P95 (μs) | P99 (μs) | Max (μs) |\n" <>
      "|-----------|-------|----------|----------|----------|----------|----------|----------|\n" <>
      generate_latency_rows(snapshot) <>
      "\n" <>
      "### Performance Interpretation\n" <>
      "\n" <>
      generate_performance_analysis(snapshot) <>
      "\n" <>
      "### Actor Model Benefits\n" <>
      "\n" <>
      "- **Non-blocking**: Operations don't wait for responses\n" <>
      "- **Concurrent**: Thousands of operations processed simultaneously\n" <>
      "- **Fault-tolerant**: Actor crashes don't affect other actors\n" <>
      "- **Scalable**: Can distribute across multiple machines\n"
    }
    False -> {
      "## Latency Analysis\n" <>
      "\n" <>
      "**Note**: No latency data was collected during this simulation.\n" <>
      "This may occur if operations completed too quickly to measure or if\n" <>
      "timing collection was not enabled.\n" <>
      "\n" <>
      "### Actor Model Benefits\n" <>
      "\n" <>
      "- **Non-blocking**: Operations don't wait for responses\n" <>
      "- **Concurrent**: Thousands of operations processed simultaneously\n" <>
      "- **Fault-tolerant**: Actor crashes don't affect other actors\n" <>
      "- **Scalable**: Can distribute across multiple machines\n"
    }
  }
}

// FIXED: Format as microseconds with proper number formatting
fn generate_latency_rows(snapshot: metrics_collector.MetricsSnapshot) -> String {
  dict.fold(snapshot.latency_stats, "", fn(acc, _key, stats) {
    acc <> "| " <> stats.operation <>
    " | " <> int.to_string(stats.count) <>
    " | " <> format_float(stats.min_us, 1) <>
    " | " <> format_float(stats.avg_us, 1) <>
    " | " <> format_float(stats.p50_us, 1) <>
    " | " <> format_float(stats.p95_us, 1) <>
    " | " <> format_float(stats.p99_us, 1) <>
    " | " <> format_float(stats.max_us, 1) <> " |\n"
  })
}

fn generate_performance_analysis(snapshot: metrics_collector.MetricsSnapshot) -> String {
  case dict.size(snapshot.latency_stats) > 0 {
    True -> {
      let avg_latency = calculate_average_latency(snapshot.latency_stats)
      
      let performance_rating = case avg_latency {
        x if x <. 100.0 -> "⭐⭐⭐⭐⭐ **Excellent** (sub-100μs average)"
        x if x <. 500.0 -> "⭐⭐⭐⭐ **Very Good** (sub-500μs average)"
        x if x <. 1000.0 -> "⭐⭐⭐ **Good** (sub-1ms average)"
        x if x <. 5000.0 -> "⭐⭐ **Acceptable** (1-5ms average)"
        _ -> "⭐ **Needs Optimization** (>5ms average)"
      }
      
      "**System Performance**: " <> performance_rating <> "\n" <>
      "\n" <>
      "**Average Latency**: " <> format_float(avg_latency, 1) <> " μs (" <> format_float(avg_latency /. 1000.0, 3) <> " ms)\n" <>
      "\n" <>
      "**Fastest Operation**: " <> get_fastest_operation(snapshot.latency_stats) <> "\n" <>
      "**Slowest Operation**: " <> get_slowest_operation(snapshot.latency_stats) <> "\n"
    }
    False -> {
      "**System Performance**: Unable to calculate (no latency data)\n"
    }
  }
}

fn calculate_average_latency(stats: Dict(String, metrics_collector.LatencyStats)) -> Float {
  let total_ops = dict.fold(stats, 0, fn(acc, _, s) { acc + s.count })
  let total_time = dict.fold(stats, 0.0, fn(acc, _, s) {
    acc +. s.avg_us *. int.to_float(s.count)
  })
  
  case total_ops > 0 {
    True -> total_time /. int.to_float(total_ops)
    False -> 0.0
  }
}

fn get_fastest_operation(stats: Dict(String, metrics_collector.LatencyStats)) -> String {
  case dict.to_list(stats) {
    [] -> "N/A"
    ops -> {
      let sorted = list.sort(ops, fn(a, b) {
        float.compare(a.1.avg_us, b.1.avg_us)
      })
      case list.first(sorted) {
        Ok(#(_, stat)) -> stat.operation <> " (" <> format_float(stat.avg_us, 1) <> " μs avg)"
        Error(_) -> "N/A"
      }
    }
  }
}

fn get_slowest_operation(stats: Dict(String, metrics_collector.LatencyStats)) -> String {
  case dict.to_list(stats) {
    [] -> "N/A"
    ops -> {
      let sorted = list.sort(ops, fn(a, b) {
        float.compare(b.1.avg_us, a.1.avg_us)
      })
      case list.first(sorted) {
        Ok(#(_, stat)) -> stat.operation <> " (" <> format_float(stat.avg_us, 1) <> " μs avg)"
        Error(_) -> "N/A"
      }
    }
  }
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

fn generate_zipf_section(config: simulation_types.SimulationConfig) -> String {
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

// REMOVED: generate_conclusions function

// ============================================================================
// Helper Functions
// ============================================================================

fn format_float(f: Float, decimals: Int) -> String {
  let multiplier = case decimals {
    0 -> 1.0
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
  
  case decimals {
    0 -> int.to_string(int_part)
    _ -> {
      let decimal_str = int.to_string(decimal_int)
      let padded = pad_zeros(decimal_str, decimals)
      int.to_string(int_part) <> "." <> padded
    }
  }
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
  "2025"
}