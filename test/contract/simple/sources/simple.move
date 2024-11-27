module 0x999::simple {

    fun add(a: u64, b:u64): u64 {
        a + b 
    }

    #[test]
    fun test_simple(){
        assert!(1==1,1);
    }

    #[test]
    fun test_simple2(){
        let addr: address = @0x11;
        assert!(add(1,1)==2,2);
    }

}
