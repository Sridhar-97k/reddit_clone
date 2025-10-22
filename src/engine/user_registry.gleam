// User Registry - Manages users and direct messages
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import shared/protocol.{type EngineResponse}
import shared/types.{
  type DirectMessage, type Id, type User, type UserProfile, DirectMessage, User,
  UserProfile,
}
import shared/utils

// ============================================================================
// State
// ============================================================================

pub type UserRegistryState {
  UserRegistryState(
    users: Dict(Id, User),
    usernames: Dict(String, Id),
    direct_messages: Dict(Id, List(DirectMessage)),
  )
}

// ============================================================================
// Messages
// ============================================================================

pub type UserRegistryMessage {
  RegisterUser(
    client: Subject(EngineResponse),
    username: String,
    password: String,
  )
  LoginUser(
    client: Subject(EngineResponse),
    username: String,
    password: String,
  )
  GetUserProfile(client: Subject(EngineResponse), user_id: Id)
  GetUser(client: Subject(EngineResponse), user_id: Id)
  UpdateUserKarma(user_id: Id, karma_delta: Int)
  SubscribeToSubreddit(user_id: Id, subreddit_id: Id)
  UnsubscribeFromSubreddit(user_id: Id, subreddit_id: Id)
  SendDirectMessage(
    client: Subject(EngineResponse),
    from_user_id: Id,
    to_user_id: Id,
    content: String,
  )
  GetDirectMessages(client: Subject(EngineResponse), user_id: Id)
  MarkMessageAsRead(
    client: Subject(EngineResponse),
    user_id: Id,
    message_id: Id,
  )
}

// ============================================================================
// API
// ============================================================================
pub fn start() -> Result(Subject(UserRegistryMessage), actor.StartError) {
  case actor.start(actor.new(init_state()), handle_message) {
    Ok(started) -> Ok(started.0)
    Error(e) -> Error(e)
  }
}

pub fn register_user(
  registry: Subject(UserRegistryMessage),
  client: Subject(EngineResponse),
  username: String,
  password: String,
) -> Nil {
  process.send(registry, RegisterUser(client, username, password))
}

pub fn login_user(
  registry: Subject(UserRegistryMessage),
  client: Subject(EngineResponse),
  username: String,
  password: String,
) -> Nil {
  process.send(registry, LoginUser(client, username, password))
}

pub fn get_user_profile(
  registry: Subject(UserRegistryMessage),
  client: Subject(EngineResponse),
  user_id: Id,
) -> Nil {
  process.send(registry, GetUserProfile(client, user_id))
}

pub fn update_user_karma(
  registry: Subject(UserRegistryMessage),
  user_id: Id,
  karma_delta: Int,
) -> Nil {
  process.send(registry, UpdateUserKarma(user_id, karma_delta))
}

pub fn send_direct_message(
  registry: Subject(UserRegistryMessage),
  client: Subject(EngineResponse),
  from_user_id: Id,
  to_user_id: Id,
  content: String,
) -> Nil {
  process.send(registry, SendDirectMessage(client, from_user_id, to_user_id, content))
}

pub fn get_direct_messages(
  registry: Subject(UserRegistryMessage),
  client: Subject(EngineResponse),
  user_id: Id,
) -> Nil {
  process.send(registry, GetDirectMessages(client, user_id))
}

pub fn mark_message_as_read(
  registry: Subject(UserRegistryMessage),
  client: Subject(EngineResponse),
  user_id: Id,
  message_id: Id,
) -> Nil {
  process.send(registry, MarkMessageAsRead(client, user_id, message_id))
}

// ============================================================================
// Implementation
// ============================================================================

fn init_state() -> UserRegistryState {
  UserRegistryState(
    users: dict.new(),
    usernames: dict.new(),
    direct_messages: dict.new(),
  )
}

fn handle_message(
  message: UserRegistryMessage,
  state: UserRegistryState,
) -> actor.Next(UserRegistryState, UserRegistryMessage) {
  case message {
    RegisterUser(client, username, password) -> {
      let result = case utils.validate_username(username) {
        Error(reason) -> {
          Error(protocol.InvalidRequest(reason))
        }
        Ok(valid_username) -> {
          case dict.has_key(state.usernames, valid_username) {
            True -> Error(protocol.UsernameAlreadyExists(valid_username))
            False -> {
              let user_id = utils.generate_user_id()
              let password_hash = hash_password(password)
              let user =
                User(
                  id: user_id,
                  username: valid_username,
                  password_hash: password_hash,
                  karma: 0,
                  joined_at: utils.get_current_timestamp(),
                  subscribed_subreddits: [],
                )

              let new_users = dict.insert(state.users, user_id, user)
              let new_usernames =
                dict.insert(state.usernames, valid_username, user_id)
              let new_state =
                UserRegistryState(
                  users: new_users,
                  usernames: new_usernames,
                  direct_messages: state.direct_messages,
                )

              Ok(#(new_state, user))
            }
          }
        }
      }

      case result {
        Ok(#(new_state, user)) -> {
          process.send(client, protocol.UserRegistered(user.id, user.username))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }

    LoginUser(client, username, password) -> {
      let result = case dict.get(state.usernames, username) {
        Error(_) -> Error(protocol.InvalidCredentials)
        Ok(user_id) -> {
          case dict.get(state.users, user_id) {
            Error(_) -> Error(protocol.InvalidCredentials)
            Ok(user) -> {
              case verify_password(password, user.password_hash) {
                True -> Ok(user)
                False -> Error(protocol.InvalidCredentials)
              }
            }
          }
        }
      }

      case result {
        Ok(user) -> {
          process.send(
            client,
            protocol.UserLoggedIn(user.id, user.username, user.karma),
          )
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
        }
      }

      actor.continue(state)
    }

    GetUserProfile(client, user_id) -> {
      let result = case dict.get(state.users, user_id) {
        Error(_) -> Error(protocol.UserNotFound(user_id))
        Ok(user) -> {
          let profile =
            UserProfile(
              id: user.id,
              username: user.username,
              karma: user.karma,
              joined_at: user.joined_at,
            )
          Ok(profile)
        }
      }

      case result {
        Ok(profile) -> {
          process.send(client, protocol.UserProfileResponse(profile))
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
        }
      }

      actor.continue(state)
    }

    GetUser(client, user_id) -> {
      case dict.get(state.users, user_id) {
        Ok(user) -> {
          process.send(client, protocol.UserProfileResponse(UserProfile(
            id: user.id,
            username: user.username,
            karma: user.karma,
            joined_at: user.joined_at,
          )))
        }
        Error(_) -> {
          process.send(client, protocol.Error(protocol.UserNotFound(user_id)))
        }
      }
      actor.continue(state)
    }

    UpdateUserKarma(user_id, karma_delta) -> {
      let new_state = case dict.get(state.users, user_id) {
        Error(_) -> state
        Ok(user) -> {
          let updated_user = User(..user, karma: user.karma + karma_delta)
          let new_users = dict.insert(state.users, user_id, updated_user)
          UserRegistryState(..state, users: new_users)
        }
      }
      actor.continue(new_state)
    }

    SubscribeToSubreddit(user_id, subreddit_id) -> {
      let new_state = case dict.get(state.users, user_id) {
        Error(_) -> state
        Ok(user) -> {
          let updated_subs = [subreddit_id, ..user.subscribed_subreddits]
          let updated_user = User(..user, subscribed_subreddits: updated_subs)
          let new_users = dict.insert(state.users, user_id, updated_user)
          UserRegistryState(..state, users: new_users)
        }
      }
      actor.continue(new_state)
    }

    UnsubscribeFromSubreddit(user_id, subreddit_id) -> {
      let new_state = case dict.get(state.users, user_id) {
        Error(_) -> state
        Ok(user) -> {
          let updated_subs =
            list.filter(user.subscribed_subreddits, fn(id) {
              id != subreddit_id
            })
          let updated_user = User(..user, subscribed_subreddits: updated_subs)
          let new_users = dict.insert(state.users, user_id, updated_user)
          UserRegistryState(..state, users: new_users)
        }
      }
      actor.continue(new_state)
    }

    SendDirectMessage(client, from_user_id, to_user_id, content) -> {
      let result = case from_user_id == to_user_id {
        True -> Error(protocol.CannotMessageSelf(from_user_id))
        False -> {
          case dict.get(state.users, from_user_id) {
            Error(_) -> Error(protocol.UserNotFound(from_user_id))
            Ok(from_user) -> {
              case dict.get(state.users, to_user_id) {
                Error(_) -> Error(protocol.UserNotFound(to_user_id))
                Ok(to_user) -> {
                  let message_id = utils.generate_message_id()
                  let message =
                    DirectMessage(
                      id: message_id,
                      from_user_id: from_user_id,
                      from_username: from_user.username,
                      to_user_id: to_user_id,
                      to_username: to_user.username,
                      content: content,
                      created_at: utils.get_current_timestamp(),
                      read: False,
                    )

                  let existing_messages =
                    dict.get(state.direct_messages, to_user_id)
                    |> result.unwrap([])
                  let updated_messages = [message, ..existing_messages]
                  let new_dms =
                    dict.insert(state.direct_messages, to_user_id, updated_messages)

                  let new_state = UserRegistryState(..state, direct_messages: new_dms)
                  Ok(#(new_state, message))
                }
              }
            }
          }
        }
      }

      case result {
        Ok(#(new_state, message)) -> {
          process.send(client, protocol.MessageSent(message))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }

    GetDirectMessages(client, user_id) -> {
      let messages =
        dict.get(state.direct_messages, user_id)
        |> result.unwrap([])

      process.send(client, protocol.MessagesResponse(messages))
      actor.continue(state)
    }

    MarkMessageAsRead(client, user_id, message_id) -> {
      let result = case dict.get(state.direct_messages, user_id) {
        Error(_) -> Error(protocol.MessageNotFound(message_id))
        Ok(messages) -> {
          let updated_messages =
            list.map(messages, fn(msg) {
              case msg.id == message_id {
                True -> DirectMessage(..msg, read: True)
                False -> msg
              }
            })

          let new_dms =
            dict.insert(state.direct_messages, user_id, updated_messages)
          let new_state = UserRegistryState(..state, direct_messages: new_dms)
          Ok(new_state)
        }
      }

      case result {
        Ok(new_state) -> {
          process.send(client, protocol.MessageMarkedRead(message_id))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn hash_password(password: String) -> String {
  // TODO: Use proper password hashing (bcrypt/argon2)
  // For now, just a placeholder
  "hashed_" <> password
}

fn verify_password(password: String, hash: String) -> Bool {
  // TODO: Use proper password verification
  hash == "hashed_" <> password
}