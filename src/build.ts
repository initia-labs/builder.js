import * as ref from 'ref-napi';
import path = require('path');
import { readFile } from 'fs/promises';
import {
  InitiaCompilerArgumentType,
  ByteSliceViewType,
  BuildOptions,
  TestOptions,
  InitiaCompilerTestOptionType,
  FFIResult,
  CleanOptions,
  ProveOptions,
  InitiaCompilerProveOptionType,
} from './types';
import { libinitiavm } from './vm';
import { handleResponse, createRawErrMsg } from './utils';

export class MoveBuilder {
  private packagePath: string;
  private buildOptions: BuildOptions;

  /**
   *
   * @param packagePath full path to package directory
   * @param buildOptions move package build options
   */
  constructor(packagePath: string, buildOptions: BuildOptions) {
    this.packagePath = packagePath;
    this.buildOptions = buildOptions;
  }

  makeRawBuildConfig() {
    // make compiler args
    const compilerArgs = ref.alloc(InitiaCompilerArgumentType);
    const rawArgs = compilerArgs.deref();

    // set package path
    rawArgs.package_path.is_nil = false;
    rawArgs.package_path.ptr = ref.allocCString(this.packagePath, 'utf-8');
    rawArgs.package_path.len = Buffer.from(this.packagePath, 'utf-8').length;

    // set build config
    rawArgs.build_config.dev_mode = this.buildOptions.devMode || false;
    rawArgs.build_config.test_mode = this.buildOptions.testMode || false;
    rawArgs.build_config.generate_docs =
      this.buildOptions.generateDocs || false;
    rawArgs.build_config.generate_abis =
      this.buildOptions.generateAbis || false;
    rawArgs.build_config.force_recompilation =
      this.buildOptions.forceRecompilation || false;
    rawArgs.build_config.fetch_deps_only =
      this.buildOptions.fetchDepsOnly || false;
    rawArgs.build_config.skip_fetch_latest_git_deps =
      this.buildOptions.skipFetchLatestGitDeps || false;
    rawArgs.build_config.bytecode_version =
      this.buildOptions.bytecodeVersion || 6;

    // set install dir
    rawArgs.build_config.install_dir.is_nil = false;
    rawArgs.build_config.install_dir.ptr = ref.allocCString(
      this.buildOptions.installDir || '',
      'utf-8'
    );
    rawArgs.build_config.install_dir.len = Buffer.from(
      this.buildOptions.installDir || '',
      'utf-8'
    ).length;

    return rawArgs;
  }

  /**
   *
   * Execute move compiler to generate new move package
   *
   * @returns if success return "ok", else throw an error
   */
  public async new(packageName: string): Promise<FFIResult> {
    const errMsg = createRawErrMsg();
    const rawArgs = this.makeRawBuildConfig();

    const packageNameView = ref.alloc(ByteSliceViewType);
    const rawPackageNameView = packageNameView.deref();
    rawPackageNameView.is_nil = false;
    rawPackageNameView.ptr = ref.allocCString(packageName, 'utf-8');
    rawPackageNameView.len = Buffer.from(packageName, 'utf-8').length;

    return handleResponse(
      libinitiavm.create_new_move_package.async,
      errMsg,
      'utf-8',
      rawArgs,
      packageNameView
    );
  }

  /**
   *
   * Execute move compiler to clean move package
   *
   * @returns if success return "ok", else throw an error
   */
  public async clean(options?: CleanOptions): Promise<FFIResult> {
    const errMsg = createRawErrMsg();
    const rawArgs = this.makeRawBuildConfig();

    return handleResponse(
      libinitiavm.clean_move_package.async,
      errMsg,
      'utf-8',
      rawArgs,
      options?.cleanCache || false,
      options?.cleanByProduct || false,
      options?.force === undefined ? true : options?.force
    );
  }

  /**
   *
   * Execute move compiler to generate move bytecode
   *
   * @returns if success return "ok", else throw an error
   */
  public async build(): Promise<FFIResult> {
    const errMsg = createRawErrMsg();
    const rawArgs = this.makeRawBuildConfig();

    return handleResponse(
      libinitiavm.build_move_package.async,
      errMsg,
      'utf-8',
      rawArgs
    );
  }

  /**
   *
   * Return compiled Move module bytecode.
   *
   * @param moduleName the module name to retrieve
   * @returns the module bytecode
   */
  public async get(moduleName: string): Promise<Buffer> {
    const moveTomlPath = path.join(this.packagePath, 'Move.toml');
    const moveToml = await readFile(moveTomlPath);

    const packageNameLine = new RegExp(/(name\s=\s"[1-9a-zA-Z_]+")/).exec(
      moveToml.toString('utf-8')
    );
    if (packageNameLine === null || packageNameLine.length === 0) {
      throw new Error('failed to lookup package name from Move.toml');
    }

    const packageName = new RegExp(/"[1-9a-zA-Z_]+"/).exec(packageNameLine[0]);
    if (packageName === null || packageName.length === 0) {
      throw new Error('failed to lookup package name from Move.toml');
    }

    const bytecodePath = path.join(
      this.packagePath,
      'build',
      packageName[0].slice(1, -1),
      'bytecode_modules',
      moduleName + '.mv'
    );

    return readFile(bytecodePath);
  }

  /**
   *
   * @param precompiledBinary precompiled module bytes code
   * @param moduleName the module name to change
   *
   * @returns name converted module bytes
   */
  public static async convert_module_name(
    precompiledBinary: Buffer,
    moduleName: string
  ): Promise<FFIResult> {
    const errMsg = createRawErrMsg();

    const precompiledView = ref.alloc(ByteSliceViewType);
    const rawPrecompiledView = precompiledView.deref();
    rawPrecompiledView.is_nil = false;
    rawPrecompiledView.ptr = ref.allocCString(
      precompiledBinary.toString('base64'),
      'base64'
    );
    rawPrecompiledView.len = precompiledBinary.length;

    const moduleNameView = ref.alloc(ByteSliceViewType);
    const rawModuleNameView = moduleNameView.deref();
    rawModuleNameView.is_nil = false;
    rawModuleNameView.ptr = ref.allocCString(moduleName, 'utf-8');
    rawModuleNameView.len = Buffer.from(moduleName, 'utf-8').length;

    return handleResponse(
      libinitiavm.convert_module_name.async,
      errMsg,
      'buffer',
      rawPrecompiledView,
      rawModuleNameView
    );
  }

  /**
   *
   * Execute move compiler to unittest
   *
   * @param options move package test options
   *
   * @returns if success return "ok", else throw an error
   */
  public async test(options?: TestOptions): Promise<FFIResult> {
    const errMsg = createRawErrMsg();

    const buildRawArgs = this.makeRawBuildConfig();

    buildRawArgs.package_path.is_nil = false;
    buildRawArgs.package_path.ptr = ref.allocCString(this.packagePath, 'utf-8');
    buildRawArgs.package_path.len = Buffer.from(
      this.packagePath,
      'utf-8'
    ).length;

    const testArgs = ref.alloc(InitiaCompilerTestOptionType);
    const testRawArgs = testArgs.deref();

    testRawArgs.gas_limit = options?.gasLimit || 1_000_000;
    testRawArgs.list = options?.list || false;
    testRawArgs.num_threads = options?.numThreads || 1;
    testRawArgs.report_statistics = options?.reportStatistics || false;
    testRawArgs.report_storage_on_error =
      options?.reportStorageOnError || false;
    testRawArgs.ignore_compile_warnings =
      options?.ignoreCompileWarnings || false;
    testRawArgs.check_stackless_vm = options?.checkStacklessVm || false;
    testRawArgs.verbose_mode = options?.verboseMode || false;
    testRawArgs.compute_coverage = options?.computeCoverage || false;

    return handleResponse(
      libinitiavm.test_move_package.async,
      errMsg,
      'utf-8',
      buildRawArgs,
      testRawArgs
    );
  }

  /**
   *
   * Decode module bytes to move module
   *
   * @param moduleBytes move module bytes
   *
   * @returns if success return "ok", else throw an error
   */
  public static async decode_module_bytes(
    moduleBytes: Buffer
  ): Promise<FFIResult> {
    const errMsg = createRawErrMsg();

    const moduleBytesView = ref.alloc(ByteSliceViewType);
    const rawModuleBytesView = moduleBytesView.deref();
    rawModuleBytesView.is_nil = false;
    rawModuleBytesView.ptr = ref.allocCString(
      moduleBytes.toString('base64'),
      'base64'
    );
    rawModuleBytesView.len = moduleBytes.length;

    return handleResponse(
      libinitiavm.decode_module_bytes.async,
      errMsg,
      'utf-8',
      rawModuleBytesView
    );
  }

  /**
   *
   * Decode script bytes to move function
   *
   * @param scriptBytes move script bytes
   *
   * @returns if success return "ok", else throw an error
   */
  public static async decode_script_bytes(
    scriptBytes: Buffer
  ): Promise<FFIResult> {
    const errMsg = createRawErrMsg();

    const scriptBytesView = ref.alloc(ByteSliceViewType);
    const rawScriptBytesView = scriptBytesView.deref();
    rawScriptBytesView.is_nil = false;
    rawScriptBytesView.ptr = ref.allocCString(
      scriptBytes.toString('base64'),
      'base64'
    );
    rawScriptBytesView.len = scriptBytes.length;

    return handleResponse(
      libinitiavm.decode_script_bytes.async,
      errMsg,
      'utf-8',
      rawScriptBytesView
    );
  }

  /**
   *
   * Read module info from bytes
   *
   * @param compiledBinary move compiled bytes
   *
   * @returns if success return "ok", else throw an error
   */
  public static async read_module_info(
    compiledBinary: Buffer
  ): Promise<FFIResult> {
    const errMsg = createRawErrMsg();

    const compiledView = ref.alloc(ByteSliceViewType);
    const rawCompiledView = compiledView.deref();
    rawCompiledView.is_nil = false;
    rawCompiledView.ptr = ref.allocCString(
      compiledBinary.toString('base64'),
      'base64'
    );
    rawCompiledView.len = compiledBinary.length;

    return handleResponse(
      libinitiavm.read_module_info.async,
      errMsg,
      'utf-8',
      rawCompiledView
    );
  }
}
