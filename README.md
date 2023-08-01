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
    const builder = new MoveBuilder(/* path to move package */, {});

    // execute move compiler via ffi
    await builder.build();
    
    // load compiled module bytes as `Buffer`
    const compiledModuleBytes = await builder.get(/* module name */);
    console.info(compiledModuleBytes.toString('hex'));

    // change module name to what you want
    const nameConvertedModuleBytes = await MoveBuilder.convert_module_name(compiledModuleBytes, /* new module name */);
    console.info(nameConvertedModuleBytes.toString('hex'));
}

```

### Create and Clean Move Package

```ts
import { MoveBuilder } from '@initia/builder.js';

async function createAndCleanExample() {
    // recommend to use full package path, not relative path
    // ex) path.resolve(__dirname, "../relative_path")
    const builder = new MoveBuilder(/* path to move package */, {});

    // create new move package
    await builder.new(/* package name */);
    
    await builder.build();
    
    // clean /build directory
    await builder.clean();
}
```

### Read Move Package

```ts
import { MoveBuilder } from '@initia/builder.js';

async function readExample() {
    const builder = new MoveBuilder(/* path to move package */, {});

    const binary = await builder.get(/* module name */);

    // read module bytes
    const moduleInfo = await MoveBuilder.read_module_info(binary)
    console.log(moduleInfo)

    // decode module bytes
    const decodedModule = await MoveBuilder.decode_module_bytes(binary);
    console.log(decodedModule)
}
```