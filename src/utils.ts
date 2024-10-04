import ref from '@eleccookie/ref-napi'
import struct from 'ref-struct-di'

import { UnmanagedVectorType, FFIResultFormat, FFIResult } from './types'
import { Buffer } from 'buffer'

// Define the structure for ErrMsg and Result
type ErrMsgStruct = struct.StructObject<{
  is_none: boolean
  ptr: ref.Pointer<string | null>
  len: number
  cap: number
}>

// Define MethodType as a function that accepts ErrMsg and arguments
type MethodType = (
  errMsg: ref.Pointer<ErrMsgStruct>,
  ...args: unknown[]
) => void

/**
 * Handles the response from an FFI call.
 *
 * @param method - The FFI method to invoke.
 * @param errMsg - A pointer to the ErrMsg structure for capturing errors.
 * @param format - The expected format of the result.
 * @param args - Additional arguments to pass to the method.
 * @returns A Promise resolving with the FFI result or rejecting with an error.
 */
export async function handleResponse(
  method: MethodType,
  errMsg: ref.Pointer<ErrMsgStruct>,
  format: FFIResultFormat,
  ...args: unknown[]
): Promise<FFIResult> {
  return new Promise((resolve, reject) => {
    method(errMsg, ...args, (_err: unknown, res: ErrMsgStruct) => {
      const resErrMsg = errMsg.deref()

      console.log(resErrMsg)
      console.log(resErrMsg.toJSON())

      if (!resErrMsg.is_none) {
        // If the error message is not "none", reject the promise with the error.
        const errorMessage = resErrMsg.ptr
          .reinterpret(resErrMsg.len)
          .toString('utf-8')
        reject(new Error(errorMessage))
      } else if (res.is_none) {
        // Handle case where result is "none".
        reject(new Error('Unknown error occurred'))
      } else {
        try {
          const buffer = Buffer.from(
            res.ptr.reinterpret(res.len).toString('utf-8')
          )
          const result = buffer.subarray(0, res.cap).toString('utf-8')
          resolve(result)
        } catch (e) {
          // Catch any error that occurs during processing and reject the promise.
          const error =
            e instanceof Error ? e : new Error('Unknown processing error')
          reject(
            new Error(
              `Failed to process pointer. Expected format: ${format}. Error: ${error.message}`
            )
          )
        }
      }
    })
  })
}

/**
 * Creates and initializes a raw ErrMsg structure.
 *
 * @returns A pointer to the initialized ErrMsg structure.
 */
export function createRawErrMsg(): ref.Pointer<ErrMsgStruct> {
  const errMsg = ref.alloc(UnmanagedVectorType) as ref.Pointer<ErrMsgStruct>
  const rawErrMsg = errMsg.deref()

  rawErrMsg.is_none = true
  rawErrMsg.ptr = ref.NULL
  rawErrMsg.len = 0
  rawErrMsg.cap = 0

  return errMsg
}
