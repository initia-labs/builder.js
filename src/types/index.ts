import ref from '@eleccookie/ref-napi'
import struct from 'ref-struct-di'

const StructType = struct(ref)
export type FFIResult = string | Buffer | null
export type FFIResultFormat = 'utf-8' | 'buffer'

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

///////////////////
//  clean config //
///////////////////

export interface CleanOptions {
  cleanCache?: boolean
  cleanByProduct?: boolean
  force?: boolean
}

///////////////////
//  build config //
///////////////////
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
}

export interface TestOptions {
  gasLimit?: number
  filter?: string
  list?: boolean
  numThreads?: number
  reportStatistics?: boolean
  reportStorageOnError?: boolean
  ignoreCompileWarnings?: boolean
  checkStacklessVm?: boolean
  verboseMode?: boolean
  computeCoverage?: boolean
}
