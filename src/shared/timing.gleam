// Timing utilities for performance measurement
import shared/utils
import engine/metrics_collector
// ============================================================================
// Timing Helpers
// ============================================================================

/// Simple timing record
pub type TimedOperation {
  TimedOperation(
    start_time: Int,
    operation_name: String,
  )
}

/// Start timing an operation
pub fn start_timer(operation_name: String) -> TimedOperation {
  TimedOperation(
    start_time: utils.get_current_timestamp(),
    operation_name: operation_name,
  )
}

/// Get elapsed time in milliseconds
pub fn get_elapsed_ms(timer: TimedOperation) -> Int {
  let current = utils.get_current_timestamp()
  current - timer.start_time
}

/// Get elapsed time in microseconds
pub fn get_elapsed_micros(timer: TimedOperation) -> Int {
  get_elapsed_ms(timer) * 1000
}

/// Get operation name from timer
pub fn get_operation_name(timer: TimedOperation) -> String {
  timer.operation_name
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Quick operation names for common operations
pub const register_user = "register_user"
pub const login_user = "login_user"
pub const create_subreddit = "create_subreddit"
pub const join_subreddit = "join_subreddit"
pub const create_post = "create_post"
pub const create_comment = "create_comment"
pub const vote_post = "vote_post"
pub const vote_comment = "vote_comment"
pub const get_feed = "get_feed"
pub const send_dm = "send_direct_message"
pub const get_messages = "get_messages"