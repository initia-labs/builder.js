import { readFile } from 'fs/promises';
import { MoveBuilder } from './build';
import path from 'path';

describe('build move package', () => {
  it('builds correctly', async () => {
    const builder = new MoveBuilder(path.resolve(__dirname, 'move'), {});
    expect(await builder.build()).toEqual('ok');
    expect(await builder.get('dummy')).toEqual(
      await readFile(
        path.resolve(
          __dirname,
          'move/build/DummyContract/bytecode_modules/dummy.mv'
        )
      )
    );
  });
});
