// User Actor - Simulates individual user behavior
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import shared/protocol.{type ClientRequest, type EngineResponse}
import shared/types.{type Id, Upvote, Downvote}
import engine/core

// ============================================================================
// User Actor State
// ============================================================================

pub type UserActorState {
  UserActorState(
    username: String,
    engine: Subject(core.EngineMessage),
    subscribed_subreddits: List(Id),
    posts_created: Int,
    comments_created: Int,
    votes_cast: Int,
    is_connected: Bool,
    action_count: Int,
  )
}

// ============================================================================
// User Actor Messages
// ============================================================================

pub type UserActorMessage {
  PerformAction(action: UserAction)
  Connect
  Disconnect
  GetStats
  Shutdown
}

pub type UserAction {
  Register
  Login
  CreatePost(subreddit_id: Id, title: String, content: String)
  CreateComment(post_id: Id, content: String)
  VotePost(post_id: Id, upvote: Bool)
  JoinSubreddit(subreddit_id: Id)
  LeaveSubreddit(subreddit_id: Id)
  ViewFeed
  SendMessage(to_user: String, content: String)
}

// ============================================================================
// API
// ============================================================================

pub fn start(
  username: String,
  engine: Subject(core.EngineMessage),
) -> Result(Subject(UserActorMessage), actor.StartError) {
  let init_state = UserActorState(
    username: username,
    engine: engine,
    subscribed_subreddits: [],
    posts_created: 0,
    comments_created: 0,
    votes_cast: 0,
    is_connected: False,
    action_count: 0,
  )
  
  // FIXED: Use actor.start directly
  actor.start(init_state, handle_message)
}

pub fn perform_action(
  user: Subject(UserActorMessage),
  action: UserAction,
) -> Nil {
  process.send(user, PerformAction(action))
}

pub fn connect(user: Subject(UserActorMessage)) -> Nil {
  process.send(user, Connect)
}

pub fn disconnect(user: Subject(UserActorMessage)) -> Nil {
  process.send(user, Disconnect)
}

pub fn shutdown(user: Subject(UserActorMessage)) -> Nil {
  process.send(user, Shutdown)
}

// ============================================================================
// Implementation
// ============================================================================

// FIXED: Changed parameter order - message first, then state
// FIXED: Changed return type parameters
fn handle_message(
  message: UserActorMessage,
  state: UserActorState,
) -> actor.Next(UserActorMessage, UserActorState) {
  case message {
    PerformAction(action) -> {
      let new_state = execute_action(state, action)
      actor.continue(new_state)
    }

    Connect -> {
      // For simulation, we don't track user_id separately
      // The username serves as identifier
      let client = process.new_subject()
      let user_id = "user_" <> state.username
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.Connect(user_id),
      )
      actor.continue(UserActorState(..state, is_connected: True))
    }

    Disconnect -> {
      let client = process.new_subject()
      let user_id = "user_" <> state.username
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.Disconnect(user_id),
      )
      actor.continue(UserActorState(..state, is_connected: False))
    }

    GetStats -> {
      // Log or return stats
      actor.continue(state)
    }

    Shutdown -> {
      // FIXED: Use actor.Stop instead of actor.stop()
      actor.Stop(process.Normal)
    }
  }
}

fn execute_action(state: UserActorState, action: UserAction) -> UserActorState {
  let client = process.new_subject()
  let user_id = "user_" <> state.username

  case action {
    Register -> {
      let password = "password123" // Simulated password
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.RegisterUser(state.username, password),
      )
      
      UserActorState(..state, action_count: state.action_count + 1)
    }

    Login -> {
      let password = "password123"
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.LoginUser(state.username, password),
      )
      UserActorState(..state, action_count: state.action_count + 1)
    }

    CreatePost(subreddit_id, title, content) -> {
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.CreatePost(
          user_id,
          subreddit_id,
          title,
          content,
          False,
          None,
        ),
      )
      UserActorState(
        ..state,
        posts_created: state.posts_created + 1,
        action_count: state.action_count + 1,
      )
    }

    CreateComment(post_id, content) -> {
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.CreateComment(user_id, post_id, None, content),
      )
      UserActorState(
        ..state,
        comments_created: state.comments_created + 1,
        action_count: state.action_count + 1,
      )
    }

    VotePost(post_id, upvote) -> {
      let vote_type = case upvote {
        True -> Upvote
        False -> Downvote
      }
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.VotePost(user_id, post_id, vote_type),
      )
      UserActorState(
        ..state,
        votes_cast: state.votes_cast + 1,
        action_count: state.action_count + 1,
      )
    }

    JoinSubreddit(subreddit_id) -> {
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.JoinSubreddit(user_id, subreddit_id),
      )
      
      let new_subs = case list.contains(state.subscribed_subreddits, subreddit_id) {
        True -> state.subscribed_subreddits
        False -> [subreddit_id, ..state.subscribed_subreddits]
      }
      
      UserActorState(
        ..state,
        subscribed_subreddits: new_subs,
        action_count: state.action_count + 1,
      )
    }

    LeaveSubreddit(subreddit_id) -> {
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.LeaveSubreddit(user_id, subreddit_id),
      )
      
      let new_subs = list.filter(state.subscribed_subreddits, fn(id) {
        id != subreddit_id
      })
      
      UserActorState(
        ..state,
        subscribed_subreddits: new_subs,
        action_count: state.action_count + 1,
      )
    }

    ViewFeed -> {
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.GetFeed(user_id, 25),
      )
      UserActorState(..state, action_count: state.action_count + 1)
    }

    SendMessage(to_user, content) -> {
      core.handle_request(
        state.engine,
        generate_request_id(),
        client,
        protocol.SendDirectMessage(user_id, "user_" <> to_user, content),
      )
      UserActorState(..state, action_count: state.action_count + 1)
    }
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn generate_request_id() -> String {
  let random = int.random(1_000_000)
  "req_" <> int.to_string(random)
}

/// Generate random content for posts
pub fn generate_post_content(post_num: Int) -> #(String, String) {
  let title = "Post #" <> int.to_string(post_num) <> " - Simulated Content"
  let content =
    "This is simulated post content for testing purposes. Post number: "
    <> int.to_string(post_num)
  #(title, content)
}

/// Generate random comment
pub fn generate_comment_content(comment_num: Int) -> String {
  "Comment #" <> int.to_string(comment_num) <> " - Simulated comment text"
}
