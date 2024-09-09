import { readFile } from 'fs/promises'
import { MoveBuilder } from '../build'
import path from 'path'

describe('build move package', () => {
  jest.setTimeout(20000)
  const contractDir = 'contract/dummy'
  const builder = new MoveBuilder(path.resolve(__dirname, contractDir), {})

  it('build correctly', async () => {
    expect(await builder.build()).toEqual('ok')
    expect(await builder.get('dummy')).toEqual(
      await readFile(
        path.resolve(
          __dirname,
          `${contractDir}/build/DummyContract/bytecode_modules/dummy.mv`
        )
      )
    )
  })

  it('decode module bytes', async () => {
    const binary = await builder.get('dummy')
    expect(await MoveBuilder.decode_module_bytes(binary)).toEqual(
      '{"address":"0x999","name":"dummy","friends":[],"exposed_functions":[{"name":"return_0","visibility":"public","is_entry":false,"is_view":false,"generic_type_params":[],"params":[],"return":["u32"]},{"name":"return_10","visibility":"public","is_entry":false,"is_view":false,"generic_type_params":[],"params":[],"return":["u32"]}],"structs":[]}'
    )
  })

  it('read module info', async () => {
    const binary = await builder.get('dummy')
    expect(await MoveBuilder.read_module_info(binary)).toEqual(
      '{"address":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,153],"name":"dummy"}'
    )
  })

  // it('convert module name', async () => {
  //   const binary = await builder.get('dummy')
  //   expect(await MoveBuilder.convert_module_name(binary, 'hihi')).toEqual(
  //     await readFile(
  //       path.resolve(
  //         __dirname,
  //         `${contractDir}/build/DummyContract/bytecode_modules/hihi.mv`
  //       )
  //     )
  //   )
  // })

  it('clean move pacakge correctly', async () => {
    expect(await builder.clean({})).toEqual('ok')
  })
})
