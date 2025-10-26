// File Writer - Writes reports to disk
import gleam/result
import gleam/io

// ============================================================================
// File Writing via Erlang FFI
// ============================================================================

/// Write content to a file
pub fn write_file(filename: String, content: String) -> Result(Nil, String) {
  case erlang_write_file(filename, content) {
    Ok(_) -> {
      io.println("📄 Report saved to: " <> filename)
      Ok(Nil)
    }
    Error(reason) -> {
      io.println("❌ Failed to write file: " <> reason)
      Error(reason)
    }
  }
}

/// Write file with timestamp
pub fn write_timestamped_report(content: String) -> Result(Nil, String) {
  let filename = "PERFORMANCE_REPORT.md"
  write_file(filename, content)
}

// ============================================================================
// Erlang FFI
// ============================================================================

@external(erlang, "file", "write_file")
fn erlang_write_file(filename: String, content: String) -> Result(String, String)