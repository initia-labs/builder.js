import { bcs, BcsType } from '@mysten/bcs'
interface CompilerBuildConfig {
  [key: string]: BcsType<unknown, unknown>
  dev_mode: BcsType<boolean>
  test_mode: BcsType<boolean>
  generate_docs: BcsType<boolean>
  generate_abis: BcsType<boolean>
  install_dir: BcsType<string | null, string | null | undefined>
  force_recompilation: BcsType<boolean>
  fetch_deps_only: BcsType<boolean>
  skip_fetch_latest_git_deps: BcsType<boolean>
  bytecode_version: BcsType<number>
  compiler_version: BcsType<string>
  language_version: BcsType<string>
  additional_named_addresses: BcsType<
    [string, string][],
    Iterable<[string, string]> & { length: number }
  >
}
// Build Config Bcs
const compilerBuildConfig: CompilerBuildConfig = {
  dev_mode: bcs.bool(),
  test_mode: bcs.bool(),
  generate_docs: bcs.bool(),
  generate_abis: bcs.bool(),
  install_dir: bcs.option(bcs.string()),
  force_recompilation: bcs.bool(),
  fetch_deps_only: bcs.bool(),
  skip_fetch_latest_git_deps: bcs.bool(),
  bytecode_version: bcs.u32(),
  compiler_version: bcs.string(),
  language_version: bcs.string(),
  additional_named_addresses: bcs.vector(
    bcs.tuple([bcs.string(), bcs.string()]) as BcsType<
      [string, string],
      [string, string]
    >
  ),
}
// eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-call
export const compilerPayloadBcsType = bcs.struct('CompilerArguments', {
  package_path: bcs.option(bcs.string()),
  verbose: bcs.bool(),
  // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-call
  build_config: bcs.struct('BuildConfig', compilerBuildConfig),
})

const testOption = {
  filter: bcs.option(bcs.string()),
  report_statistics: bcs.bool(),
  report_storage_on_error: bcs.bool(),
  ignore_compile_warnings: bcs.bool(),
  compute_coverage: bcs.bool(),
}

// eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-call
export const testOptBcsType = bcs.struct('TestOptions', testOption)
