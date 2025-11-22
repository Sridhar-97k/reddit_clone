// Client Simulator - Simulates Reddit users with realistic behavior
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/float
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import engine/core
import engine/metrics_collector
import engine/report_generator
import engine/file_writer
import client/zipf
import client/connection_scheduler
import client/simulation_types.{type SimulationConfig, type SimulationMetrics}
import shared/protocol.{type ClientRequest, type EngineResponse}
import shared/types.{type Id, type VoteType, Downvote, Upvote}
import shared/utils

// ============================================================================
// Configuration (using imported types)
// ============================================================================

pub fn default_config() -> SimulationConfig {
  simulation_types.default_config()
}

pub fn large_scale_config() -> SimulationConfig {
  simulation_types.large_scale_config()
}

// ============================================================================
// Simulator State
// ============================================================================

pub type SimulatorState {
  SimulatorState(
    engine: Subject(core.EngineMessage),
    config: SimulationConfig,
    users: List(SimulatedUser),
    subreddits: List(Id),
    subreddit_names: List(String),
    subreddit_popularity: Dict(Int, Int),
    metrics: SimulationMetrics,
    metrics_collector: Subject(metrics_collector.MetricsMessage),
    connection_scheduler: Option(Subject(connection_scheduler.SchedulerMessage)),
  )
}

pub type SimulatedUser {
  SimulatedUser(
    id: Id,
    username: String,
    password: String,
    client: Subject(EngineResponse),
    subscribed_subreddits: List(Id),
    is_connected: Bool,
  )
}

// ============================================================================
// Simulator Messages
// ============================================================================

pub type SimulatorMessage {
  StartSimulation
  UserAction(user_id: Id, action: UserAction)
  CollectMetrics
  PrintStatus
  Shutdown
}

pub type UserAction {
  CreateSubredditAction(name: String, description: String)
  JoinSubredditAction(subreddit_id: Id)
  CreatePostAction(subreddit_id: Id, title: String, content: String)
  CreateCommentAction(post_id: Id, content: String)
  VoteAction(target_id: Id, vote_type: VoteType)
  SendMessageAction(to_user_id: Id, content: String)
  GetFeedAction
}

// ============================================================================
// API
// ============================================================================

pub fn start(
  engine: Subject(core.EngineMessage),
  config: SimulationConfig,
) -> Result(Subject(SimulatorMessage), actor.StartError) {
  let assert Ok(metrics_col) = metrics_collector.start()
  
  let init_state = SimulatorState(
    engine: engine,
    config: config,
    users: [],
    subreddits: [],
    subreddit_names: [],
    subreddit_popularity: dict.new(),
    metrics: simulation_types.init_metrics(),
    metrics_collector: metrics_col,
    connection_scheduler: None,
  )
  
  // FIXED: Use actor.start directly with init_state and handler
  actor.start(init_state, handle_simulator_message)
}

pub fn start_simulation(simulator: Subject(SimulatorMessage)) -> Nil {
  process.send(simulator, StartSimulation)
}

// ============================================================================
// Implementation
// ============================================================================

// FIXED: Changed parameter order - message first, then state
// FIXED: Changed return type parameters
fn handle_simulator_message(
  message: SimulatorMessage,
  state: SimulatorState,
) -> actor.Next(SimulatorMessage, SimulatorState) {
  case message {
    StartSimulation -> {
      io.println("🚀 Starting simulation phase...")
      
      // Phase 1: Register users
      io.println("\n👥 Phase 1: Registering users...")
      let new_state = register_users(state)
      io.println("✅ " <> int.to_string(new_state.config.num_users) <> " users registered")
      
      // Phase 2: Create subreddits
      io.println("\n🏙️ Phase 2: Creating subreddits...")
      let new_state2 = create_subreddits(new_state)
      io.println("✅ " <> int.to_string(new_state2.config.num_subreddits) <> " subreddits created")
      
      // Phase 3: Users join subreddits
      io.println("\n👥 Phase 3: Users joining subreddits...")
      let new_state3 = users_join_subreddits(new_state2)
      io.println("✅ Users subscribed to subreddits")
      
      // Phase 4: Simulate activities
      io.println("\n🎬 Phase 4: Simulating user activities...")
      let new_state4 = simulate_user_activities(new_state3)
      io.println("✅ Activities completed")
      
      // Print simulation metrics
      print_final_metrics(new_state4.metrics)
      
      // Generate and save report to file
      io.println("\n📊 Generating performance report...")
      export_report_to_file(new_state4)
      
      actor.continue(new_state4)
    }

    UserAction(user_id, action) -> {
      let new_state = handle_user_action(state, user_id, action)
      actor.continue(new_state)
    }

    CollectMetrics -> {
      print_metrics(state.metrics)
      actor.continue(state)
    }

    PrintStatus -> {
      print_status(state)
      actor.continue(state)
    }

    Shutdown -> {
      io.println("\n🛑 Shutting down simulator...")
      // FIXED: Use actor.Stop instead of actor.stop()
      actor.Stop(process.Normal)
    }
  }
}

// Add timing measurements to operations in client/simulator.gleam
// Replace the register_users, create_subreddits, and action functions

// ============================================================================
// Phase 1: Register Users (with timing)
// ============================================================================

fn register_users(state: SimulatorState) -> SimulatorState {
  let start_phase = utils.get_current_timestamp()
  
  let users = list.range(1, state.config.num_users)
  |> list.map(fn(i) {
    let username = "user" <> int.to_string(i)
    let password = "pass" <> int.to_string(i)
    let user_id = utils.generate_user_id()
    
    let assert Ok(client) = create_user_client()
    
    // Measure operation time
    let op_start = utils.get_current_timestamp()
    
    core.handle_request(
      state.engine,
      utils.generate_request_id(),
      client,
      protocol.RegisterUser(username, password),
    )
    
    let op_duration = utils.get_current_timestamp() - op_start
    
    // Record operation with timing (convert ms to microseconds)
    // FIXED: Convert Int to Float
    metrics_collector.record_operation(
      state.metrics_collector,
      "register_user",
      int.to_float(op_duration * 1000),
    )
    
    io.println("  ✓ " <> username <> " registered")
    
    SimulatedUser(
      id: user_id,
      username: username,
      password: password,
      client: client,
      subscribed_subreddits: [],
      is_connected: True,
    )
  })
  
  let new_metrics = simulation_types.SimulationMetrics(
    ..state.metrics,
    users_registered: state.config.num_users,
  )
  
  process.sleep(100)
  
  let phase_duration = { utils.get_current_timestamp() - start_phase } * 1000
  io.println("  ⏱️  Phase duration: " <> int.to_string(phase_duration / 1000) <> "ms")
  
  SimulatorState(
    ..state,
    users: users,
    metrics: new_metrics,
    connection_scheduler: state.connection_scheduler,
  )
}
// ============================================================================
// Phase 2: Create Subreddits
// ============================================================================

fn create_subreddits(state: SimulatorState) -> SimulatorState {
  let start_phase = utils.get_current_timestamp()
  
  let subreddits = list.range(1, state.config.num_subreddits)
  |> list.map(fn(i) {
    let name = "sub_" <> int.to_string(i)
    let description = "Subreddit about topic " <> int.to_string(i)
    
    // Pick a random user to create the subreddit
    let creator_idx = int.random(list.length(state.users))
    case get_at(state.users, creator_idx) {
      Ok(creator) -> {
        let subreddit_id = utils.generate_subreddit_id()
        
        // Measure operation time
        let op_start = utils.get_current_timestamp()
        
        core.handle_request(
          state.engine,
          utils.generate_request_id(),
          creator.client,
          protocol.CreateSubreddit(name, description, creator.id),
        )
        
        let op_duration = utils.get_current_timestamp() - op_start
        
        // Record operation with timing
        // FIXED: Convert Int to Float
        metrics_collector.record_operation(
          state.metrics_collector,
          "create_subreddit",
          int.to_float(op_duration * 1000),
        )
        
        io.println("  ✓ r/" <> name <> " created by " <> creator.username)
        
        Some(subreddit_id)
      }
      Error(_) -> None
    }
  })
  |> list.filter_map(fn(maybe_id) {
    case maybe_id {
      Some(id) -> Ok(id)
      None -> Error(Nil)
    }
  })
  
  let subreddit_names = list.range(1, state.config.num_subreddits)
  |> list.map(fn(i) { "sub_" <> int.to_string(i) })
  
  let new_metrics = simulation_types.SimulationMetrics(
    ..state.metrics,
    subreddits_created: state.config.num_subreddits,
  )
  
  process.sleep(100)
  
  let phase_duration = { utils.get_current_timestamp() - start_phase } * 1000
  io.println("  ⏱️  Phase duration: " <> int.to_string(phase_duration / 1000) <> "ms")
  
  SimulatorState(
    ..state,
    subreddits: subreddits,
    subreddit_names: subreddit_names,
    metrics: new_metrics,
  )
}

// ============================================================================
// Phase 3: Users Join Subreddits
// ============================================================================

fn users_join_subreddits(state: SimulatorState) -> SimulatorState {
  let start_phase = utils.get_current_timestamp()
  
  // Each user subscribes to a random number of subreddits based on Zipf distribution
  let updated_users = list.map(state.users, fn(user) {
    // Number of subreddits this user will subscribe to (1-5)
    let num_subscriptions = int.min(
      1 + int.random(5),
      list.length(state.subreddits),
    )
    
    // Pick random subreddits using Zipf distribution (popular ones more likely)
    let subscriptions = list.range(1, num_subscriptions)
    |> list.map(fn(_) {
      let params = zipf.with_skewness(list.length(state.subreddits), 1.07)
      let idx = zipf.select_zipf(params, int.random(1000))
      get_at(state.subreddits, idx)
    })
    |> list.filter_map(fn(maybe_sub) {
      case maybe_sub {
        Ok(sub_id) -> Ok(sub_id)
        Error(_) -> Error(Nil)
      }
    })
    
    // Send join requests to engine
    list.each(subscriptions, fn(sub_id) {
      // Measure operation time
      let op_start = utils.get_current_timestamp()
      
      core.handle_request(
        state.engine,
        utils.generate_request_id(),
        user.client,
        protocol.JoinSubreddit(user.id, sub_id),
      )
      
      let op_duration = utils.get_current_timestamp() - op_start
      
      // Record operation with timing
      // FIXED: Convert Int to Float
      metrics_collector.record_operation(
        state.metrics_collector,
        "join_subreddit",
        int.to_float(op_duration * 1000),
      )
    })
    
    SimulatedUser(..user, subscribed_subreddits: subscriptions)
  })
  
  process.sleep(100)
  
  let phase_duration = { utils.get_current_timestamp() - start_phase } * 1000
  io.println("  ⏱️  Phase duration: " <> int.to_string(phase_duration / 1000) <> "ms")
  
  SimulatorState(..state, users: updated_users)
}

// ============================================================================
// Phase 4: Simulate Activities
// ============================================================================

fn simulate_user_activities(state: SimulatorState) -> SimulatorState {
  let start_phase = utils.get_current_timestamp()
  
  let total_actions = state.config.num_users * state.config.actions_per_user
  io.println("\n  🎭 Simulating " <> int.to_string(total_actions) <> " user actions...")
  
  let final_state = list.range(1, total_actions)
  |> list.fold(state, fn(current_state, _action_num) {
    // Pick a random user
    let user_idx = int.random(list.length(current_state.users))
    
    case get_at(current_state.users, user_idx) {
      Ok(user) -> {
        case user.is_connected {
          True -> {
            // Randomly choose an action (Zipf distribution for realism)
            let params = zipf.with_skewness(6, 1.5)
            let action_type = zipf.select_zipf(params, int.random(1000))
            
            case action_type {
              0 -> create_random_post(current_state, user)
              1 -> create_random_comment(current_state, user)
              2 -> get_user_feed(current_state, user)
              3 -> cast_random_vote(current_state, user)
              4 -> send_random_message(current_state, user)
              5 -> create_random_repost(current_state, user)
              _ -> current_state
            }
          }
          False -> current_state
        }
      }
      Error(_) -> current_state
    }
  })
  
  let phase_duration = { utils.get_current_timestamp() - start_phase } * 1000
  io.println("\n  ⏱️  Phase duration: " <> int.to_string(phase_duration / 1000) <> "ms")
  
  final_state
}

// ============================================================================
// Individual Actions
// ============================================================================

fn create_random_post(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  case list.first(user.subscribed_subreddits) {
    Ok(subreddit_id) -> {
      let post_title = "Interesting topic by " <> user.username
      let post_content = "This is a simulated post with some content. Lorem ipsum dolor sit amet."
      
      // Measure operation time
      let op_start = utils.get_current_timestamp()
      
      core.handle_request(
        state.engine,
        utils.generate_request_id(),
        user.client,
        protocol.CreatePost(user.id, subreddit_id, post_title, post_content, False, option.None),
      )
      
      let op_duration = utils.get_current_timestamp() - op_start
      
      // Record operation with timing
      // FIXED: Convert Int to Float
      metrics_collector.record_operation(
        state.metrics_collector,
        "create_post",
        int.to_float(op_duration * 1000),
      )
      
      io.println("  📝 " <> user.username <> " created post: \"" <> post_title <> "\"")
      
      let new_metrics = simulation_types.SimulationMetrics(
        ..state.metrics,
        posts_created: state.metrics.posts_created + 1,
      )
      
      SimulatorState(..state, metrics: new_metrics)
    }
    Error(_) -> state
  }
}

fn create_random_repost(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  case list.first(user.subscribed_subreddits) {
    Ok(subreddit_id) -> {
      let fake_original_post_id = "post_" <> int.to_string(int.random(100))
      
      // Measure operation time
      let op_start = utils.get_current_timestamp()
      
      core.handle_request(
        state.engine,
        utils.generate_request_id(),
        user.client,
        protocol.CreatePost(user.id, subreddit_id, "Repost", "Reposted content", True, option.Some(fake_original_post_id)),
      )
      
      let op_duration = utils.get_current_timestamp() - op_start
      
      // Record operation with timing
      // FIXED: Convert Int to Float
      metrics_collector.record_operation(
        state.metrics_collector,
        "create_repost",
        int.to_float(op_duration * 1000),
      )
      
      io.println("  🔄 " <> user.username <> " reposted")
      
      case int.random(10) < 7 {
        True -> {
          let new_metrics = simulation_types.SimulationMetrics(
            ..state.metrics,
            reposts_created: state.metrics.reposts_created + 1,
          )
          
          SimulatorState(..state, metrics: new_metrics)
        }
        False -> {
          let new_metrics = simulation_types.SimulationMetrics(
            ..state.metrics,
            posts_created: state.metrics.posts_created + 1,
          )
          
          SimulatorState(..state, metrics: new_metrics)
        }
      }
    }
    Error(_) -> state
  }
}


fn create_random_comment(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  let comment_content = "Great post! Thanks for sharing."
  let fake_post_id = "post_" <> int.to_string(int.random(100))
  
  // Measure operation time
  let op_start = utils.get_current_timestamp()
  
  core.handle_request(
    state.engine,
    utils.generate_request_id(),
    user.client,
    protocol.CreateComment(user.id, fake_post_id, None, comment_content),
  )
  
  let op_duration = utils.get_current_timestamp() - op_start
  
  // Record operation with timing
  // FIXED: Convert Int to Float
  metrics_collector.record_operation(
    state.metrics_collector,
    "create_comment",
    int.to_float(op_duration * 1000),
  )
  
  io.println("  💬 " <> user.username <> " commented: \"" <> comment_content <> "\"")
  
  let new_metrics = simulation_types.SimulationMetrics(
    ..state.metrics,
    comments_created: state.metrics.comments_created + 1,
  )
  
  SimulatorState(..state, metrics: new_metrics)
}

fn get_user_feed(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  // Measure operation time
  let op_start = utils.get_current_timestamp()
  
  core.handle_request(
    state.engine,
    utils.generate_request_id(),
    user.client,
    protocol.GetFeed(user.id, 25),
  )
  
  let op_duration = utils.get_current_timestamp() - op_start
  
  // Record operation with timing
  // FIXED: Convert Int to Float
  metrics_collector.record_operation(
    state.metrics_collector,
    "get_feed",
    int.to_float(op_duration * 1000),
  )
  
  io.println("  📰 " <> user.username <> " viewed their feed")
  
  state
}


fn send_random_message(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  let recipient_idx = int.random(list.length(state.users))
  case get_at(state.users, recipient_idx) {
    Ok(recipient) -> {
      case recipient.id == user.id {
        True -> state
        False -> {
          // Measure operation time
          let op_start = utils.get_current_timestamp()
          
          core.handle_request(
            state.engine,
            utils.generate_request_id(),
            user.client,
            protocol.SendDirectMessage(
              user.id,
              recipient.id,
              "Hey! This is a simulated message.",
            ),
          )
          
          let op_duration = utils.get_current_timestamp() - op_start
          
          // Record operation with timing
          // FIXED: Convert Int to Float
          metrics_collector.record_operation(
            state.metrics_collector,
            "send_direct_message",
            int.to_float(op_duration * 1000),
          )
          
          io.println("  ✉️  " <> user.username <> " sent DM to " <> recipient.username)
          
          let new_metrics = simulation_types.SimulationMetrics(
            ..state.metrics,
            messages_sent: state.metrics.messages_sent + 1,
          )
          
          SimulatorState(..state, metrics: new_metrics)
        }
      }
    }
    Error(_) -> state
  }
}
fn cast_random_vote(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  let vote_type = case int.random(10) < 8 {
    True -> Upvote
    False -> Downvote
  }
  
  let fake_target_id = "post_" <> int.to_string(int.random(100))
  
  // Measure operation time
  let op_start = utils.get_current_timestamp()
  
  core.handle_request(
    state.engine,
    utils.generate_request_id(),
    user.client,
    protocol.VotePost(user.id, fake_target_id, vote_type),
  )
  
  let op_duration = utils.get_current_timestamp() - op_start
  
  // Record operation with timing
  // FIXED: Convert Int to Float
  metrics_collector.record_operation(
    state.metrics_collector,
    "vote_post",
    int.to_float(op_duration * 1000),
  )
  
  let vote_emoji = case vote_type {
    Upvote -> "⬆️"
    Downvote -> "⬇️"
  }
  io.println("  " <> vote_emoji <> " " <> user.username <> " voted on a post")
  
  let new_metrics = simulation_types.SimulationMetrics(
    ..state.metrics,
    votes_cast: state.metrics.votes_cast + 1,
  )
  
  SimulatorState(..state, metrics: new_metrics)
}
// ============================================================================
// User Client Actor
// ============================================================================

// FIXED: Use actor.start directly
fn create_user_client() -> Result(Subject(EngineResponse), actor.StartError) {
  actor.start(Nil, fn(_response: EngineResponse, _state) {
    actor.continue(Nil)
  })
}

// ============================================================================
// Helper Functions
// ============================================================================

fn handle_user_action(
  state: SimulatorState,
  user_id: Id,
  action: UserAction,
) -> SimulatorState {
  state
}

fn get_at(list: List(a), index: Int) -> Result(a, Nil) {
  case index < 0 {
    True -> Error(Nil)
    False -> {
      list
      |> list.drop(index)
      |> list.first()
    }
  }
}

fn print_metrics(metrics: SimulationMetrics) -> Nil {
  io.println("\n📊 Current Metrics:")
  io.println("  Users: " <> int.to_string(metrics.users_registered))
  io.println("  Subreddits: " <> int.to_string(metrics.subreddits_created))
  io.println("  Posts: " <> int.to_string(metrics.posts_created))
  io.println("  Reposts: " <> int.to_string(metrics.reposts_created))
  io.println("  Comments: " <> int.to_string(metrics.comments_created))
  io.println("  Votes: " <> int.to_string(metrics.votes_cast))
  io.println("  Messages: " <> int.to_string(metrics.messages_sent))
  io.println("  Errors: " <> int.to_string(metrics.errors))
}

fn print_final_metrics(metrics: SimulationMetrics) -> Nil {
  io.println("\n========== Final Simulation Results ==========")
  print_metrics(metrics)
  io.println("==============================================")
}

fn print_status(state: SimulatorState) -> Nil {
  io.println("\n📈 Simulator Status:")
  io.println("  Active Users: " <> int.to_string(list.length(state.users)))
  io.println("  Subreddits: " <> int.to_string(list.length(state.subreddits)))
  print_metrics(state.metrics)
}

// ============================================================================
// Report Export
// ============================================================================

// FIXED: Use get_snapshot instead of export_snapshot
fn export_report_to_file(state: SimulatorState) -> Nil {
  io.println("\n📊 Generating performance report...")
  
  // Create a client actor to receive the snapshot
  let assert Ok(snapshot_client) = actor.start(Nil, fn(snapshot: metrics_collector.MetricsSnapshot, _state) {
    // Generate and write report
    let report = report_generator.generate_report(
      snapshot,
      state.metrics,
      state.config,
    )
    
    case file_writer.write_timestamped_report(report) {
      Ok(_) -> {
        io.println("✅ Report successfully saved to PERFORMANCE_REPORT.md")
        io.println("   ✨ Includes full latency statistics!")
      }
      Error(_) -> io.println("❌ Failed to save report")
    }
    
    actor.continue(Nil)
  })
  
  // Request snapshot from metrics collector
  metrics_collector.get_snapshot(state.metrics_collector, snapshot_client)
  
  // Give it time to process
  process.sleep(100)
}

fn create_operations_dict(metrics: SimulationMetrics) -> Dict(String, Int) {
  dict.new()
  |> dict.insert("register_user", metrics.users_registered)
  |> dict.insert("create_subreddit", metrics.subreddits_created)
  |> dict.insert("create_post", metrics.posts_created)
  |> dict.insert("create_repost", metrics.reposts_created)
  |> dict.insert("create_comment", metrics.comments_created)
  |> dict.insert("vote_post", metrics.votes_cast)
  |> dict.insert("send_direct_message", metrics.messages_sent)
}
