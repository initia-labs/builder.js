import { MoveBuilder } from '../build'
import path from 'path'

jest.setTimeout(30000)

describe('test move package', () => {
  const contractDir = path.resolve(__dirname, 'contract/simple')
  const builder = new MoveBuilder(contractDir, {})

  it('executes tests successfully', async () => {
    const testResult = await builder.test()
    expect(testResult).toEqual('ok')
  })
})
