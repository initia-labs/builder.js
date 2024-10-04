import ref from '@eleccookie/ref-napi'
import ffi from '@eleccookie/ffi-napi'
import * as path from 'path'
import {
  UnmanagedVectorType,
  UnmanagedVectorPtr,
  ByteSliceViewPtr,
} from './types'

let compilerName: string
let movevmName: string
if (process.platform == 'darwin') {
  compilerName = 'libcompiler.dylib'
  movevmName = 'libmovevm.dylib'
} else if (process.platform == 'linux' && process.arch == 'arm64') {
  compilerName = 'libcompiler.aarch64.so'
  movevmName = 'libmovevm.aarch64.so'
} else if (process.platform == 'linux' && process.arch == 'x64') {
  compilerName = 'libcompiler.x86_64.so'
  movevmName = 'libmovevm.x86_64.so'
} else {
  throw new Error(`${process.platform}/${process.arch} not supported`)
}

export const libcompiler = ffi.Library(
  path.resolve(__dirname, `../library/${compilerName}`),
  {
    create_new_move_package: [
      UnmanagedVectorType,
      [
        UnmanagedVectorPtr,
        ByteSliceViewPtr,
        ByteSliceViewPtr,
        ByteSliceViewPtr,
        ref.types.bool,
      ],
    ],
    clean_move_package: [
      UnmanagedVectorType,
      [
        UnmanagedVectorPtr,
        ByteSliceViewPtr,
        ref.types.bool,
        ref.types.bool,
        ref.types.bool,
      ],
    ],
    build_move_package: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewPtr],
    ],
    test_move_package: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewPtr, ByteSliceViewPtr],
    ],
  }
)

export const libmovevm = ffi.Library(
  path.resolve(__dirname, `../library/${movevmName}`),
  {
    convert_module_name: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewPtr, ByteSliceViewPtr],
    ],
    read_module_info: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewPtr],
    ],
    stringify_struct_tag: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewPtr],
    ],
    parse_struct_tag: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewPtr],
    ],
    decode_module_bytes: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewPtr],
    ],
    decode_script_bytes: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewPtr],
    ],
  }
)
