# initia builder.js

This SDK is a Javascript wrapper for Initia Move Compiler using [ffi-napi](https://www.npmjs.com/package/ffi-napi) library.

## How to install

```
$ npm install @initia/builder.js
```

## How to use

### Build Move Package

```ts
import { MoveBuilder } from '@initia/builder.js';

async function buildExample() {
    // recommend to use full package path, not relative path
    // ex) path.resolve(__dirname, "../relative_path")
    const builder = new MoveBuilder(
        path.resolve(__dirname, 'moon_coin'), // move package path 
        {} // build options
    );

    // execute move compiler via ffi
    await builder.build();
    
    // load compiled module bytes as `Buffer`
    const compiledModuleBytes = await builder.get(
        'moon_coin' // module name
    );
    console.info(compiledModuleBytes.toString('hex'));

    // change module name to what you want
    const nameConvertedModuleBytes = await MoveBuilder.convert_module_name(
        compiledModuleBytes,  // compiled module bytes
        'sun_coin' // new module name 
    );
    console.info(nameConvertedModuleBytes.toString('hex'));
}

```

### Create and Clean Move Package

```ts
import { MoveBuilder } from '@initia/builder.js';

async function createAndCleanExample() {
    const builder = new MoveBuilder(path.resolve(__dirname, 'moon_coin'), {});
    
    // create new move package
    await builder.new('new'/* package name */);
    
    await builder.build();
    
    // clean /build directory
    await builder.clean();
}
```

### Read Move Package

```ts
import { MoveBuilder } from '@initia/builder.js';

async function readExample() {
    const builder = new MoveBuilder(path.resolve(__dirname, 'moon_coin'), {});

    const binary = await builder.get('moon_coin');

    // read module bytes
    const moduleInfo = await MoveBuilder.read_module_info(binary)
    console.log(moduleInfo)

    // decode module bytes
    const decodedModule = await MoveBuilder.decode_module_bytes(binary);
    console.log(decodedModule)
}
```

## Options

For more details on the available options, refer to the [source code](src/types/options.ts).

### BuildOptions
The `BuildOptions` interface provides various options to customize the build process.

```ts
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
    compilerVersion?: string
    languageVersion?: string
    addtionalNamedAddresses?: [string, string][]
}
```

### CleanOptions
The `CleanOptions` interface provides options to clean the build artifacts.

```ts
export interface CleanOptions {
    cleanCache?: boolean
    cleanByProduct?: boolean
    force?: boolean
}
```

### TestOptions
The `TestOptions` interface provides options to customize the testing process.

```ts
export interface TestOptions {
    filter?: string
    reportStatistics?: boolean
    reportStorageOnError?: boolean
    ignoreCompileWarnings?: boolean
    computeCoverage?: boolean
}
```