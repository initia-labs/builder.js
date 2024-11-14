module 0x999::dummy {
    public fun return_0(): u32 {
        0
    }

    public fun return_10(): u32 {
        10
    }

    #[test]
    fun test_return_0() {
        assert!(return_0() == 0,1);
    }
}