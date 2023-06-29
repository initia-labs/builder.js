import * as ffi from 'ffi-napi';
import * as ref from 'ref-napi';
import struct = require('ref-struct-di');
import path = require('path');
import { readFile } from 'fs/promises';
import {
  UnmanagedVectorType,
  UnmanagedVectorPtr,
  InitiaCompilerArgumentType,
  ByteSliceViewType,
  BuildOptions,
  TestOptions,
  InitiaCompilerTestOptionType,
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

const libinitiavm = ffi.Library(path.resolve(__dirname, `../${libraryName}`), {
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
});

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
   * Execute move compiler to generate move bytecode
   *
   * @returns if success return "ok", else throw an error
   */
  public async build(): Promise<string | null> {
    const errMsg = ref.alloc(UnmanagedVectorType);
    const rawErrMsg = errMsg.deref();

    rawErrMsg.is_none = true;
    rawErrMsg.ptr = ref.NULL;
    rawErrMsg.len = 0;
    rawErrMsg.cap = 0;

    const rawArgs = this.makeRawBuildConfig();

    return new Promise((resolve, reject) => {
      libinitiavm.build_move_package.async(
        errMsg,
        rawArgs,
        function (_err, res) {
          const resErrMsg = errMsg.deref();
          if (!resErrMsg.is_none) {
            const errorMessage = Buffer.from(
              resErrMsg.ptr.buffer.slice(0, resErrMsg.len as number)
            ).toString('utf-8');

            reject(new Error(errorMessage));
          } else if (res.is_none) {
            reject(new Error('unknown error'));
          } else {
            const resMessage = Buffer.from(
              res.ptr.buffer.slice(0, res.len as number)
            ).toString('utf-8');
            resolve(resMessage);
          }
        }
      );
    });
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
   * @returns name converted module bytes
   */
  public static async convert_module_name(
    precompiledBinary: Buffer,
    moduleName: string
  ): Promise<Buffer> {
    // make empty err msg
    const errMsg = ref.alloc(UnmanagedVectorType);
    const rawErrMsg = errMsg.deref();

    rawErrMsg.is_none = true;
    rawErrMsg.ptr = ref.NULL;
    rawErrMsg.len = 0;
    rawErrMsg.cap = 0;

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

    return new Promise((resolve, reject) => {
      libinitiavm.convert_module_name.async(
        errMsg,
        rawPrecompiledView,
        rawModuleNameView,
        function (_err, res) {
          const resErrMsg = errMsg.deref();
          if (!resErrMsg.is_none) {
            const errorMessage = Buffer.from(
              resErrMsg.ptr.buffer.slice(0, resErrMsg.len as number)
            ).toString('utf-8');

            reject(new Error(errorMessage));
          } else if (res.is_none) {
            reject(new Error('unknown error'));
          } else {
            const resultBinary = Buffer.from(
              res.ptr.buffer.slice(0, res.len as number)
            );
            resolve(resultBinary);
          }
        }
      );
    });
  }

  /**
   *
   * Execute move compiler to unittest
   *
   * @param testOptions move package test options
   *
   * @returns if success return "ok", else throw an error
   */
  public async test(options: TestOptions): Promise<string | null> {
    const errMsg = ref.alloc(UnmanagedVectorType);
    const rawErrMsg = errMsg.deref();

    rawErrMsg.is_none = true;
    rawErrMsg.ptr = ref.NULL;
    rawErrMsg.len = 0;
    rawErrMsg.cap = 0;

    const buildRawArgs = this.makeRawBuildConfig();

    buildRawArgs.package_path.is_nil = false;
    buildRawArgs.package_path.ptr = ref.allocCString(this.packagePath, 'utf-8');
    buildRawArgs.package_path.len = Buffer.from(
      this.packagePath,
      'utf-8'
    ).length;

    const testArgs = ref.alloc(InitiaCompilerTestOptionType);
    const testRawArgs = testArgs.deref();

    testRawArgs.gas_limit = options.gasLimit || 1000000000;
    testRawArgs.list = options.list || false;
    testRawArgs.num_threads = options.numThreads || 1;
    testRawArgs.report_statistics = options.reportStatistics || false;
    testRawArgs.report_storage_on_error = options.reportStorageOnError || false;
    testRawArgs.ignore_compile_warnings =
      options.ignoreCompileWarnings || false;
    testRawArgs.check_stackless_vm = options.checkStacklessVm || false;
    testRawArgs.verbose_mode = options.verboseMode || false;
    testRawArgs.compute_coverage = options.computeCoverage || false;

    return new Promise((resolve, reject) => {
      libinitiavm.test_move_package.async(
        errMsg,
        buildRawArgs,
        testRawArgs,
        function (_err, res) {
          const resErrMsg = errMsg.deref();
          if (!resErrMsg.is_none) {
            const errorMessage = Buffer.from(
              resErrMsg.ptr.buffer.slice(0, resErrMsg.len as number)
            ).toString('utf-8');

            reject(new Error(errorMessage));
          } else if (res.is_none) {
            reject(new Error('unknown error'));
          } else {
            const resMessage = Buffer.from(
              res.ptr.buffer.slice(0, res.len as number)
            ).toString('utf-8');
            resolve(resMessage);
          }
        }
      );
    });
  }
}
