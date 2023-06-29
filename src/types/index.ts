import * as ref from 'ref-napi';
import struct = require('ref-struct-di');
import path = require('path');

const StructType = struct(ref);
export const UnmanagedVectorType = StructType({
  is_none: ref.types.bool,
  ptr: ref.refType(ref.types.CString),
  len: ref.types.size_t,
  cap: ref.types.size_t,
});
export const UnmanagedVectorPtr = ref.refType(UnmanagedVectorType);

export const ByteSliceViewType = StructType({
  is_nil: ref.types.bool,
  ptr: ref.refType(ref.types.CString),
  len: ref.types.size_t,
});

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
});

export const InitiaCompilerArgumentType = StructType({
  package_path: ByteSliceViewType,
  verbose: ref.types.bool,
  build_config: InitiaCompilerBuildConfig,
});

export interface BuildOptions {
  devMode?: boolean;
  testMode?: boolean;
  generateDocs?: boolean;
  generateAbis?: boolean;
  installDir?: string;
  forceRecompilation?: boolean;
  fetchDepsOnly?: boolean;
  skipFetchLatestGitDeps?: boolean;
  bytecodeVersion?: number;
}

////////////////////
//   test config  //
////////////////////

export interface TestOptions {
  gasLimit?: number;
  list?: boolean;
  numThreads?: number;
  reportStatistics?: boolean;
  reportStorageOnError?: boolean;
  ignoreCompileWarnings?: boolean;
  checkStacklessVm?: boolean;
  verboseMode?: boolean;
  computeCoverage?: boolean;
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
});
