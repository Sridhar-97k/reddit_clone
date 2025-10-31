// Advanced version with argv package
import argv
import gleam/io
import gleam/int
import gleam/float
import gleam/erlang/process
import gleam/result
import engine/core
import client/simulator
import client/simulation_types

pub fn main() -> Nil {
  let config = case parse_args() {
    Ok(cfg) -> cfg
    Error(msg) -> {
      io.println("Error: " <> msg)
      print_usage()
      simulation_types.default_config()
    }
  }
  
  run_simulation(config)
}

type ConfigMode {
  Default
  LargeScale
  Custom(users: Int, subreddits: Int)
}

fn parse_args() -> Result(simulation_types.SimulationConfig, String) {
  let args = argv.load().arguments
  
  case args {
    [] -> Ok(simulation_types.default_config())
    
    ["--large"] | ["-l"] -> 
      Ok(simulation_types.large_scale_config())
    
    ["--users", users_str, "--subreddits", subs_str] | 
    ["-u", users_str, "-s", subs_str] -> {
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
    
    ["--help"] | ["-h"] -> {
      print_usage()
      Error("Help requested")
    }
    
    _ -> Error("Unknown arguments")
  }
}

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

fn print_usage() -> Nil {
  io.println("Usage: gleam run [options]")
  io.println("")
  io.println("Options:")
  io.println("  (no args)                    Default simulation (50 users, 10 subreddits)")
  io.println("  -l, --large                  Large-scale (1000 users, 50 subreddits)")
  io.println("  -u <n> -s <n>               Custom users and subreddits")
  io.println("  --users <n> --subreddits <n> Custom users and subreddits")
  io.println("  -h, --help                   Show this help message")
  io.println("")
  io.println("Examples:")
  io.println("  gleam run")
  io.println("  gleam run --large")
  io.println("  gleam run -u 200 -s 20")
  io.println("  gleam run --users 500 --subreddits 30")
}

fn float_to_string(f: Float) -> String {
  case f {
    1.0 -> "1.0"
    1.5 -> "1.5"
    2.0 -> "2.0"
    _ -> int.to_string(float.round(f))
  }
}