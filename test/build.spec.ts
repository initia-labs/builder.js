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
    additionalNamedAddresses: [['test', '0x4']],
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
    expect(await MoveBuilder.decodeModuleBytes(dummy)).toEqual({
      address: '0x4',
      name: 'dummy',
      friends: ['0x4::hihi'],
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
        {
          name: 'return_10_by_friend',
          visibility: 'friend',
          is_entry: false,
          is_view: false,
          generic_type_params: [],
          params: [],
          return: ['u32'],
        },
      ],
      structs: [],
    })
    const hihi = await builder.get('hihi')
    expect(await MoveBuilder.decodeModuleBytes(hihi)).toEqual({
      address: '0x4',
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
        {
          name: 'call_friend',
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
  })

  it('reads module info correctly', async () => {
    const modules = await builder.getAll()
    const dummy = modules['dummy']
    const hihi = modules['hihi']

    expect(await MoveBuilder.readModuleInfo(dummy)).toEqual({
      address: '0x4',
      name: 'dummy',
    })
    expect(await MoveBuilder.readModuleInfo(hihi)).toEqual({
      address: '0x4',
      name: 'hihi',
    })
  })

  it('reads source maps correctly', async () => {
    const sourceMaps = await builder.getAllSourceMaps()
    const dummySourceMap = sourceMaps['dummy']
    const hihiSourceMap = sourceMaps['hihi']

    expect(dummySourceMap).toBeDefined()
    expect(hihiSourceMap).toBeDefined()

    const singleSourceMap = await builder.getSourceMap('dummy')
    expect(singleSourceMap).toEqual(dummySourceMap)
  })

  it('reads module info correctly', async () => {
    const binary = await builder.get('dummy')
    const moduleInfo = await MoveBuilder.readModuleInfo(binary)

    expect(moduleInfo).toEqual({
      address: '0x4',
      name: 'dummy',
    })
  })

  it('cleans the package correctly', async () => {
    const cleanResult = await builder.clean({})
    expect(cleanResult).toEqual('ok')
  })
})
