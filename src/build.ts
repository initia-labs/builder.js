import * as ffi from 'ffi-napi';
import * as ref from 'ref-napi';
import struct = require('ref-struct-di');
import path = require('path');
import { readFile } from 'fs/promises';

///////////////////
// Type Definitions

const StructType = struct(ref);
const UnmanagedVectorType = StructType({
  is_none: ref.types.bool,
  ptr: ref.refType(ref.types.CString),
  len: ref.types.size_t,
  cap: ref.types.size_t,
});
const UnmanagedVectorPtr = ref.refType(UnmanagedVectorType);

const ByteSliceViewType = StructType({
  is_nil: ref.types.bool,
  ptr: ref.refType(ref.types.CString),
  len: ref.types.size_t,
});

const InitiaCompilerBuildConfig = StructType({
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
const InitiaCompilerArgumentType = StructType({
  package_path: ByteSliceViewType,
  verbose: ref.types.bool,
  build_config: InitiaCompilerBuildConfig,
});

///////////////////////
// Function Definitions

const libinitiavm = ffi.Library(path.resolve(__dirname, '../libinitia'), {
  build_move_package: [
    UnmanagedVectorType,
    [UnmanagedVectorPtr, InitiaCompilerArgumentType],
  ],
});

///////////////////////
// Implementation

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

  /**
   *
   * Execute move compiler to generate move bytecode
   *
   * @returns if success return "ok", else throw an error
   */
  public async build(): Promise<string | null> {
    // make empty err msg
    const errMsg = ref.alloc(UnmanagedVectorType);
    const rawErrMsg = errMsg.deref();

    rawErrMsg.is_none = true;
    rawErrMsg.ptr = ref.NULL;
    rawErrMsg.len = 0;
    rawErrMsg.cap = 0;

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
            resolve(null);
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
}

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
