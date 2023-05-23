/// Utility functions used by the framework modules.
module initia_std::util {
    /// Native function to deserialize a type T.
    /// TODO: may want to move it in extra module if needed also in other places inside of the Fx.
    /// However, should not make this function public outside of the Fx.
    public(friend) native fun from_bytes<T: copy + drop>(bytes: vector<u8>): T;
}
