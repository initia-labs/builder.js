import { bcs } from '@initia/initia.js'
// BCS Type for serializing CompilerBuildConfig
const compilerBuildConfig = {
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
    bcs.tuple([bcs.string(), bcs.address()])
  ),
}

// BCS Type for serializing CompilerBuildConfig
const testOption = {
  filter: bcs.option(bcs.string()),
  report_statistics: bcs.bool(),
  report_storage_on_error: bcs.bool(),
  ignore_compile_warnings: bcs.bool(),
  compute_coverage: bcs.bool(),
}

export const compilerPayloadBcsType = bcs.struct('CompilerArguments', {
  package_path: bcs.option(bcs.string()),
  verbose: bcs.bool(),
  build_config: bcs.struct('BuildConfig', compilerBuildConfig),
})

export const testOptBcsType = bcs.struct('TestOptions', testOption)
