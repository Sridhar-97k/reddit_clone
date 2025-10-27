// Metrics Collector - Tracks performance metrics for the Reddit Clone
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/float
import gleam/string
import shared/utils

// ============================================================================
// Metrics Types
// ============================================================================

pub type MetricsState {
  MetricsState(
    // Operation counts
    total_operations: Int,
    operations_by_type: Dict(String, Int),
    
    // Timing data (in microseconds)
    operation_times: Dict(String, List(Int)),
    
    // Throughput tracking
    start_time: Int,
    last_report_time: Int,
    
    // Error tracking
    error_count: Int,
    errors_by_type: Dict(String, Int),
    
    // Memory tracking (approximate)
    peak_memory: Int,
    current_operations: Int,
  )
}

pub type MetricsMessage {
  RecordOperation(operation_type: String, duration_micros: Int)
  RecordError(error_type: String)
  IncrementOperationCount(operation_type: String)
  GetMetrics(client: Subject(MetricsSnapshot))
  PrintReport
  Reset
}

pub type MetricsSnapshot {
  MetricsSnapshot(
    total_operations: Int,
    operations_by_type: Dict(String, Int),
    total_duration_seconds: Float,
    operations_per_second: Float,
    latency_stats: Dict(String, LatencyStats),
    error_rate: Float,
    errors_by_type: Dict(String, Int),
  )
}

pub type LatencyStats {
  LatencyStats(
    operation: String,
    count: Int,
    min_ms: Float,
    max_ms: Float,
    avg_ms: Float,
    p50_ms: Float,
    p95_ms: Float,
    p99_ms: Float,
  )
}

// ============================================================================
// API
// ============================================================================

pub fn start() -> Result(Subject(MetricsMessage), actor.StartError) {
  let init_state = MetricsState(
    total_operations: 0,
    operations_by_type: dict.new(),
    operation_times: dict.new(),
    start_time: utils.get_current_timestamp(),
    last_report_time: utils.get_current_timestamp(),
    error_count: 0,
    errors_by_type: dict.new(),
    peak_memory: 0,
    current_operations: 0,
  )
  
  actor.new(init_state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

/// Record a completed operation with its duration
pub fn record_operation(
  metrics: Subject(MetricsMessage),
  operation_type: String,
  duration_micros: Int,
) -> Nil {
  process.send(metrics, RecordOperation(operation_type, duration_micros))
}

/// Record an error
pub fn record_error(
  metrics: Subject(MetricsMessage),
  error_type: String,
) -> Nil {
  process.send(metrics, RecordError(error_type))
}

/// Increment operation count (without timing data)
pub fn increment_count(
  metrics: Subject(MetricsMessage),
  operation_type: String,
) -> Nil {
  process.send(metrics, IncrementOperationCount(operation_type))
}

/// Get current metrics snapshot
pub fn get_metrics(
  metrics: Subject(MetricsMessage),
  client: Subject(MetricsSnapshot),
) -> Nil {
  process.send(metrics, GetMetrics(client))
}

/// Print a formatted report
pub fn print_report(metrics: Subject(MetricsMessage)) -> Nil {
  process.send(metrics, PrintReport)
}

/// Reset all metrics
pub fn reset(metrics: Subject(MetricsMessage)) -> Nil {
  process.send(metrics, Reset)
}

// ============================================================================
// Implementation
// ============================================================================

fn handle_message(
  state: MetricsState,
  message: MetricsMessage,
) -> actor.Next(MetricsState, MetricsMessage) {
  case message {
    RecordOperation(op_type, duration) -> {
      // Update operation count
      let op_count = dict.get(state.operations_by_type, op_type)
        |> result.unwrap(0)
      let new_ops = dict.insert(state.operations_by_type, op_type, op_count + 1)
      
      // Store timing data
      let times = dict.get(state.operation_times, op_type)
        |> result.unwrap([])
      let new_times = [duration, ..times]
      let updated_times = dict.insert(state.operation_times, op_type, new_times)
      
      let new_state = MetricsState(
        ..state,
        total_operations: state.total_operations + 1,
        operations_by_type: new_ops,
        operation_times: updated_times,
      )
      
      actor.continue(new_state)
    }
    
    RecordError(error_type) -> {
      let error_count = dict.get(state.errors_by_type, error_type)
        |> result.unwrap(0)
      let new_errors = dict.insert(state.errors_by_type, error_type, error_count + 1)
      
      let new_state = MetricsState(
        ..state,
        error_count: state.error_count + 1,
        errors_by_type: new_errors,
      )
      
      actor.continue(new_state)
    }
    
    IncrementOperationCount(op_type) -> {
      let op_count = dict.get(state.operations_by_type, op_type)
        |> result.unwrap(0)
      let new_ops = dict.insert(state.operations_by_type, op_type, op_count + 1)
      
      let new_state = MetricsState(
        ..state,
        total_operations: state.total_operations + 1,
        operations_by_type: new_ops,
      )
      
      actor.continue(new_state)
    }
    
    GetMetrics(client) -> {
      let snapshot = create_snapshot(state)
      process.send(client, snapshot)
      actor.continue(state)
    }
    
    PrintReport -> {
      print_metrics_report(state)
      actor.continue(state)
    }
    
    Reset -> {
      let new_state = MetricsState(
        total_operations: 0,
        operations_by_type: dict.new(),
        operation_times: dict.new(),
        start_time: utils.get_current_timestamp(),
        last_report_time: utils.get_current_timestamp(),
        error_count: 0,
        errors_by_type: dict.new(),
        peak_memory: 0,
        current_operations: 0,
      )
      actor.continue(new_state)
    }
  }
}

// ============================================================================
// Metrics Calculation
// ============================================================================

fn create_snapshot(state: MetricsState) -> MetricsSnapshot {
  let current_time = utils.get_current_timestamp()
  let duration_ms = current_time - state.start_time
  let duration_seconds = int.to_float(duration_ms) /. 1000.0
  
  let ops_per_second = case duration_seconds >. 0.0 {
    True -> int.to_float(state.total_operations) /. duration_seconds
    False -> 0.0
  }
  
  let error_rate = case state.total_operations > 0 {
    True -> int.to_float(state.error_count) /. int.to_float(state.total_operations)
    False -> 0.0
  }
  
  // Calculate latency stats for each operation type
  let latency_stats = dict.fold(
    state.operation_times,
    dict.new(),
    fn(acc, op_type, times) {
      case list.is_empty(times) {
        True -> acc
        False -> {
          let stats = calculate_latency_stats(op_type, times)
          dict.insert(acc, op_type, stats)
        }
      }
    }
  )
  
  MetricsSnapshot(
    total_operations: state.total_operations,
    operations_by_type: state.operations_by_type,
    total_duration_seconds: duration_seconds,
    operations_per_second: ops_per_second,
    latency_stats: latency_stats,
    error_rate: error_rate,
    errors_by_type: state.errors_by_type,
  )
}

fn calculate_latency_stats(op_type: String, times: List(Int)) -> LatencyStats {
  let count = list.length(times)
  
  // Convert microseconds to milliseconds
  let times_ms = list.map(times, fn(t) { int.to_float(t) /. 1000.0 })
  
  let sorted = list.sort(times_ms, float.compare)
  
  let min = case list.first(sorted) {
    Ok(v) -> v
    Error(_) -> 0.0
  }
  
  let max = case list.last(sorted) {
    Ok(v) -> v
    Error(_) -> 0.0
  }
  
  let sum = list.fold(times_ms, 0.0, fn(acc, t) { acc +. t })
  let avg = case count > 0 {
    True -> sum /. int.to_float(count)
    False -> 0.0
  }
  
  let p50 = percentile(sorted, 50)
  let p95 = percentile(sorted, 95)
  let p99 = percentile(sorted, 99)
  
  LatencyStats(
    operation: op_type,
    count: count,
    min_ms: min,
    max_ms: max,
    avg_ms: avg,
    p50_ms: p50,
    p95_ms: p95,
    p99_ms: p99,
  )
}

fn percentile(sorted_list: List(Float), p: Int) -> Float {
  let len = list.length(sorted_list)
  case len {
    0 -> 0.0
    _ -> {
      let index = { p * len } / 100
      case list_get_at(sorted_list, index) {
        Ok(v) -> v
        Error(_) -> 0.0
      }
    }
  }
}

fn list_get_at(list: List(a), index: Int) -> Result(a, Nil) {
  list
  |> list.drop(index)
  |> list.first()
}

// ============================================================================
// Reporting
// ============================================================================

fn print_metrics_report(state: MetricsState) -> Nil {
  let snapshot = create_snapshot(state)
  
  io.println("")
  io.println("╔═══════════════════════════════════════════════════════════╗")
  io.println("║           PERFORMANCE METRICS REPORT                      ║")
  io.println("╚═══════════════════════════════════════════════════════════╝")
  io.println("")
  
  // Overall Stats
  io.println("📊 OVERALL STATISTICS")
  io.println("─────────────────────────────────────────────────────────────")
  io.println("  Total Operations:     " <> int.to_string(snapshot.total_operations))
  io.println("  Duration:             " <> format_float(snapshot.total_duration_seconds, 2) <> " seconds")
  io.println("  Throughput:           " <> format_float(snapshot.operations_per_second, 2) <> " ops/sec")
  io.println("  Error Rate:           " <> format_float(snapshot.error_rate *. 100.0, 2) <> "%")
  io.println("  Total Errors:         " <> int.to_string(state.error_count))
  io.println("")
  
  // Operations Breakdown
  io.println("📈 OPERATIONS BREAKDOWN")
  io.println("─────────────────────────────────────────────────────────────")
  dict.fold(snapshot.operations_by_type, Nil, fn(_, op_type, count) {
    let percentage = case snapshot.total_operations > 0 {
      True -> { int.to_float(count) /. int.to_float(snapshot.total_operations) } *. 100.0
      False -> 0.0
    }
    io.println("  " <> pad_right(op_type, 25) <> ": " <> pad_left(int.to_string(count), 6) <> " (" <> format_float(percentage, 1) <> "%)")
    Nil
  })
  io.println("")
  
  // Latency Stats
  io.println("⏱️  LATENCY STATISTICS (milliseconds)")
  io.println("─────────────────────────────────────────────────────────────")
  io.println("  Operation             Count    Min      Avg      P50      P95      P99      Max")
  io.println("  ────────────────────  ─────  ───────  ───────  ───────  ───────  ───────  ───────")
  
  dict.fold(snapshot.latency_stats, Nil, fn(_, _op_type, stats) {
    io.println(
      "  " <> pad_right(stats.operation, 20) <>
      "  " <> pad_left(int.to_string(stats.count), 5) <>
      "  " <> pad_left(format_float(stats.min_ms, 2), 7) <>
      "  " <> pad_left(format_float(stats.avg_ms, 2), 7) <>
      "  " <> pad_left(format_float(stats.p50_ms, 2), 7) <>
      "  " <> pad_left(format_float(stats.p95_ms, 2), 7) <>
      "  " <> pad_left(format_float(stats.p99_ms, 2), 7) <>
      "  " <> pad_left(format_float(stats.max_ms, 2), 7)
    )
    Nil
  })
  io.println("")
  
  // Error Breakdown
  case state.error_count > 0 {
    True -> {
      io.println("❌ ERROR BREAKDOWN")
      io.println("─────────────────────────────────────────────────────────────")
      dict.fold(snapshot.errors_by_type, Nil, fn(_, error_type, count) {
        io.println("  " <> pad_right(error_type, 30) <> ": " <> int.to_string(count))
        Nil
      })
      io.println("")
    }
    False -> Nil
  }
  
  io.println("═══════════════════════════════════════════════════════════")
  io.println("")
}

// ============================================================================
// Helper Functions
// ============================================================================

fn format_float(f: Float, decimals: Int) -> String {
  // Simplified float formatting
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
  
  // Convert to positive integer for decimal part
  let decimal_int = float.round(float.absolute_value(int.to_float(decimal_part)))
  
  int.to_string(int_part) <> "." <> int.to_string(decimal_int)
}

fn pad_right(str: String, width: Int) -> String {
  let len = string_length(str)
  case width > len {
    True -> str <> repeat_string(" ", width - len)
    False -> str
  }
}

fn pad_left(str: String, width: Int) -> String {
  let len = string_length(str)
  case width > len {
    True -> repeat_string(" ", width - len) <> str
    False -> str
  }
}

fn string_length(s: String) -> Int {
  // Placeholder - in real code use string.length
  string.length(s)
  // case s {
  //   "" -> 0
  //   _ -> 10 // Approximate
  // }
}

fn repeat_string(str: String, times: Int) -> String {
  string.repeat(str, times)
  // case times <= 0 {
  //   True -> ""
  //   False -> str <> repeat_string(str, times - 1)
  // }

}