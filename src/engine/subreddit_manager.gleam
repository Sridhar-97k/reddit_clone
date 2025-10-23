// Subreddit Manager - Manages subreddit creation and membership
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import shared/protocol.{type EngineResponse}
import shared/types.{type Id, type Subreddit, Subreddit}
import shared/utils

// ============================================================================
// State
// ============================================================================

pub type SubredditManagerState {
  SubredditManagerState(
    subreddits: Dict(Id, Subreddit),
    subreddit_names: Dict(String, Id),
    members: Dict(Id, List(Id)),
  )
}

// ============================================================================
// Messages
// ============================================================================

pub type SubredditMessage {
  CreateSubreddit(
    client: Subject(EngineResponse),
    name: String,
    description: String,
    creator_id: Id,
  )
  JoinSubreddit(client: Subject(EngineResponse), user_id: Id, subreddit_id: Id)
  LeaveSubreddit(
    client: Subject(EngineResponse),
    user_id: Id,
    subreddit_id: Id,
  )
  GetSubreddit(client: Subject(EngineResponse), subreddit_id: Id)
  ListSubreddits(client: Subject(EngineResponse))
  IncrementPostCount(subreddit_id: Id)
}

// ============================================================================
// API
// ============================================================================

/// Compilation error here. Have to debug


pub fn start() -> Result(Subject(SubredditMessage), actor.StartError) {
  actor.new(init_state())
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

pub fn create_subreddit(
  manager: Subject(SubredditMessage),
  client: Subject(EngineResponse),
  name: String,
  description: String,
  creator_id: Id,
) -> Nil {
  process.send(manager, CreateSubreddit(client, name, description, creator_id))
}

pub fn join_subreddit(
  manager: Subject(SubredditMessage),
  client: Subject(EngineResponse),
  user_id: Id,
  subreddit_id: Id,
) -> Nil {
  process.send(manager, JoinSubreddit(client, user_id, subreddit_id))
}

pub fn leave_subreddit(
  manager: Subject(SubredditMessage),
  client: Subject(EngineResponse),
  user_id: Id,
  subreddit_id: Id,
) -> Nil {
  process.send(manager, LeaveSubreddit(client, user_id, subreddit_id))
}

pub fn get_subreddit(
  manager: Subject(SubredditMessage),
  client: Subject(EngineResponse),
  subreddit_id: Id,
) -> Nil {
  process.send(manager, GetSubreddit(client, subreddit_id))
}

pub fn list_subreddits(
  manager: Subject(SubredditMessage),
  client: Subject(EngineResponse),
) -> Nil {
  process.send(manager, ListSubreddits(client))
}

pub fn increment_post_count(
  manager: Subject(SubredditMessage),
  subreddit_id: Id,
) -> Nil {
  process.send(manager, IncrementPostCount(subreddit_id))
}

// ============================================================================
// Implementation
// ============================================================================

fn init_state() -> SubredditManagerState {
  SubredditManagerState(
    subreddits: dict.new(),
    subreddit_names: dict.new(),
    members: dict.new(),
  )
}

fn handle_message(
  state: SubredditManagerState,
  message: SubredditMessage,
) -> actor.Next(SubredditManagerState, SubredditMessage) {
  case message {
    CreateSubreddit(client, name, description, creator_id) -> {
      let result = case utils.validate_subreddit_name(name) {
        Error(reason) -> Error(protocol.InvalidRequest(reason))
        Ok(valid_name) -> {
          case dict.has_key(state.subreddit_names, valid_name) {
            True -> Error(protocol.SubredditNameAlreadyExists(valid_name))
            False -> {
              let subreddit_id = utils.generate_subreddit_id()
              let subreddit =
                Subreddit(
                  id: subreddit_id,
                  name: valid_name,
                  description: description,
                  created_by: creator_id,
                  created_at: utils.get_current_timestamp(),
                  member_count: 1,
                  post_count: 0,
                )

              let new_subreddits =
                dict.insert(state.subreddits, subreddit_id, subreddit)
              let new_names =
                dict.insert(state.subreddit_names, valid_name, subreddit_id)
              let new_members =
                dict.insert(state.members, subreddit_id, [creator_id])

              let new_state =
                SubredditManagerState(
                  subreddits: new_subreddits,
                  subreddit_names: new_names,
                  members: new_members,
                )

              Ok(#(new_state, subreddit))
            }
          }
        }
      }

      case result {
        Ok(#(new_state, subreddit)) -> {
          process.send(client, protocol.SubredditCreated(subreddit))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }

    JoinSubreddit(client, user_id, subreddit_id) -> {
      let result = case dict.get(state.subreddits, subreddit_id) {
        Error(_) -> Error(protocol.SubredditNotFound(subreddit_id))
        Ok(subreddit) -> {
          let current_members =
            dict.get(state.members, subreddit_id)
            |> result.unwrap([])

          case list.contains(current_members, user_id) {
            True -> Error(protocol.AlreadySubscribed(user_id, subreddit_id))
            False -> {
              let new_members = [user_id, ..current_members]
              let updated_subreddit =
                Subreddit(
                  ..subreddit,
                  member_count: subreddit.member_count + 1,
                )

              let new_subreddits =
                dict.insert(state.subreddits, subreddit_id, updated_subreddit)
              let new_member_dict =
                dict.insert(state.members, subreddit_id, new_members)

              let new_state =
                SubredditManagerState(
                  ..state,
                  subreddits: new_subreddits,
                  members: new_member_dict,
                )

              Ok(new_state)
            }
          }
        }
      }

      case result {
        Ok(new_state) -> {
          process.send(client, protocol.SubredditJoined(subreddit_id, user_id))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }

    LeaveSubreddit(client, user_id, subreddit_id) -> {
      let result = case dict.get(state.subreddits, subreddit_id) {
        Error(_) -> Error(protocol.SubredditNotFound(subreddit_id))
        Ok(subreddit) -> {
          let current_members =
            dict.get(state.members, subreddit_id)
            |> result.unwrap([])

          case list.contains(current_members, user_id) {
            False -> Error(protocol.NotSubscribed(user_id, subreddit_id))
            True -> {
              let new_members =
                list.filter(current_members, fn(id) { id != user_id })
              let updated_subreddit =
                Subreddit(
                  ..subreddit,
                  member_count: subreddit.member_count - 1,
                )

              let new_subreddits =
                dict.insert(state.subreddits, subreddit_id, updated_subreddit)
              let new_member_dict =
                dict.insert(state.members, subreddit_id, new_members)

              let new_state =
                SubredditManagerState(
                  ..state,
                  subreddits: new_subreddits,
                  members: new_member_dict,
                )

              Ok(new_state)
            }
          }
        }
      }

      case result {
        Ok(new_state) -> {
          process.send(client, protocol.SubredditLeft(subreddit_id, user_id))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }

    GetSubreddit(client, subreddit_id) -> {
      case dict.get(state.subreddits, subreddit_id) {
        Ok(subreddit) -> {
          process.send(client, protocol.SubredditResponse(subreddit))
        }
        Error(_) -> {
          process.send(
            client,
            protocol.Error(protocol.SubredditNotFound(subreddit_id)),
          )
        }
      }
      actor.continue(state)
    }

    ListSubreddits(client) -> {
      let subreddits = dict.values(state.subreddits)
      process.send(client, protocol.SubredditListResponse(subreddits))
      actor.continue(state)
    }

    IncrementPostCount(subreddit_id) -> {
      let new_state = case dict.get(state.subreddits, subreddit_id) {
        Error(_) -> state
        Ok(subreddit) -> {
          let updated =
            Subreddit(..subreddit, post_count: subreddit.post_count + 1)
          let new_subreddits =
            dict.insert(state.subreddits, subreddit_id, updated)
          SubredditManagerState(..state, subreddits: new_subreddits)
        }
      }
      actor.continue(new_state)
    }
  }
}