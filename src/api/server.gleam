// src/api/server.gleam - Complete HTTP REST API Server with Full Validation
import gleam/erlang/process.{type Subject}
import gleam/bytes_builder
import gleam/http/response.{type Response}
import gleam/io
import gleam/int
import gleam/json
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/string_builder
import gleam/list
import gleam/dynamic
import gleam/regex
import mist
import wisp
import engine/core
import gleam/http
import shared/protocol
import shared/types

// ============================================================================
// Validation Types and Results
// ============================================================================

pub type ValidationError {
  EmptyField(field: String)
  TooShort(field: String, min_length: Int)
  TooLong(field: String, max_length: Int)
  InvalidFormat(field: String, reason: String)
  InvalidValue(field: String, reason: String)
}

pub type ValidationResult(a) =
  Result(a, List(ValidationError))

// ============================================================================
// Server Context
// ============================================================================

pub type Context {
  Context(
    engine: Subject(core.EngineMessage),
    secret_key: String,
  )
}

// ============================================================================
// API - Start HTTP Server
// ============================================================================

pub fn start(engine: Subject(core.EngineMessage)) -> Result(Nil, String) {
  io.println("🌐 Starting HTTP server on http://localhost:8000")
  
  let ctx = Context(
    engine: engine,
    secret_key: "your-secret-key-change-this-in-production",
  )
  
  let handler = handle_request(_, ctx)
  
  let assert Ok(_) =
    wisp.mist_handler(handler, secret_key(ctx))
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http
  
  io.println("✅ HTTP server started successfully!")
  io.println("   API Documentation:")
  io.println("   - POST   /api/register")
  io.println("   - POST   /api/login")
  io.println("   - POST   /api/subreddits")
  io.println("   - GET    /api/subreddits")
  io.println("   - POST   /api/subreddits/:id/join")
  io.println("   - POST   /api/posts")
  io.println("   - GET    /api/posts/:id")
  io.println("   - POST   /api/comments")
  io.println("   - POST   /api/vote")
  io.println("   - GET    /api/feed/:user_id")
  io.println("   - POST   /api/messages")
  io.println("   - GET    /health")
  io.println("")
  
  Ok(Nil)
}

// ============================================================================
// Request Router
// ============================================================================

fn handle_request(req: wisp.Request, ctx: Context) -> wisp.Response {
  use req <- middleware(req, ctx)
  
  case wisp.path_segments(req) {
    ["health"] -> health_handler(req, ctx)
    ["api", ..rest] -> api_router(req, rest, ctx)
    _ -> wisp.not_found()
  }
}

// ============================================================================
// Middleware
// ============================================================================

fn middleware(
  req: wisp.Request,
  ctx: Context,
  handler: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let method = http_method_to_string(req.method)
  let path = wisp.path_segments(req) |> string.join("/")
  io.println("[" <> method <> "] /" <> path)
  
  let response = handler(req)
  
  let response = response
    |> wisp.set_header("access-control-allow-origin", "*")
    |> wisp.set_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> wisp.set_header("access-control-allow-headers", "Content-Type, Authorization")
  
  io.println("    → " <> int.to_string(response.status) <> " " <> status_text(response.status))
  
  response
}

// ============================================================================
// API Router
// ============================================================================

fn api_router(
  req: wisp.Request,
  segments: List(String),
  ctx: Context,
) -> wisp.Response {
  case req.method, segments {
    http.Post, ["register"] -> register_handler(req, ctx)
    http.Post, ["login"] -> login_handler(req, ctx)
    http.Get, ["users", user_id] -> get_user_handler(req, ctx, user_id)
    
    http.Post, ["subreddits"] -> create_subreddit_handler(req, ctx)
    http.Get, ["subreddits"] -> list_subreddits_handler(req, ctx)
    http.Get, ["subreddits", sub_id] -> get_subreddit_handler(req, ctx, sub_id)
    http.Post, ["subreddits", sub_id, "join"] -> join_subreddit_handler(req, ctx, sub_id)
    http.Post, ["subreddits", sub_id, "leave"] -> leave_subreddit_handler(req, ctx, sub_id)
    http.Get, ["subreddits", sub_id, "posts"] -> get_subreddit_posts_handler(req, ctx, sub_id)
    
    http.Post, ["posts"] -> create_post_handler(req, ctx)
    http.Get, ["posts", post_id] -> get_post_handler(req, ctx, post_id)
    http.Delete, ["posts", post_id] -> delete_post_handler(req, ctx, post_id)
    
    http.Post, ["comments"] -> create_comment_handler(req, ctx)
    http.Get, ["posts", post_id, "comments"] -> get_post_comments_handler(req, ctx, post_id)
    
    http.Post, ["vote"] -> vote_handler(req, ctx)
    http.Delete, ["vote"] -> remove_vote_handler(req, ctx)
    
    http.Get, ["feed", user_id] -> get_feed_handler(req, ctx, user_id)
    http.Get, ["home", user_id] -> get_home_feed_handler(req, ctx, user_id)
    
    http.Post, ["messages"] -> send_message_handler(req, ctx)
    http.Get, ["messages", user_id] -> get_messages_handler(req, ctx, user_id)
    
    _, _ -> {
      json_response(404, json.object([
        #("error", json.string("Not Found")),
        #("message", json.string("API endpoint not found")),
        #("path", json.string(string.join(segments, "/"))),
      ]))
    }
  }
}

// ============================================================================
// Validation Functions
// ============================================================================

fn validate_username(username: String) -> ValidationResult(String) {
  let errors = []
  
  // Check if empty
  let errors = case string.is_empty(username) {
    True -> [EmptyField("username"), ..errors]
    False -> errors
  }
  
  // Check length (3-20 characters)
  let errors = case string.length(username) < 3 {
    True -> [TooShort("username", 3), ..errors]
    False -> errors
  }
  
  let errors = case string.length(username) > 20 {
    True -> [TooLong("username", 20), ..errors]
    False -> errors
  }
  
  // Check format (alphanumeric and underscore only)
  let errors = case validate_alphanumeric(username) {
    False -> [InvalidFormat("username", "must contain only letters, numbers, and underscores"), ..errors]
    True -> errors
  }
  
  case errors {
    [] -> Ok(username)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_password(password: String) -> ValidationResult(String) {
  let errors = []
  
  let errors = case string.is_empty(password) {
    True -> [EmptyField("password"), ..errors]
    False -> errors
  }
  
  let errors = case string.length(password) < 6 {
    True -> [TooShort("password", 6), ..errors]
    False -> errors
  }
  
  let errors = case string.length(password) > 100 {
    True -> [TooLong("password", 100), ..errors]
    False -> errors
  }
  
  case errors {
    [] -> Ok(password)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_subreddit_name(name: String) -> ValidationResult(String) {
  let errors = []
  
  let errors = case string.is_empty(name) {
    True -> [EmptyField("name"), ..errors]
    False -> errors
  }
  
  let errors = case string.length(name) < 3 {
    True -> [TooShort("name", 3), ..errors]
    False -> errors
  }
  
  let errors = case string.length(name) > 21 {
    True -> [TooLong("name", 21), ..errors]
    False -> errors
  }
  
  let errors = case validate_alphanumeric(name) {
    False -> [InvalidFormat("name", "must contain only letters, numbers, and underscores"), ..errors]
    True -> errors
  }
  
  case errors {
    [] -> Ok(name)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_description(desc: String) -> ValidationResult(String) {
  let errors = []
  
  let errors = case string.is_empty(desc) {
    True -> [EmptyField("description"), ..errors]
    False -> errors
  }
  
  let errors = case string.length(desc) > 500 {
    True -> [TooLong("description", 500), ..errors]
    False -> errors
  }
  
  case errors {
    [] -> Ok(desc)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_post_title(title: String) -> ValidationResult(String) {
  let errors = []
  
  let errors = case string.is_empty(title) {
    True -> [EmptyField("title"), ..errors]
    False -> errors
  }
  
  let errors = case string.length(title) < 3 {
    True -> [TooShort("title", 3), ..errors]
    False -> errors
  }
  
  let errors = case string.length(title) > 300 {
    True -> [TooLong("title", 300), ..errors]
    False -> errors
  }
  
  case errors {
    [] -> Ok(title)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_post_content(content: String) -> ValidationResult(String) {
  let errors = []
  
  let errors = case string.is_empty(content) {
    True -> [EmptyField("content"), ..errors]
    False -> errors
  }
  
  let errors = case string.length(content) > 40000 {
    True -> [TooLong("content", 40000), ..errors]
    False -> errors
  }
  
  case errors {
    [] -> Ok(content)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_comment_content(content: String) -> ValidationResult(String) {
  let errors = []
  
  let errors = case string.is_empty(content) {
    True -> [EmptyField("content"), ..errors]
    False -> errors
  }
  
  let errors = case string.length(content) < 1 {
    True -> [TooShort("content", 1), ..errors]
    False -> errors
  }
  
  let errors = case string.length(content) > 10000 {
    True -> [TooLong("content", 10000), ..errors]
    False -> errors
  }
  
  case errors {
    [] -> Ok(content)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_message_content(content: String) -> ValidationResult(String) {
  let errors = []
  
  let errors = case string.is_empty(content) {
    True -> [EmptyField("content"), ..errors]
    False -> errors
  }
  
  let errors = case string.length(content) > 10000 {
    True -> [TooLong("content", 10000), ..errors]
    False -> errors
  }
  
  case errors {
    [] -> Ok(content)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_user_id(user_id: String) -> ValidationResult(String) {
  let errors = []
  
  let errors = case string.is_empty(user_id) {
    True -> [EmptyField("user_id"), ..errors]
    False -> errors
  }
  
  case errors {
    [] -> Ok(user_id)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_id(field_name: String, id: String) -> ValidationResult(String) {
  let errors = []
  
  let errors = case string.is_empty(id) {
    True -> [EmptyField(field_name), ..errors]
    False -> errors
  }
  
  case errors {
    [] -> Ok(id)
    _ -> Error(list.reverse(errors))
  }
}

fn validate_vote_type(vote_type: String) -> ValidationResult(String) {
  case vote_type {
    "upvote" | "downvote" -> Ok(vote_type)
    _ -> Error([InvalidValue("vote_type", "must be 'upvote' or 'downvote'")])
  }
}

fn validate_alphanumeric(str: String) -> Bool {
  // Check if string contains only letters, numbers, and underscores
  string.to_graphemes(str)
  |> list.all(fn(char) {
    case char {
      "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l" | "m" |
      "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z" |
      "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L" | "M" |
      "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z" |
      "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "_" -> True
      _ -> False
    }
  })
}

fn validation_errors_to_json(errors: List(ValidationError)) -> json.Json {
  let error_objects = list.map(errors, fn(error) {
    case error {
      EmptyField(field) -> 
        json.object([
          #("field", json.string(field)),
          #("error", json.string("required")),
          #("message", json.string(field <> " is required")),
        ])
      TooShort(field, min) ->
        json.object([
          #("field", json.string(field)),
          #("error", json.string("too_short")),
          #("message", json.string(field <> " must be at least " <> int.to_string(min) <> " characters")),
        ])
      TooLong(field, max) ->
        json.object([
          #("field", json.string(field)),
          #("error", json.string("too_long")),
          #("message", json.string(field <> " must be at most " <> int.to_string(max) <> " characters")),
        ])
      InvalidFormat(field, reason) ->
        json.object([
          #("field", json.string(field)),
          #("error", json.string("invalid_format")),
          #("message", json.string(field <> " " <> reason)),
        ])
      InvalidValue(field, reason) ->
        json.object([
          #("field", json.string(field)),
          #("error", json.string("invalid_value")),
          #("message", json.string(field <> " " <> reason)),
        ])
    }
  })
  
  json.array(error_objects, fn(x) { x })
}

// ============================================================================
// User Handlers with Validation
// ============================================================================

fn register_handler(req: wisp.Request, ctx: Context) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  let result = {
    use username <- result.try(get_string_field(json_body, "username"))
    use password <- result.try(get_string_field(json_body, "password"))
    Ok(#(username, password))
  }
  
  case result {
    Ok(#(username, password)) -> {
      // Validate username
      let username_result = validate_username(username)
      let password_result = validate_password(password)
      
      case username_result, password_result {
        Ok(valid_username), Ok(valid_password) -> {
          // Send to engine
          case send_and_wait_for_response(
            ctx.engine,
            protocol.RegisterUser(valid_username, valid_password),
            5000,
          ) {
            Ok(protocol.UserRegistered(user_id, username)) -> {
              json_response(201, json.object([
                #("message", json.string("User registered successfully")),
                #("username", json.string(username)),
                #("user_id", json.string(user_id)),
              ]))
            }
            Ok(protocol.Error(error)) -> {
              let error_msg = case error {
                protocol.UsernameAlreadyExists(_) -> "Username already taken"
                _ -> "Registration failed"
              }
              json_response(400, json.object([
                #("error", json.string("Bad Request")),
                #("message", json.string(error_msg)),
              ]))
            }
            Error(_) -> {
              json_response(500, json.object([
                #("error", json.string("Internal Server Error")),
                #("message", json.string("Request timeout")),
              ]))
            }
            _ -> {
              json_response(500, json.object([
                #("error", json.string("Internal Server Error")),
                #("message", json.string("Unexpected response")),
              ]))
            }
          }
        }
        Error(username_errors), Error(password_errors) -> {
          let all_errors = list.append(username_errors, password_errors)
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("message", json.string("Invalid input data")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
        Error(errors), _ | _, Error(errors) -> {
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("message", json.string("Invalid input data")),
            #("validation_errors", validation_errors_to_json(errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'username' and 'password' fields")),
      ]))
    }
  }
}

fn login_handler(req: wisp.Request, ctx: Context) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  let result = {
    use username <- result.try(get_string_field(json_body, "username"))
    use password <- result.try(get_string_field(json_body, "password"))
    Ok(#(username, password))
  }
  
  case result {
    Ok(#(username, password)) -> {
      // Validate input
      let username_result = validate_username(username)
      let password_result = validate_password(password)
      
      case username_result, password_result {
        Ok(_), Ok(_) -> {
          case send_and_wait_for_response(
            ctx.engine,
            protocol.LoginUser(username, password),
            5000,
          ) {
            Ok(protocol.UserLoggedIn(user_id, username, karma)) -> {
              json_response(200, json.object([
                #("message", json.string("Login successful")),
                #("username", json.string(username)),
                #("user_id", json.string(user_id)),
                #("karma", json.int(karma)),
              ]))
            }
            Ok(protocol.Error(_)) -> {
              json_response(401, json.object([
                #("error", json.string("Unauthorized")),
                #("message", json.string("Invalid username or password")),
              ]))
            }
            Error(_) -> {
              json_response(500, json.object([
                #("error", json.string("Internal Server Error")),
                #("message", json.string("Request timeout")),
              ]))
            }
            _ -> {
              json_response(500, json.object([
                #("error", json.string("Internal Server Error")),
                #("message", json.string("Unexpected response")),
              ]))
            }
          }
        }
        Error(username_errors), Error(password_errors) -> {
          let all_errors = list.append(username_errors, password_errors)
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("message", json.string("Invalid input data")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
        Error(errors), _ | _, Error(errors) -> {
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("message", json.string("Invalid input data")),
            #("validation_errors", validation_errors_to_json(errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'username' and 'password'")),
      ]))
    }
  }
}

fn get_user_handler(_req: wisp.Request, ctx: Context, user_id: String) -> wisp.Response {
  case validate_user_id(user_id) {
    Ok(valid_id) -> {
      let client = create_response_client()
      
      core.handle_request(
        ctx.engine,
        generate_request_id(),
        client,
        protocol.GetUserProfile(valid_id),
      )
      
      json_response(200, json.object([
        #("user_id", json.string(valid_id)),
        #("message", json.string("User profile retrieved")),
      ]))
    }
    Error(errors) -> {
      json_response(400, json.object([
        #("error", json.string("Validation Failed")),
        #("validation_errors", validation_errors_to_json(errors)),
      ]))
    }
  }
}

// ============================================================================
// Subreddit Handlers with Validation
// ============================================================================

fn create_subreddit_handler(req: wisp.Request, ctx: Context) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  let result = {
    use name <- result.try(get_string_field(json_body, "name"))
    use description <- result.try(get_string_field(json_body, "description"))
    use creator_id <- result.try(get_string_field(json_body, "creator_id"))
    Ok(#(name, description, creator_id))
  }
  
  case result {
    Ok(#(name, description, creator_id)) -> {
      let name_result = validate_subreddit_name(name)
      let desc_result = validate_description(description)
      let creator_result = validate_user_id(creator_id)
      
      case name_result, desc_result, creator_result {
        Ok(valid_name), Ok(valid_desc), Ok(valid_creator) -> {
          let client = create_response_client()
          
          core.handle_request(
            ctx.engine,
            generate_request_id(),
            client,
            protocol.CreateSubreddit(valid_name, valid_desc, valid_creator),
          )
          
          json_response(201, json.object([
            #("message", json.string("Subreddit created successfully")),
            #("name", json.string(valid_name)),
          ]))
        }
        _, _, _ -> {
          let all_errors = []
          let all_errors = case name_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case desc_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case creator_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'name', 'description', 'creator_id'")),
      ]))
    }
  }
}

fn list_subreddits_handler(_req: wisp.Request, ctx: Context) -> wisp.Response {
  let client = create_response_client()
  
  core.handle_request(
    ctx.engine,
    generate_request_id(),
    client,
    protocol.ListSubreddits,
  )
  
  json_response(200, json.object([
    #("message", json.string("Subreddits retrieved")),
  ]))
}

fn get_subreddit_handler(_req: wisp.Request, ctx: Context, sub_id: String) -> wisp.Response {
  case validate_id("subreddit_id", sub_id) {
    Ok(valid_id) -> {
      let client = create_response_client()
      
      core.handle_request(
        ctx.engine,
        generate_request_id(),
        client,
        protocol.GetSubreddit(valid_id),
      )
      
      json_response(200, json.object([
        #("subreddit_id", json.string(valid_id)),
        #("message", json.string("Subreddit retrieved")),
      ]))
    }
    Error(errors) -> {
      json_response(400, json.object([
        #("error", json.string("Validation Failed")),
        #("validation_errors", validation_errors_to_json(errors)),
      ]))
    }
  }
}

fn join_subreddit_handler(req: wisp.Request, ctx: Context, sub_id: String) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  case get_string_field(json_body, "user_id") {
    Ok(user_id) -> {
      let user_result = validate_user_id(user_id)
      let sub_result = validate_id("subreddit_id", sub_id)
      
      case user_result, sub_result {
        Ok(valid_user), Ok(valid_sub) -> {
          let client = create_response_client()
          
          core.handle_request(
            ctx.engine,
            generate_request_id(),
            client,
            protocol.JoinSubreddit(valid_user, valid_sub),
          )
          
          json_response(200, json.object([
            #("message", json.string("Joined subreddit successfully")),
            #("subreddit_id", json.string(valid_sub)),
          ]))
        }
        _, _ -> {
          let all_errors = []
          let all_errors = case user_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case sub_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'user_id'")),
      ]))
    }
  }
}

fn leave_subreddit_handler(req: wisp.Request, ctx: Context, sub_id: String) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  case get_string_field(json_body, "user_id") {
    Ok(user_id) -> {
      let user_result = validate_user_id(user_id)
      let sub_result = validate_id("subreddit_id", sub_id)
      
      case user_result, sub_result {
        Ok(valid_user), Ok(valid_sub) -> {
          let client = create_response_client()
          
          core.handle_request(
            ctx.engine,
            generate_request_id(),
            client,
            protocol.LeaveSubreddit(valid_user, valid_sub),
          )
          
          json_response(200, json.object([
            #("message", json.string("Left subreddit successfully")),
            #("subreddit_id", json.string(valid_sub)),
          ]))
        }
        _, _ -> {
          let all_errors = []
          let all_errors = case user_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case sub_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'user_id'")),
      ]))
    }
  }
}

fn get_subreddit_posts_handler(_req: wisp.Request, ctx: Context, sub_id: String) -> wisp.Response {
  case validate_id("subreddit_id", sub_id) {
    Ok(valid_id) -> {
      let client = create_response_client()
      
      core.handle_request(
        ctx.engine,
        generate_request_id(),
        client,
        protocol.GetSubredditPosts(valid_id, 25),
      )
      
      json_response(200, json.object([
        #("subreddit_id", json.string(valid_id)),
        #("message", json.string("Posts retrieved")),
      ]))
    }
    Error(errors) -> {
      json_response(400, json.object([
        #("error", json.string("Validation Failed")),
        #("validation_errors", validation_errors_to_json(errors)),
      ]))
    }
  }
}

// ============================================================================
// Post Handlers with Validation
// ============================================================================

fn create_post_handler(req: wisp.Request, ctx: Context) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  let result = {
    use author_id <- result.try(get_string_field(json_body, "author_id"))
    use subreddit_id <- result.try(get_string_field(json_body, "subreddit_id"))
    use title <- result.try(get_string_field(json_body, "title"))
    use content <- result.try(get_string_field(json_body, "content"))
    Ok(#(author_id, subreddit_id, title, content))
  }
  
  case result {
    Ok(#(author_id, subreddit_id, title, content)) -> {
      let author_result = validate_user_id(author_id)
      let sub_result = validate_id("subreddit_id", subreddit_id)
      let title_result = validate_post_title(title)
      let content_result = validate_post_content(content)
      
      case author_result, sub_result, title_result, content_result {
        Ok(valid_author), Ok(valid_sub), Ok(valid_title), Ok(valid_content) -> {
          // Send to engine and wait for response
          case send_and_wait_for_response(
            ctx.engine,
            protocol.CreatePost(valid_author, valid_sub, valid_title, valid_content, False, None),
            5000,
          ) {
            Ok(protocol.PostCreated(_post)) -> {
              json_response(201, json.object([
                #("message", json.string("Post created successfully")),
                #("title", json.string(valid_title)),
              ]))
            }
            Ok(protocol.Error(error)) -> {
              let error_msg = case error {
                protocol.UserNotFound(_) -> "User not found. Please login first."
                protocol.SubredditNotFound(_) -> "Subreddit not found"
                protocol.NotSubscribed(_, _) -> "You must join the subreddit first"
                _ -> "Failed to create post"
              }
              json_response(400, json.object([
                #("error", json.string("Bad Request")),
                #("message", json.string(error_msg)),
              ]))
            }
            Error(_) -> {
              json_response(500, json.object([
                #("error", json.string("Internal Server Error")),
                #("message", json.string("Request timeout")),
              ]))
            }
            _ -> {
              json_response(500, json.object([
                #("error", json.string("Internal Server Error")),
                #("message", json.string("Unexpected response")),
              ]))
            }
          }
        }
        _, _, _, _ -> {
          let all_errors = []
          let all_errors = case author_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case sub_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case title_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case content_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'author_id', 'subreddit_id', 'title', 'content'")),
      ]))
    }
  }
}

fn get_post_handler(_req: wisp.Request, ctx: Context, post_id: String) -> wisp.Response {
  case validate_id("post_id", post_id) {
    Ok(valid_id) -> {
      let client = create_response_client()
      
      core.handle_request(
        ctx.engine,
        generate_request_id(),
        client,
        protocol.GetPost(valid_id),
      )
      
      json_response(200, json.object([
        #("post_id", json.string(valid_id)),
        #("message", json.string("Post retrieved")),
      ]))
    }
    Error(errors) -> {
      json_response(400, json.object([
        #("error", json.string("Validation Failed")),
        #("validation_errors", validation_errors_to_json(errors)),
      ]))
    }
  }
}

fn delete_post_handler(req: wisp.Request, ctx: Context, post_id: String) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  case get_string_field(json_body, "user_id") {
    Ok(user_id) -> {
      let user_result = validate_user_id(user_id)
      let post_result = validate_id("post_id", post_id)
      
      case user_result, post_result {
        Ok(valid_user), Ok(valid_post) -> {
          let client = create_response_client()
          
          core.handle_request(
            ctx.engine,
            generate_request_id(),
            client,
            protocol.DeletePost(valid_post, valid_user),
          )
          
          json_response(200, json.object([
            #("message", json.string("Post deleted successfully")),
            #("post_id", json.string(valid_post)),
          ]))
        }
        _, _ -> {
          let all_errors = []
          let all_errors = case user_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case post_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'user_id'")),
      ]))
    }
  }
}

// ============================================================================
// Comment Handlers with Validation
// ============================================================================

fn create_comment_handler(req: wisp.Request, ctx: Context) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  let result = {
    use author_id <- result.try(get_string_field(json_body, "author_id"))
    use post_id <- result.try(get_string_field(json_body, "post_id"))
    use content <- result.try(get_string_field(json_body, "content"))
    Ok(#(author_id, post_id, content))
  }
  
  case result {
    Ok(#(author_id, post_id, content)) -> {
      let author_result = validate_user_id(author_id)
      let post_result = validate_id("post_id", post_id)
      let content_result = validate_comment_content(content)
      
      case author_result, post_result, content_result {
        Ok(valid_author), Ok(valid_post), Ok(valid_content) -> {
          // Send to engine and wait for response
          case send_and_wait_for_response(
            ctx.engine,
            protocol.CreateComment(valid_author, valid_post, None, valid_content),
            5000,
          ) {
            Ok(protocol.CommentCreated(_comment)) -> {
              json_response(201, json.object([
                #("message", json.string("Comment created successfully")),
              ]))
            }
            Ok(protocol.Error(error)) -> {
              let error_msg = case error {
                protocol.UserNotFound(_) -> "User not found. Please login first."
                protocol.PostNotFound(_) -> "Post not found"
                _ -> "Failed to create comment"
              }
              json_response(400, json.object([
                #("error", json.string("Bad Request")),
                #("message", json.string(error_msg)),
              ]))
            }
            Error(_) -> {
              json_response(500, json.object([
                #("error", json.string("Internal Server Error")),
                #("message", json.string("Request timeout")),
              ]))
            }
            _ -> {
              json_response(500, json.object([
                #("error", json.string("Internal Server Error")),
                #("message", json.string("Unexpected response")),
              ]))
            }
          }
        }
        _, _, _ -> {
          let all_errors = []
          let all_errors = case author_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case post_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case content_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'author_id', 'post_id', 'content'")),
      ]))
    }
  }
}

fn get_post_comments_handler(_req: wisp.Request, ctx: Context, post_id: String) -> wisp.Response {
  case validate_id("post_id", post_id) {
    Ok(valid_id) -> {
      let client = create_response_client()
      
      core.handle_request(
        ctx.engine,
        generate_request_id(),
        client,
        protocol.GetPostComments(valid_id),
      )
      
      json_response(200, json.object([
        #("post_id", json.string(valid_id)),
        #("message", json.string("Comments retrieved")),
      ]))
    }
    Error(errors) -> {
      json_response(400, json.object([
        #("error", json.string("Validation Failed")),
        #("validation_errors", validation_errors_to_json(errors)),
      ]))
    }
  }
}

// ============================================================================
// Vote Handlers with Validation
// ============================================================================

fn vote_handler(req: wisp.Request, ctx: Context) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  let result = {
    use user_id <- result.try(get_string_field(json_body, "user_id"))
    use target_id <- result.try(get_string_field(json_body, "target_id"))
    use vote_type_str <- result.try(get_string_field(json_body, "vote_type"))
    Ok(#(user_id, target_id, vote_type_str))
  }
  
  case result {
    Ok(#(user_id, target_id, vote_type_str)) -> {
      let user_result = validate_user_id(user_id)
      let target_result = validate_id("target_id", target_id)
      let vote_result = validate_vote_type(vote_type_str)
      
      case user_result, target_result, vote_result {
        Ok(valid_user), Ok(valid_target), Ok(valid_vote_str) -> {
          let vote = case valid_vote_str {
            "upvote" -> types.Upvote
            _ -> types.Downvote
          }
          
          let client = create_response_client()
          
          core.handle_request(
            ctx.engine,
            generate_request_id(),
            client,
            protocol.VotePost(valid_user, valid_target, vote),
          )
          
          json_response(200, json.object([
            #("message", json.string("Vote recorded successfully")),
          ]))
        }
        _, _, _ -> {
          let all_errors = []
          let all_errors = case user_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case target_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case vote_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'user_id', 'target_id', 'vote_type' (upvote/downvote)")),
      ]))
    }
  }
}

fn remove_vote_handler(req: wisp.Request, ctx: Context) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  let result = {
    use user_id <- result.try(get_string_field(json_body, "user_id"))
    use target_id <- result.try(get_string_field(json_body, "target_id"))
    Ok(#(user_id, target_id))
  }
  
  case result {
    Ok(#(user_id, target_id)) -> {
      let user_result = validate_user_id(user_id)
      let target_result = validate_id("target_id", target_id)
      
      case user_result, target_result {
        Ok(valid_user), Ok(valid_target) -> {
          let client = create_response_client()
          
          core.handle_request(
            ctx.engine,
            generate_request_id(),
            client,
            protocol.RemoveVote(valid_user, valid_target),
          )
          
          json_response(200, json.object([
            #("message", json.string("Vote removed successfully")),
          ]))
        }
        _, _ -> {
          let all_errors = []
          let all_errors = case user_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case target_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'user_id', 'target_id'")),
      ]))
    }
  }
}

// ============================================================================
// Feed Handlers with Validation
// ============================================================================

fn get_feed_handler(_req: wisp.Request, ctx: Context, user_id: String) -> wisp.Response {
  case validate_user_id(user_id) {
    Ok(valid_id) -> {
      let client = create_response_client()
      
      core.handle_request(
        ctx.engine,
        generate_request_id(),
        client,
        protocol.GetFeed(valid_id, 25),
      )
      
      json_response(200, json.object([
        #("user_id", json.string(valid_id)),
        #("message", json.string("Feed retrieved")),
      ]))
    }
    Error(errors) -> {
      json_response(400, json.object([
        #("error", json.string("Validation Failed")),
        #("validation_errors", validation_errors_to_json(errors)),
      ]))
    }
  }
}

fn get_home_feed_handler(_req: wisp.Request, ctx: Context, user_id: String) -> wisp.Response {
  case validate_user_id(user_id) {
    Ok(valid_id) -> {
      let client = create_response_client()
      
      core.handle_request(
        ctx.engine,
        generate_request_id(),
        client,
        protocol.GetHomeFeed(valid_id, 25),
      )
      
      json_response(200, json.object([
        #("user_id", json.string(valid_id)),
        #("message", json.string("Home feed retrieved")),
      ]))
    }
    Error(errors) -> {
      json_response(400, json.object([
        #("error", json.string("Validation Failed")),
        #("validation_errors", validation_errors_to_json(errors)),
      ]))
    }
  }
}

// ============================================================================
// Message Handlers with Validation
// ============================================================================

fn send_message_handler(req: wisp.Request, ctx: Context) -> wisp.Response {
  use json_body <- wisp.require_json(req)
  
  let result = {
    use from_user_id <- result.try(get_string_field(json_body, "from_user_id"))
    use to_user_id <- result.try(get_string_field(json_body, "to_user_id"))
    use content <- result.try(get_string_field(json_body, "content"))
    Ok(#(from_user_id, to_user_id, content))
  }
  
  case result {
    Ok(#(from_user_id, to_user_id, content)) -> {
      let from_result = validate_user_id(from_user_id)
      let to_result = validate_user_id(to_user_id)
      let content_result = validate_message_content(content)
      
      case from_result, to_result, content_result {
        Ok(valid_from), Ok(valid_to), Ok(valid_content) -> {
          // Check if trying to message self
          case valid_from == valid_to {
            True -> {
              json_response(400, json.object([
                #("error", json.string("Validation Failed")),
                #("message", json.string("Cannot send message to yourself")),
              ]))
            }
            False -> {
              // Send to engine and wait for response
              case send_and_wait_for_response(
                ctx.engine,
                protocol.SendDirectMessage(valid_from, valid_to, valid_content),
                5000,
              ) {
                Ok(protocol.MessageSent(_message)) -> {
                  json_response(201, json.object([
                    #("message", json.string("Message sent successfully")),
                  ]))
                }
                Ok(protocol.Error(error)) -> {
                  let error_msg = case error {
                    protocol.UserNotFound(username) -> "User '" <> username <> "' not found"
                    _ -> "Failed to send message"
                  }
                  json_response(404, json.object([
                    #("error", json.string("Not Found")),
                    #("message", json.string(error_msg)),
                  ]))
                }
                Error(_) -> {
                  json_response(500, json.object([
                    #("error", json.string("Internal Server Error")),
                    #("message", json.string("Request timeout")),
                  ]))
                }
                _ -> {
                  json_response(500, json.object([
                    #("error", json.string("Internal Server Error")),
                    #("message", json.string("Unexpected response")),
                  ]))
                }
              }
            }
          }
        }
        _, _, _ -> {
          let all_errors = []
          let all_errors = case from_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case to_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          let all_errors = case content_result {
            Error(e) -> list.append(all_errors, e)
            _ -> all_errors
          }
          
          json_response(400, json.object([
            #("error", json.string("Validation Failed")),
            #("validation_errors", validation_errors_to_json(all_errors)),
          ]))
        }
      }
    }
    Error(_) -> {
      json_response(400, json.object([
        #("error", json.string("Bad Request")),
        #("message", json.string("Invalid JSON: requires 'from_user_id', 'to_user_id', 'content'")),
      ]))
    }
  }
}

fn get_messages_handler(_req: wisp.Request, ctx: Context, user_id: String) -> wisp.Response {
  case validate_user_id(user_id) {
    Ok(valid_id) -> {
      let client = create_response_client()
      
      core.handle_request(
        ctx.engine,
        generate_request_id(),
        client,
        protocol.GetDirectMessages(valid_id),
      )
      
      json_response(200, json.object([
        #("user_id", json.string(valid_id)),
        #("message", json.string("Messages retrieved")),
      ]))
    }
    Error(errors) -> {
      json_response(400, json.object([
        #("error", json.string("Validation Failed")),
        #("validation_errors", validation_errors_to_json(errors)),
      ]))
    }
  }
}

// ============================================================================
// Health Check Handler
// ============================================================================

fn health_handler(_req: wisp.Request, _ctx: Context) -> wisp.Response {
  json_response(200, json.object([
    #("status", json.string("ok")),
    #("service", json.string("reddit-clone-api")),
    #("version", json.string("1.0.0")),
  ]))
}

// ============================================================================
// Helper Functions
// ============================================================================

fn secret_key(ctx: Context) -> String {
  ctx.secret_key
}

fn generate_request_id() -> String {
  let random = int.random(1_000_000)
  "req_" <> int.to_string(random)
}

fn create_response_client() -> Subject(protocol.EngineResponse) {
  let assert Ok(client) = actor.start(Nil, fn(_response: protocol.EngineResponse, _state) {
    actor.continue(Nil)
  })
  client
}

fn send_and_wait_for_response(
  engine: Subject(core.EngineMessage),
  request: protocol.ClientRequest,
  timeout_ms: Int,
) -> Result(protocol.EngineResponse, Nil) {
  let response_subject = process.new_subject()
  
  core.handle_request(
    engine,
    generate_request_id(),
    response_subject,
    request,
  )
  
  process.new_selector()
  |> process.selecting(response_subject, fn(resp) { resp })
  |> process.select(timeout_ms)
}

fn json_response(status: Int, json_value: json.Json) -> wisp.Response {
  let json_string = json.to_string(json_value)
  
  wisp.response(status)
  |> wisp.set_header("content-type", "application/json")
  |> wisp.set_body(wisp.Text(string_builder.from_string(json_string)))
}

fn get_string_field(json: dynamic.Dynamic, field: String) -> Result(String, Nil) {
  json
  |> dynamic.field(field, dynamic.string)
  |> result.nil_error
}

fn http_method_to_string(method: http.Method) -> String {
  case method {
    http.Get -> "GET"
    http.Post -> "POST"
    http.Put -> "PUT"
    http.Delete -> "DELETE"
    http.Patch -> "PATCH"
    http.Head -> "HEAD"
    http.Options -> "OPTIONS"
    http.Connect -> "CONNECT"
    http.Trace -> "TRACE"
    http.Other(s) -> s
  }
}

fn status_text(code: Int) -> String {
  case code {
    200 -> "OK"
    201 -> "Created"
    204 -> "No Content"
    400 -> "Bad Request"
    401 -> "Unauthorized"
    403 -> "Forbidden"
    404 -> "Not Found"
    500 -> "Internal Server Error"
    _ -> "Status " <> int.to_string(code)
  }
}
