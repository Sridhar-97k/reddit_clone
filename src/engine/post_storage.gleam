// Post Storage - Manages posts and comments
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import shared/protocol.{type EngineResponse}
import shared/types.{type Comment, type Feed, type Id, type Post, Comment, Feed, FeedItem, Post}
import shared/utils

// ============================================================================
// State
// ============================================================================

pub type PostStorageState {
  PostStorageState(
    posts: Dict(Id, Post),
    comments: Dict(Id, Comment),
    post_comments: Dict(Id, List(Id)),
    subreddit_posts: Dict(Id, List(Id)),
  )
}

// ============================================================================
// Messages
// ============================================================================

pub type PostStorageMessage {
  CreatePost(
    client: Subject(EngineResponse),
    author_id: Id,
    subreddit_id: Id,
    title: String,
    content: String,
    is_repost: Bool,
    original_post_id: Option(Id),
  )
  GetPost(client: Subject(EngineResponse), post_id: Id)
  GetSubredditPosts(client: Subject(EngineResponse), subreddit_id: Id, limit: Int)
  DeletePost(client: Subject(EngineResponse), post_id: Id, user_id: Id)
  CreateComment(
    client: Subject(EngineResponse),
    author_id: Id,
    post_id: Id,
    parent_comment_id: Option(Id),
    content: String,
  )
  GetComment(client: Subject(EngineResponse), comment_id: Id)
  GetPostComments(client: Subject(EngineResponse), post_id: Id)
  DeleteComment(client: Subject(EngineResponse), comment_id: Id, user_id: Id)
  UpdatePostVotes(post_id: Id, upvotes: Int, downvotes: Int)
  UpdateCommentVotes(comment_id: Id, upvotes: Int, downvotes: Int)
  GetFeed(client: Subject(EngineResponse), user_id: Id, limit: Int)
  GetHomeFeed(client: Subject(EngineResponse), user_id: Id, limit: Int)
}

// ============================================================================
// API
// ============================================================================

pub fn start() -> Result(Subject(PostStorageMessage), actor.StartError) {
  actor.start(init_state, handle_message)
}

pub fn create_post(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  author_id: Id,
  subreddit_id: Id,
  title: String,
  content: String,
  is_repost: Bool,
  original_post_id: Option(Id),
) -> Nil {
  process.send(
    storage,
    CreatePost(
      client,
      author_id,
      subreddit_id,
      title,
      content,
      is_repost,
      original_post_id,
    ),
  )
}

pub fn get_post(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  post_id: Id,
) -> Nil {
  process.send(storage, GetPost(client, post_id))
}

pub fn get_subreddit_posts(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  subreddit_id: Id,
  limit: Int,
) -> Nil {
  process.send(storage, GetSubredditPosts(client, subreddit_id, limit))
}

pub fn delete_post(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  post_id: Id,
  user_id: Id,
) -> Nil {
  process.send(storage, DeletePost(client, post_id, user_id))
}

pub fn create_comment(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  author_id: Id,
  post_id: Id,
  parent_comment_id: Option(Id),
  content: String,
) -> Nil {
  process.send(
    storage,
    CreateComment(client, author_id, post_id, parent_comment_id, content),
  )
}

pub fn get_comment(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  comment_id: Id,
) -> Nil {
  process.send(storage, GetComment(client, comment_id))
}

pub fn get_post_comments(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  post_id: Id,
) -> Nil {
  process.send(storage, GetPostComments(client, post_id))
}

pub fn delete_comment(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  comment_id: Id,
  user_id: Id,
) -> Nil {
  process.send(storage, DeleteComment(client, comment_id, user_id))
}

pub fn get_feed(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  user_id: Id,
  limit: Int,
) -> Nil {
  process.send(storage, GetFeed(client, user_id, limit))
}

pub fn get_home_feed(
  storage: Subject(PostStorageMessage),
  client: Subject(EngineResponse),
  user_id: Id,
  limit: Int,
) -> Nil {
  process.send(storage, GetHomeFeed(client, user_id, limit))
}

// ============================================================================
// Implementation
// ============================================================================

fn init_state() -> PostStorageState {
  PostStorageState(
    posts: dict.new(),
    comments: dict.new(),
    post_comments: dict.new(),
    subreddit_posts: dict.new(),
  )
}

fn handle_message(
  message: PostStorageMessage,
  state: PostStorageState,
) -> actor.Next(PostStorageState, PostStorageMessage) {
  case message {
    CreatePost(
      client,
      author_id,
      subreddit_id,
      title,
      content,
      is_repost,
      original_post_id,
    ) -> {
      let result = {
        use valid_title <- result.try(utils.validate_post_title(title))
        use valid_content <- result.try(utils.validate_post_content(content))

        let post_id = utils.generate_post_id()
        // TODO: Get author username and subreddit name from registries
        let post =
          Post(
            id: post_id,
            author_id: author_id,
            author_username: "user_" <> author_id,
            subreddit_id: subreddit_id,
            subreddit_name: "sub_" <> subreddit_id,
            title: valid_title,
            content: valid_content,
            upvotes: 0,
            downvotes: 0,
            comment_count: 0,
            created_at: utils.get_current_timestamp(),
            is_repost: is_repost,
            original_post_id: original_post_id,
          )

        let new_posts = dict.insert(state.posts, post_id, post)
        let existing_posts =
          dict.get(state.subreddit_posts, subreddit_id)
          |> result.unwrap([])
        let updated_posts = [post_id, ..existing_posts]
        let new_subreddit_posts =
          dict.insert(state.subreddit_posts, subreddit_id, updated_posts)

        let new_state =
          PostStorageState(
            ..state,
            posts: new_posts,
            subreddit_posts: new_subreddit_posts,
          )

        Ok(#(new_state, post))
      }

      case result {
        Ok(#(new_state, post)) -> {
          process.send(client, protocol.PostCreated(post))
          actor.continue(new_state)
        }
        Error(reason) -> {
          process.send(client, protocol.Error(protocol.InvalidPost(reason)))
          actor.continue(state)
        }
      }
    }

    GetPost(client, post_id) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> process.send(client, protocol.PostResponse(post))
        Error(_) ->
          process.send(client, protocol.Error(protocol.PostNotFound(post_id)))
      }
      actor.continue(state)
    }

    GetSubredditPosts(client, subreddit_id, limit) -> {
      let post_ids =
        dict.get(state.subreddit_posts, subreddit_id)
        |> result.unwrap([])
        |> list.take(limit)

      let posts =
        list.filter_map(post_ids, fn(id) { dict.get(state.posts, id) })

      process.send(client, protocol.PostsResponse(posts))
      actor.continue(state)
    }

    DeletePost(client, post_id, user_id) -> {
      let result = case dict.get(state.posts, post_id) {
        Error(_) -> Error(protocol.PostNotFound(post_id))
        Ok(post) -> {
          case post.author_id == user_id {
            False -> Error(protocol.Unauthorized(user_id, "delete post"))
            True -> {
              let new_posts = dict.delete(state.posts, post_id)
              let new_state = PostStorageState(..state, posts: new_posts)
              Ok(new_state)
            }
          }
        }
      }

      case result {
        Ok(new_state) -> {
          process.send(client, protocol.PostDeleted(post_id))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }

    CreateComment(client, author_id, post_id, parent_comment_id, content) -> {
      let result = {
        use valid_content <- result.try(utils.validate_comment_content(content))
        use post <- result.try(
          dict.get(state.posts, post_id)
          |> result.replace_error(protocol.PostNotFound(post_id)),
        )

        // Validate parent comment if specified
        let depth = case parent_comment_id {
          None -> 0
          Some(parent_id) -> {
            case dict.get(state.comments, parent_id) {
              Error(_) -> {
                // Parent not found
                return Error(protocol.ParentCommentNotFound(parent_id))
              }
              Ok(parent) -> parent.depth + 1
            }
          }
        }

        let comment_id = utils.generate_comment_id()
        let comment =
          Comment(
            id: comment_id,
            author_id: author_id,
            author_username: "user_" <> author_id,
            post_id: post_id,
            parent_comment_id: parent_comment_id,
            content: valid_content,
            upvotes: 0,
            downvotes: 0,
            depth: depth,
            created_at: utils.get_current_timestamp(),
            children: [],
          )

        let new_comments = dict.insert(state.comments, comment_id, comment)
        let existing_comments =
          dict.get(state.post_comments, post_id)
          |> result.unwrap([])
        let updated_comments = [comment_id, ..existing_comments]
        let new_post_comments =
          dict.insert(state.post_comments, post_id, updated_comments)

        // Update post comment count
        let updated_post =
          Post(..post, comment_count: post.comment_count + 1)
        let new_posts = dict.insert(state.posts, post_id, updated_post)

        let new_state =
          PostStorageState(
            posts: new_posts,
            comments: new_comments,
            post_comments: new_post_comments,
            subreddit_posts: state.subreddit_posts,
          )

        Ok(#(new_state, comment))
      }

      case result {
        Ok(#(new_state, comment)) -> {
          process.send(client, protocol.CommentCreated(comment))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }

    GetComment(client, comment_id) -> {
      case dict.get(state.comments, comment_id) {
        Ok(comment) -> process.send(client, protocol.CommentResponse(comment))
        Error(_) ->
          process.send(
            client,
            protocol.Error(protocol.CommentNotFound(comment_id)),
          )
      }
      actor.continue(state)
    }

    GetPostComments(client, post_id) -> {
      let comment_ids =
        dict.get(state.post_comments, post_id)
        |> result.unwrap([])

      let comments =
        list.filter_map(comment_ids, fn(id) { dict.get(state.comments, id) })

      process.send(client, protocol.CommentsResponse(comments))
      actor.continue(state)
    }

    DeleteComment(client, comment_id, user_id) -> {
      let result = case dict.get(state.comments, comment_id) {
        Error(_) -> Error(protocol.CommentNotFound(comment_id))
        Ok(comment) -> {
          case comment.author_id == user_id {
            False -> Error(protocol.Unauthorized(user_id, "delete comment"))
            True -> {
              let new_comments = dict.delete(state.comments, comment_id)
              let new_state = PostStorageState(..state, comments: new_comments)
              Ok(new_state)
            }
          }
        }
      }

      case result {
        Ok(new_state) -> {
          process.send(client, protocol.CommentDeleted(comment_id))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }

    UpdatePostVotes(post_id, upvotes, downvotes) -> {
      let new_state = case dict.get(state.posts, post_id) {
        Error(_) -> state
        Ok(post) -> {
          let updated = Post(..post, upvotes: upvotes, downvotes: downvotes)
          let new_posts = dict.insert(state.posts, post_id, updated)
          PostStorageState(..state, posts: new_posts)
        }
      }
      actor.continue(new_state)
    }

    UpdateCommentVotes(comment_id, upvotes, downvotes) -> {
      let new_state = case dict.get(state.comments, comment_id) {
        Error(_) -> state
        Ok(comment) -> {
          let updated =
            Comment(..comment, upvotes: upvotes, downvotes: downvotes)
          let new_comments = dict.insert(state.comments, comment_id, updated)
          PostStorageState(..state, comments: new_comments)
        }
      }
      actor.continue(new_state)
    }

    GetFeed(client, user_id, limit) -> {
      // Simple feed: all posts sorted by time
      let all_posts = dict.values(state.posts)
      let sorted = utils.sort_posts_by_new(all_posts)
      let limited = list.take(sorted, limit)

      // TODO: Add subreddit info
      let feed_items = list.map(limited, fn(post) {
        FeedItem(post: post, subreddit: types.Subreddit(
          id: post.subreddit_id,
          name: post.subreddit_name,
          description: "",
          created_by: "",
          created_at: 0,
          member_count: 0,
          post_count: 0,
        ))
      })

      let feed = Feed(items: feed_items, generated_at: utils.get_current_timestamp())
      process.send(client, protocol.FeedResponse(feed))
      actor.continue(state)
    }

    GetHomeFeed(client, user_id, limit) -> {
      // TODO: Filter by user's subscriptions
      // For now, same as GetFeed
      handle_message(GetFeed(client, user_id, limit), state)
    }
  }
}