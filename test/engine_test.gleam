import gleeunit
import engine/subreddit_manager
import engine/post_storage
import engine/vote_tracker

pub fn main() {
  gleeunit.main()
}

pub fn test_subreddit_creation() {
  let assert Ok(_manager) = subreddit_manager.start()
  // Test passes if manager starts
}

pub fn test_post_storage() {
  let assert Ok(_storage) = post_storage.start()
  // Test passes if storage starts
}

pub fn test_vote_tracker() {
  let assert Ok(_tracker) = vote_tracker.start()
  // Test passes if tracker starts
}