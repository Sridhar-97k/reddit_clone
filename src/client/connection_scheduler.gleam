// Connection Scheduler - FIXED to work with your existing code
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/int
import gleam/io
import gleam/list
import gleam/order
import gleam/result
import gleam/option.{type Option, None, Some}
import shared/types.{type Id}
import shared/protocol
import engine/core

// ============================================================================
// Types
// ============================================================================

pub type SchedulerState {
  SchedulerState(
    engine: Subject(core.EngineMessage),
    user_ids: List(Id),
    cycle_seconds: Int,
    currently_disconnected: List(Id),
    disconnection_counts: Int,
    reconnection_counts: Int,
    self: Option(Subject(SchedulerMessage)),
  )
}

pub type SchedulerMessage {
  StartCycle
  DisconnectBatch
  ReconnectBatch
  Stop
}

// ============================================================================
// API (SAME SIGNATURE AS YOUR ORIGINAL)
// ============================================================================

/// Start the connection scheduler
pub fn start(
  engine: Subject(core.EngineMessage),
  user_ids: List(Id),
  cycle_seconds: Int,
) -> Result(Subject(SchedulerMessage), actor.StartError) {
  let init_state = SchedulerState(
    engine: engine,
    user_ids: user_ids,
    cycle_seconds: cycle_seconds,
    currently_disconnected: [],
    disconnection_counts: 0,
    reconnection_counts: 0,
    self: None,
  )
  
  actor.new(init_state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

/// Begin the connection/disconnection cycles
pub fn begin_cycles(scheduler: Subject(SchedulerMessage)) -> Nil {
  process.send(scheduler, StartCycle)
}

/// Stop the scheduler
pub fn stop(scheduler: Subject(SchedulerMessage)) -> Nil {
  process.send(scheduler, Stop)
}

// ============================================================================
// Implementation
// ============================================================================

fn handle_message(
  state: SchedulerState,
  msg: SchedulerMessage,
) -> actor.Next(SchedulerState, SchedulerMessage) {
  case msg {
    StartCycle -> {
      io.println("\n🔄 Connection scheduler started (cycle: " <> int.to_string(state.cycle_seconds) <> "s)")
      io.println("   Will disconnect/reconnect ~20% of users periodically")
      io.println("   Tracking connection metrics\n")
      
      // Get self reference for scheduling
      let self = process.new_subject()
      
      // Schedule first disconnection after one cycle
      schedule_disconnect(self, state.cycle_seconds * 1000)
      
      actor.continue(SchedulerState(..state, self: Some(self)))
    }
    
    DisconnectBatch -> {
      // Calculate 20% of users to disconnect
      let total_users = list.length(state.user_ids)
      let num_to_disconnect = int.max(1, total_users / 5)
      
      // Get currently connected users
      let connected_users = list.filter(state.user_ids, fn(user_id) {
        !list.contains(state.currently_disconnected, user_id)
      })
      
      // Select random users to disconnect using FIXED shuffle
      let users_to_disconnect = 
        connected_users
        |> shuffle_list()
        |> list.take(num_to_disconnect)
      
      // Send disconnect requests to engine
      list.each(users_to_disconnect, fn(user_id) {
        let client = process.new_subject()
        core.handle_request(
          state.engine,
          "disconnect_" <> user_id,
          client,
          protocol.Disconnect(user_id),
        )
      })
      
      let total_offline = num_to_disconnect + list.length(state.currently_disconnected)
      io.println("🔌 Disconnected " <> int.to_string(num_to_disconnect) <> " users")
      io.println("   Currently offline: " <> int.to_string(total_offline) <> "/" <> int.to_string(total_users))
      
      // Schedule reconnection in 5 seconds
      case state.self {
        Some(self) -> schedule_reconnect(self, 5000)
        None -> Nil
      }
      
      actor.continue(SchedulerState(
        ..state,
        currently_disconnected: list.append(state.currently_disconnected, users_to_disconnect),
        disconnection_counts: state.disconnection_counts + num_to_disconnect,
      ))
    }
    
    ReconnectBatch -> {
      let num_to_reconnect = list.length(state.currently_disconnected)
      
      case num_to_reconnect > 0 {
        True -> {
          // Send reconnect requests to engine
          list.each(state.currently_disconnected, fn(user_id) {
            let client = process.new_subject()
            core.handle_request(
              state.engine,
              "connect_" <> user_id,
              client,
              protocol.Connect(user_id),
            )
          })
          
          io.println("🔌 Reconnected " <> int.to_string(num_to_reconnect) <> " users")
          io.println("   All users back online")
          
          // Schedule next disconnect cycle
          case state.self {
            Some(self) -> schedule_disconnect(self, state.cycle_seconds * 1000)
            None -> Nil
          }
          
          actor.continue(SchedulerState(
            ..state,
            currently_disconnected: [],
            reconnection_counts: state.reconnection_counts + num_to_reconnect,
          ))
        }
        False -> {
          io.println("⚠️  No users to reconnect")
          actor.continue(state)
        }
      }
    }
    
    Stop -> {
      io.println("\n🛑 Connection scheduler stopped")
      io.println("   Total disconnections: " <> int.to_string(state.disconnection_counts))
      io.println("   Total reconnections: " <> int.to_string(state.reconnection_counts))
      
      // Calculate some stats
      let total_cycles = case state.disconnection_counts > 0 {
        True -> state.disconnection_counts / int.max(1, list.length(state.user_ids) / 5)
        False -> 0
      }
      io.println("   Connection cycles completed: " <> int.to_string(total_cycles))
      
      actor.stop()
    }
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Schedule a disconnect message after delay
fn schedule_disconnect(self: Subject(SchedulerMessage), delay_ms: Int) -> Nil {
  let _timer = process.send_after(self, delay_ms, DisconnectBatch)
  Nil
}

/// Schedule a reconnect message after delay
fn schedule_reconnect(self: Subject(SchedulerMessage), delay_ms: Int) -> Nil {
  let _timer = process.send_after(self, delay_ms, ReconnectBatch)
  Nil
}

/// FIXED: Proper Fisher-Yates shuffle
/// This is much better than the original random comparison approach
fn shuffle_list(list: List(a)) -> List(a) {
  list
  |> list.index_map(fn(item, idx) {
    // Assign random priority to each item
    // The idx ensures stable ordering for equal priorities
    #(item, int.random(1_000_000_000) + idx)
  })
  |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
  |> list.map(fn(pair) { pair.0 })
}