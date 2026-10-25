import { curriculum } from '../data/corpus.js'

const counts = new Map<string, number>()
for (const word of curriculum) {
  counts.set(word.cefrLevel, (counts.get(word.cefrLevel) ?? 0) + 1)
}

console.log(`words ${curriculum.length}`)
for (const level of ['A1', 'A2', 'B1', 'B2', 'C1']) {
  console.log(`${level} ${counts.get(level) ?? 0}`)
}
