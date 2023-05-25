# initia builder.js

This SDK is a Javascript wrapper for Initia Move Compiler using [ffi-napi](https://www.npmjs.com/package/ffi-napi) library.

## How to install

```
$ npm install @initia/builder.js
```

### How to use

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

    // change module name what you want
    const nameConvertedModuleBytes = await MoveBuilder.convert_module_name(compiledModuleBytes, /* new module name */);
    console.info(nameConvertedModuleBytes.toString('hex'));
}

```