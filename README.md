# initia builder.js

This SDK is a Javascript wrapper for Initia Move Compiler using [ffi-napi](https://www.npmjs.com/package/ffi-napi) library.

## How to install

```
$ npm install @initia-labs/builder.js
```

### How to use

```ts
import { MoveBuilder } from '@initia-labs/builder.js';

async function buildExample() {
    // recommend to use full package path, not relative path
    // ex) path.resolve(__dirname, "../relative_path")
    const builder = new MoveBuilder(/* path to move package */, {});

    // execute move compiler via ffi
    await builder.build();
    
    // load compiled module bytes as `Buffer`
    const compiledModuleBytes = await builder.get(/* module name */);
    console.info(compiledModuleBytes.toString('hex'));
}

```