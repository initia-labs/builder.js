/* eslint-disable @typescript-eslint/unbound-method */
import ref from '@eleccookie/ref-napi'
import path = require('path')
import { readFile } from 'fs/promises'
import {
  ByteSliceViewType,
  BuildOptions,
  TestOptions,
  FFIResult,
  CleanOptions,
} from './types'
import { libcompiler, libmovevm } from './vm'
import { handleResponse, createRawErrMsg } from './utils'
import { compilerPayloadBcsType, testOptBcsType } from './types/bcs'

export class MoveBuilder {
  private readonly packagePath: string
  private buildOptions: BuildOptions

  /**
   *
   * @param packagePath full path to package directory
   * @param buildOptions move package build options
   */
  constructor(packagePath: string, buildOptions: BuildOptions) {
    this.packagePath = packagePath
    this.buildOptions = buildOptions
  }

  makeRawBuildConfig = () => {
    const compilerPayloadBytes = Buffer.from(
      compilerPayloadBcsType
        .serialize({
          package_path: this.packagePath,
          verbose: false,
          build_config: {
            dev_mode: this.buildOptions.devMode || false,
            test_mode: this.buildOptions.testMode || false,
            generate_docs: this.buildOptions.generateDocs || false,
            generate_abis: this.buildOptions.generateAbis || false,
            install_dir: this.buildOptions.installDir || '',
            force_recompilation: this.buildOptions.forceRecompilation || false,
            fetch_deps_only: this.buildOptions.fetchDepsOnly || false,
            skip_fetch_latest_git_deps:
              this.buildOptions.skipFetchLatestGitDeps || false,
            bytecode_version: this.buildOptions.bytecodeVersion || 0,
            compiler_version: this.buildOptions.compilerVersion || '0',
            language_version: this.buildOptions.languageVersion || '0',
            additional_named_addresses:
              this.buildOptions.addtionalNamedAddresses || [],
          },
        })
        .toBytes()
    )
    const compilerPayload = ref.alloc(ByteSliceViewType)
    const rawCompilerPayload = compilerPayload.deref()
    rawCompilerPayload.is_nil = false
    rawCompilerPayload.len = compilerPayloadBytes.length
    rawCompilerPayload.ptr = ref.allocCString(
      compilerPayloadBytes.toString(),
      'utf-8'
    )
    return rawCompilerPayload
  }

  /**
   *
   * Execute move compiler to generate new move package
   *
   * @returns if success return "ok", else throw an error
   */
  public new(
    packageName: string,
    moveVersion = 'main',
    minitia = false
  ): Promise<FFIResult> {
    const errMsg = createRawErrMsg()
    const rawCompilerArgsPayload = this.makeRawBuildConfig()

    const packageNameView = ref.alloc(ByteSliceViewType)
    const rawPackageNameView = packageNameView.deref()
    rawPackageNameView.is_nil = false
    rawPackageNameView.ptr = ref.allocCString(packageName, 'utf-8')
    rawPackageNameView.len = Buffer.from(packageName, 'utf-8').length

    const moveVersionView = ref.alloc(ByteSliceViewType)
    const rawMoveVersionView = moveVersionView.deref()
    rawMoveVersionView.is_nil = !moveVersion
    rawMoveVersionView.ptr = moveVersion
      ? ref.allocCString(moveVersion)
      : ref.NULL
    rawMoveVersionView.len = Buffer.from(moveVersion, 'utf-8').length
    return handleResponse(
      libcompiler.create_new_move_package.async,
      errMsg,
      'utf-8',
      rawCompilerArgsPayload,
      rawPackageNameView,
      rawMoveVersionView,
      minitia
    )
  }

  /**
   *
   * Execute move compiler to clean move package
   *
   * @returns if success return "ok", else throw an error
   */
  public async clean(options?: CleanOptions): Promise<FFIResult> {
    const errMsg = createRawErrMsg()
    const rawCompilerArgsPayload = this.makeRawBuildConfig()

    return handleResponse(
      libcompiler.clean_move_package.async,
      errMsg,
      'utf-8',
      rawCompilerArgsPayload,
      options?.cleanCache || false,
      options?.cleanByProduct || false,
      options?.force === undefined ? true : options?.force
    )
  }

  /**
   *
   * Execute move compiler to generate move bytecode
   *
   * @returns if success return "ok", else throw an error
   */
  public async build(): Promise<FFIResult> {
    const errMsg = createRawErrMsg()
    const rawCompilerArgsPayload = this.makeRawBuildConfig()

    return handleResponse(
      libcompiler.build_move_package.async,
      errMsg,
      'utf-8',
      rawCompilerArgsPayload
    )
  }

  /**
   *
   * Return compiled Move module bytecode.
   *
   * @param moduleName the module name to retrieve
   * @returns the module bytecode
   */
  public async get(moduleName: string): Promise<Buffer> {
    const moveTomlPath = path.join(this.packagePath, 'Move.toml')
    const moveToml = await readFile(moveTomlPath)

    const packageNameLine = new RegExp(/(name\s=\s"[1-9a-zA-Z_]+")/).exec(
      moveToml.toString('utf-8')
    )
    if (packageNameLine === null || packageNameLine.length === 0) {
      throw new Error('failed to lookup package name from Move.toml')
    }

    const packageName = new RegExp(/"[1-9a-zA-Z_]+"/).exec(packageNameLine[0])
    if (packageName === null || packageName.length === 0) {
      throw new Error('failed to lookup package name from Move.toml')
    }

    const bytecodePath = path.join(
      this.packagePath,
      'build',
      packageName[0].slice(1, -1),
      'bytecode_modules',
      moduleName + '.mv'
    )

    return readFile(bytecodePath)
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
    const errMsg = createRawErrMsg()
    const rawCompilerArgsPayload = this.makeRawBuildConfig()
    const testOptBytes = Buffer.from(
      testOptBcsType
        .serialize({
          filter: options?.filter || '',
          report_statistics: options?.reportStatistics || false,
          report_storage_on_error: options?.reportStorageOnError || false,
          ignore_compile_warnings: options?.ignoreCompileWarnings || false,
          compute_coverage: options?.computeCoverage || false,
        })
        .toBytes()
    )
    const testOpt = ref.alloc(ByteSliceViewType)
    const rawTestOpt = testOpt.deref()
    rawTestOpt.is_nil = false
    rawTestOpt.len = testOptBytes.length
    rawTestOpt.ptr = ref.allocCString(testOptBytes.toString(), 'utf-8')
    return handleResponse(
      libcompiler.test_move_package.async,
      errMsg,
      'utf-8',
      rawCompilerArgsPayload,
      rawTestOpt
    )
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
    const errMsg = createRawErrMsg()

    const precompiledView = ref.alloc(ByteSliceViewType)
    const rawPrecompiledView = precompiledView.deref()
    rawPrecompiledView.is_nil = false
    rawPrecompiledView.ptr = ref.allocCString(
      precompiledBinary.toString('base64'),
      'base64'
    )
    rawPrecompiledView.len = precompiledBinary.length

    const moduleNameView = ref.alloc(ByteSliceViewType)
    const rawModuleNameView = moduleNameView.deref()
    rawModuleNameView.is_nil = false
    rawModuleNameView.ptr = ref.allocCString(moduleName, 'utf-8')
    rawModuleNameView.len = Buffer.from(moduleName, 'utf-8').length

    return handleResponse(
      libmovevm.convert_module_name.async,
      errMsg,
      'buffer',
      rawPrecompiledView,
      rawModuleNameView
    )
  }

  /**
   *
   * Decode module bytes to move module
   *
   * @param moduleBytes move module bytes
   *
   * @returns if success return buffer, else throw an error
   */
  public static async decode_module_bytes(
    moduleBytes: Buffer
  ): Promise<FFIResult> {
    const errMsg = createRawErrMsg()

    const moduleBytesView = ref.alloc(ByteSliceViewType)
    const rawModuleBytesView = moduleBytesView.deref()
    rawModuleBytesView.is_nil = false
    rawModuleBytesView.ptr = ref.allocCString(
      moduleBytes.toString('base64'),
      'base64'
    )
    rawModuleBytesView.len = moduleBytes.length

    return handleResponse(
      libmovevm.decode_module_bytes.async,
      errMsg,
      'utf-8',
      rawModuleBytesView
    )
  }

  /**
   *
   * Decode script bytes to move function
   *
   * @param scriptBytes move script bytes
   *
   * @returns if success return buffer, else throw an error
   */
  public static async decode_script_bytes(
    scriptBytes: Buffer
  ): Promise<FFIResult> {
    const errMsg = createRawErrMsg()

    const scriptBytesView = ref.alloc(ByteSliceViewType)
    const rawScriptBytesView = scriptBytesView.deref()
    rawScriptBytesView.is_nil = false
    rawScriptBytesView.ptr = ref.allocCString(
      scriptBytes.toString('base64'),
      'base64'
    )
    rawScriptBytesView.len = scriptBytes.length

    return handleResponse(
      libmovevm.decode_script_bytes.async,
      errMsg,
      'utf-8',
      rawScriptBytesView
    )
  }

  /**
   *
   * Read module info from bytes
   *
   * @param compiledBinary move compiled bytes
   *
   * @returns if success return buffer, else throw an error
   */
  public static async read_module_info(
    compiledBinary: Buffer
  ): Promise<FFIResult> {
    const errMsg = createRawErrMsg()

    const compiledView = ref.alloc(ByteSliceViewType)
    const rawCompiledView = compiledView.deref()
    rawCompiledView.is_nil = false
    rawCompiledView.ptr = ref.allocCString(
      compiledBinary.toString('base64'),
      'base64'
    )
    rawCompiledView.len = compiledBinary.length

    return handleResponse(
      libmovevm.read_module_info.async,
      errMsg,
      'utf-8',
      rawCompiledView
    )
  }
}
