/* eslint-disable @typescript-eslint/unbound-method */
import ref from '@eleccookie/ref-napi'
import * as path from 'path'
import { readdir, readFile } from 'fs/promises'
import { handleResponse, createRawErrMsg, libcompiler, libmovevm } from './lib'
import {
  ByteSliceViewType,
  FFIResult,
  BuildOptions,
  CleanOptions,
  compilerPayloadBcsType,
  testOptBcsType,
  TestOptions,
} from './types'

type ModuleName = string

export class MoveBuilder {
  private readonly packagePath: string
  private buildOptions: BuildOptions

  /**
   * Create a MoveBuilder.
   * @param packagePath - Full path to package directory.
   * @param buildOptions - Move package build options.
   */
  constructor(packagePath: string, buildOptions: BuildOptions) {
    this.packagePath = packagePath
    this.buildOptions = buildOptions
  }

  /**
   * Create raw build configuration.
   * @returns Raw build configuration.
   */
  private makeRawBuildConfig = () => {
    const additionalNamedAddresses: [string, Uint8Array][] = this.buildOptions
      .additionalNamedAddresses
      ? this.buildOptions.additionalNamedAddresses.map(([name, address]) => {
          if (address.startsWith('0x')) {
            address = address.slice(2).padStart(64, '0')
          }
          return [name, Buffer.from(address, 'hex')]
        })
      : []

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
            additional_named_addresses: additionalNamedAddresses,
          },
        })
        .toBytes()
    )

    const compilerPayload = ref.alloc(ByteSliceViewType)
    const rawCompilerPayload = compilerPayload.deref()
    rawCompilerPayload.is_nil = false
    rawCompilerPayload.len = compilerPayloadBytes.length
    rawCompilerPayload.ptr = ref.allocCString(
      compilerPayloadBytes.toString('base64'),
      'base64'
    )

    return rawCompilerPayload
  }

  private async getPackageName(): Promise<string> {
    const moveTomlPath = path.join(this.packagePath, 'Move.toml')
    const moveToml = await readFile(moveTomlPath).catch(() => {
      throw new Error('Move.toml file not found at ${moveTomlPath}')
    })
    const packageNameLine = new RegExp(/(name\s=\s"[0-9a-zA-Z_]+")/).exec(
      moveToml.toString('utf-8')
    )
    if (packageNameLine === null || packageNameLine.length === 0) {
      throw new Error('Move.toml is missing or has invalid "name" field format')
    }
    const packageName = new RegExp(/"[0-9a-zA-Z_]+"/).exec(packageNameLine[0])
    if (packageName === null || packageName.length === 0) {
      throw new Error('Move.toml is missing or has invalid "name" field format')
    }
    return packageName[0].slice(1, -1)
  }

  private async readFiles(
    subdir: string,
    extension: string
  ): Promise<Record<ModuleName, Buffer>> {
    const packageName = await this.getPackageName()
    const dirPath = path.join(this.packagePath, 'build', packageName, subdir)
    const files = await readdir(dirPath).catch(() => {
      throw new Error(`Directory not found: ${dirPath}`)
    })
    const filteredFiles = files.filter((file) => file.endsWith(extension))
    if (filteredFiles.length === 0) {
      throw new Error(
        `No files found with extension "${extension}" in ${dirPath}`
      )
    }
    const results = await Promise.all(
      filteredFiles.map(async (file) => {
        const name = file.slice(0, -extension.length)
        const content = await readFile(path.join(dirPath, file)).catch(() => {
          throw new Error(`Failed to read file: ${file}`)
        })
        return { name, content }
      })
    )
    return results.reduce(
      (acc, { name, content }) => {
        acc[name] = content
        return acc
      },
      {} as Record<ModuleName, Buffer>
    )
  }
  /**
   * Execute move compiler to generate new move package.
   * @param packageName - Name of the package.
   * @param moveVersion - Version of the move (default is 'main').
   * @param minitia - Boolean flag for minitia (default is false).
   * @returns If success, return "ok", else throw an error.
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
      rawCompilerArgsPayload,
      rawPackageNameView,
      rawMoveVersionView,
      minitia
    )
  }

  /**
   * Execute move compiler to clean move package.
   * @param options - Options for cleaning the package.
   * @returns If success, return "ok", else throw an error.
   */
  public async clean(options?: CleanOptions): Promise<FFIResult> {
    const errMsg = createRawErrMsg()
    const rawCompilerArgsPayload = this.makeRawBuildConfig()

    return handleResponse(
      libcompiler.clean_move_package.async,
      errMsg,
      rawCompilerArgsPayload,
      options?.cleanCache || false,
      options?.cleanByProduct || false,
      true
    )
  }

  /**
   * Execute move compiler to generate move bytecode.
   * @returns If success, return "ok", else throw an error.
   */
  public async build(): Promise<FFIResult> {
    const errMsg = createRawErrMsg()
    const rawCompilerArgsPayload = this.makeRawBuildConfig()

    return handleResponse(
      libcompiler.build_move_package.async,
      errMsg,
      rawCompilerArgsPayload
    )
  }

  /**
   * Return compiled Move module bytecode.
   * @returns The module bytecode.
   */
  public async getAll(): Promise<Record<ModuleName, Buffer>> {
    return this.readFiles('bytecode_modules', '.mv')
  }

  /**
   * Return compiled Move module bytecode.
   * @param moduleName - The module name to retrieve.
   * @returns The module bytecode.
   */
  public async get(moduleName: string): Promise<Buffer> {
    const bytecodeModules = await this.readFiles('bytecode_modules', '.mv')
    if (!bytecodeModules[moduleName]) {
      throw new Error(`Bytecode for module ${moduleName} not found`)
    }
    return bytecodeModules[moduleName]
  }

  /**
   * Return compiled Move module source map.
   * @returns The module source map.
   */
  public async getAllSourceMaps(): Promise<Record<ModuleName, Buffer>> {
    return this.readFiles('source_maps', '.mvsm')
  }

  /**
   * Return compiled Move module source map.
   * @param moduleName - The module name to retrieve.
   * @returns The module source map.
   */
  public async getSourceMap(moduleName: string): Promise<Buffer> {
    const sourceMaps = await this.readFiles('source_maps', '.mvsm')
    if (!sourceMaps[moduleName]) {
      throw new Error(`Source map for module ${moduleName} not found`)
    }
    return sourceMaps[moduleName]
  }

  /**
   * Execute move compiler to unittest.
   * @param options - Move package test options.
   * @returns If success, return "ok", else throw an error.
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
    rawTestOpt.ptr = ref.allocCString(testOptBytes.toString('base64'), 'base64')

    return handleResponse(
      libcompiler.test_move_package.async,
      errMsg,
      rawCompilerArgsPayload,
      rawTestOpt
    )
  }

  /**
   * Decode module bytes to move module.
   * @param moduleBytes - Move module bytes.
   * @returns If success, return buffer, else throw an error.
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
      rawModuleBytesView
    )
  }

  /**
   * Decode script bytes to move function.
   * @param scriptBytes - Move script bytes.
   * @returns If success, return buffer, else throw an error.
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
      rawScriptBytesView
    )
  }

  /**
   * Read module info from bytes.
   * @param compiledBinary - Move compiled bytes.
   * @returns If success, return buffer, else throw an error.
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
      rawCompiledView
    )
  }
}
