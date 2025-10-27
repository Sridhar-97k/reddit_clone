// File Writer - Writes reports to disk
import gleam/dynamic
import gleam/result
import gleam/io

// ============================================================================
// File Writing via Erlang FFI
// ============================================================================

/// Write content to a file
pub fn write_file(filename: String, content: String) -> Result(Nil, String) {
  // Erlang file:write_file returns 'ok' or {error, Reason}
  case erlang_write_file(filename, content) {
    True -> {
      io.println("📄 Report saved to: " <> filename)
      Ok(Nil)
    }
    False -> {
      let msg = "Failed to write file"
      io.println("❌ " <> msg)
      Error(msg)
    }
  }
}

/// Write file with timestamp
pub fn write_timestamped_report(content: String) -> Result(Nil, String) {
  let filename = "PERFORMANCE_REPORT.md"
  write_file(filename, content)
}

// ============================================================================
// Erlang FFI - Returns True if successful, False if error
// ============================================================================

@external(erlang, "engine_ffi", "write_file")
fn erlang_write_file(filename: String, content: String) -> Bool