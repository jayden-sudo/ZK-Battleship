use poseidon::poseidon2::Poseidon2;

pub fn init_board(
    cruiser: [Field; 3],
    destroyer: [Field; 2],
    submarine: Field,
    salt: Field,
) -> Field {
    let params: [Field; 7] =
        [cruiser[0], cruiser[1], cruiser[2], destroyer[0], destroyer[1], submarine, salt];

    // Validate ship position
    let max_value: Field = 36; // 6x6 grid, positions 0..35
    for i in 0..cruiser.len() {
        assert(cruiser[i].lt(max_value));
        if i > 0 {
            assert(cruiser[i - 1].lt(cruiser[i]));
            let s: Field = cruiser[i] - cruiser[i - 1];
            if s != 1 {
                assert(s == 6);
            }
        }
    }
    for i in 0..destroyer.len() {
        assert(destroyer[i].lt(max_value));
        if i > 0 {
            assert(destroyer[i - 1].lt(destroyer[i]));
            let s: Field = destroyer[i] - destroyer[i - 1];
            if s != 1 {
                assert(s == 6);
            }
        }
    }
    assert(submarine.lt(max_value));

    let mut grid: [bool; 36] = [false; 36];
    for i in 0..(params.len() - 1) {
        assert(grid[i] == false);
        grid[i] = true;
    }

    // Compute Poseidon hash
    Poseidon2::hash(params, params.len())
}

// pub global STATUS_ERROR: Field = 0; // error
pub global STATUS_MISS: Field = 1; // miss
pub global STATUS_HIT: Field = 2; // hit
pub global STATUS_SUNK: Field = 3; // sunk

pub fn process_shot(
    cruiser: [Field; 3],
    destroyer: [Field; 2],
    submarine: Field,
    grid_snapshot: Field,
    shot_position: Field,
) -> Field {
    assert(shot_position.lt(36));
    let grid_snapshot_bits: [u1; 36] = grid_snapshot.to_le_bits();
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
