import { readFile } from 'fs/promises'
import { MoveBuilder } from '../build'
import path from 'path'

describe('build move package', () => {
  const contractDir = path.resolve(__dirname, 'contract/dummy')
  const builder = new MoveBuilder(contractDir, {})
  const dummyModulePath = path.join(
    contractDir,
    'build/DummyContract/bytecode_modules/dummy.mv'
  )
  jest.setTimeout(20000)

  it('builds the package correctly', async () => {
    const buildResult = await builder.build()
    const expectedBinary = await readFile(dummyModulePath)

    expect(buildResult).toEqual('ok')
    expect(await builder.get('dummy')).toEqual(expectedBinary)
  })

  it('decodes module bytes correctly', async () => {
    const binary = await builder.get('dummy')
    // {
    //   "address":"0x999",
    //   "name":"dummy",
    //   "friends":[],
    //   "exposed_functions":
    //   [
    //     {
    //       "name":"return_0",
    //       "visibility":"public",
    //       "is_entry":false,
    //       "is_view":false,
    //       "generic_type_params":[],
    //       "params":[],
    //       "return":["u32"]
    //     },
    //     {
    //       "name":"return_10",
    //       "visibility":"public",
    //       "is_entry":false,
    //       "is_view":false,
    //       "generic_type_params":[],
    //       "params":[],
    //       "return":["u32"]
    //     }
    //   ],
    //   "structs":[]
    // }
    const expectedDecoded = JSON.stringify({
      address: '0x999',
      name: 'dummy',
      friends: [],
      exposed_functions: [
        {
          name: 'return_0',
          visibility: 'public',
          is_entry: false,
          is_view: false,
          generic_type_params: [],
          params: [],
          return: ['u32'],
        },
        {
          name: 'return_10',
          visibility: 'public',
          is_entry: false,
          is_view: false,
          generic_type_params: [],
          params: [],
          return: ['u32'],
        },
      ],
      structs: [],
    })

    expect(await MoveBuilder.decode_module_bytes(binary)).toEqual(
      expectedDecoded
    )
  })

  it('reads module info correctly', async () => {
    const binary = await builder.get('dummy')
    expect(await MoveBuilder.read_module_info(binary)).toEqual(
      '{"address":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,153],"name":"dummy"}'
    )
  })

  it('reads module info correctly', async () => {
    const binary = await builder.get('dummy')
    const moduleInfo = await MoveBuilder.read_module_info(binary)
    // {
    //   "address":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,153],
    //   "name":"dummy"
    // }
    const expectedModuleInfo = JSON.stringify({
      address: [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 9, 153,
      ],
      name: 'dummy',
    })

    expect(moduleInfo).toEqual(expectedModuleInfo)
  })

  it('cleans the package correctly', async () => {
    const cleanResult = await builder.clean({})
    expect(cleanResult).toEqual('ok')
  })
})
