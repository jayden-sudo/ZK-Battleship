use board_lib::{init_board, process_shot, STATUS_HIT, STATUS_MISS, STATUS_SUNK};

fn main(
    cruiser: [Field; 3],
    destroyer: [Field; 2],
    submarine: Field,
    salt: Field,
    expected_hash: pub Field,
    grid_snapshot: pub Field,
    shot_position: pub Field,
) -> pub Field {
    let hash: Field = init_board(cruiser, destroyer, submarine, salt);
    assert(hash == expected_hash, "Computed hash does not match expected hash");

    process_shot(cruiser, destroyer, submarine, grid_snapshot, shot_position)
}

#[test]
fn test_main() {
    let cruiser: [Field; 3] = [0, 6, 12];
    let destroyer: [Field; 2] = [14, 15];
    let submarine: Field = 21;
    let salt: Field = 7;
    let expected_hash: Field = 0x04df209ed0aad0968c3aa95d735485f04ed83fb29173287fda6716461da5815d;
    //let mut grid_snapshot: [bool; 36] = [false; 36];
    let mut grid_snapshot: Field = 0;
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

    for i in 0..36 {
        println(f"round: {i}");
        let status: Field = main(
            cruiser,
            destroyer,
            submarine,
            salt,
            expected_hash,
            grid_snapshot,
            i as Field,
        );
        println(f"status: {status}");
        if i == 0 {
            assert(status == STATUS_HIT);
        } else if i == 6 {
            assert(status == STATUS_HIT);
        } else if i == 12 {
            assert(status == STATUS_SUNK);
        } else if i == 14 {
            assert(status == STATUS_HIT);
        } else if i == 15 {
            assert(status == STATUS_SUNK);
        } else if i == 21 {
            assert(status == STATUS_SUNK);
        } else {
            assert(status == STATUS_MISS);
        }

        if status != STATUS_MISS {
            // grid_snapshot[i] = true;
            let bit = 1 as u64 << i; //(36 - 1 - i);
            grid_snapshot = grid_snapshot + bit as Field;
            println(grid_snapshot);
            let grid_snapshot_bits: [u1; 36] = grid_snapshot.to_le_bits();
            println(grid_snapshot_bits);
            assert(grid_snapshot_bits[i as u32] == 1);
        }
    }
}
