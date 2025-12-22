use poseidon::poseidon2::Poseidon2;

pub fn init_board(cruiser: [u8; 3], destroyer: [u8; 2], submarine: u8, salt: Field) -> Field {
    // Validate ship position
    let max_value: u8 = 36; // 6x6 grid, positions 0..35
    for i in 0..cruiser.len() {
        assert(cruiser[i] < max_value);
        if i > 0 {
            assert(cruiser[i - 1] < cruiser[i]);
            let s = cruiser[i] - cruiser[i - 1];
            if s != 1 {
                assert(s == 6);
            }
        }
    }
    for i in 0..destroyer.len() {
        assert(destroyer[i] < max_value);
        if i > 0 {
            assert(destroyer[i - 1] < destroyer[i]);
            let s = destroyer[i] - destroyer[i - 1];
            if s != 1 {
                assert(s == 6);
            }
        }
    }
    assert(submarine < max_value);

    let params: [Field; 7] = [
        cruiser[0] as Field,
        cruiser[1] as Field,
        cruiser[2] as Field,
        destroyer[0] as Field,
        destroyer[1] as Field,
        submarine as Field,
        salt,
    ];

    let mut grid: [bool; 36] = [false; 36];
    for i in 0..(params.len() - 1) {
        let pos = params[i] as u32;
        assert(grid[pos] == false);
        grid[pos] = true;
    }

    // Compute Poseidon hash
    Poseidon2::hash(params, params.len())
}

pub global STATUS_MISS: u8 = 0; // miss
pub global STATUS_HIT: u8 = 1; // hit
pub global STATUS_SUNK: u8 = 2; // sunk

pub fn process_shot(
    cruiser: [u8; 3],
    destroyer: [u8; 2],
    submarine: u8,
    grid_snapshot_bits: [u1; 36],
    shot_position: u8,
) -> u8 {
    assert(shot_position < 36);
    assert(grid_snapshot_bits[shot_position as u32] == 0);

    let mut status = STATUS_MISS;

    if status == STATUS_MISS {
        for i in 0..cruiser.len() {
            if status == STATUS_MISS {
                if shot_position == cruiser[i] {
                    status = STATUS_SUNK;
                    for j in 0..cruiser.len() {
                        if j != i {
                            if status == STATUS_SUNK {
                                if grid_snapshot_bits[cruiser[j] as u32] == 0 {
                                    status = STATUS_HIT;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if status == STATUS_MISS {
        for i in 0..destroyer.len() {
            if status == STATUS_MISS {
                if shot_position == destroyer[i] {
                    status = STATUS_SUNK;
                    for j in 0..destroyer.len() {
                        if j != i {
                            if status == STATUS_SUNK {
                                if grid_snapshot_bits[destroyer[j] as u32] == 0 {
                                    status = STATUS_HIT;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if status == STATUS_MISS {
        if shot_position == submarine {
            status = STATUS_SUNK;
        }
    }

    status
}

#[test]
fn test_init_board() {
    let hash = init_board([0, 6, 12], [14, 15], 21, 7);
    assert(hash == 0x04df209ed0aad0968c3aa95d735485f04ed83fb29173287fda6716461da5815d);
}
