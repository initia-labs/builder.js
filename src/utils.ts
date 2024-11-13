import ref from '@eleccookie/ref-napi'
import struct from 'ref-struct-di'
import { UnmanagedVectorType, FFIResult } from './types'
import { Buffer } from 'buffer'

// define the structure for ErrMsg and Result
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
 * @param args - Additional arguments to pass to the method.
 * @returns A Promise resolving with the FFI result or rejecting with an error.
 */
export async function handleResponse(
  method: MethodType,
  errMsg: ref.Pointer<ErrMsgStruct>,
  ...args: unknown[]
): Promise<FFIResult> {
  return new Promise((resolve, reject) => {
    method(errMsg, ...args, (_err: unknown, res: ErrMsgStruct) => {
      const errorData = errMsg.deref()

      if (errorData && !errorData.is_none) {
        const errorMessage = errorData.ptr
          .reinterpret(errorData.len)
          .toString('utf-8')
        return reject(new Error(errorMessage))
      }

      if (!res || res.is_none) {
        return reject(new Error('Unknown error occurred'))
      }

      try {
        const result = parseFFIResult(res)
        resolve(result)
      } catch (error) {
        reject(
          new Error(
            `Failed to process pointer. Error: ${error instanceof Error ? error.message : 'Unknown processing error'}`
          )
        )
      }
    })
  })
}

/**
 * Parses the FFI result buffer based on the provided format.
 * @param res - The FFI result struct containing the pointer to result data.
 * @param format - The expected format of the FFI result.
 * @returns Parsed FFI result as a string.
 */
function parseFFIResult(res: ErrMsgStruct): string {
  const buffer = Buffer.from(res.ptr.reinterpret(res.len).toString('utf-8'))
  return buffer.subarray(0, res.cap).toString('utf-8')
}

/**
 * Creates and initializes a raw ErrMsg structure.
 *
 * @returns A pointer to the initialized ErrMsg structure.
 */
export function createRawErrMsg(): ref.Pointer<ErrMsgStruct> {
  // allocate memory for ErrMsg structure
  const errMsg = ref.alloc(UnmanagedVectorType) as ref.Pointer<ErrMsgStruct>
  const rawErrMsg = errMsg.deref()

  rawErrMsg.is_none = true
  rawErrMsg.ptr = ref.NULL
  rawErrMsg.len = 0
  rawErrMsg.cap = 0

  return errMsg
}
