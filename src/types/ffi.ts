import struct from 'ref-struct-di'
import ref from '@eleccookie/ref-napi'

export type ErrMsgStruct = struct.StructObject<{
  is_none: boolean
  ptr: ref.Pointer<string | null>
  len: number
  cap: number
}>

export type MethodType = (
  errMsg: ref.Pointer<ErrMsgStruct>,
  ...args: unknown[]
) => void
