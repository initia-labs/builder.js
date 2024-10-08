import { describe, expect, it } from '@jest/globals'
import { MoveBuilder } from '../build'
import path from 'path'
describe('create and clean new move package', () => {
  const contractDir = 'contract/new'
  const builder = new MoveBuilder(path.resolve(__dirname, contractDir), {})

  it('create move package', async () => {
    expect(await builder.new('new')).toEqual('ok')
  }, 6000)

  it('clean move package', async () => {
    expect(await builder.clean()).toEqual('ok')
  }, 6000)
})
