import { readFile } from 'fs/promises';
import { MoveBuilder } from './build';
import path from 'path';

describe('build move package', () => {
  const contractDir = 'move/dummy';
  it('build correctly', async () => {
    const builder = new MoveBuilder(path.resolve(__dirname, contractDir), {});
    expect(await builder.build()).toEqual('ok');
    expect(await builder.get('dummy')).toEqual(
      await readFile(
        path.resolve(
          __dirname,
          `${contractDir}/build/DummyContract/bytecode_modules/dummy.mv`
        )
      )
    );
  });

  it('convert module name', async () => {
    const builder = new MoveBuilder(path.resolve(__dirname, contractDir), {});
    expect(await builder.build()).toEqual('ok');

    const binary = await builder.get('dummy');
    expect(await MoveBuilder.convert_module_name(binary, 'hihi')).toEqual(
      await readFile(
        path.resolve(
          __dirname,
          `${contractDir}/build/DummyContract/bytecode_modules/hihi.mv`
        )
      )
    );
  });
});

describe('test move package', () => {
  // need time to get dependencies
  jest.setTimeout(100000);
  const contractDir = 'move/table';

  it('test correctly', async () => {
    const builder = new MoveBuilder(path.resolve(__dirname, contractDir), {});
    expect(await builder.test({})).toEqual('ok');
  });
});
