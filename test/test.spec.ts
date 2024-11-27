import path from 'path'
import { MoveBuilder } from 'build'

describe('test move package', () => {
  const contractDir = path.resolve(__dirname, 'contract/simple')
  const builder = new MoveBuilder(contractDir, {})

  it('executes tests successfully', async () => {
    const testResult = await builder.test()
    expect(testResult).toEqual('ok')
  }, 100000000)
})
