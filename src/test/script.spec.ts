import { MoveBuilder } from '../build'
import path from 'path'
import { readFile } from 'fs/promises'

describe('build script', () => {
  const contractDir = 'contract/script'
  const builder = new MoveBuilder(path.resolve(__dirname, contractDir), {})

  it('build script', async () => {
    expect(await builder.build()).toEqual('ok')
  }, 10000)

  it('decode_script_bytes', async () => {
    const bytePath = 'contract/script/build/script/bytecode_scripts/even.mv'
    const binary = await readFile(path.resolve(__dirname, bytePath))
    expect(await MoveBuilder.decode_script_bytes(binary)).toEqual(
      '{"name":"main","visibility":"public","is_entry":true,"is_view":false,"generic_type_params":[],"params":["u64"],"return":[]}'
    )
  })
})
