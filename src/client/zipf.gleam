// Zipf Distribution - For realistic user behavior simulation
import gleam/int
import gleam/list
import gleam/float

// ============================================================================
// Zipf Distribution
// ============================================================================

/// Zipf distribution parameters
pub type ZipfParams {
  ZipfParams(
    n: Int,        // Number of items (e.g., number of subreddits)
    s: Float,      // Skewness parameter (typically 1.0-2.0)
  )
}

/// Generate Zipf-distributed values
/// Returns a list of (item_index, frequency) pairs
pub fn generate_distribution(params: ZipfParams) -> List(#(Int, Int)) {
  let ZipfParams(n, s) = params
  
  // Calculate normalization constant (Harmonic number)
  let h_n = calculate_harmonic_number(n, s)
  
  // Generate probabilities for each rank
  list.range(1, n)
  |> list.map(fn(rank) {
    let probability = zipf_probability(rank, s, h_n)
    let frequency = float.round(probability *. int.to_float(n) *. 100.0)
    #(rank - 1, frequency)
  })
}

/// Calculate probability for a given rank
fn zipf_probability(rank: Int, s: Float, h_n: Float) -> Float {
  let rank_float = int.to_float(rank)
  let denominator = power_float(rank_float, s)
  1.0 /. denominator /. h_n
}

/// Calculate Harmonic number H(n,s) = sum(1/k^s) for k=1 to n
fn calculate_harmonic_number(n: Int, s: Float) -> Float {
  list.range(1, n)
  |> list.fold(0.0, fn(acc, k) {
    let k_float = int.to_float(k)
    acc +. { 1.0 /. power_float(k_float, s) }
  })
}

/// Simple power function for floats (x^y)
fn power_float(base: Float, exponent: Float) -> Float {
  // Simplified: x^y = e^(y * ln(x))
  // For integer-like exponents, we can approximate
  case exponent {
    1.0 -> base
    2.0 -> base *. base
    _ -> {
      // Approximation for other values
      // This is a simplified version - in production, use proper math library
      case exponent >. 0.0 {
        True -> base *. base  // Approximation
        False -> 1.0 /. base
      }
    }
  }
}

// ============================================================================
// Zipf Selection
// ============================================================================

/// Select an item according to Zipf distribution
/// Returns the index of the selected item
pub fn select_zipf(params: ZipfParams, random_value: Int) -> Int {
  let distribution = generate_distribution(params)
  
  // Calculate cumulative frequencies
  let total_frequency = 
    list.fold(distribution, 0, fn(acc, pair) { acc + pair.1 })
  
  // Normalize random value
  let normalized = random_value % total_frequency
  
  // Find the item based on cumulative probability
  select_from_cumulative(distribution, normalized, 0)
}

fn select_from_cumulative(
  distribution: List(#(Int, Int)),
  target: Int,
  cumulative: Int,
) -> Int {
  case distribution {
    [] -> 0
    [#(index, freq), ..rest] -> {
      let new_cumulative = cumulative + freq
      case target < new_cumulative {
        True -> index
        False -> select_from_cumulative(rest, target, new_cumulative)
      }
    }
  }
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create default Zipf parameters (s=1.0)
pub fn default_params(n: Int) -> ZipfParams {
  ZipfParams(n: n, s: 1.0)
}

/// Create Zipf parameters with custom skewness
pub fn with_skewness(n: Int, s: Float) -> ZipfParams {
  ZipfParams(n: n, s: s)
}

/// Generate member counts for subreddits following Zipf distribution
/// Returns list of member counts, highest first
pub fn generate_subreddit_members(
  num_subreddits: Int,
  total_members: Int,
  skewness: Float,
) -> List(Int) {
  let params = ZipfParams(n: num_subreddits, s: skewness)
  let distribution = generate_distribution(params)
  
  // Calculate total frequency
  let total_freq = 
    list.fold(distribution, 0, fn(acc, pair) { acc + pair.1 })
  
  // Distribute members proportionally
  list.map(distribution, fn(pair) {
    let #(_index, freq) = pair
    { freq * total_members } / total_freq
  })
}

/// Sample: Get top N items that account for X% of total activity
pub fn get_top_n_accounting_for_percent(
  distribution: List(#(Int, Int)),
  percent: Float,
) -> Int {
  let total = list.fold(distribution, 0, fn(acc, pair) { acc + pair.1 })
  let target = float.round(int.to_float(total) *. percent /. 100.0)
  
  count_until_target(distribution, target, 0, 0)
}

fn count_until_target(
  distribution: List(#(Int, Int)),
  target: Int,
  current_sum: Int,
  count: Int,
) -> Int {
  case distribution {
    [] -> count
    [#(_index, freq), ..rest] -> {
      let new_sum = current_sum + freq
      case new_sum >= target {
        True -> count + 1
        False -> count_until_target(rest, target, new_sum, count + 1)
      }
    }
  }
}