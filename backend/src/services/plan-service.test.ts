import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { pacedNewLimit } from './plan-service.js'

describe('pacedNewLimit', () => {
  it('keeps the settings limit when reviews are light', () => {
    assert.deepEqual(pacedNewLimit(8, 0), { limit: 8, note: null })
    assert.deepEqual(pacedNewLimit(8, 24), { limit: 8, note: null })
  })

  it('caps new words when reviews are busy', () => {
    assert.deepEqual(pacedNewLimit(8, 25), {
      limit: 3,
      note: 'Reviews are busy. New words are capped at 3 today.',
    })
    assert.deepEqual(pacedNewLimit(2, 30), { limit: 2, note: null })
  })

  it('pauses new words when reviews are heavy', () => {
    assert.deepEqual(pacedNewLimit(8, 40), {
      limit: 0,
      note: 'Reviews are heavy today. New words pause until the pile shrinks.',
    })
    assert.deepEqual(pacedNewLimit(50, 100), {
      limit: 0,
      note: 'Reviews are heavy today. New words pause until the pile shrinks.',
    })
  })
})
