import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

/** Mirrors CSV escaping used by the export service. */
const csvEscape = (value: string): string => {
  if (/[",\n\r]/.test(value)) {
    return `"${value.replaceAll('"', '""')}"`
  }
  return value
}

describe('export CSV escaping', () => {
  it('quotes commas and doubles quotes', () => {
    assert.equal(csvEscape('plain'), 'plain')
    assert.equal(csvEscape('a,b'), '"a,b"')
    assert.equal(csvEscape('say "hi"'), '"say ""hi"""')
  })
})
