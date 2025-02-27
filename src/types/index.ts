import struct from 'ref-struct-di'
import ref from '@eleccookie/ref-napi'
export * from './options'
export * from './bcs'
export * from './ffi'
export * from './type'

const StructType = struct(ref)

// for FFI results
export type FFIResult = string | Buffer | null

export const UnmanagedVectorType = StructType({
  is_none: ref.types.bool,
  ptr: ref.refType(ref.types.CString),
  len: ref.types.size_t,
  cap: ref.types.size_t,
})

export const UnmanagedVectorPtr = ref.refType(UnmanagedVectorType)

export const ByteSliceViewType = StructType({
  is_nil: ref.types.bool,
  ptr: ref.refType(ref.types.CString),
  len: ref.types.size_t,
})
