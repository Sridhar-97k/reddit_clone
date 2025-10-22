// Vote Tracker - Manages voting and karma
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import shared/protocol.{type EngineResponse}
import shared/types.{type Id, type Vote, type VoteType, Vote}
import shared/utils

// ============================================================================
// State
// ============================================================================

pub type VoteTrackerState {
  VoteTrackerState(
    // Key: user_id <> ":" <> target_id
    votes: Dict(String, Vote),
    // Target votes: target_id -> (upvotes, downvotes)
    target_votes: Dict(Id, #(Int, Int)),
    // User karma tracking: user_id -> karma_delta
    user_karma: Dict(Id, Int),
  )
}

// ============================================================================
// Messages
// ============================================================================

pub type VoteTrackerMessage {
  VotePost(
    client: Subject(EngineResponse),
    user_id: Id,
    post_id: Id,
    vote_type: VoteType,
  )
  VoteComment(
    client: Subject(EngineResponse),
    user_id: Id,
    comment_id: Id,
    vote_type: VoteType,
  )
  RemoveVote(client: Subject(EngineResponse), user_id: Id, target_id: Id)
  GetVoteStats(target_id: Id)
}

// ============================================================================
// API
// ============================================================================

pub fn start() -> Result(Subject(VoteTrackerMessage), actor.StartError) {
  actor.start(fn() { init_state() }, fn(msg, state) { handle_message(msg, state) })
}

pub fn vote_post(
  tracker: Subject(VoteTrackerMessage),
  client: Subject(EngineResponse),
  user_id: Id,
  post_id: Id,
  vote_type: VoteType,
) -> Nil {
  process.send(tracker, VotePost(client, user_id, post_id, vote_type))
}

pub fn vote_comment(
  tracker: Subject(VoteTrackerMessage),
  client: Subject(EngineResponse),
  user_id: Id,
  comment_id: Id,
  vote_type: VoteType,
) -> Nil {
  process.send(tracker, VoteComment(client, user_id, comment_id, vote_type))
}

pub fn remove_vote(
  tracker: Subject(VoteTrackerMessage),
  client: Subject(EngineResponse),
  user_id: Id,
  target_id: Id,
) -> Nil {
  process.send(tracker, RemoveVote(client, user_id, target_id))
}

// ============================================================================
// Implementation
// ============================================================================

fn init_state() -> VoteTrackerState {
  VoteTrackerState(
    votes: dict.new(),
    target_votes: dict.new(),
    user_karma: dict.new(),
  )
}

fn handle_message(
  message: VoteTrackerMessage,
  state: VoteTrackerState,
) -> actor.Next(VoteTrackerState, VoteTrackerMessage) {
  case message {
    VotePost(client, user_id, post_id, vote_type) -> {
      handle_vote(state, client, user_id, post_id, vote_type)
    }

    VoteComment(client, user_id, comment_id, vote_type) -> {
      handle_vote(state, client, user_id, comment_id, vote_type)
    }

    RemoveVote(client, user_id, target_id) -> {
      let vote_key = make_vote_key(user_id, target_id)

      let result = case dict.get(state.votes, vote_key) {
        Error(_) -> Error(protocol.VoteNotFound(user_id, target_id))
        Ok(vote) -> {
          // Remove the vote
          let new_votes = dict.delete(state.votes, vote_key)

          // Update target vote counts
          let #(upvotes, downvotes) =
            dict.get(state.target_votes, target_id)
            |> result.unwrap(#(0, 0))

          let new_counts = case vote.vote_type {
            types.Upvote -> #(upvotes - 1, downvotes)
            types.Downvote -> #(upvotes, downvotes - 1)
          }

          let new_target_votes =
            dict.insert(state.target_votes, target_id, new_counts)

          let new_state =
            VoteTrackerState(
              votes: new_votes,
              target_votes: new_target_votes,
              user_karma: state.user_karma,
            )

          let new_score = utils.calculate_karma(new_counts.0, new_counts.1)
          Ok(#(new_state, new_score))
        }
      }

      case result {
        Ok(#(new_state, new_score)) -> {
          process.send(client, protocol.VoteRemoved(target_id, new_score))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(client, protocol.Error(error))
          actor.continue(state)
        }
      }
    }

    GetVoteStats(target_id) -> {
      // Internal message, no response needed
      actor.continue(state)
    }
  }
}

fn handle_vote(
  state: VoteTrackerState,
  client: Subject(EngineResponse),
  user_id: Id,
  target_id: Id,
  vote_type: VoteType,
) -> actor.Next(VoteTrackerMessage, VoteTrackerState) {
  let vote_key = make_vote_key(user_id, target_id)

  let result = case dict.get(state.votes, vote_key) {
    Ok(existing_vote) -> {
      // User already voted, update the vote
      case existing_vote.vote_type == vote_type {
        True -> {
          // Same vote type, no change
          Error(protocol.AlreadyVoted(user_id, target_id))
        }
        False -> {
          // Different vote type, update
          let updated_vote =
            Vote(..existing_vote, vote_type: vote_type, created_at: utils.get_current_timestamp())

          let new_votes = dict.insert(state.votes, vote_key, updated_vote)

          // Update target vote counts
          let #(upvotes, downvotes) =
            dict.get(state.target_votes, target_id)
            |> result.unwrap(#(0, 0))

          let new_counts = case existing_vote.vote_type, vote_type {
            types.Upvote, types.Downvote -> #(upvotes - 1, downvotes + 1)
            types.Downvote, types.Upvote -> #(upvotes + 1, downvotes - 1)
            _, _ -> #(upvotes, downvotes)
          }

          let new_target_votes =
            dict.insert(state.target_votes, target_id, new_counts)

          let new_state =
            VoteTrackerState(
              votes: new_votes,
              target_votes: new_target_votes,
              user_karma: state.user_karma,
            )

          let new_score = utils.calculate_karma(new_counts.0, new_counts.1)
          let user_karma =
            dict.get(state.user_karma, user_id)
            |> result.unwrap(0)

          Ok(#(new_state, new_score, user_karma))
        }
      }
    }
    Error(_) -> {
      // New vote
      let vote =
        Vote(
          user_id: user_id,
          target_id: target_id,
          vote_type: vote_type,
          created_at: utils.get_current_timestamp(),
        )

      let new_votes = dict.insert(state.votes, vote_key, vote)

      // Update target vote counts
      let #(upvotes, downvotes) =
        dict.get(state.target_votes, target_id)
        |> result.unwrap(#(0, 0))

      let new_counts = case vote_type {
        types.Upvote -> #(upvotes + 1, downvotes)
        types.Downvote -> #(upvotes, downvotes + 1)
      }

      let new_target_votes =
        dict.insert(state.target_votes, target_id, new_counts)

      let new_state =
        VoteTrackerState(
          votes: new_votes,
          target_votes: new_target_votes,
          user_karma: state.user_karma,
        )

      let new_score = utils.calculate_karma(new_counts.0, new_counts.1)
      let user_karma =
        dict.get(state.user_karma, user_id)
        |> result.unwrap(0)

      Ok(#(new_state, new_score, user_karma))
    }
  }

  case result {
    Ok(#(new_state, new_score, user_karma)) -> {
      process.send(client, protocol.VoteRecorded(target_id, new_score, user_karma))
      actor.continue(new_state)
    }
    Error(error) -> {
      process.send(client, protocol.Error(error))
      actor.continue(state)
    }
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn make_vote_key(user_id: Id, target_id: Id) -> String {
  user_id <> ":" <> target_id
}