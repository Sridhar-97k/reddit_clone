
// Domain models for the Reddit Clone
import gleam/dict.{type Dict}
import gleam/option.{type Option}

// ============================================================================
// Core Domain Types
// ============================================================================

/// Unique identifier type
pub type Id =
  String

/// Unix timestamp in milliseconds
pub type Timestamp =
  Int

// ============================================================================
// User Types
// ============================================================================

pub type User {
  User(
    id: Id,
    username: String,
    password_hash: String,
    karma: Int,
    joined_at: Timestamp,
    subscribed_subreddits: List(Id),
  )
}

pub type UserProfile {
  UserProfile(id: Id, username: String, karma: Int, joined_at: Timestamp)
}

// ============================================================================
// Subreddit Types
// ============================================================================

pub type Subreddit {
  Subreddit(
    id: Id,
    name: String,
    description: String,
    created_by: Id,
    created_at: Timestamp,
    member_count: Int,
    post_count: Int,
  )
}

// ============================================================================
// Post Types
// ============================================================================

pub type Post {
  Post(
    id: Id,
    author_id: Id,
    author_username: String,
    subreddit_id: Id,
    subreddit_name: String,
    title: String,
    content: String,
    upvotes: Int,
    downvotes: Int,
    comment_count: Int,
    created_at: Timestamp,
    is_repost: Bool,
    original_post_id: Option(Id),
  )
}

// ============================================================================
// Comment Types (Hierarchical)
// ============================================================================

pub type Comment {
  Comment(
    id: Id,
    author_id: Id,
    author_username: String,
    post_id: Id,
    parent_comment_id: Option(Id),
    content: String,
    upvotes: Int,
    downvotes: Int,
    depth: Int,
    created_at: Timestamp,
    children: List(Id),
  )
}

// ============================================================================
// Voting Types
// ============================================================================

pub type VoteType {
  Upvote
  Downvote
}

pub type Vote {
  Vote(user_id: Id, target_id: Id, vote_type: VoteType, created_at: Timestamp)
}

pub type VoteTarget {
  PostVote(post_id: Id)
  CommentVote(comment_id: Id)
}

// ============================================================================
// Direct Message Types
// ============================================================================

pub type DirectMessage {
  DirectMessage(
    id: Id,
    from_user_id: Id,
    from_username: String,
    to_user_id: Id,
    to_username: String,
    content: String,
    created_at: Timestamp,
    read: Bool,
  )
}

// ============================================================================
// Feed Types
// ============================================================================

pub type FeedItem {
  FeedItem(post: Post, subreddit: Subreddit)
}

pub type Feed {
  Feed(items: List(FeedItem), generated_at: Timestamp)
}

// ============================================================================
// Connection Status
// ============================================================================

pub type ConnectionStatus {
  Connected
  Disconnected
}

pub type UserConnection {
  UserConnection(
    user_id: Id,
    status: ConnectionStatus,
    connected_at: Option(Timestamp),
    disconnected_at: Option(Timestamp),
  )
}

// ============================================================================
// Statistics and Metrics
// ============================================================================

pub type UserStats {
  UserStats(
    user_id: Id,
    post_count: Int,
    comment_count: Int,
    total_upvotes: Int,
    total_downvotes: Int,
    karma: Int,
  )
}

pub type SubredditStats {
  SubredditStats(
    subreddit_id: Id,
    member_count: Int,
    post_count: Int,
    total_votes: Int,
    active_users: Int,
  )
}