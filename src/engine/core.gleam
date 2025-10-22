// Main Reddit Engine - Central coordinator
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/dict.{type Dict}
import gleam/result
import shared/protocol.{
  type ClientRequest, type EngineResponse, type Message,
}
import shared/types.{type Id}
import engine/user_registry
import engine/subreddit_manager
import engine/post_storage
import engine/vote_tracker

// ============================================================================
// Engine State
// ============================================================================

pub type EngineState {
  EngineState(
    user_registry: Subject(user_registry.UserRegistryMessage),
    subreddit_manager: Subject(subreddit_manager.SubredditMessage),
    post_storage: Subject(post_storage.PostStorageMessage),
    vote_tracker: Subject(vote_tracker.VoteTrackerMessage),
    active_connections: Dict(Id, Subject(EngineResponse)),
  )
}

// ============================================================================
// Engine Messages
// ============================================================================

pub type EngineMessage {
  HandleRequest(
    request_id: String,
    client: Subject(EngineResponse),
    request: ClientRequest,
  )
  RegisterConnection(user_id: Id, client: Subject(EngineResponse))
  UnregisterConnection(user_id: Id)
  Shutdown
}

// ============================================================================
// Engine API
// ============================================================================

/// Start the Reddit engine
pub fn start() -> Result(Subject(EngineMessage), actor.StartError) {
  actor.start(init_state, handle_message)
}

/// Send a request to the engine
pub fn handle_request(
  engine: Subject(EngineMessage),
  request_id: String,
  client: Subject(EngineResponse),
  request: ClientRequest,
) -> Nil {
  process.send(engine, HandleRequest(request_id, client, request))
}

/// Register a client connection
pub fn register_connection(
  engine: Subject(EngineMessage),
  user_id: Id,
  client: Subject(EngineResponse),
) -> Nil {
  process.send(engine, RegisterConnection(user_id, client))
}

/// Unregister a client connection
pub fn unregister_connection(engine: Subject(EngineMessage), user_id: Id) -> Nil {
  process.send(engine, UnregisterConnection(user_id))
}

/// Shutdown the engine
pub fn shutdown(engine: Subject(EngineMessage)) -> Nil {
  process.send(engine, Shutdown)
}

// ============================================================================
// Internal Implementation
// ============================================================================

fn init_state() -> EngineState {
  // Start all subsystem actors
  let assert Ok(user_reg) = user_registry.start()
  let assert Ok(subreddit_mgr) = subreddit_manager.start()
  let assert Ok(post_store) = post_storage.start()
  let assert Ok(vote_track) = vote_tracker.start()

  EngineState(
    user_registry: user_reg,
    subreddit_manager: subreddit_mgr,
    post_storage: post_store,
    vote_tracker: vote_track,
    active_connections: dict.new(),
  )
}

fn handle_message(
  message: EngineMessage,
  state: EngineState,
) -> actor.Next(EngineState, EngineMessage) {
  case message {
    HandleRequest(request_id, client, request) -> {
      handle_client_request(state, request_id, client, request)
      actor.continue(state)
    }

    RegisterConnection(user_id, client) -> {
      let new_connections = dict.insert(state.active_connections, user_id, client)
      let new_state =
        EngineState(..state, active_connections: new_connections)
      
      // Send connection confirmation
      process.send(client, protocol.Connected(user_id, get_timestamp()))
      
      actor.continue(new_state)
    }

    UnregisterConnection(user_id) -> {
      let new_connections = dict.delete(state.active_connections, user_id)
      let new_state =
        EngineState(..state, active_connections: new_connections)
      actor.continue(new_state)
    }

    Shutdown -> {
      actor.Stop(process.Normal)
    }
  }
}

fn handle_client_request(
  state: EngineState,
  request_id: String,
  client: Subject(EngineResponse),
  request: ClientRequest,
) -> Nil {
  case request {
    // User Operations
    protocol.RegisterUser(username, password) -> {
      user_registry.register_user(
        state.user_registry,
        client,
        username,
        password,
      )
    }

    protocol.LoginUser(username, password) -> {
      user_registry.login_user(state.user_registry, client, username, password)
    }

    protocol.GetUserProfile(user_id) -> {
      user_registry.get_user_profile(state.user_registry, client, user_id)
    }

    // Subreddit Operations
    protocol.CreateSubreddit(name, description, creator_id) -> {
      subreddit_manager.create_subreddit(
        state.subreddit_manager,
        client,
        name,
        description,
        creator_id,
      )
    }

    protocol.JoinSubreddit(user_id, subreddit_id) -> {
      subreddit_manager.join_subreddit(
        state.subreddit_manager,
        client,
        user_id,
        subreddit_id,
      )
    }

    protocol.LeaveSubreddit(user_id, subreddit_id) -> {
      subreddit_manager.leave_subreddit(
        state.subreddit_manager,
        client,
        user_id,
        subreddit_id,
      )
    }

    protocol.GetSubreddit(subreddit_id) -> {
      subreddit_manager.get_subreddit(
        state.subreddit_manager,
        client,
        subreddit_id,
      )
    }

    protocol.ListSubreddits -> {
      subreddit_manager.list_subreddits(state.subreddit_manager, client)
    }

    // Post Operations
    protocol.CreatePost(author_id, subreddit_id, title, content, is_repost, original_post_id) -> {
      post_storage.create_post(
        state.post_storage,
        client,
        author_id,
        subreddit_id,
        title,
        content,
        is_repost,
        original_post_id,
      )
    }

    protocol.GetPost(post_id) -> {
      post_storage.get_post(state.post_storage, client, post_id)
    }

    protocol.GetSubredditPosts(subreddit_id, limit) -> {
      post_storage.get_subreddit_posts(
        state.post_storage,
        client,
        subreddit_id,
        limit,
      )
    }

    protocol.DeletePost(post_id, user_id) -> {
      post_storage.delete_post(state.post_storage, client, post_id, user_id)
    }

    // Comment Operations
    protocol.CreateComment(author_id, post_id, parent_comment_id, content) -> {
      post_storage.create_comment(
        state.post_storage,
        client,
        author_id,
        post_id,
        parent_comment_id,
        content,
      )
    }

    protocol.GetPostComments(post_id) -> {
      post_storage.get_post_comments(state.post_storage, client, post_id)
    }

    protocol.GetComment(comment_id) -> {
      post_storage.get_comment(state.post_storage, client, comment_id)
    }

    protocol.DeleteComment(comment_id, user_id) -> {
      post_storage.delete_comment(state.post_storage, client, comment_id, user_id)
    }

    // Voting Operations
    protocol.VotePost(user_id, post_id, vote_type) -> {
      vote_tracker.vote_post(
        state.vote_tracker,
        client,
        user_id,
        post_id,
        vote_type,
      )
    }

    protocol.VoteComment(user_id, comment_id, vote_type) -> {
      vote_tracker.vote_comment(
        state.vote_tracker,
        client,
        user_id,
        comment_id,
        vote_type,
      )
    }

    protocol.RemoveVote(user_id, target_id) -> {
      vote_tracker.remove_vote(state.vote_tracker, client, user_id, target_id)
    }

    // Feed Operations
    protocol.GetFeed(user_id, limit) -> {
      post_storage.get_feed(state.post_storage, client, user_id, limit)
    }

    protocol.GetHomeFeed(user_id, limit) -> {
      post_storage.get_home_feed(state.post_storage, client, user_id, limit)
    }

    // Direct Message Operations
    protocol.SendDirectMessage(from_user_id, to_user_id, content) -> {
      user_registry.send_direct_message(
        state.user_registry,
        client,
        from_user_id,
        to_user_id,
        content,
      )
    }

    protocol.GetDirectMessages(user_id) -> {
      user_registry.get_direct_messages(state.user_registry, client, user_id)
    }

    protocol.MarkMessageAsRead(user_id, message_id) -> {
      user_registry.mark_message_as_read(
        state.user_registry,
        client,
        user_id,
        message_id,
      )
    }

    // Connection Management
    protocol.Connect(user_id) -> {
      register_connection(process.subject_owner(client), user_id, client)
    }

    protocol.Disconnect(user_id) -> {
      unregister_connection(process.subject_owner(client), user_id)
      process.send(client, protocol.Disconnected(user_id, get_timestamp()))
    }

    protocol.Heartbeat(user_id) -> {
      process.send(client, protocol.HeartbeatAck(user_id, get_timestamp()))
    }
  }
}

// Helper to get current timestamp
fn get_timestamp() -> Int {
  // TODO: Use proper Erlang timestamp
  0
}