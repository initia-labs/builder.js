import path from 'path'
import { MoveBuilder } from '../src/builder'

describe('test move package', () => {
  const contractDir = path.resolve(__dirname, 'contract/simple')
  const builder = new MoveBuilder(contractDir, {})

  it('executes tests successfully', async () => {
    const testResult = await builder.test({
      filter: 'test_simple',
    })
    expect(testResult).toEqual('ok')
  }, 100000000)

  it('executes tests with options', async () => {
    const testResult = await builder.test({
      filter: 'test_simple2',
      reportStatistics: true,
      reportStorageOnError: true,
      ignoreCompileWarnings: true,
    })
    expect(testResult).toEqual('ok')
  }, 100000000)
})
