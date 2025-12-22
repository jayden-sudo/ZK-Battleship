use board_lib::init_board;

fn main(
    cruiser: [u8; 3],
    destroyer: [u8; 2],
    submarine: u8,
    salt: Field,
    expected_hash: pub Field,
) {
    let hash: Field = init_board(cruiser, destroyer, submarine, salt);
    println(hash);
    assert(hash == expected_hash, "Computed hash does not match expected hash");
}

#[test]
fn test_init_board() {
    main(
        [0, 6, 12],
        [14, 15],
        21,
        7,
        0x04df209ed0aad0968c3aa95d735485f04ed83fb29173287fda6716461da5815d,
    );
}
