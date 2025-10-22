// Communication protocol between Client and Engine
import gleam/option.{type Option}
import shared/types.{
  type Comment, type DirectMessage, type Feed, type Id, type Post,
  type Subreddit, type Timestamp, type UserProfile, type VoteType,
}

// ============================================================================
// Client → Engine (Requests/Commands)
// ============================================================================

pub type ClientRequest {
  // User Operations
  RegisterUser(username: String, password: String)
  LoginUser(username: String, password: String)
  GetUserProfile(user_id: Id)
  
  // Subreddit Operations
  CreateSubreddit(name: String, description: String, creator_id: Id)
  JoinSubreddit(user_id: Id, subreddit_id: Id)
  LeaveSubreddit(user_id: Id, subreddit_id: Id)
  GetSubreddit(subreddit_id: Id)
  ListSubreddits
  
  // Post Operations
  CreatePost(
    author_id: Id,
    subreddit_id: Id,
    title: String,
    content: String,
    is_repost: Bool,
    original_post_id: Option(Id),
  )
  GetPost(post_id: Id)
  GetSubredditPosts(subreddit_id: Id, limit: Int)
  DeletePost(post_id: Id, user_id: Id)
  
  // Comment Operations
  CreateComment(
    author_id: Id,
    post_id: Id,
    parent_comment_id: Option(Id),
    content: String,
  )
  GetPostComments(post_id: Id)
  GetComment(comment_id: Id)
  DeleteComment(comment_id: Id, user_id: Id)
  
  // Voting Operations
  VotePost(user_id: Id, post_id: Id, vote_type: VoteType)
  VoteComment(user_id: Id, comment_id: Id, vote_type: VoteType)
  RemoveVote(user_id: Id, target_id: Id)
  
  // Feed Operations
  GetFeed(user_id: Id, limit: Int)
  GetHomeFeed(user_id: Id, limit: Int)
  
  // Direct Message Operations
  SendDirectMessage(from_user_id: Id, to_user_id: Id, content: String)
  GetDirectMessages(user_id: Id)
  MarkMessageAsRead(user_id: Id, message_id: Id)
  
  // Connection Management
  Connect(user_id: Id)
  Disconnect(user_id: Id)
  Heartbeat(user_id: Id)
}

// ============================================================================
// Engine → Client (Responses)
// ============================================================================

pub type EngineResponse {
  // Success Responses
  UserRegistered(user_id: Id, username: String)
  UserLoggedIn(user_id: Id, username: String, karma: Int)
  UserProfileResponse(profile: UserProfile)
  
  SubredditCreated(subreddit: Subreddit)
  SubredditJoined(subreddit_id: Id, user_id: Id)
  SubredditLeft(subreddit_id: Id, user_id: Id)
  SubredditResponse(subreddit: Subreddit)
  SubredditListResponse(subreddits: List(Subreddit))
  
  PostCreated(post: Post)
  PostResponse(post: Post)
  PostsResponse(posts: List(Post))
  PostDeleted(post_id: Id)
  
  CommentCreated(comment: Comment)
  CommentResponse(comment: Comment)
  CommentsResponse(comments: List(Comment))
  CommentDeleted(comment_id: Id)
  
  VoteRecorded(target_id: Id, new_score: Int, user_karma: Int)
  VoteRemoved(target_id: Id, new_score: Int)
  
  FeedResponse(feed: Feed)
  
  MessageSent(message: DirectMessage)
  MessagesResponse(messages: List(DirectMessage))
  MessageMarkedRead(message_id: Id)
  
  Connected(user_id: Id, timestamp: Timestamp)
  Disconnected(user_id: Id, timestamp: Timestamp)
  HeartbeatAck(user_id: Id, timestamp: Timestamp)
  
  // Error Responses
  Error(error: EngineError)
  
  // Notifications (Push from Engine)
  NewPostNotification(post: Post)
  NewCommentNotification(comment: Comment)
  NewDirectMessageNotification(message: DirectMessage)
}

// ============================================================================
// Error Types
// ============================================================================

pub type EngineError {
  // User Errors
  UserNotFound(user_id: Id)
  UsernameAlreadyExists(username: String)
  InvalidCredentials
  Unauthorized(user_id: Id, action: String)
  
  // Subreddit Errors
  SubredditNotFound(subreddit_id: Id)
  SubredditNameAlreadyExists(name: String)
  AlreadySubscribed(user_id: Id, subreddit_id: Id)
  NotSubscribed(user_id: Id, subreddit_id: Id)
  
  // Post Errors
  PostNotFound(post_id: Id)
  InvalidPost(reason: String)
  
  // Comment Errors
  CommentNotFound(comment_id: Id)
  InvalidComment(reason: String)
  ParentCommentNotFound(parent_id: Id)
  
  // Vote Errors
  AlreadyVoted(user_id: Id, target_id: Id)
  VoteNotFound(user_id: Id, target_id: Id)
  CannotVoteOwnContent(user_id: Id)
  
  // Direct Message Errors
  MessageNotFound(message_id: Id)
  CannotMessageSelf(user_id: Id)
  
  // Generic Errors
  InvalidRequest(reason: String)
  InternalError(message: String)
}

// ============================================================================
// Message Envelope (for process communication)
// ============================================================================

pub type Message {
  Request(request_id: String, from_pid: String, request: ClientRequest)
  Response(request_id: String, to_pid: String, response: EngineResponse)
}