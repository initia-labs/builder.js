import path from 'path'
import { readFile } from 'fs/promises'
import { MoveBuilder } from '../src/builder'

describe('build move package', () => {
  const contractDir = path.resolve(__dirname, 'contract/dummy')
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
      ['test', '0x4'],
      ['test2', '0x4c4e8f7def3c24453ae7eee7d9aee9b7556a26a0'],
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
    const dummy = await builder.get('dummy')

    expect(await MoveBuilder.decode_module_bytes(dummy)).toEqual(
      JSON.stringify({
        address: '0x4',
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
    const hihi = await builder.get('hihi')

    expect(await MoveBuilder.decode_module_bytes(hihi)).toEqual(
      JSON.stringify({
        address: '0x4c4e8f7def3c24453ae7eee7d9aee9b7556a26a0',
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
    const dummy = await builder.get('dummy')
    expect(await MoveBuilder.read_module_info(dummy)).toEqual(
      '{"address":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4],"name":"dummy"}'
    )
    const hihi = await builder.get('hihi')
    expect(await MoveBuilder.read_module_info(hihi)).toEqual(
      '{"address":[0,0,0,0,0,0,0,0,0,0,0,0,76,78,143,125,239,60,36,69,58,231,238,231,217,174,233,183,85,106,38,160],"name":"hihi"}'
    )
  })

  it('reads module info correctly', async () => {
    const binary = await builder.get('dummy')
    const moduleInfo = await MoveBuilder.read_module_info(binary)
    const expectedModuleInfo = JSON.stringify({
      address: [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 4,
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
