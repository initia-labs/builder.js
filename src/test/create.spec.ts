import { MoveBuilder } from '../build'
import path from 'path'

describe('create and clean new move package', () => {
  const contractDir = 'contract/new'

  it('create move package correctly', async () => {
    const builder = new MoveBuilder(path.resolve(__dirname, contractDir), {})
    expect(await builder.new('new')).toEqual('ok')
  })
})
