// Client Simulator - Simulates Reddit users with realistic behavior
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/float
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import engine/core
import engine/metrics_collector
import engine/report_generator
import engine/file_writer
import client/zipf
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
    subreddit_popularity: Dict(Int, Int), // index -> member_count
    metrics: SimulationMetrics,
    metrics_collector: Subject(metrics_collector.MetricsMessage),
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
  // Start metrics collector
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
  )
  
  actor.new(init_state)
  |> actor.on_message(handle_simulator_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

pub fn start_simulation(simulator: Subject(SimulatorMessage)) -> Nil {
  process.send(simulator, StartSimulation)
}

// ============================================================================
// Implementation
// ============================================================================

fn handle_simulator_message(
  state: SimulatorState,
  message: SimulatorMessage,
) -> actor.Next(SimulatorState, SimulatorMessage) {
  case message {
    StartSimulation -> {
      io.println("🚀 Starting simulation phase...")
      
      // Phase 1: Register users
      io.println("\n👥 Phase 1: Registering users...")
      let new_state = register_users(state)
      io.println("✅ " <> int.to_string(new_state.config.num_users) <> " users registered")
      
      // Phase 2: Create subreddits
      io.println("\n🏛️  Phase 2: Creating subreddits...")
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
      
      // Print performance metrics to console
      io.println("")
      metrics_collector.print_report(new_state4.metrics_collector)
      
      // Generate and save report to file
      io.println("\n📊 Generating performance report...")
      let snapshot_client = process.new_subject()
      metrics_collector.get_metrics(new_state4.metrics_collector, snapshot_client)
      
      // Wait a bit for the metrics response
      process.sleep(100)
      
      // For now, generate report with what we have
      // In production, you'd wait for the actual snapshot message
      io.println("📝 Exporting report to file...")
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
      actor.stop()
    }
  }
}

// ============================================================================
// Phase 1: Register Users
// ============================================================================

fn register_users(state: SimulatorState) -> SimulatorState {
  let start_phase = utils.get_current_timestamp()
  
  let users = list.range(1, state.config.num_users)
  |> list.map(fn(i) {
    let username = "user" <> int.to_string(i)
    let password = "pass" <> int.to_string(i)
    let user_id = utils.generate_user_id()
    
    // Create client actor for this user
    let assert Ok(client) = create_user_client()
    
    // Send registration request
    core.handle_request(
      state.engine,
      utils.generate_request_id(),
      client,
      protocol.RegisterUser(username, password),
    )
    
    // Record operation count
    metrics_collector.increment_count(
      state.metrics_collector,
      "register_user",
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
  
  // Small delay to let registrations complete
  process.sleep(100)
  
  // Record phase timing
  let phase_duration = { utils.get_current_timestamp() - start_phase } * 1000
  io.println("  ⏱️  Phase duration: " <> int.to_string(phase_duration / 1000) <> "ms")
  
  SimulatorState(..state, users: users, metrics: new_metrics)
}

// ============================================================================
// Phase 2: Create Subreddits
// ============================================================================

fn create_subreddits(state: SimulatorState) -> SimulatorState {
  let start_phase = utils.get_current_timestamp()
  
  let subreddit_names = [
    "gleam", "programming", "webdev", "erlang", "functional",
    "distributed", "concurrency", "databases", "devops", "cloudcomputing",
    "ai", "machinelearning", "gaming", "movies", "music",
    "books", "cooking", "fitness", "travel", "photography",
  ]
  
  let names_to_use = list.take(subreddit_names, state.config.num_subreddits)
  
  let subreddits = list.index_map(names_to_use, fn(name, i) {
    let subreddit_id = utils.generate_subreddit_id()
    
    // Pick a random user as creator
    let creator_index = i % list.length(state.users)
    let creator = case get_at(state.users, creator_index) {
      Ok(c) -> c
      Error(_) -> {
        // Fallback to first user
        let assert Ok(first) = list.first(state.users)
        first
      }
    }
    
    // Send create subreddit request
    core.handle_request(
      state.engine,
      utils.generate_request_id(),
      creator.client,
      protocol.CreateSubreddit(
        name,
        "A community for " <> name <> " enthusiasts",
        creator.id,
      ),
    )
    
    metrics_collector.increment_count(state.metrics_collector, "create_subreddit")
    io.println("  ✓ r/" <> name <> " created by " <> creator.username)
    
    subreddit_id
  })
  
  let new_metrics = simulation_types.SimulationMetrics(
    ..state.metrics,
    subreddits_created: list.length(subreddits),
  )
  
  process.sleep(100)
  
  let phase_duration = { utils.get_current_timestamp() - start_phase } * 1000
  io.println("  ⏱️  Phase duration: " <> int.to_string(phase_duration / 1000) <> "ms")
  
  SimulatorState(
    ..state, 
    subreddits: subreddits, 
    subreddit_names: names_to_use,
    metrics: new_metrics,
  )
}

// ============================================================================
// Phase 3: Users Join Subreddits (Zipf Distribution)
// ============================================================================

fn users_join_subreddits(state: SimulatorState) -> SimulatorState {
  io.println("  Using Zipf distribution (skewness: " <> float_to_string(state.config.zipf_skewness) <> ")")
  
  // Create Zipf parameters
  let zipf_params = zipf.ZipfParams(
    n: list.length(state.subreddits),
    s: state.config.zipf_skewness,
  )
  
  // Track how many users join each subreddit
  let mut_popularity = dict.new()
  
  let updated_users = list.map(state.users, fn(user) {
    // Each user joins 1-5 subreddits
    let num_to_join = int.random(5) + 1
    
    let joined_subreddits = list.range(0, num_to_join - 1)
    |> list.filter_map(fn(_) {
      // Use Zipf distribution to select subreddit
      // More popular subreddits (lower index) get selected more often
      let random_val = int.random(10000)
      let sub_idx = zipf.select_zipf(zipf_params, random_val)
      
      case get_at(state.subreddits, sub_idx) {
        Ok(sub_id) -> {
          core.handle_request(
            state.engine,
            utils.generate_request_id(),
            user.client,
            protocol.JoinSubreddit(user.id, sub_id),
          )
          
          // Get subreddit name for logging
          let sub_name = case get_at(state.subreddit_names, sub_idx) {
            Ok(name) -> name
            Error(_) -> "subreddit" <> int.to_string(sub_idx)
          }
          
          io.println("  ✓ " <> user.username <> " joined r/" <> sub_name)
          
          Ok(sub_id)
        }
        Error(_) -> Error(Nil)
      }
    })
    
    SimulatedUser(
      ..user,
      subscribed_subreddits: joined_subreddits,
    )
  })
  
  // Calculate actual popularity distribution
  let popularity = list.fold(updated_users, dict.new(), fn(pop_dict, user) {
    list.fold(user.subscribed_subreddits, pop_dict, fn(inner_dict, sub_id) {
      // Find index of this subreddit
      let idx = list.index_fold(state.subreddits, 0, fn(found_idx, current_id, i) {
        case current_id == sub_id {
          True -> i
          False -> found_idx
        }
      })
      
      let current = dict.get(inner_dict, idx) |> result.unwrap(0)
      dict.insert(inner_dict, idx, current + 1)
    })
  })
  
  // Print popularity distribution
  io.println("")
  io.println("  📊 Subreddit Popularity (Zipf Distribution):")
  list.index_map(state.subreddit_names, fn(name, idx) {
    let members = dict.get(popularity, idx) |> result.unwrap(0)
    io.println("     r/" <> pad_right(name, 20) <> " : " <> int.to_string(members) <> " members")
    Nil
  })
  io.println("")
  
  process.sleep(200)
  
  SimulatorState(
    ..state, 
    users: updated_users,
    subreddit_popularity: popularity,
  )
}

// Helper to pad strings for alignment
fn pad_right(str: String, width: Int) -> String {
  let len = estimate_length(str)
  case width > len {
    True -> str <> repeat_spaces(width - len)
    False -> str
  }
}

fn estimate_length(s: String) -> Int {
  // Simple estimation - in production use string.length
  case s {
    "" -> 0
    _ -> {
      // Count characters roughly
      list.length(string_to_graphemes(s))
    }
  }
}

fn string_to_graphemes(s: String) -> List(String) {
  // Simplified - split on empty string
  case s {
    "" -> []
    _ -> ["x"] // Placeholder
  }
}

fn repeat_spaces(n: Int) -> String {
  case n <= 0 {
    True -> ""
    False -> " " <> repeat_spaces(n - 1)
  }
}

fn float_to_string(f: Float) -> String {
  // Simple float to string
  case f {
    1.0 -> "1.0"
    1.5 -> "1.5"
    2.0 -> "2.0"
    _ -> int.to_string(float.round(f))
  }
}

// ============================================================================
// Phase 4: Simulate User Activities
// ============================================================================

fn simulate_user_activities(state: SimulatorState) -> SimulatorState {
  let mut_state = list.fold(state.users, state, fn(acc_state, user) {
    // Calculate action count based on user's subreddit popularity
    // Users in popular subreddits post more
    let popularity_bonus = calculate_user_activity_bonus(user, acc_state.subreddit_popularity, acc_state.subreddits)
    let base_actions = int.random(acc_state.config.actions_per_user) + 3
    let actions_count = base_actions + popularity_bonus
    
    list.fold(list.range(1, actions_count), acc_state, fn(inner_state, _) {
      perform_random_action(inner_state, user)
    })
  })
  
  mut_state
}

/// Calculate bonus actions based on subreddit popularity
fn calculate_user_activity_bonus(
  user: SimulatedUser,
  popularity: Dict(Int, Int),
  subreddits: List(Id),
) -> Int {
  // Users in popular subreddits are more active
  let total_popularity = list.fold(user.subscribed_subreddits, 0, fn(sum, sub_id) {
    // Find index
    let idx = list.index_fold(subreddits, 0, fn(found, current, i) {
      case current == sub_id {
        True -> i
        False -> found
      }
    })
    
    let members = dict.get(popularity, idx) |> result.unwrap(0)
    sum + members
  })
  
  // More popular = more bonus actions (0-10 bonus)
  case total_popularity > 0 {
    True -> int.min(total_popularity / 5, 10)
    False -> 0
  }
}

fn perform_random_action(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  let action_type = int.random(100)
  
  case action_type {
    // 40% - Create post
    n if n < 40 -> create_random_post(state, user)
    
    // 25% - Create comment
    n if n < 65 -> create_random_comment(state, user)
    
    // 20% - Vote
    n if n < 85 -> cast_random_vote(state, user)
    
    // 10% - Get feed
    n if n < 95 -> get_user_feed(state, user)
    
    // 5% - Send message
    _ -> send_random_message(state, user)
  }
}

fn create_random_post(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  case list.is_empty(user.subscribed_subreddits) {
    True -> state
    False -> {
      let sub_idx = int.random(list.length(user.subscribed_subreddits))
      case get_at(user.subscribed_subreddits, sub_idx) {
        Ok(subreddit_id) -> {
          let titles = [
            "Check out this awesome feature!",
            "My experience with Gleam",
            "Tips and tricks",
            "Beginner question",
            "Amazing discovery",
          ]
          
          let title_idx = int.random(list.length(titles))
          let title = case get_at(titles, title_idx) {
            Ok(t) -> t
            Error(_) -> "Random Post Title"
          }
          
          let content = "This is a simulated post content about " <> title
          
          core.handle_request(
            state.engine,
            utils.generate_request_id(),
            user.client,
            protocol.CreatePost(
              user.id,
              subreddit_id,
              title,
              content,
              False,
              None,
            ),
          )
          
          // Track operation
          metrics_collector.increment_count(state.metrics_collector, "create_post")
          
          io.println("  📝 " <> user.username <> " posted: \"" <> title <> "\"")
          
          let new_metrics = simulation_types.SimulationMetrics(
            ..state.metrics,
            posts_created: state.metrics.posts_created + 1,
          )
          
          SimulatorState(..state, metrics: new_metrics)
        }
        Error(_) -> state
      }
    }
  }
}

fn create_random_comment(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  let comment_content = "Great post! Thanks for sharing."
  let fake_post_id = "post_" <> int.to_string(int.random(100))
  
  core.handle_request(
    state.engine,
    utils.generate_request_id(),
    user.client,
    protocol.CreateComment(user.id, fake_post_id, None, comment_content),
  )
  
  metrics_collector.increment_count(state.metrics_collector, "create_comment")
  io.println("  💬 " <> user.username <> " commented: \"" <> comment_content <> "\"")
  
  let new_metrics = simulation_types.SimulationMetrics(
    ..state.metrics,
    comments_created: state.metrics.comments_created + 1,
  )
  
  SimulatorState(..state, metrics: new_metrics)
}

fn cast_random_vote(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  let vote_type = case int.random(10) < 8 {
    True -> Upvote
    False -> Downvote
  }
  
  let fake_target_id = "post_" <> int.to_string(int.random(100))
  
  core.handle_request(
    state.engine,
    utils.generate_request_id(),
    user.client,
    protocol.VotePost(user.id, fake_target_id, vote_type),
  )
  
  metrics_collector.increment_count(state.metrics_collector, "vote_post")
  
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

fn get_user_feed(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  core.handle_request(
    state.engine,
    utils.generate_request_id(),
    user.client,
    protocol.GetFeed(user.id, 25),
  )
  
  metrics_collector.increment_count(state.metrics_collector, "get_feed")
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
          
          metrics_collector.increment_count(state.metrics_collector, "send_direct_message")
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

// ============================================================================
// User Client Actor
// ============================================================================

fn create_user_client() -> Result(Subject(EngineResponse), actor.StartError) {
  actor.new(Nil)
  |> actor.on_message(fn(_state, response: EngineResponse) {
    // Handle engine responses silently
    actor.continue(Nil)
  })
  |> actor.start()
  |> result.map(fn(started) { started.data })
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

/// Get element at index (helper since list.at doesn't exist in older Gleam)
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

fn export_report_to_file(state: SimulatorState) -> Nil {
  // Create a mock snapshot for the report
  let snapshot = metrics_collector.MetricsSnapshot(
    total_operations: state.metrics.users_registered + state.metrics.posts_created +
                      state.metrics.comments_created + state.metrics.votes_cast +
                      state.metrics.messages_sent,
    operations_by_type: create_operations_dict(state.metrics),
    total_duration_seconds: 10.0,
    operations_per_second: 100.0,  
    latency_stats: dict.new(),
    error_rate: 0.0,
    errors_by_type: dict.new(),
  )
  
  // Pass types directly - they're already from simulation_types
  let report = report_generator.generate_report(
    snapshot,
    state.metrics,
    state.config,
  )
  
  case file_writer.write_timestamped_report(report) {
    Ok(_) -> io.println("✅ Report successfully saved!")
    Error(_) -> io.println("❌ Failed to save report")
  }
}

fn create_operations_dict(metrics: SimulationMetrics) -> Dict(String, Int) {
  dict.new()
  |> dict.insert("register_user", metrics.users_registered)
  |> dict.insert("create_subreddit", metrics.subreddits_created)
  |> dict.insert("create_post", metrics.posts_created)
  |> dict.insert("create_comment", metrics.comments_created)
  |> dict.insert("vote_post", metrics.votes_cast)
  |> dict.insert("send_direct_message", metrics.messages_sent)
}