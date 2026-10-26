import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { curriculum } from '../data/corpus.js'
import {
  blankInSentence,
  cardRecallsWord,
  practiceSentence,
  type PracticeWord,
} from './practice-sentence.js'

const toPractice = (
  word: (typeof curriculum)[number],
  sortOrder: number,
): PracticeWord => ({
  lemma: word.lemma,
  gender: word.gender,
  plural: word.plural,
  glossEn: word.glossEn,
  tags: word.tags,
  sortOrder,
  exampleDe: word.exampleDe,
  exampleEn: word.exampleEn,
})

const wordCount = (sentence: string): number =>
  sentence
    .replace(/[„“”".,!?;:()]/g, ' ')
    .split(/\s+/)
    .filter((token) => token.length > 0).length

describe('practiceSentence', () => {
  it('uses the real example when it is a short daily sentence', () => {
    const ich = practiceSentence(toPractice(curriculum[0]!, 1))
    assert.equal(ich.de, 'Ich lerne Deutsch.')
    assert.equal(ich.en, 'I am learning German.')

    const mann = curriculum.find((word) => word.lemma === 'der Mann')
    assert.ok(mann)
    const mannIndex = curriculum.indexOf(mann) + 1
    const sentence = practiceSentence(toPractice(mann, mannIndex))
    assert.equal(sentence.de, 'Der Mann liest.')
    assert.equal(sentence.en, 'The man is reading.')
  })

  it('replaces the repeated wichtig template with a daily sentence', () => {
    const sentence = practiceSentence({
      lemma: 'der Tisch',
      gender: 'der',
      plural: 'die Tische',
      glossEn: 'table',
      tags: ['noun'],
      sortOrder: 500,
      exampleDe: 'Der Tisch ist wichtig.',
      exampleEn: 'The table is important.',
    })
    assert.equal(sentence.de, 'Ich brauche den Tisch.')
    assert.equal(sentence.en, 'I need the table.')
  })

  it('keeps every practice sentence short and free of the long noun frame', () => {
    const weak: string[] = []

    for (const [position, word] of curriculum.entries()) {
      const sentence = practiceSentence(toPractice(word, position + 1))
      const count = wordCount(sentence.de)
      assert.ok(
        count >= 2 && count <= 8,
        `${word.lemma} has ${count} words: ${sentence.de}`,
      )
      assert.equal(sentence.de.includes('_____'), false)
      assert.equal(sentence.de.includes('Für viele Menschen'), false, word.lemma)

      const bare = word.lemma.replace(/^(der|die|das)\s+/i, '')
      if (word.tags.includes('noun')) {
        assert.ok(
          sentence.de.toLowerCase().includes(bare.toLowerCase()),
          `${word.lemma} missing from ${sentence.de}`,
        )
      }

      const needle = word.lemma
        .replace(/\s*\([^)]*\)/g, '')
        .replace(/^(der|die|das)\s+/i, '')
        .trim()
        .toLowerCase()
      const usesInflectedForm = [
        'sein',
        'haben',
        'werden',
        'können',
        'müssen',
        'wollen',
        'mögen',
        'dürfen',
        'sollen',
      ].includes(word.lemma)
      const usesStoredExample = sentence.de === word.exampleDe.trim()
      if (!usesInflectedForm && !usesStoredExample) {
        assert.ok(
          sentence.de.toLowerCase().includes(needle),
          `${word.lemma} missing from ${sentence.de}`,
        )
      }

      const lastResort = `Das ist ${word.lemma}.`
      const namedPronoun = word.lemma === 'er' || word.lemma === 'sie' || word.lemma === 'es'
      if (
        sentence.de === lastResort &&
        !word.tags.includes('adjective') &&
        !word.tags.includes('noun') &&
        !namedPronoun
      ) {
        weak.push(`${word.lemma} [${word.tags.join(',')}] => ${sentence.de}`)
      }
    }

    assert.deepEqual(weak, [])
  })

  it('asks for the word while a card is young and skips that step after a week', () => {
    assert.equal(cardRecallsWord(0, 0), true)
    assert.equal(cardRecallsWord(1, 0), true)
    assert.equal(cardRecallsWord(3, 1), true)
    assert.equal(cardRecallsWord(2, 6), true)
    assert.equal(cardRecallsWord(2, 7), false)
    assert.equal(cardRecallsWord(2, 21), false)
  })

  it('blanks the article and noun together, and the conjugated form of a verb', () => {
    const noun = {
      lemma: 'der Tisch',
      gender: 'der',
      plural: 'die Tische',
      glossEn: 'table',
      tags: ['noun'],
      sortOrder: 1,
      exampleDe: '',
      exampleEn: '',
    }
    assert.deepEqual(blankInSentence('Wo ist der Tisch?', noun), {
      blankDe: 'Wo ist _____?',
      blankAnswer: 'der Tisch',
    })
    assert.deepEqual(blankInSentence('Ich sehe den Tisch.', noun), {
      blankDe: 'Ich sehe _____.',
      blankAnswer: 'den Tisch',
    })
    assert.deepEqual(blankInSentence('Die Tür ist offen.', {
      ...noun,
      lemma: 'die Tür',
      gender: 'die',
      plural: 'die Türen',
    }), {
      blankDe: '_____ ist offen.',
      blankAnswer: 'Die Tür',
    })
    assert.deepEqual(blankInSentence('Ich kann schwimmen.', {
      ...noun,
      lemma: 'schwimmen',
      gender: null,
      plural: null,
      tags: ['verb'],
    }), {
      blankDe: 'Ich kann _____.',
      blankAnswer: 'schwimmen',
    })
    assert.deepEqual(blankInSentence('Ich bin da.', {
      ...noun,
      lemma: 'sein',
      gender: null,
      plural: null,
      tags: ['verb'],
    }), {
      blankDe: 'Ich _____ da.',
      blankAnswer: 'bin',
    })
    assert.deepEqual(blankInSentence('Das finde ich wichtig.', {
      ...noun,
      lemma: 'wichtig',
      gender: null,
      plural: null,
      tags: ['adjective'],
    }), {
      blankDe: 'Das finde ich _____.',
      blankAnswer: 'wichtig',
    })
  })

  it('puts exactly one blank back into the original sentence for every word', () => {
    const broken: string[] = []
    for (const [position, word] of curriculum.entries()) {
      const sentence = practiceSentence(toPractice(word, position + 1))
      const rebuilt = sentence.blankDe.replace('_____', sentence.blankAnswer)
      const blanks = sentence.blankDe.match(/_____/g) ?? []
      if (rebuilt !== sentence.de || blanks.length !== 1 || sentence.blankAnswer.trim().length === 0) {
        broken.push(`${word.lemma} => [${sentence.blankAnswer}] ${sentence.blankDe}`)
      }
    }
    assert.deepEqual(broken, [])
  })
})
