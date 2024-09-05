/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unsafe-argument */
import ref from 'ref-napi'
import struct = require('ref-struct-di')

import { UnmanagedVectorType, FFIResultFormat, FFIResult } from './types'

// Define the structure for ErrMsg and Result
type ErrMsgStruct = struct.StructObject<{
  is_none: boolean
  ptr: ref.Pointer<string | null>
  len: string | number
  cap: string | number
}>

// Define MethodType as a function that accepts ErrMsg and arguments
type MethodType = (errMsg: ref.Pointer<ErrMsgStruct>, ...args: any[]) => void

// Function to handle the response from the FFI call
export async function handleResponse(
  method: MethodType,
  errMsg: ref.Pointer<ErrMsgStruct>,
  format: FFIResultFormat,
  ...args: any[]
): Promise<FFIResult> {
  return new Promise((resolve, reject) => {
    method(errMsg, ...args, (_err: any, res: ErrMsgStruct) => {
      const resErrMsg = errMsg.deref()

      if (!resErrMsg.is_none) {
        const errorMessage = Buffer.from(
          resErrMsg.ptr.buffer.slice(0, resErrMsg.len as number)
        ).toString('utf-8')

        reject(new Error(errorMessage))
      } else if (res.is_none) {
        // Handle unknown error case
        reject(new Error('Unknown error'))
      } else {
        const result = Buffer.from(res.ptr.buffer.slice(0, res.len as number))
        resolve(format === 'utf-8' ? result.toString('utf-8') : result)
      }
    })
  })
}

export function createRawErrMsg(): ref.Pointer<ErrMsgStruct> {
  const errMsg = ref.alloc(UnmanagedVectorType) as ref.Pointer<ErrMsgStruct>
  const rawErrMsg = errMsg.deref()

  rawErrMsg.is_none = true
  rawErrMsg.ptr = ref.NULL
  rawErrMsg.len = 0
  rawErrMsg.cap = 0

  return errMsg
}
