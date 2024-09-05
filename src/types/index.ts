import ref from 'ref-napi'
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
//  prove config //
///////////////////

export interface ProveOptions {
  verbosity?: string
  filter?: string
  trace?: boolean
  cvc5?: boolean
  stratificationDepth?: number
  randomSeed?: number
  procCores?: number
  vcTimeout?: number
  checkInconsistency?: boolean
  keepLoops?: boolean
  loopUnroll?: number
  stableTestOutput?: boolean
  dump?: boolean
  forTest?: boolean
}

export const InitiaCompilerProveOptionType = StructType({
  verbosity: ByteSliceViewType,
  filter: ByteSliceViewType,
  trace: ref.types.bool,
  cvc5: ref.types.bool,
  stratification_depth: ref.types.size_t,
  random_seed: ref.types.size_t,
  proc_cores: ref.types.size_t,
  vc_timeout: ref.types.size_t,
  check_inconsistency: ref.types.bool,
  keep_loops: ref.types.bool,
  loop_unroll: ref.types.uint64,
  stable_test_output: ref.types.bool,
  dump: ref.types.bool,
  for_test: ref.types.bool,
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

export const InitiaCompilerBuildConfig = StructType({
  dev_mode: ref.types.bool,
  test_mode: ref.types.bool,
  generate_docs: ref.types.bool,
  generate_abis: ref.types.bool,
  install_dir: ByteSliceViewType,
  force_recompilation: ref.types.bool,
  fetch_deps_only: ref.types.bool,
  skip_fetch_latest_git_deps: ref.types.bool,
  bytecode_version: ref.types.uint32,
})

export const InitiaCompilerArgumentType = StructType({
  package_path: ByteSliceViewType,
  verbose: ref.types.bool,
  build_config: InitiaCompilerBuildConfig,
})

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

////////////////////
//   test config  //
////////////////////

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

export const InitiaCompilerTestOptionType = StructType({
  gas_limit: ref.types.uint64,
  filter: ByteSliceViewType,
  list: ref.types.bool,
  num_threads: ref.types.size_t,
  report_statistics: ref.types.bool,
  report_storage_on_error: ref.types.bool,
  ignore_compile_warnings: ref.types.bool,
  check_stackless_vm: ref.types.bool,
  verbose_mode: ref.types.bool,
  compute_coverage: ref.types.bool,
})
