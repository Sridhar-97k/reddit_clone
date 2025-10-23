// Main entry point for Reddit Clone simulation
import gleam/io
import gleam/erlang/process
import engine/core
import client/simulator

pub fn main() -> Nil {
  io.println("🎮 Reddit Clone - Distributed System Simulation")
  io.println("================================================\n")
  
  // Start the engine
  io.println("🔧 Starting Reddit Engine...")
  let assert Ok(engine) = core.start()
  io.println("✅ Engine started successfully\n")
  
  // Create simulation config
  let config = simulator.default_config()
  
  // Start simulator
  io.println("🎬 Starting Simulator...")
  let assert Ok(sim) = simulator.start(engine, config)
  io.println("✅ Simulator ready\n")
  
  // Run simulation
  simulator.start_simulation(sim)
  
  // Keep main process alive to observe results
  process.sleep(5000)
  
  io.println("\n🎉 Simulation completed successfully!")
}

// Alternative: Run large-scale simulation
pub fn main_large_scale() -> Nil {
  io.println("🎮 Reddit Clone - Large Scale Simulation")
  io.println("=========================================\n")
  
  io.println("⚠️  WARNING: This will simulate 1000+ users")
  io.println("    Press Ctrl+C to cancel within 3 seconds...\n")
  process.sleep(3000)
  
  // Start engine
  io.println("🔧 Starting Reddit Engine...")
  let assert Ok(engine) = core.start()
  io.println("✅ Engine started\n")
  
  // Large scale config
  let config = simulator.large_scale_config()
  
  // Start simulator
  io.println("🎬 Starting Large Scale Simulator...")
  let assert Ok(sim) = simulator.start(engine, config)
  
  // Run simulation
  simulator.start_simulation(sim)
  
  // Keep alive
  process.sleep(10_000)
  
  io.println("\n🎉 Large scale simulation completed!")
}

// Custom configuration simulation
pub fn main_custom(num_users: Int, num_subreddits: Int) -> Nil {
  io.println("🎮 Reddit Clone - Custom Simulation")
  io.println("====================================\n")
  
  // Start engine
  let assert Ok(engine) = core.start()
  
  // Custom config
  let config = simulator.SimulationConfig(
    num_users: num_users,
    num_subreddits: num_subreddits,
    zipf_skewness: 1.0,
    simulation_duration_seconds: 120,
    actions_per_user: 15,
    connection_cycle_seconds: 20,
  )
  
  let assert Ok(sim) = simulator.start(engine, config)
  simulator.start_simulation(sim)
  
  process.sleep(8000)
  io.println("\n✅ Custom simulation completed!")
}