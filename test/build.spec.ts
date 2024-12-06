import path from 'path'
import { readFile } from 'fs/promises'
import { MoveBuilder } from '../src/builder'
import { AccAddress } from '@initia/initia.js'

describe('build move package', () => {
  const contractDir = path.resolve(__dirname, 'contract/dummy')
  const test2ModuleAddr = 'init1f38g7l008sjy2wh8amnanthfka2k5f4qmv9z28'
  const builder = new MoveBuilder(path.resolve(__dirname, contractDir), {
    devMode: true,
    testMode: true,
    generateDocs: true,
    generateAbis: true,
    forceRecompilation: true,
    fetchDepsOnly: true,
    skipFetchLatestGitDeps: true,
    bytecodeVersion: 7,
    compilerVersion: '2',
    languageVersion: '1',
    addtionalNamedAddresses: [
      ['test', '0x18ced7410ef397b346338b0fc06f7adc138dbf48'],
      ['test2', 'init1f38g7l008sjy2wh8amnanthfka2k5f4qmv9z28'],
    ],
  })
  const dummyModulePath = path.join(
    contractDir,
    'build/DummyContract/bytecode_modules/dummy.mv'
  )
  jest.setTimeout(200000)

  it('builds the package correctly', async () => {
    const buildResult = await builder.build()
    const expectedBinary = await readFile(dummyModulePath)

    expect(buildResult).toEqual('ok')
    expect(await builder.get('dummy')).toEqual(expectedBinary)
  })

  it('decodes module bytes correctly', async () => {
    expect(
      await MoveBuilder.decode_module_bytes(await builder.get('dummy'))
    ).toEqual(
      JSON.stringify({
        address: '0x18ced7410ef397b346338b0fc06f7adc138dbf48',
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
    )

    expect(
      await MoveBuilder.decode_module_bytes(await builder.get('hihi'))
    ).toEqual(
      JSON.stringify({
        address: AccAddress.toHex(test2ModuleAddr),
        name: 'hihi',
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
    )
  })

  it('reads module info correctly', async () => {
    const binary = await builder.get('dummy')
    expect(await MoveBuilder.read_module_info(binary)).toEqual(
      '{"address":[0,0,0,0,0,0,0,0,0,0,0,0,24,206,215,65,14,243,151,179,70,51,139,15,192,111,122,220,19,141,191,72],"name":"dummy"}'
    )
  })

  it('reads module info correctly', async () => {
    const binary = await builder.get('dummy')
    const moduleInfo = await MoveBuilder.read_module_info(binary)
    const expectedModuleInfo = JSON.stringify({
      address: [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 24, 206, 215, 65, 14, 243, 151, 179,
        70, 51, 139, 15, 192, 111, 122, 220, 19, 141, 191, 72,
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
