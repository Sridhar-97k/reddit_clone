// Client Simulator - Simulates Reddit users with realistic behavior
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import engine/core
import shared/protocol.{type ClientRequest, type EngineResponse}
import shared/types.{type Id, type VoteType, Downvote, Upvote}
import shared/utils

// ============================================================================
// Configuration
// ============================================================================

pub type SimulationConfig {
  SimulationConfig(
    num_users: Int,
    num_subreddits: Int,
    zipf_skewness: Float,
    simulation_duration_seconds: Int,
    actions_per_user: Int,
    connection_cycle_seconds: Int,
  )
}

pub fn default_config() -> SimulationConfig {
  SimulationConfig(
    num_users: 50,
    num_subreddits: 10,
    zipf_skewness: 1.0,
    simulation_duration_seconds: 60,
    actions_per_user: 10,
    connection_cycle_seconds: 15,
  )
}

pub fn large_scale_config() -> SimulationConfig {
  SimulationConfig(
    num_users: 1000,
    num_subreddits: 50,
    zipf_skewness: 1.5,
    simulation_duration_seconds: 300,
    actions_per_user: 20,
    connection_cycle_seconds: 30,
  )
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
    metrics: SimulationMetrics,
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

pub type SimulationMetrics {
  SimulationMetrics(
    users_registered: Int,
    subreddits_created: Int,
    posts_created: Int,
    comments_created: Int,
    votes_cast: Int,
    messages_sent: Int,
    errors: Int,
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

// pub fn start(
//   engine: Subject(core.EngineMessage),
//   config: SimulationConfig,
// ) -> Result(Subject(SimulatorMessage), actor.StartError) {
//   let init_state = SimulatorState(
//     engine: engine,
//     config: config,
//     users: [],
//     subreddits: [],
//     metrics: init_metrics(),
//   )
  
//   actor.start(init_state, handle_simulator_message)
// }

pub fn start(
  engine: Subject(core.EngineMessage),
  config: SimulationConfig,
) -> Result(Subject(SimulatorMessage), actor.StartError) {
  let init_state = SimulatorState(
    engine: engine,
    config: config,
    users: [],
    subreddits: [],
    metrics: init_metrics(),
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

fn init_metrics() -> SimulationMetrics {
  SimulationMetrics(
    users_registered: 0,
    subreddits_created: 0,
    posts_created: 0,
    comments_created: 0,
    votes_cast: 0,
    messages_sent: 0,
    errors: 0,
  )
}

fn handle_simulator_message(
  message: SimulatorMessage,
  state: SimulatorState,
) -> actor.Next(SimulatorState, SimulatorMessage) {
  case message {
    StartSimulation -> {
      io.println("🚀 Starting simulation phase...")
      
      // Phase 1: Register users
      io.println("\n📝 Phase 1: Registering users...")
      let new_state = register_users(state)
      io.println("✅ " <> int.to_string(new_state.config.num_users) <> " users registered")
      
      // Phase 2: Create subreddits
      io.println("\n🏘️  Phase 2: Creating subreddits...")
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
      
      // Print final metrics
      print_final_metrics(new_state4.metrics)
      
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
      actor.Stop(process.Normal)
    }
  }
}

// ============================================================================
// Phase 1: Register Users
// ============================================================================

fn register_users(state: SimulatorState) -> SimulatorState {
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
    
    SimulatedUser(
      id: user_id,
      username: username,
      password: password,
      client: client,
      subscribed_subreddits: [],
      is_connected: True,
    )
  })
  
  let new_metrics = SimulationMetrics(
    ..state.metrics,
    users_registered: state.config.num_users,
  )
  
  // Small delay to let registrations complete
  process.sleep(100)
  
  SimulatorState(..state, users: users, metrics: new_metrics)
}

// ============================================================================
// Phase 2: Create Subreddits
// ============================================================================

fn create_subreddits(state: SimulatorState) -> SimulatorState {
  let subreddit_names = [
    "gleam", "programming", "webdev", "erlang", "functional",
    "distributed", "concurrency", "databases", "devops", "cloudcomputing",
    "ai", "machinelearning", "gaming", "movies", "music",
    "books", "cooking", "fitness", "travel", "photography",
  ]
  
  let subreddits = list.take(subreddit_names, state.config.num_subreddits)
  |> list.index_map(fn(name, i) {
    let subreddit_id = utils.generate_subreddit_id()
    
    // Pick a random user as creator
    let creator_index = i % list.length(state.users)
    let assert Ok(creator) = list.at(state.users, creator_index)
    
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
    
    subreddit_id
  })
  
  let new_metrics = SimulationMetrics(
    ..state.metrics,
    subreddits_created: list.length(subreddits),
  )
  
  process.sleep(100)
  
  SimulatorState(..state, subreddits: subreddits, metrics: new_metrics)
}

// ============================================================================
// Phase 3: Users Join Subreddits (Zipf Distribution)
// ============================================================================

fn users_join_subreddits(state: SimulatorState) -> SimulatorState {
  let updated_users = list.map(state.users, fn(user) {
    // Each user joins 1-5 random subreddits
    let num_to_join = int.random(5) + 1
    let subreddit_indices = list.range(0, num_to_join - 1)
    |> list.map(fn(_) { 
      int.random(list.length(state.subreddits))
    })
    
    let joined_subreddits = list.filter_map(subreddit_indices, fn(idx) {
      case list.at(state.subreddits, idx) {
        Ok(sub_id) -> {
          core.handle_request(
            state.engine,
            utils.generate_request_id(),
            user.client,
            protocol.JoinSubreddit(user.id, sub_id),
          )
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
  
  process.sleep(200)
  
  SimulatorState(..state, users: updated_users)
}

// ============================================================================
// Phase 4: Simulate User Activities
// ============================================================================

fn simulate_user_activities(state: SimulatorState) -> SimulatorState {
  let mut_state = list.fold(state.users, state, fn(acc_state, user) {
    // Each user performs random actions
    let actions_count = int.random(acc_state.config.actions_per_user) + 3
    
    list.fold(list.range(1, actions_count), acc_state, fn(inner_state, _) {
      perform_random_action(inner_state, user)
    })
  })
  
  mut_state
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
      case list.at(user.subscribed_subreddits, sub_idx) {
        Ok(subreddit_id) -> {
          let titles = [
            "Check out this awesome feature!",
            "My experience with Gleam",
            "Tips and tricks",
            "Beginner question",
            "Amazing discovery",
          ]
          
          let title_idx = int.random(list.length(titles))
          let assert Ok(title) = list.at(titles, title_idx)
          
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
          
          let new_metrics = SimulationMetrics(
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
  // For simplicity, comment on a random post
  // In real scenario, we'd track post IDs
  let comment_content = "Great post! Thanks for sharing."
  
  // Generate a fake post ID for demo
  let fake_post_id = "post_" <> int.to_string(int.random(100))
  
  core.handle_request(
    state.engine,
    utils.generate_request_id(),
    user.client,
    protocol.CreateComment(user.id, fake_post_id, None, comment_content),
  )
  
  let new_metrics = SimulationMetrics(
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
  
  let new_metrics = SimulationMetrics(
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
  
  state
}

fn send_random_message(state: SimulatorState, user: SimulatedUser) -> SimulatorState {
  let recipient_idx = int.random(list.length(state.users))
  case list.at(state.users, recipient_idx) {
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
          
          let new_metrics = SimulationMetrics(
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

// fn create_user_client() -> Result(Subject(EngineResponse), actor.StartError) {
//   actor.start(Nil, fn(response, _state) {
//     // Handle engine responses
//     case response {
//       protocol.UserRegistered(_, _) -> actor.continue(Nil)
//       protocol.Error(_) -> actor.continue(Nil)
//       _ -> actor.continue(Nil)
//     }
//   })
// }



fn create_user_client() -> Result(Subject(EngineResponse), actor.StartError) {
  actor.new(Nil)
  |> actor.on_message(fn(response, _state) {
    // Handle engine responses
    case response {
      protocol.UserRegistered(_, _) -> actor.continue(Nil)
      protocol.Error(_) -> actor.continue(Nil)
      _ -> actor.continue(Nil)
    }
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
  io.println("\n" <> "="  <> " Final Simulation Results " <> "=")
  print_metrics(metrics)
  io.println("=" <> "=" <> "=")
}

fn print_status(state: SimulatorState) -> Nil {
  io.println("\n📈 Simulator Status:")
  io.println("  Active Users: " <> int.to_string(list.length(state.users)))
  io.println("  Subreddits: " <> int.to_string(list.length(state.subreddits)))
  print_metrics(state.metrics)
}