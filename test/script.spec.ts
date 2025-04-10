import path from 'path'
import { readFile } from 'fs/promises'
import { MoveBuilder } from '../src/builder'

describe('build script and decode', () => {
  const contractDir = path.resolve(__dirname, 'contract/script')
  const builder = new MoveBuilder(contractDir, { devMode: true })

  it('builds the script successfully', async () => {
    expect(await builder.build()).toEqual('ok')
  }, 100000000)

  it('decodes script bytes', async () => {
    const bytePath = path.resolve(
      __dirname,
      'contract/script/build/script/bytecode_scripts/even_0.mv'
    )
    const binary = await readFile(bytePath)
    const decodedScript = await MoveBuilder.decodeScriptBytes(binary)
    expect(decodedScript).toEqual({
      generic_type_params: [],
      is_entry: true,
      is_view: false,
      name: 'main',
      params: ['u64'],
      return: [],
      visibility: 'public',
    })
  })
})
