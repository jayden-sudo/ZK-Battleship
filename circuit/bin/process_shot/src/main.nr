//! This Noir program serves as the circuit for processing and verifying a single shot
//! in a ZK-Battleship game. It ensures that a player correctly reports the outcome
//! (Miss, Hit, or Sunk) of a shot fired by their opponent.
//!
//! The circuit proves two main things:
//! 1. The defender is using the same board they committed to at the start of the game.
//! 2. The reported outcome of the shot is consistent with the private board layout and the
//!    current state of the game (i.e., previous hits).

use board_lib::{init_board, process_shot, STATUS_HIT, STATUS_MISS, STATUS_SUNK};

/// The main entry point for the shot processing circuit.
///
/// This function validates that the reported result of a shot (`hit_status`) is correct
/// based on the defender's private board layout and the public game state.
///
/// # Arguments
///
/// * `cruiser`, `destroyer`, `submarine` - Private inputs defining the defender's ship placements.
/// * `salt` - The private salt used to create the initial board commitment.
/// * `expected_hash` - A public input representing the defender's board commitment hash.
/// * `pub_input` - A public `u64` value that packs together the public information about the turn:
///   - `grid_snapshot` (36 bits): A bitmask of all previously hit cells on the board.
///   - `shot_position` (8 bits): The coordinate (0-35) of the current shot.
///   - `hit_status` (4 bits): The claimed result of the shot (0 for Miss, 1 for Hit, 2 for Sunk).
///
/// # Panics
///
/// The proof will fail if:
/// 1. The computed board hash does not match `expected_hash`.
/// 2. The computed shot status (derived from private inputs) does not match the public `hit_status`.
fn main(
    cruiser: [u8; 3],
    destroyer: [u8; 2],
    submarine: u8,
    salt: Field,
    expected_hash: pub Field,
    pub_input: pub u64,
) {
    // First, prove that the private board layout matches the public commitment hash.
    let hash: Field = init_board(cruiser, destroyer, submarine, salt);
    assert(hash == expected_hash, "Computed hash does not match expected hash");

    // Unpack the public input to extract game state information.
    // The `pub_input` is structured as follows:
    // - Bits 0-3:    hit_status
    // - Bits 4-11:   shot_position
    // - Bits 12-47:  grid_snapshot (36 bits)
    // - Bits 48-55:  sunk_head_position
    // - Bits 56-63:  sunk_end_position
    let hit_status: u8 = (pub_input & 0x0f) as u8;
    let shot_position: u8 = ((pub_input >> 4) & 0xff) as u8;

    // Extract the 36-bit grid snapshot into an array of bits.
    let mut grid_snapshot_bits: [u1; 36] = [0; 36];
    let _pub_input = pub_input >> 12;
    let grid_snapshot_bits_len = grid_snapshot_bits.len() as u64;
    for i in 0..grid_snapshot_bits_len {
        grid_snapshot_bits[i as u32] = ((_pub_input >> (grid_snapshot_bits_len - 1 - i)) & 1) as u1;
    }
    let sunk_head_position: u8 = ((pub_input >> 48) & 0xff) as u8;
    let sunk_end_position: u8 = ((pub_input >> 56) & 0xff) as u8;

    // Process the shot using the private board layout and public game state to compute the true outcome.
    let shotResult = process_shot(
        cruiser,
        destroyer,
        submarine,
        grid_snapshot_bits,
        shot_position,
    );

    // Assert that the privately computed status matches the publicly declared hit_status.
    // This is the core constraint for verifying the shot report.
    assert(
        shotResult.status == hit_status,
        "Computed shot status does not match public hit status",
    );
    assert(
        shotResult.sunk_head_position == sunk_head_position,
        "Sunk head position does not match",
    );
    assert(shotResult.sunk_end_position == sunk_end_position, "Sunk head position does not match");
}

/// A test helper function to convert a 36-bit array (big-endian) to a u64.
fn be_bits_to_u64(bits: [u1; 36]) -> u64 {
    let mut result = 0u64;
    for i in 0..bits.len() {
        if bits[i] == 1 {
            result += (1u64 << (bits.len() - 1 - i) as u64) as u64;
        }
    }
    result
}

/// A comprehensive test that simulates a series of shots for a full game,
/// verifying the shot processing circuit at each step.
#[test]
fn test_main() {
    // Define a fixed board layout for the test.
    let cruiser: [u8; 3] = [0, 6, 12];
    let destroyer: [u8; 2] = [14, 15];
    let submarine: u8 = 21;
    let salt: Field = 7;
    let expected_hash: Field = 0x04df209ed0aad0968c3aa95d735485f04ed83fb29173287fda6716461da5815d;

    // Initialize an empty grid snapshot, representing no previous hits.
    let mut grid_snapshot_bits: [u1; 36] = [0; 36];
    /*
    * +--------+---+---+---+---+--------+
    * |    +--+|   |   |   |   |        |
    * |    |0 ||1  |2  |3  |4  |5       |
    * |    |  ||   |   |   |   |        |
    * +----|--|+---+---+---+---+--------+
    * |    |  ||   |   |   |   |        |
    * |    |6 ||7  |8  |9  |10 |11      |
    * |    |  ||   |   |   |   |        |
    * +----|--|+---+---+---+---+--------+
    * |    |  ||   +------+|   |        |
    * |    |12||13 |14 |15||16 |17      |
    * |    +--+|   +------+|   |        |
    * +--------+---+---+---+---+--------+
    * |        |   |   +--+|   |        |
    * |     18 |17 |20 |21||22 |23      |
    * |        |   |   +--+|   |        |
    * +--------+---+---+---+---+--------+
    * |        |   |   |   |   |        |
    * |     24 |25 |26 |27 |28 |29      |
    * |        |   |   |   |   |        |
    * +--------+---+---+---+---+--------+
    * |        |   |   |   |   |        |
    * |     30 |31 |32 |33 |34 |35      |
    * |        |   |   |   |   |        |
    * +--------+---+---+---+---+--------+
    */

    // The test simulates a player firing at every cell (0-35) of the board.
    for i in 0..36 {
        println(f"round: {i}");
        let mut hit_status = 0;

        // Define the expected outcome for shots that hit a ship.
        if i == 0 {
            hit_status = STATUS_HIT;
        } else if i == 6 {
            hit_status = STATUS_HIT;
        } else if i == 12 {
            hit_status = STATUS_SUNK; // Final hit on the cruiser
        } else if i == 14 {
            hit_status = STATUS_HIT;
        } else if i == 15 {
            hit_status = STATUS_SUNK; // Final hit on the destroyer
        } else if i == 21 {
            hit_status = STATUS_SUNK; // Hit on the submarine
        } else {
            hit_status = STATUS_MISS;
        }

        // Pack the public inputs for the main circuit function.
        let mut pub_input: u64 =
            hit_status as u64 + (i << 4u64) + (be_bits_to_u64(grid_snapshot_bits) << 12);
        if i == 12 {
            pub_input = pub_input + ((0 << 48) + (12 << 56))
        } else if i == 15 {
            pub_input = pub_input + ((14 << 48) + (15 << 56))
        } else if i == 21 {
            pub_input = pub_input + ((21 << 48) + (21 << 56))
        }

        // Run the circuit with the current shot's data.
        main(
            cruiser,
            destroyer,
            submarine,
            salt,
            expected_hash,
            pub_input,
        );
        println(f"status: {hit_status}");

        // If the shot was a hit or sunk a ship, update the grid snapshot for the next iteration.
        if hit_status != STATUS_MISS {
            grid_snapshot_bits[i as u32] = 1;
        }
    }
}
