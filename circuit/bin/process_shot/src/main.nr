use board_lib::{init_board, process_shot, STATUS_HIT, STATUS_MISS, STATUS_SUNK};

fn main(
    cruiser: [u8; 3],
    destroyer: [u8; 2],
    submarine: u8,
    salt: Field,
    expected_hash: pub Field,
    pub_input: pub u64,
) {
    let hash: Field = init_board(cruiser, destroyer, submarine, salt);
    assert(hash == expected_hash, "Computed hash does not match expected hash");

    /*
        pub_input:

        grid_snapshot[36bit]  shot_position[8bit]  hit_status[4bit]
               16..51             52..59                60..63

    */
    let hit_status: u8 = (pub_input & 0x0f) as u8;
    let shot_position: u8 = ((pub_input >> 4) & 0xff) as u8;
    let mut grid_snapshot_bits: [u1; 36] = [0; 36];
    let _pub_input = pub_input >> 12;
    let grid_snapshot_bits_len = grid_snapshot_bits.len() as u64;
    for i in 0..grid_snapshot_bits_len as u64 {
        grid_snapshot_bits[i as u32] = ((_pub_input >> (grid_snapshot_bits_len - 1 - i)) & 1) as u1;
    }

    let status = process_shot(
        cruiser,
        destroyer,
        submarine,
        grid_snapshot_bits,
        shot_position,
    );
    assert(status == hit_status)
}

fn be_bits_to_u8(bits: [u1; 36]) -> u64 {
    // 0b000010 -> 2
    let mut result = 0u64;
    for i in 0..bits.len() {
        if bits[i] == 1 {
            result += (1u64 << (bits.len() - 1 - i) as u64) as u64;
        }
    }
    result
}

#[test]
fn test_main() {
    let cruiser: [u8; 3] = [0, 6, 12];
    let destroyer: [u8; 2] = [14, 15];
    let submarine: u8 = 21;
    let salt: Field = 7;
    let expected_hash: Field = 0x04df209ed0aad0968c3aa95d735485f04ed83fb29173287fda6716461da5815d;
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

    for i in 0..36 {
        println(f"round: {i}");
        let mut hit_status = 0;
        if i == 0 {
            hit_status = STATUS_HIT;
        } else if i == 6 {
            hit_status = STATUS_HIT;
        } else if i == 12 {
            hit_status = STATUS_SUNK;
        } else if i == 14 {
            hit_status = STATUS_HIT;
        } else if i == 15 {
            hit_status = STATUS_SUNK;
        } else if i == 21 {
            hit_status = STATUS_SUNK;
        } else {
            hit_status = STATUS_MISS;
        }

        let pub_input: u64 =hit_status as u64 + (i<<4u64) + (be_bits_to_u8(grid_snapshot_bits) << 12);

        main(
            cruiser,
            destroyer,
            submarine,
            salt,
            expected_hash,
            pub_input,
        );
        println(f"status: {hit_status}");

        if hit_status != STATUS_MISS {
            grid_snapshot_bits[i as u32] = 1;
        }
    }
}
