import ref from '@eleccookie/ref-napi'
import struct from 'ref-struct-di'

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

export interface CleanOptions {
  cleanCache?: boolean
  cleanByProduct?: boolean
  force?: boolean
}

export interface BuildOptions {
  devMode?: boolean
  testMode?: boolean
  generateDocs?: boolean
  generateAbis?: boolean
  installDir?: string
  forceRecompilation?: boolean
  fetchDepsOnly?: boolean
  skipFetchLatestGitDeps?: boolean
  bytecodeVersion?: number
  compilerVersion?: string
  languageVersion?: string
  addtionalNamedAddresses?: [string, string][]
}

export interface TestOptions {
  filter?: string
  reportStatistics?: boolean
  reportStorageOnError?: boolean
  ignoreCompileWarnings?: boolean
  computeCoverage?: boolean
}
