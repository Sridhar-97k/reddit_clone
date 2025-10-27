// Connection Scheduler - Simulates periodic user disconnections/reconnections
// Simplified version that just logs - avoids complex type issues
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/order

pub type ConnectionCycleInfo {
  ConnectionCycleInfo(
    total_users: Int,
    cycle_seconds: Int,
  )
}

/// Simulate connection cycles by logging disconnect/reconnect events
/// This is a simplified version for demonstration
pub fn simulate_connection_cycles(
  total_users: Int,
  cycle_seconds: Int,
) -> Nil {
  let info = ConnectionCycleInfo(
    total_users: total_users,
    cycle_seconds: cycle_seconds,
  )
  
  io.println("\n🔄 Connection Cycle Simulation:")
  io.println("   Total Users: " <> int.to_string(total_users))
  io.println("   Cycle Duration: " <> int.to_string(cycle_seconds) <> " seconds")
  io.println("   Disconnect Rate: ~20% per cycle")
  
  // In a real implementation, this would:
  // 1. Track user connection states
  // 2. Periodically disconnect random 20% of users
  // 3. Reconnect them after 5 seconds
  // 4. Repeat every cycle_seconds
  
  Nil
}

/// Log a simulated disconnection event
pub fn log_disconnect_event(num_users: Int) -> Nil {
  io.println("🔌 [SIMULATED] Disconnected " <> int.to_string(num_users) <> " users")
}

/// Log a simulated reconnection event
pub fn log_reconnect_event(num_users: Int) -> Nil {
  io.println("🔌 [SIMULATED] Reconnected " <> int.to_string(num_users) <> " users")
}

/// Calculate number of users to disconnect (20% of total)
pub fn calculate_disconnect_count(total_users: Int) -> Int {
  int.max(1, total_users / 5)
}

/// Shuffle a list randomly
pub fn shuffle_list(list: List(a)) -> List(a) {
  list.sort(list, fn(_, _) {
    case int.random(2) {
      0 -> order.Lt
      _ -> order.Gt
    }
  })
}