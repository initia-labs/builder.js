import { MoveBuilder } from '../build'
import path from 'path'

describe('test move package', () => {
  const contractDir = path.resolve(__dirname, 'contract/simple')
  const builder = new MoveBuilder(contractDir, {})

  beforeAll(() => {
    jest.setTimeout(200000)
  })

  it('executes tests successfully', async () => {
    const testResult = await builder.test()
    expect(testResult).toEqual('ok')
  })
})
