import ref from '@eleccookie/ref-napi'
import ffi from '@eleccookie/ffi-napi'
import * as path from 'path'
import {
  UnmanagedVectorPtr,
  ByteSliceViewType,
  UnmanagedVectorType,
} from './types'

// determine library file names based on platform and architecture
let compilerName: string
let movevmName: string

if (process.platform == 'darwin') {
  // macOS
  compilerName = 'libcompiler.dylib'
  movevmName = 'libmovevm.dylib'
} else if (process.platform == 'linux' && process.arch == 'arm64') {
  // linux arm64
  compilerName = 'libcompiler.aarch64.so'
  movevmName = 'libmovevm.aarch64.so'
} else if (process.platform == 'linux' && process.arch == 'x64') {
  // linux x64
  compilerName = 'libcompiler.x86_64.so'
  movevmName = 'libmovevm.x86_64.so'
} else {
  // unsupported platform/architecture
  throw new Error(`${process.platform}/${process.arch} not supported`)
}

// load the libcompiler library and define its FFI function signatures
export const libcompiler = ffi.Library(
  path.resolve(__dirname, `../library/${compilerName}`),
  {
    create_new_move_package: [
      UnmanagedVectorType,
      [
        UnmanagedVectorPtr,
        ByteSliceViewType,
        ByteSliceViewType,
        ByteSliceViewType,
        ref.types.bool,
      ],
    ],
    clean_move_package: [
      UnmanagedVectorType,
      [
        UnmanagedVectorPtr,
        ByteSliceViewType,
        ref.types.bool,
        ref.types.bool,
        ref.types.bool,
      ],
    ],
    build_move_package: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewType],
    ],
    test_move_package: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewType, ByteSliceViewType],
    ],
  }
)

// load the libmovevm library and define its FFI function signatures
export const libmovevm = ffi.Library(
  path.resolve(__dirname, `../library/${movevmName}`),
  {
    read_module_info: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewType],
    ],
    stringify_struct_tag: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewType],
    ],
    parse_struct_tag: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewType],
    ],
    decode_module_bytes: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewType],
    ],
    decode_script_bytes: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewType],
    ],
  }
)
