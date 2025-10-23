// Feed Generator - Enhanced feed generation with multiple algorithms
import gleam/dict.{type Dict}
import gleam/list
import gleam/int
import gleam/option.{None, Some}
// import shared/types.{type Feed, type FeedItem, type Id, type Post, type Subreddit, Feed, FeedItem}
import shared/types.{type Feed, type FeedItem, type Id, type Post, type Subreddit, Feed, FeedItem, Subreddit}
import shared/utils

// ============================================================================
// Feed Types
// ============================================================================

pub type FeedAlgorithm {
  Hot
  New
  Top
  Rising
}

pub type FeedConfig {
  FeedConfig(
    algorithm: FeedAlgorithm,
    limit: Int,
    time_window_hours: Int,
  )
}

// ============================================================================
// Feed Generation
// ============================================================================

/// Generate a personalized feed for a user based on their subscriptions
pub fn generate_user_feed(
  posts: List(Post),
  subreddits: Dict(Id, Subreddit),
  subscribed_subreddit_ids: List(Id),
  config: FeedConfig,
) -> Feed {
  // Filter posts from subscribed subreddits
  let filtered_posts = case list.is_empty(subscribed_subreddit_ids) {
    True -> posts // If no subscriptions, show all posts
    False ->
      list.filter(posts, fn(post) {
        list.contains(subscribed_subreddit_ids, post.subreddit_id)
      })
  }

  // Apply sorting algorithm
  let sorted_posts = case config.algorithm {
    Hot -> sort_by_hot(filtered_posts)
    New -> utils.sort_posts_by_new(filtered_posts)
    Top -> utils.sort_posts_by_top(filtered_posts)
    Rising -> sort_by_rising(filtered_posts)
  }

  // Apply limit
  let limited_posts = list.take(sorted_posts, config.limit)

  // Create feed items with subreddit info
  let feed_items =
    list.map(limited_posts, fn(post) {
      let subreddit = case dict.get(subreddits, post.subreddit_id) {
        Ok(sub) -> sub
        Error(_) ->
          Subreddit(
            id: post.subreddit_id,
            name: post.subreddit_name,
            description: "",
            created_by: "",
            created_at: 0,
            member_count: 0,
            post_count: 0,
          )
      }
      FeedItem(post: post, subreddit: subreddit)
    })

  Feed(items: feed_items, generated_at: utils.get_current_timestamp())
}

/// Generate a feed for a specific subreddit
pub fn generate_subreddit_feed(
  posts: List(Post),
  subreddit: Subreddit,
  config: FeedConfig,
) -> Feed {
  // Filter posts from this subreddit
  let subreddit_posts =
    list.filter(posts, fn(post) { post.subreddit_id == subreddit.id })

  // Apply sorting algorithm
  let sorted_posts = case config.algorithm {
    Hot -> sort_by_hot(subreddit_posts)
    New -> utils.sort_posts_by_new(subreddit_posts)
    Top -> utils.sort_posts_by_top(subreddit_posts)
    Rising -> sort_by_rising(subreddit_posts)
  }

  // Apply limit
  let limited_posts = list.take(sorted_posts, config.limit)

  // Create feed items
  let feed_items =
    list.map(limited_posts, fn(post) {
      FeedItem(post: post, subreddit: subreddit)
    })

  Feed(items: feed_items, generated_at: utils.get_current_timestamp())
}

// ============================================================================
// Sorting Algorithms
// ============================================================================

/// Sort by Hot - Reddit's hot algorithm
/// score = log10(max(|ups - downs|, 1)) + sign(ups - downs) * seconds / 45000
fn sort_by_hot(posts: List(Post)) -> List(Post) {
  list.sort(posts, fn(a, b) {
    let score_a = calculate_hot_score(a)
    let score_b = calculate_hot_score(b)
    int.compare(score_b, score_a)
  })
}

fn calculate_hot_score(post: Post) -> Int {
  let score = post.upvotes - post.downvotes
  let abs_score = int.absolute_value(score)
  let order = log10_approximation(int.max(abs_score, 1))
  
  let sign = case score {
    s if s > 0 -> 1
    s if s < 0 -> -1
    _ -> 0
  }

  let current_time = utils.get_current_timestamp()
  let age_seconds = { current_time - post.created_at } / 1000
  
  // Simplified: order * 10000 + sign * (age_penalty)
  let age_penalty = age_seconds / 45_000
  
  order * 10_000 + sign * 1000 - age_penalty
}

/// Sort by Rising - Recent posts with growing engagement
fn sort_by_rising(posts: List(Post)) -> List(Post) {
  list.sort(posts, fn(a, b) {
    let score_a = calculate_rising_score(a)
    let score_b = calculate_rising_score(b)
    int.compare(score_b, score_a)
  })
}

fn calculate_rising_score(post: Post) -> Int {
  let current_time = utils.get_current_timestamp()
  let age_hours = { current_time - post.created_at } / 3_600_000
  
  // Only consider posts less than 24 hours old
  case age_hours > 24 {
    True -> 0
    False -> {
      let score = post.upvotes - post.downvotes
      let engagement = post.comment_count + score
      
      // Rising score: engagement / (age_hours + 1)
      case age_hours > 0 {
        True -> { engagement * 100 } / { age_hours + 1 }
        False -> engagement * 100
      }
    }
  }
}

// ============================================================================
// Filtering
// ============================================================================

/// Filter posts within a time window
pub fn filter_by_time_window(posts: List(Post), hours: Int) -> List(Post) {
  let current_time = utils.get_current_timestamp()
  let cutoff_time = current_time - { hours * 3_600_000 }
  
  list.filter(posts, fn(post) { post.created_at >= cutoff_time })
}

/// Filter posts by minimum score
pub fn filter_by_min_score(posts: List(Post), min_score: Int) -> List(Post) {
  list.filter(posts, fn(post) {
    let score = post.upvotes - post.downvotes
    score >= min_score
  })
}

/// Filter out posts from blocked users
pub fn filter_blocked_users(
  posts: List(Post),
  blocked_user_ids: List(Id),
) -> List(Post) {
  list.filter(posts, fn(post) {
    !list.contains(blocked_user_ids, post.author_id)
  })
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Approximate log10 for integer values (used in hot score)
fn log10_approximation(n: Int) -> Int {
  case n {
    x if x < 10 -> 0
    x if x < 100 -> 1
    x if x < 1000 -> 2
    x if x < 10_000 -> 3
    x if x < 100_000 -> 4
    x if x < 1_000_000 -> 5
    _ -> 6
  }
}

/// Create default feed config
pub fn default_config() -> FeedConfig {
  FeedConfig(algorithm: Hot, limit: 25, time_window_hours: 24)
}

pub fn hot_config(limit: Int) -> FeedConfig {
  FeedConfig(algorithm: Hot, limit: limit, time_window_hours: 24)
}

pub fn new_config(limit: Int) -> FeedConfig {
  FeedConfig(algorithm: New, limit: limit, time_window_hours: 24)
}

pub fn top_config(limit: Int, time_window_hours: Int) -> FeedConfig {
  FeedConfig(algorithm: Top, limit: limit, time_window_hours: time_window_hours)
}

pub fn rising_config(limit: Int) -> FeedConfig {
  FeedConfig(algorithm: Rising, limit: limit, time_window_hours: 24)
}