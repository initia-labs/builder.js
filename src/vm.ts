import * as ref from 'ref-napi';
import * as ffi from 'ffi-napi';
import path = require('path');
import {
  UnmanagedVectorType,
  UnmanagedVectorPtr,
  InitiaCompilerArgumentType,
  ByteSliceViewType,
  InitiaCompilerTestOptionType,
  InitiaCompilerProveOptionType,
} from './types';

///////////////////////
// Function Definitions

let libraryName: string;
if (process.platform == 'darwin') {
  libraryName = 'libinitia.dylib';
} else if (process.platform == 'linux' && process.arch == 'arm64') {
  libraryName = 'libinitia.aarch64.so';
} else if (process.platform == 'linux' && process.arch == 'x64') {
  libraryName = 'libinitia.x86_64.so';
} else {
  throw new Error(`${process.platform}/${process.arch} not supported`);
}

export const libinitiavm = ffi.Library(
  path.resolve(__dirname, `../${libraryName}`),
  {
    // move
    create_new_move_package: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, InitiaCompilerArgumentType, ByteSliceViewType],
    ],
    clean_move_package: [
      UnmanagedVectorType,
      [
        UnmanagedVectorPtr,
        InitiaCompilerArgumentType,
        ref.types.bool,
        ref.types.bool,
        ref.types.bool,
      ],
    ],
    prove_move_package: [
      UnmanagedVectorType,
      [
        UnmanagedVectorPtr,
        InitiaCompilerArgumentType,
        InitiaCompilerProveOptionType,
      ],
    ],
    build_move_package: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, InitiaCompilerArgumentType],
    ],
    convert_module_name: [
      UnmanagedVectorType,
      [UnmanagedVectorPtr, ByteSliceViewType, ByteSliceViewType],
    ],
    test_move_package: [
      UnmanagedVectorType,
      [
        UnmanagedVectorPtr,
        InitiaCompilerArgumentType,
        InitiaCompilerTestOptionType,
      ],
    ],

    // utils
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
);
