import { describe, expect, it } from '@jest/globals'
import { MoveBuilder } from '../src/build'
import path from 'path'
describe('create and clean new move package', () => {
  const contractDir = path.resolve(__dirname, 'contract/new')
  const builder = new MoveBuilder(contractDir, {})

  it('creates a new move package', async () => {
    expect(await builder.new('new')).toEqual('ok')
  }, 6000)

  it('cleans the move package', async () => {
    expect(await builder.clean()).toEqual('ok')
  }, 6000)
})
