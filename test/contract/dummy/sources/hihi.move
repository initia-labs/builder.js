module test::hihi {
    use test::dummy;
    
    struct HiHi has store {
        count: u64
    }

    public fun return_0(): u32 {
        0
    }

    public fun return_10(): u32 {
        10
    }

    public fun call_friend(): u32 {
      dummy::return_10_by_friend()
    }
}