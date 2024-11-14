script {
    fun even(x: u64) {
        let y = x * 2;
        assert!(y % 2 == 0, 1);
    }
}