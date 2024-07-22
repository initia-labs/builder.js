import  ref from 'ref-napi';
import struct = require('ref-struct-di');

import { UnmanagedVectorType, FFIResultFromat, FFIResult } from './types';

export async function handleResponse(
  method: Function,
  errMsg: ref.Pointer<
    struct.StructObject<{
      is_none: boolean;
      ptr: ref.Pointer<string | null>;
      len: string | number;
      cap: string | number;
    }>
  >,
  format: FFIResultFromat,
  ...args: any[]
): Promise<FFIResult> {
  return new Promise((resolve, reject) => {
    method(
      errMsg,
      ...args,
      (
        _err: any,
        res: struct.StructObject<{
          is_none: boolean;
          ptr: ref.Pointer<string | null>;
          len: string | number;
          cap: string | number;
        }>
      ) => {
        const resErrMsg = errMsg.deref();
        if (!resErrMsg.is_none) {
          const errorMessage = Buffer.from(
            resErrMsg.ptr.buffer.slice(0, resErrMsg.len as number)
          ).toString('utf-8');

          reject(new Error(errorMessage));
        } else if (res.is_none) {
          reject(new Error('unknown error'));
        } else {
          const result = Buffer.from(
            res.ptr.buffer.slice(0, res.len as number)
          );
          resolve(format === 'utf-8' ? result.toString('utf-8') : result);
        }
      }
    );
  });
}

export function createRawErrMsg() {
  const errMsg = ref.alloc(UnmanagedVectorType);
  const rawErrMsg = errMsg.deref();

  rawErrMsg.is_none = true;
  rawErrMsg.ptr = ref.NULL;
  rawErrMsg.len = 0;
  rawErrMsg.cap = 0;

  return errMsg;
}
