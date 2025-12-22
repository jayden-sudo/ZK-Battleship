//! This Noir program serves as the circuit for initializing a ZK-Battleship game board.
//! It computes a commitment hash from the private ship placements and a secret salt,
//! then verifies this commitment against a publicly provided hash. This ensures that a player
//! commits to a valid board layout at the start of the game without revealing the ship positions.

use board_lib::init_board;

/// The main entry point for the board initialization circuit.
///
/// # Arguments
///
/// * `cruiser`     - An array of 3 coordinates representing the placement of the Cruiser ship.
/// * `destroyer`   - An array of 2 coordinates representing the placement of the Destroyer ship.
/// * `submarine`   - A single coordinate representing the placement of the Submarine.
/// * `salt`        - A private field element used as a salt to ensure the uniqueness of the commitment hash.
/// * `expected_hash` - A public field element representing the expected board commitment hash. The circuit
///                   will prove that the computed hash of the private inputs matches this value.
///
/// # Panics
///
/// This function will cause the proof to fail if the computed hash from the private inputs
/// does not match the `expected_hash`.
fn main(
    cruiser: [u8; 3],
    destroyer: [u8; 2],
    submarine: u8,
    salt: Field,
    expected_hash: pub Field,
) {
    // Compute the board commitment hash using the private ship placements and salt.
    let hash: Field = init_board(cruiser, destroyer, submarine, salt);

    // For debugging purposes, print the computed hash.
    // This output is not part of the proof itself.
    println(hash);
    
    // Assert that the computed hash matches the publicly known expected hash.
    // This is the core constraint of the circuit.
    assert(hash == expected_hash, "Computed hash does not match expected hash");
}

/// A test case to verify the `init_board` circuit logic with a sample set of inputs.
#[test]
fn test_init_board() {
    // These inputs correspond to a known valid board layout and its corresponding hash.
    main(
        [0, 6, 12],
        [14, 15],
        21,
        7,
        0x04df209ed0aad0968c3aa95d735485f04ed83fb29173287fda6716461da5815d,
    );
}
