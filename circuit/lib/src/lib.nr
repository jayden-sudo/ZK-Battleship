//! This library provides the core cryptographic and logical functions for the ZK-Battleship circuits.
//! It includes functions for validating board layouts, creating board commitments, and processing shots.

use poseidon::poseidon2::Poseidon2;

// =================================================================================================
// Constants
// =================================================================================================

/// Represents the status of a shot that did not hit any ship.
pub global STATUS_MISS: u8 = 0;
/// Represents the status of a shot that hit a part of a ship, but did not sink it.
pub global STATUS_HIT: u8 = 1;
/// Represents the status of a shot that hit the final part of a ship, causing it to sink.
pub global STATUS_SUNK: u8 = 2;

// =================================================================================================
// Public Functions
// =================================================================================================

/**
 * @notice Validates a board layout and computes its commitment hash using Poseidon.
 * @dev This function enforces several constraints on ship placement:
 *      1. All ship coordinates must be within the 6x6 grid (0-35).
 *      2. Ship segments must be contiguous, either horizontally (diff = 1) or vertically (diff = 6).
 *      3. All ship coordinates must be unique (no overlapping ships).
 * @param cruiser An array of 3 coordinates for the Cruiser.
 * @param destroyer An array of 2 coordinates for the Destroyer.
 * @param submarine A single coordinate for the Submarine.
 * @param salt A private value to ensure the uniqueness of the hash.
 * @return The Poseidon hash of the board configuration, serving as a commitment.
 */
pub fn init_board(cruiser: [u8; 3], destroyer: [u8; 2], submarine: u8, salt: Field) -> Field {
    let max_value: u8 = 36; // 6x6 grid, positions 0..35

    // Validate cruiser placement: check bounds and contiguity.
    for i in 0..cruiser.len() {
        assert(cruiser[i] < max_value);
        if i > 0 {
            assert(cruiser[i - 1] < cruiser[i]); // Assert coordinates are sorted
            let s = cruiser[i] - cruiser[i - 1];
            // Must be adjacent horizontally (1) or vertically (6)
            if s != 1 {
                assert(s == 6);
            }
        }
    }

    // Validate destroyer placement: check bounds and contiguity.
    for i in 0..destroyer.len() {
        assert(destroyer[i] < max_value);
        if i > 0 {
            assert(destroyer[i - 1] < destroyer[i]); // Assert coordinates are sorted
            let s = destroyer[i] - destroyer[i - 1];
            // Must be adjacent horizontally (1) or vertically (6)
            if s != 1 {
                assert(s == 6);
            }
        }
    }

    // Validate submarine placement: check bounds.
    assert(submarine < max_value);

    // Collect all ship coordinates and the salt to be hashed.
    let params: [Field; 7] = [
        cruiser[0] as Field,
        cruiser[1] as Field,
        cruiser[2] as Field,
        destroyer[0] as Field,
        destroyer[1] as Field,
        submarine as Field,
        salt,
    ];

    // Validate non-overlapping ships by marking positions on a grid.
    let mut grid: [bool; 36] = [false; 36];
    for i in 0..(params.len() - 1) {
        // -1 to exclude the salt
        let pos = params[i] as u32;
        assert(grid[pos] == false, "Ship coordinates overlap");
        grid[pos] = true;
    }

    // Compute and return the Poseidon hash of the board parameters.
    Poseidon2::hash(params, params.len())
}

pub struct ShotResult {
    pub status: u8,
    pub sunk_head_position: u8,
    pub sunk_end_position: u8,
}

/**
 * @notice Determines the result of a shot based on the board layout and previous hits.
 * @dev Checks if a shot is a Miss, Hit, or Sunk. A "Sunk" occurs if the shot hits
 *      the last undamaged part of a ship.
 * @param cruiser The coordinates of the Cruiser.
 * @param destroyer The coordinates of the Destroyer.
 * @param submarine The coordinate of the Submarine.
 * @param grid_snapshot_bits A 36-bit array showing the locations of previous hits.
 * @param shot_position The coordinate of the current shot.
 * @return The status of the shot (STATUS_MISS, STATUS_HIT, or STATUS_SUNK).
 */
pub fn process_shot(
    cruiser: [u8; 3],
    destroyer: [u8; 2],
    submarine: u8,
    grid_snapshot_bits: [u1; 36],
    shot_position: u8,
) -> ShotResult {
    // Ensure the shot is within the board and hasn't been fired before.
    assert(shot_position < 36);
    assert(grid_snapshot_bits[shot_position as u32] == 0, "Position already shot at");

    let mut shotResult =
        ShotResult { status: STATUS_MISS, sunk_head_position: 0, sunk_end_position: 0 };

    // Check if the shot hits the cruiser.
    if shotResult.status == STATUS_MISS {
        for i in 0..cruiser.len() {
            if shotResult.status == STATUS_MISS {
                if shot_position == cruiser[i] {
                    shotResult.status = STATUS_SUNK;
                    for j in 0..cruiser.len() {
                        if j != i {
                            if shotResult.status == STATUS_SUNK {
                                if grid_snapshot_bits[cruiser[j] as u32] == 0 {
                                    shotResult.status = STATUS_HIT;
                                }
                            }
                        }
                    }
                    if shotResult.status == STATUS_SUNK {
                        shotResult.sunk_head_position = cruiser[0];
                        shotResult.sunk_end_position = cruiser[cruiser.len() - 1];
                    }
                }
            }
        }
    }

    // Check if the shot hits the destroyer.
    if shotResult.status == STATUS_MISS {
        for i in 0..destroyer.len() {
            if shotResult.status == STATUS_MISS {
                if shot_position == destroyer[i] {
                    shotResult.status = STATUS_SUNK;
                    for j in 0..destroyer.len() {
                        if j != i {
                            if shotResult.status == STATUS_SUNK {
                                if grid_snapshot_bits[destroyer[j] as u32] == 0 {
                                    shotResult.status = STATUS_HIT;
                                }
                            }
                        }
                    }
                    if shotResult.status == STATUS_SUNK {
                        shotResult.sunk_head_position = destroyer[0];
                        shotResult.sunk_end_position = destroyer[destroyer.len() - 1];
                    }
                }
            }
        }
    }

    // Check if the shot hits the submarine. A single hit sinks it.
    if shotResult.status == STATUS_MISS {
        if shot_position == submarine {
            shotResult.status = STATUS_SUNK;
            shotResult.sunk_head_position = submarine;
            shotResult.sunk_end_position = submarine;
        }
    }

    shotResult
}

// =================================================================================================
// Tests
// =================================================================================================

/// Tests the `init_board` function with a known valid board layout and hash.
#[test]
fn test_init_board() {
    let hash = init_board([0, 6, 12], [14, 15], 21, 7);
    assert(hash == 0x04df209ed0aad0968c3aa95d735485f04ed83fb29173287fda6716461da5815d);
}
