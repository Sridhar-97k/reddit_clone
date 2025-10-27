// Utility functions for the Reddit Clone
import gleam/int
import gleam/list
import gleam/string
import gleam/option
import shared/types.{type Comment, type Id, type Post, type Timestamp}

// ============================================================================
// ID Generation
// ============================================================================

/// Generate a unique ID using timestamp + random component
pub fn generate_id(prefix: String) -> Id {
  let timestamp = get_current_timestamp()
  let random = int.random(1_000_000)
  prefix <> "_" <> int.to_string(timestamp) <> "_" <> int.to_string(random)
}

pub fn generate_user_id() -> Id {
  generate_id("user")
}

pub fn generate_subreddit_id() -> Id {
  generate_id("sub")
}

pub fn generate_post_id() -> Id {
  generate_id("post")
}

pub fn generate_comment_id() -> Id {
  generate_id("comment")
}

pub fn generate_message_id() -> Id {
  generate_id("msg")
}

pub fn generate_request_id() -> Id {
  generate_id("req")
}

// ============================================================================
// Timestamp Utilities - FIXED!
// ============================================================================

/// Get current timestamp in milliseconds using Erlang system_time
pub fn get_current_timestamp() -> Timestamp {
  erlang_system_time_millisecond()
}

/// Calculate time difference in seconds
pub fn time_diff_seconds(start: Timestamp, end: Timestamp) -> Int {
  { end - start } / 1000
}

// ============================================================================
// Erlang FFI for System Time
// ============================================================================

// Call erlang:system_time(millisecond) directly
// The Erlang function signature is: system_time(Unit) -> integer()
// where Unit can be: second | millisecond | microsecond | nanosecond
@external(erlang, "erlang", "system_time")
fn erlang_system_time(unit: ErlangTimeUnit) -> Int

// Erlang time unit type (we'll pass millisecond as an atom)
type ErlangTimeUnit

// Create the millisecond atom for Erlang
@external(erlang, "shared_ffi", "millisecond_unit")
fn millisecond_unit() -> ErlangTimeUnit

fn erlang_system_time_millisecond() -> Int {
  erlang_system_time(millisecond_unit())
}

// ============================================================================
// Karma Calculation
// ============================================================================

/// Calculate karma from upvotes and downvotes
pub fn calculate_karma(upvotes: Int, downvotes: Int) -> Int {
  upvotes - downvotes
}

/// Calculate post score (for ranking)
pub fn calculate_post_score(post: Post) -> Int {
  calculate_karma(post.upvotes, post.downvotes)
}

/// Calculate comment score
pub fn calculate_comment_score(comment: Comment) -> Int {
  calculate_karma(comment.upvotes, comment.downvotes)
}

/// Calculate total user karma from all posts and comments
pub fn calculate_user_karma(
  post_upvotes: Int,
  post_downvotes: Int,
  comment_upvotes: Int,
  comment_downvotes: Int,
) -> Int {
  calculate_karma(post_upvotes, post_downvotes)
  + calculate_karma(comment_upvotes, comment_downvotes)
}

// ============================================================================
// Comment Tree Utilities
// ============================================================================

/// Calculate comment depth (0 for top-level comments)
pub fn calculate_comment_depth(parent_depth: Int) -> Int {
  parent_depth + 1
}

/// Check if comment is top-level (no parent)
pub fn is_top_level_comment(comment: Comment) -> Bool {
  case comment.parent_comment_id {
    option.None -> True
    option.Some(_) -> False
  }
}

// ============================================================================
// Validation Utilities
// ============================================================================

/// Validate username (alphanumeric, 3-20 characters)
pub fn validate_username(username: String) -> Result(String, String) {
  let length = string.length(username)
  case length >= 3 && length <= 20 {
    True -> Ok(username)
    False -> Error("Username must be between 3 and 20 characters")
  }
}

/// Validate subreddit name (alphanumeric + underscores, 3-21 characters)
pub fn validate_subreddit_name(name: String) -> Result(String, String) {
  let length = string.length(name)
  case length >= 3 && length <= 21 {
    True -> Ok(name)
    False -> Error("Subreddit name must be between 3 and 21 characters")
  }
}

/// Validate post title (not empty, max 300 characters)
pub fn validate_post_title(title: String) -> Result(String, String) {
  let trimmed = string.trim(title)
  let length = string.length(trimmed)
  case length > 0 && length <= 300 {
    True -> Ok(trimmed)
    False -> Error("Post title must be between 1 and 300 characters")
  }
}

/// Validate post content (max 40,000 characters)
pub fn validate_post_content(content: String) -> Result(String, String) {
  let length = string.length(content)
  case length <= 40_000 {
    True -> Ok(content)
    False -> Error("Post content must not exceed 40,000 characters")
  }
}

/// Validate comment content (not empty, max 10,000 characters)
pub fn validate_comment_content(content: String) -> Result(String, String) {
  let trimmed = string.trim(content)
  let length = string.length(trimmed)
  case length > 0 && length <= 10_000 {
    True -> Ok(trimmed)
    False -> Error("Comment must be between 1 and 10,000 characters")
  }
}

// ============================================================================
// Sorting Utilities
// ============================================================================

/// Sort posts by score (hot algorithm)
pub fn sort_posts_by_hot(posts: List(Post)) -> List(Post) {
  list.sort(posts, fn(a, b) {
    let score_a = calculate_hot_score(a)
    let score_b = calculate_hot_score(b)
    int.compare(score_b, score_a)
  })
}

/// Sort posts by newest first
pub fn sort_posts_by_new(posts: List(Post)) -> List(Post) {
  list.sort(posts, fn(a, b) { int.compare(b.created_at, a.created_at) })
}

/// Sort posts by top score
pub fn sort_posts_by_top(posts: List(Post)) -> List(Post) {
  list.sort(posts, fn(a, b) {
    let score_a = calculate_post_score(a)
    let score_b = calculate_post_score(b)
    int.compare(score_b, score_a)
  })
}

/// Calculate "hot" score (Reddit's hot algorithm simplified)
fn calculate_hot_score(post: Post) -> Int {
  let score = calculate_post_score(post)
  let abs_score = int.absolute_value(score)
  let max_score = int.max(abs_score, 1)
  let age_seconds = time_diff_seconds(post.created_at, get_current_timestamp())
  let age_hours = age_seconds / 3600
  
  // Simplified: just use score - (age in hours)
  max_score - { age_hours / 2 }
}

// ============================================================================
// String Utilities
// ============================================================================

/// Truncate string to max length with ellipsis
pub fn truncate(text: String, max_length: Int) -> String {
  case string.length(text) > max_length {
    True -> string.slice(text, 0, max_length - 3) <> "..."
    False -> text
  }
}

/// Create a preview of content (first 100 characters)
pub fn create_preview(content: String) -> String {
  truncate(content, 100)
}