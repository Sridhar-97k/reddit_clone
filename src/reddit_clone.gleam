// reddit_clone.gleam - Main entry point with multiple modes
import argv
import gleam/io
import gleam/int
import gleam/float
import gleam/erlang/process
import gleam/result
import gleam/http
import gleam/http/request
import gleam/json
import gleam/hackney
import engine/core
import client/simulator
import client/simulation_types
import api/server

pub fn main() -> Nil {
  let args = argv.load().arguments
  
  case args {
    // Start HTTP API server
    ["--api"] | ["-a"] -> run_api_mode()
    
    // Start CLI client (interactive mode)
    ["--client"] | ["-c"] -> run_client_mode()
    
    // Run automated demo via CLI client
    ["--demo"] | ["-d"] -> run_demo_mode()
    
    // Large-scale simulation
    ["--large"] | ["-l"] -> run_simulation(simulation_types.large_scale_config())
    
    // Custom configuration
    ["--users", users_str, "--subreddits", subs_str] | 
    ["-u", users_str, "-s", subs_str] -> {
      case parse_custom_config(users_str, subs_str) {
        Ok(config) -> run_simulation(config)
        Error(msg) -> {
          io.println("Error: " <> msg)
          print_usage()
        }
      }
    }
    
    ["--help"] | ["-h"] -> print_usage()
    
    // Default: Run simulation
    [] -> run_simulation(simulation_types.default_config())
    
    _ -> {
      io.println("Error: Unknown arguments")
      print_usage()
    }
  }
}

// ============================================================================
// API Mode - Start HTTP Server
// ============================================================================

fn run_api_mode() -> Nil {
  io.println("
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║        🚀 Reddit Clone - API Server Mode 🚀             ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
")
  
  io.println("📦 Step 1: Starting Reddit Engine...")
  let assert Ok(engine) = core.start()
  io.println("✅ Engine started successfully!")
  io.println("")
  
  io.println("🌐 Step 2: Starting REST API Server...")
  let assert Ok(_) = server.start(engine)
  io.println("")
  
  io.println("
╔══════════════════════════════════════════════════════════╗
║                 System Ready!                            ║
╚══════════════════════════════════════════════════════════╝

🎯 Next Steps:

1. Test the API:
   curl http://localhost:8000/health

2. Run the CLI client (in a new terminal):
   gleam run -- --client

3. Run the automated demo:
   gleam run -- --demo

4. Use curl to test endpoints:
   curl -X POST http://localhost:8000/api/register \\
     -H 'Content-Type: application/json' \\
     -d '{\"username\":\"alice\",\"password\":\"pass123\"}'

═══════════════════════════════════════════════════════════

Server is running. Press Ctrl+C to stop.
")
  
  process.sleep_forever()
}

// ============================================================================
// CLI Client Mode - Interactive Client
// ============================================================================

fn run_client_mode() -> Nil {
  io.println("
╔════════════════════════════════════════╗
║   Reddit Clone CLI Client v1.0         ║
║   Connected to: localhost:8000         ║
╚════════════════════════════════════════╝
")
  
  show_client_menu()
  
  io.println("
Note: This is a demonstration CLI client.
To use it interactively, you would need to implement
an input loop. For now, use these public functions:

  - client_register(\"username\", \"password\")
  - client_create_subreddit(\"name\", \"desc\", \"user_id\")
  - client_create_post(\"author\", \"sub\", \"title\", \"content\")
  - etc.

Or run the automated demo:
  gleam run -- --demo
")
}

fn show_client_menu() {
  io.println("
Available Commands:
─────────────────────────────────────────
USER OPERATIONS:
  register <username> <password>
  login <username> <password>
  get-user <user_id>

SUBREDDIT OPERATIONS:
  create-subreddit <name> <description> <creator_id>
  list-subreddits
  get-subreddit <subreddit_id>
  join-subreddit <user_id> <subreddit_id>

POST OPERATIONS:
  create-post <author_id> <subreddit_id> <title> <content>
  get-post <post_id>

COMMENT OPERATIONS:
  create-comment <author_id> <post_id> <content>

VOTE OPERATIONS:
  vote <user_id> <target_id> <upvote|downvote>

FEED OPERATIONS:
  get-feed <user_id>

MESSAGE OPERATIONS:
  send-message <from_user_id> <to_user_id> <content>
  get-messages <user_id>

OTHER:
  health - Check server health
  demo - Run automated demo
─────────────────────────────────────────
")
}

// ============================================================================
// Demo Mode - Automated Demonstration
// ============================================================================

fn run_demo_mode() -> Nil {
  io.println("
╔════════════════════════════════════════╗
║      Running Automated Demo            ║
╚════════════════════════════════════════╝
")
  
  // Check health
  io.println("\n1️⃣  Checking server health...")
  let _ = client_health()
  process.sleep(500)
  
  // Register users
  io.println("\n2️⃣  Registering users...")
  let _ = client_register("alice", "password123")
  process.sleep(300)
  let _ = client_register("bob", "password456")
  process.sleep(300)
  let _ = client_register("charlie", "password789")
  process.sleep(500)
  
  // Login users
  io.println("\n3️⃣  Logging in users...")
  let _ = client_login("alice", "password123")
  process.sleep(300)
  let _ = client_login("bob", "password456")
  process.sleep(500)
  
  // Create subreddits
  io.println("\n4️⃣  Creating subreddits...")
  let _ = client_create_subreddit("gaming", "For gaming discussions", "user_alice")
  process.sleep(300)
  let _ = client_create_subreddit("technology", "Tech news and discussions", "user_bob")
  process.sleep(500)
  
  // List subreddits
  io.println("\n5️⃣  Listing subreddits...")
  let _ = client_list_subreddits()
  process.sleep(500)
  
  // Join subreddits
  io.println("\n6️⃣  Users joining subreddits...")
  let _ = client_join_subreddit("user_alice", "sub_gaming")
  process.sleep(300)
  let _ = client_join_subreddit("user_bob", "sub_gaming")
  process.sleep(300)
  let _ = client_join_subreddit("user_charlie", "sub_technology")
  process.sleep(500)
  
  // Create posts
  io.println("\n7️⃣  Creating posts...")
  let _ = client_create_post("user_alice", "sub_gaming", "Best RPG of 2024", "What do you think is the best RPG game this year?")
  process.sleep(300)
  let _ = client_create_post("user_bob", "sub_technology", "AI News", "Latest developments in AI technology")
  process.sleep(500)
  
  // Create comments
  io.println("\n8️⃣  Creating comments...")
  let _ = client_create_comment("user_bob", "post_1", "I think Baldur's Gate 3 is amazing!")
  process.sleep(300)
  let _ = client_create_comment("user_charlie", "post_2", "Very interesting article!")
  process.sleep(500)
  
  // Vote on posts
  io.println("\n9️⃣  Voting on posts...")
  let _ = client_vote("user_alice", "post_1", "upvote")
  process.sleep(300)
  let _ = client_vote("user_bob", "post_2", "upvote")
  process.sleep(300)
  let _ = client_vote("user_charlie", "post_1", "downvote")
  process.sleep(500)
  
  // Get feeds
  io.println("\n🔟 Getting user feeds...")
  let _ = client_get_feed("user_alice")
  process.sleep(300)
  let _ = client_get_home_feed("user_bob")
  process.sleep(500)
  
  // Send messages
  io.println("\n1️⃣1️⃣  Sending direct messages...")
  let _ = client_send_message("user_alice", "user_bob", "Hey Bob, great post!")
  process.sleep(300)
  let _ = client_send_message("user_bob", "user_alice", "Thanks Alice!")
  process.sleep(500)
  
  // Get messages
  io.println("\n1️⃣2️⃣  Retrieving messages...")
  let _ = client_get_messages("user_alice")
  process.sleep(500)
  
  io.println("
╔════════════════════════════════════════╗
║       Demo Completed Successfully!     ║
╚════════════════════════════════════════╝
")
}

// ============================================================================
// CLI Client Functions
// ============================================================================

const api_base_url = "http://localhost:8000/api"

pub fn client_register(username: String, password: String) -> Result(String, String) {
  let body = json.object([
    #("username", json.string(username)),
    #("password", json.string(password)),
  ])
  |> json.to_string
  
  case post_request("/register", body) {
    Ok(_resp) -> {
      io.println("✅ User registered successfully!")
      io.println("   Username: " <> username)
      Ok("User registered: " <> username)
    }
    Error(e) -> {
      io.println("❌ Registration failed: " <> e)
      Error(e)
    }
  }
}

pub fn client_login(username: String, password: String) -> Result(String, String) {
  let body = json.object([
    #("username", json.string(username)),
    #("password", json.string(password)),
  ])
  |> json.to_string
  
  case post_request("/login", body) {
    Ok(_resp) -> {
      io.println("✅ Login successful!")
      io.println("   Username: " <> username)
      Ok("Logged in: " <> username)
    }
    Error(e) -> {
      io.println("❌ Login failed: " <> e)
      Error(e)
    }
  }
}

pub fn client_create_subreddit(name: String, description: String, creator_id: String) -> Result(String, String) {
  let body = json.object([
    #("name", json.string(name)),
    #("description", json.string(description)),
    #("creator_id", json.string(creator_id)),
  ])
  |> json.to_string
  
  case post_request("/subreddits", body) {
    Ok(_resp) -> {
      io.println("✅ Subreddit created successfully!")
      io.println("   Name: r/" <> name)
      io.println("   Description: " <> description)
      Ok("Subreddit created: " <> name)
    }
    Error(e) -> {
      io.println("❌ Failed to create subreddit: " <> e)
      Error(e)
    }
  }
}

pub fn client_list_subreddits() -> Result(String, String) {
  case get_request("/subreddits") {
    Ok(resp) -> {
      io.println("✅ Subreddits retrieved")
      Ok(resp)
    }
    Error(e) -> {
      io.println("❌ Failed to list subreddits: " <> e)
      Error(e)
    }
  }
}

pub fn client_join_subreddit(user_id: String, subreddit_id: String) -> Result(String, String) {
  let body = json.object([
    #("user_id", json.string(user_id)),
  ])
  |> json.to_string
  
  case post_request("/subreddits/" <> subreddit_id <> "/join", body) {
    Ok(resp) -> {
      io.println("✅ Joined subreddit successfully!")
      Ok(resp)
    }
    Error(e) -> {
      io.println("❌ Failed to join subreddit: " <> e)
      Error(e)
    }
  }
}

pub fn client_create_post(author_id: String, subreddit_id: String, title: String, content: String) -> Result(String, String) {
  let body = json.object([
    #("author_id", json.string(author_id)),
    #("subreddit_id", json.string(subreddit_id)),
    #("title", json.string(title)),
    #("content", json.string(content)),
  ])
  |> json.to_string
  
  case post_request("/posts", body) {
    Ok(_resp) -> {
      io.println("✅ Post created successfully!")
      io.println("   Title: " <> title)
      Ok("Post created")
    }
    Error(e) -> {
      io.println("❌ Failed to create post: " <> e)
      Error(e)
    }
  }
}

pub fn client_create_comment(author_id: String, post_id: String, content: String) -> Result(String, String) {
  let body = json.object([
    #("author_id", json.string(author_id)),
    #("post_id", json.string(post_id)),
    #("content", json.string(content)),
  ])
  |> json.to_string
  
  case post_request("/comments", body) {
    Ok(_resp) -> {
      io.println("✅ Comment created successfully!")
      Ok("Comment created")
    }
    Error(e) -> {
      io.println("❌ Failed to create comment: " <> e)
      Error(e)
    }
  }
}

pub fn client_vote(user_id: String, target_id: String, vote_type: String) -> Result(String, String) {
  let body = json.object([
    #("user_id", json.string(user_id)),
    #("target_id", json.string(target_id)),
    #("vote_type", json.string(vote_type)),
  ])
  |> json.to_string
  
  case post_request("/vote", body) {
    Ok(_resp) -> {
      io.println("✅ Vote recorded!")
      Ok("Vote recorded")
    }
    Error(e) -> {
      io.println("❌ Failed to vote: " <> e)
      Error(e)
    }
  }
}

pub fn client_get_feed(user_id: String) -> Result(String, String) {
  case get_request("/feed/" <> user_id) {
    Ok(resp) -> {
      io.println("✅ Feed retrieved")
      Ok(resp)
    }
    Error(e) -> {
      io.println("❌ Failed to get feed: " <> e)
      Error(e)
    }
  }
}

pub fn client_get_home_feed(user_id: String) -> Result(String, String) {
  case get_request("/home/" <> user_id) {
    Ok(resp) -> {
      io.println("✅ Home feed retrieved")
      Ok(resp)
    }
    Error(e) -> {
      io.println("❌ Failed to get home feed: " <> e)
      Error(e)
    }
  }
}

pub fn client_send_message(from_user_id: String, to_user_id: String, content: String) -> Result(String, String) {
  let body = json.object([
    #("from_user_id", json.string(from_user_id)),
    #("to_user_id", json.string(to_user_id)),
    #("content", json.string(content)),
  ])
  |> json.to_string
  
  case post_request("/messages", body) {
    Ok(_resp) -> {
      io.println("✅ Message sent!")
      Ok("Message sent")
    }
    Error(e) -> {
      io.println("❌ Failed to send message: " <> e)
      Error(e)
    }
  }
}

pub fn client_get_messages(user_id: String) -> Result(String, String) {
  case get_request("/messages/" <> user_id) {
    Ok(resp) -> {
      io.println("✅ Messages retrieved")
      Ok(resp)
    }
    Error(e) -> {
      io.println("❌ Failed to get messages: " <> e)
      Error(e)
    }
  }
}

pub fn client_health() -> Result(String, String) {
  case get_request("/../health") {
    Ok(resp) -> {
      io.println("✅ Server is healthy!")
      io.println(resp)
      Ok(resp)
    }
    Error(e) -> {
      io.println("❌ Server health check failed: " <> e)
      Error(e)
    }
  }
}

// ============================================================================
// HTTP Request Helpers
// ============================================================================

fn get_request(path: String) -> Result(String, String) {
  let url = api_base_url <> path
  
  case request.to(url) {
    Ok(req) -> {
      case hackney.send(req) {
        Ok(resp) -> {
          case resp.status {
            200 | 201 -> Ok(resp.body)
            _ -> Error("HTTP " <> int.to_string(resp.status) <> ": " <> resp.body)
          }
        }
        Error(_) -> Error("Failed to send request")
      }
    }
    Error(_) -> Error("Invalid URL")
  }
}

fn post_request(path: String, body: String) -> Result(String, String) {
  let url = api_base_url <> path
  
  case request.to(url) {
    Ok(req) -> {
      let req = request.set_method(req, http.Post)
      let req = request.set_body(req, body)
      let req = request.set_header(req, "content-type", "application/json")
      
      case hackney.send(req) {
        Ok(resp) -> {
          case resp.status {
            200 | 201 -> Ok(resp.body)
            _ -> Error("HTTP " <> int.to_string(resp.status) <> ": " <> resp.body)
          }
        }
        Error(_) -> Error("Failed to send request")
      }
    }
    Error(_) -> Error("Invalid URL")
  }
}

// ============================================================================
// Simulation Mode
// ============================================================================

fn run_simulation(config: simulation_types.SimulationConfig) -> Nil {
  io.println("🎮 Reddit Clone - Distributed System Simulation")
  io.println("================================================\n")
  io.println("📋 Configuration:")
  io.println("   Users: " <> int.to_string(config.num_users))
  io.println("   Subreddits: " <> int.to_string(config.num_subreddits))
  io.println("   Zipf Skewness: " <> float_to_string(config.zipf_skewness))
  io.println("")
  
  io.println("🔧 Starting Reddit Engine...")
  let assert Ok(engine) = core.start()
  io.println("✅ Engine started successfully\n")
  
  io.println("🎬 Starting Simulator...")
  let assert Ok(sim) = simulator.start(engine, config)
  io.println("✅ Simulator ready\n")
  
  simulator.start_simulation(sim)
  
  let sleep_time = case config.num_users {
    n if n > 500 -> 10_000
    n if n > 100 -> 7000
    _ -> 5000
  }
  
  process.sleep(sleep_time)
  io.println("\n🎉 Simulation completed successfully!")
}

// ============================================================================
// Helper Functions
// ============================================================================

fn parse_custom_config(
  users_str: String,
  subs_str: String,
) -> Result(simulation_types.SimulationConfig, String) {
  use users <- result.try(
    int.parse(users_str)
    |> result.replace_error("Invalid user count")
  )
  use subs <- result.try(
    int.parse(subs_str)
    |> result.replace_error("Invalid subreddit count")
  )
  
  Ok(simulation_types.SimulationConfig(
    num_users: users,
    num_subreddits: subs,
    zipf_skewness: 1.0,
    simulation_duration_seconds: 120,
    actions_per_user: 15,
    connection_cycle_seconds: 20,
  ))
}

fn print_usage() -> Nil {
  io.println("
╔════════════════════════════════════════════════════════════╗
║          Reddit Clone - Usage Instructions                 ║
╚════════════════════════════════════════════════════════════╝

Usage: gleam run [-- options]

Options:
  (no args)                    Default simulation (50 users, 10 subreddits)
  -a, --api                    Start HTTP API server
  -c, --client                 Start CLI client (interactive)
  -d, --demo                   Run automated demo
  -l, --large                  Large-scale simulation (1000 users, 50 subreddits)
  -u <n> -s <n>               Custom users and subreddits
  --users <n> --subreddits <n> Custom users and subreddits
  -h, --help                   Show this help message

Examples:
  gleam run                    # Run default simulation
  gleam run -- --api           # Start API server
  gleam run -- --demo          # Run automated demo
  gleam run -- --client        # Start CLI client
  gleam run -- --large         # Large scale simulation
  gleam run -- -u 200 -s 20    # Custom configuration

Typical Workflow:
  1. Terminal 1: gleam run -- --api     (Start server)
  2. Terminal 2: gleam run -- --demo    (Run demo)
  3. Terminal 3: gleam run -- --demo    (Run another demo)
  
This demonstrates multiple clients connecting to the same server!
")
}

fn float_to_string(f: Float) -> String {
  case f {
    1.0 -> "1.0"
    1.5 -> "1.5"
    2.0 -> "2.0"
    _ -> int.to_string(float.round(f))
  }
}
