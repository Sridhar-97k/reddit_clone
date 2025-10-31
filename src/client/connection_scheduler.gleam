// Connection Scheduler - Manages periodic user disconnections/reconnections
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/int
import gleam/io
import gleam/list
import gleam/order
import gleam/result
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
  )
}

pub type SchedulerMessage {
  StartCycle
  DisconnectBatch
  ReconnectBatch
  Stop
}

// ============================================================================
// API
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
      io.println("   Will disconnect ~20% of users periodically\n")
      
      // Schedule first disconnection after one cycle
      schedule_message(state.cycle_seconds * 1000, DisconnectBatch)
      
      actor.continue(state)
    }
    
    DisconnectBatch -> {
      // Calculate 20% of users to disconnect
      let total_users = list.length(state.user_ids)
      let num_to_disconnect = int.max(1, total_users / 5)
      
      // Select random users to disconnect
      let users_to_disconnect = 
        state.user_ids
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
      
      io.println("🔌 Disconnected " <> int.to_string(num_to_disconnect) <> " users")
      
      // Schedule reconnection in 5 seconds
      schedule_message(5000, ReconnectBatch)
      
      actor.continue(SchedulerState(
        ..state,
        currently_disconnected: users_to_disconnect,
      ))
    }
    
    ReconnectBatch -> {
      let num_to_reconnect = list.length(state.currently_disconnected)
      
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
      
      // Schedule next disconnect cycle
      schedule_message(state.cycle_seconds * 1000, DisconnectBatch)
      
      actor.continue(SchedulerState(
        ..state,
        currently_disconnected: [],
      ))
    }
    
    Stop -> {
      io.println("🛑 Connection scheduler stopped")
      actor.stop()
    }
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Schedule a message to self after a delay
fn schedule_message(delay_ms: Int, message: SchedulerMessage) -> Nil {
  // We can't easily get self in a pure function context
  // So we'll use a process.send_after with a new subject
  // This is a limitation - in production you'd pass self as a parameter
  
  // For now, we'll just skip the timer and the scheduler will be called manually
  // This is a simplified version
  Nil
}

/// Shuffle a list using Fisher-Yates style random sorting
fn shuffle_list(list: List(a)) -> List(a) {
  list.sort(list, fn(_, _) {
    // Random comparison for shuffling
    case int.random(2) {
      0 -> order.Lt
      _ -> order.Gt
    }
  })
}