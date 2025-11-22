// Metrics Collector - Tracks performance metrics
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/order
import gleam/result

// ============================================================================
// Types
// ============================================================================

pub type LatencyStats {
  LatencyStats(
    operation: String,
    count: Int,
    min_us: Float,
    max_us: Float,
    avg_us: Float,
    p50_us: Float,
    p95_us: Float,
    p99_us: Float,
    total_us: Float,
    samples: List(Float),
  )
}

pub type MetricsSnapshot {
  MetricsSnapshot(
    total_operations: Int,
    total_duration_seconds: Float,
    operations_per_second: Float,
    error_rate: Float,
    operations_by_type: Dict(String, Int),
    errors_by_type: Dict(String, Int),
    latency_stats: Dict(String, LatencyStats),
  )
}

pub type MetricsState {
  MetricsState(
    operations_by_type: Dict(String, Int),
    errors_by_type: Dict(String, Int),
    latencies: Dict(String, List(Float)),
    start_time: Int,
    total_operations: Int,
    total_errors: Int,
  )
}

pub type MetricsMessage {
  RecordOperation(operation: String, latency_us: Float)
  RecordError(error_type: String)
  GetSnapshot(client: Subject(MetricsSnapshot))
  Reset
  Stop
}

// ============================================================================
// API
// ============================================================================

// FIXED: Using actor.start for gleam_otp 0.14.1
pub fn start() -> Result(Subject(MetricsMessage), actor.StartError) {
  actor.start(init_state(), handle_message)
}

pub fn record_operation(
  collector: Subject(MetricsMessage),
  operation: String,
  latency_us: Float,
) -> Nil {
  process.send(collector, RecordOperation(operation, latency_us))
}

pub fn record_error(
  collector: Subject(MetricsMessage),
  error_type: String,
) -> Nil {
  process.send(collector, RecordError(error_type))
}

pub fn get_snapshot(
  collector: Subject(MetricsMessage),
  client: Subject(MetricsSnapshot),
) -> Nil {
  process.send(collector, GetSnapshot(client))
}

pub fn reset(collector: Subject(MetricsMessage)) -> Nil {
  process.send(collector, Reset)
}

pub fn stop(collector: Subject(MetricsMessage)) -> Nil {
  process.send(collector, Stop)
}

// ============================================================================
// Implementation
// ============================================================================

fn init_state() -> MetricsState {
  MetricsState(
    operations_by_type: dict.new(),
    errors_by_type: dict.new(),
    latencies: dict.new(),
    start_time: get_current_time_ms(),
    total_operations: 0,
    total_errors: 0,
  )
}

// FIXED: Parameter order changed - message FIRST, then state
// FIXED: Return type parameters swapped
fn handle_message(
  message: MetricsMessage,
  state: MetricsState,
) -> actor.Next(MetricsMessage, MetricsState) {
  case message {
    RecordOperation(operation, latency_us) -> {
      // Update operation count
      let new_ops_by_type =
        dict.update(state.operations_by_type, operation, fn(maybe_count) {
          case maybe_count {
            Some(count) -> count + 1
            None -> 1
          }
        })

      // Update latencies
      let new_latencies =
        dict.update(state.latencies, operation, fn(maybe_list) {
          case maybe_list {
            Some(list) -> [latency_us, ..list]
            None -> [latency_us]
          }
        })

      let new_state =
        MetricsState(
          ..state,
          operations_by_type: new_ops_by_type,
          latencies: new_latencies,
          total_operations: state.total_operations + 1,
        )

      actor.continue(new_state)
    }

    RecordError(error_type) -> {
      let new_errors_by_type =
        dict.update(state.errors_by_type, error_type, fn(maybe_count) {
          case maybe_count {
            Some(count) -> count + 1
            None -> 1
          }
        })

      let new_state =
        MetricsState(
          ..state,
          errors_by_type: new_errors_by_type,
          total_errors: state.total_errors + 1,
        )

      actor.continue(new_state)
    }

    GetSnapshot(client) -> {
      let snapshot = create_snapshot(state)
      process.send(client, snapshot)
      actor.continue(state)
    }

    Reset -> {
      actor.continue(init_state())
    }

    Stop -> {
      actor.Stop(process.Normal)
    }
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn create_snapshot(state: MetricsState) -> MetricsSnapshot {
  let duration_ms = get_current_time_ms() - state.start_time
  let duration_seconds = int.to_float(duration_ms) /. 1000.0

  let ops_per_second = case duration_seconds >. 0.0 {
    True -> int.to_float(state.total_operations) /. duration_seconds
    False -> 0.0
  }

  let error_rate = case state.total_operations > 0 {
    True ->
      int.to_float(state.total_errors) /. int.to_float(state.total_operations)
    False -> 0.0
  }

  // Calculate latency statistics for each operation
  let latency_stats =
    dict.map_values(state.latencies, fn(operation, samples) {
      calculate_latency_stats(operation, samples)
    })

  MetricsSnapshot(
    total_operations: state.total_operations,
    total_duration_seconds: duration_seconds,
    operations_per_second: ops_per_second,
    error_rate: error_rate,
    operations_by_type: state.operations_by_type,
    errors_by_type: state.errors_by_type,
    latency_stats: latency_stats,
  )
}

fn calculate_latency_stats(
  operation: String,
  samples: List(Float),
) -> LatencyStats {
  let count = list.length(samples)

  case count {
    0 ->
      LatencyStats(
        operation: operation,
        count: 0,
        min_us: 0.0,
        max_us: 0.0,
        avg_us: 0.0,
        p50_us: 0.0,
        p95_us: 0.0,
        p99_us: 0.0,
        total_us: 0.0,
        samples: [],
      )

    _ -> {
      let sorted_samples = list.sort(samples, float.compare)

      let min_us = case list.first(sorted_samples) {
        Ok(v) -> v
        Error(Nil) -> 0.0
      }

      let max_us = case list.last(sorted_samples) {
        Ok(v) -> v
        Error(Nil) -> 0.0
      }

      let total_us = list.fold(samples, 0.0, fn(acc, v) { acc +. v })
      let avg_us = total_us /. int.to_float(count)

      let p50_us = percentile(sorted_samples, 50)
      let p95_us = percentile(sorted_samples, 95)
      let p99_us = percentile(sorted_samples, 99)

      LatencyStats(
        operation: operation,
        count: count,
        min_us: min_us,
        max_us: max_us,
        avg_us: avg_us,
        p50_us: p50_us,
        p95_us: p95_us,
        p99_us: p99_us,
        total_us: total_us,
        samples: sorted_samples,
      )
    }
  }
}

fn percentile(sorted_samples: List(Float), p: Int) -> Float {
  let count = list.length(sorted_samples)
  case count {
    0 -> 0.0
    _ -> {
      let index = int.to_float(count) *. int.to_float(p) /. 100.0
      let index_int = float.truncate(index)
      let index_clamped = int.min(index_int, count - 1)

      case list.at(sorted_samples, index_clamped) {
        Ok(value) -> value
        Error(Nil) -> 0.0
      }
    }
  }
}

fn get_current_time_ms() -> Int {
  // Use erlang's monotonic time which returns microseconds
  // Convert to milliseconds by dividing by 1000
  erlang_monotonic_time() / 1000
}

@external(erlang, "erlang", "monotonic_time")
fn erlang_monotonic_time() -> Int
