import { curriculum } from '../data/corpus.js'

/**
 * FSRS `State.Review`. A review interval of a week or more means the word is
 * solid enough to recall on its own.
 */
const FSRS_REVIEW_STATE = 2
const MATURE_INTERVAL_DAYS = 7

const COPULA_OR_MODAL = new Set([
  'sein',
  'haben',
  'werden',
  'können',
  'müssen',
  'wollen',
  'sollen',
  'dürfen',
  'mögen',
])

/**
 * Sentences for words that arrive before a real example exists.
 * Each one is three or four words and uses only the copula floor.
 */
const FIXED: Record<string, PracticeSentence> = {
  ich: { de: 'Das bin ich.', en: 'That is me.' },
  du: { de: 'Das bist du.', en: 'That is you.' },
  er: { de: 'Das ist er.', en: 'That is him.' },
  sie: { de: 'Das ist sie.', en: 'That is her.' },
  wir: { de: 'Das sind wir.', en: 'That is us.' },
  ihr: { de: 'Das seid ihr.', en: 'That is you.' },
  sein: { de: 'Ich bin da.', en: 'I am here.' },
  haben: { de: 'Ich habe das.', en: 'I have that.' },
  werden: { de: 'Ich werde das.', en: 'I will do that.' },
  können: { de: 'Ich kann das.', en: 'I can do that.' },
  müssen: { de: 'Ich muss das.', en: 'I have to do that.' },
  wollen: { de: 'Ich will das.', en: 'I want that.' },
  mögen: { de: 'Ich mag das.', en: 'I like that.' },
  dürfen: { de: 'Ich darf das.', en: 'I may do that.' },
  sollen: { de: 'Ich soll das.', en: 'I am supposed to.' },
  es: { de: 'Das ist es.', en: 'That is it.' },
  nicht: { de: 'Ich bin nicht da.', en: 'I am not there.' },
}

const PLACE_ADVERBS = new Set([
  'hier',
  'dort',
  'da',
  'oben',
  'unten',
  'draußen',
  'drinnen',
  'links',
  'rechts',
  'vorne',
  'hinten',
  'weg',
  'irgendwo',
  'allein',
  'zurück',
])

const DEGREE_ADVERBS = new Set(['sehr', 'ganz', 'so', 'wirklich'])

const SUBORDINATORS = new Set([
  'dass',
  'weil',
  'wenn',
  'ob',
  'als',
  'bevor',
  'nachdem',
  'damit',
  'falls',
  'obwohl',
  'während',
  'sodass',
  'sofern',
  'obgleich',
  'wenngleich',
  'vorausgesetzt',
  'wohingegen',
  'anstatt',
  'bis',
])

const PREPOSITIONS: Record<string, PracticeSentence> = {
  in: { de: 'Ich bin in dem Haus.', en: 'I am in the house.' },
  an: { de: 'Ich bin an dem Haus.', en: 'I am at the house.' },
  auf: { de: 'Ich bin auf dem Haus.', en: 'I am on the house.' },
  aus: { de: 'Ich komme aus dem Haus.', en: 'I come out of the house.' },
  bei: { de: 'Ich bin bei dir.', en: 'I am with you.' },
  mit: { de: 'Ich bin mit dir.', en: 'I am with you.' },
  nach: { de: 'Ich gehe nach Hause.', en: 'I am going home.' },
  von: { de: 'Das ist von dir.', en: 'That is from you.' },
  zu: { de: 'Ich gehe zu dir.', en: 'I am going to you.' },
  für: { de: 'Das ist für dich.', en: 'That is for you.' },
  über: { de: 'Ich bin über dem Haus.', en: 'I am above the house.' },
  unter: { de: 'Ich bin unter dem Haus.', en: 'I am under the house.' },
  vor: { de: 'Ich bin vor dem Haus.', en: 'I am in front of the house.' },
  hinter: { de: 'Ich bin hinter dem Haus.', en: 'I am behind the house.' },
  neben: { de: 'Ich bin neben dem Haus.', en: 'I am next to the house.' },
  zwischen: { de: 'Ich bin zwischen dir und ihm.', en: 'I am between you and him.' },
  ohne: { de: 'Ich gehe ohne dich.', en: 'I am going without you.' },
  um: { de: 'Ich gehe um das Haus.', en: 'I am going around the house.' },
  durch: { de: 'Ich gehe durch das Haus.', en: 'I am going through the house.' },
  gegen: { de: 'Ich bin gegen das.', en: 'I am against that.' },
  seit: { de: 'Ich bin seit heute da.', en: 'I have been here since today.' },
  bis: { de: 'Bis ich da bin.', en: 'Until I am here.' },
  ab: { de: 'Ich bin ab heute da.', en: 'I am here from today.' },
  wegen: { de: 'Ich bin wegen dir da.', en: 'I am here because of you.' },
  im: { de: 'Ich bin im Haus.', en: 'I am in the house.' },
  am: { de: 'Ich bin am Haus.', en: 'I am at the house.' },
  zum: { de: 'Ich gehe zum Haus.', en: 'I am going to the house.' },
  zur: { de: 'Ich gehe zur Frau.', en: 'I am going to the woman.' },
  ins: { de: 'Ich gehe ins Haus.', en: 'I am going into the house.' },
  ans: { de: 'Ich gehe ans Haus.', en: 'I am going up to the house.' },
  vom: { de: 'Ich komme vom Haus.', en: 'I am coming from the house.' },
  beim: { de: 'Ich bin beim Haus.', en: 'I am at the house.' },
}

export type PracticeWord = {
  lemma: string
  gender: string | null
  plural: string | null
  glossEn: string
  tags: readonly string[]
  sortOrder: number
  exampleDe: string
  exampleEn: string
}

export type PracticeSentence = {
  de: string
  en: string
}

/** The practice sentence with the target word replaced by a blank. */
export type BlankedSentence = {
  blankDe: string
  blankAnswer: string
}

export type PracticePrompt = PracticeSentence & BlankedSentence

type LemmaEntry = {
  sortOrder: number
  tags: readonly string[]
  glossEn: string
}

const definiteArticle = (gender: string | null): string | null => {
  if (gender === 'der' || gender === 'die' || gender === 'das') {
    return gender
  }
  return null
}

const bareNoun = (lemma: string): string => {
  const parts = lemma.trim().split(/\s+/)
  const first = parts[0]?.toLowerCase() ?? ''
  if (parts.length >= 2 && (first === 'der' || first === 'die' || first === 'das')) {
    return parts.slice(1).join(' ')
  }
  return lemma.trim()
}

const plainGloss = (gloss: string): string => {
  const withoutParen = gloss.replace(/\s*\([^)]*\)/g, '')
  const first = withoutParen.split('/')[0] ?? withoutParen
  return first.trim()
}

const englishVerb = (gloss: string): string => plainGloss(gloss).replace(/^to\s+/i, '')

const capitalize = (value: string): string => {
  if (value.length === 0) {
    return value
  }
  return value.charAt(0).toUpperCase() + value.slice(1)
}

const withPeriod = (value: string): string => {
  const trimmed = value.trim().replace(/[.?!]+$/u, '')
  return `${trimmed}.`
}

const tokenize = (sentence: string): string[] =>
  sentence
    .replace(/[„“”".,!?;:()]/g, ' ')
    .split(/\s+/)
    .map((token) => token.trim())
    .filter((token) => token.length > 0)

let lemmaIndex: Map<string, LemmaEntry> | null = null

const curriculumIndex = (): Map<string, LemmaEntry> => {
  if (lemmaIndex) {
    return lemmaIndex
  }

  const index = new Map<string, LemmaEntry>()
  for (const [position, word] of curriculum.entries()) {
    const entry: LemmaEntry = {
      sortOrder: position + 1,
      tags: word.tags,
      glossEn: word.glossEn,
    }
    const full = word.lemma.toLowerCase()
    if (!index.has(full)) {
      index.set(full, entry)
    }
    const bare = bareNoun(word.lemma).toLowerCase()
    if (bare !== full && !index.has(bare)) {
      index.set(bare, entry)
    }
  }

  lemmaIndex = index
  return index
}

/**
 * Template lines that repeat across the noun list. They do not show how the
 * word is used, so a short daily sentence replaces them.
 */
const isBoilerplate = (sentence: string): boolean => {
  const text = sentence.trim().toLowerCase().replace(/[.?!]+$/u, '')
  if (text.includes('für viele menschen')) {
    return true
  }
  if (text.includes('ist wichtig') || text.includes('bleibt wichtig')) {
    return true
  }
  return /^das ist [\p{L}-]+$/u.test(text)
}

/**
 * The word's own example, when it is a real sentence short enough to write.
 */
const usableExample = (word: PracticeWord): boolean => {
  const tokens = tokenize(word.exampleDe)
  if (tokens.length < 2 || tokens.length > 8) {
    return false
  }
  return !isBoilerplate(word.exampleDe)
}

const known = (lemma: string, sortOrder: number, index: Map<string, LemmaEntry>): boolean => {
  const entry = index.get(lemma.toLowerCase())
  return entry !== undefined && entry.sortOrder <= sortOrder
}

const accusativeNoun = (gender: string, noun: string): string => {
  if (gender === 'der') {
    return `den ${noun}`
  }
  return `${gender} ${noun}`
}

/**
 * Everyday stand-ins for noun cards whose stored example is only a template.
 * Three different situations, all short enough to write.
 */
const nounFrames = (word: PracticeWord): PracticeSentence[] => {
  const article = definiteArticle(word.gender)
  if (!article) {
    return []
  }

  const noun = bareNoun(word.lemma)
  const gloss = plainGloss(word.glossEn)
  const object = accusativeNoun(article, noun)
  return [
    {
      de: `Wo ist ${article} ${noun}?`,
      en: `Where is the ${gloss}?`,
    },
    {
      de: withPeriod(`Ich sehe ${object}`),
      en: `I see the ${gloss}.`,
    },
    {
      de: withPeriod(`Ich brauche ${object}`),
      en: `I need the ${gloss}.`,
    },
  ]
}

const pickFrame = (frames: PracticeSentence[], sortOrder: number): PracticeSentence => {
  const index = sortOrder % frames.length
  return frames[index] ?? frames[0]!
}

/**
 * Chooses the German sentence the learner hears and later completes.
 * A real example of at most eight words wins. Template lines become a short
 * daily sentence instead. The returned blank removes the target word.
 */
export const practiceSentence = (word: PracticeWord): PracticePrompt => {
  const line = choosePracticeSentence(word)
  return { ...line, ...blankInSentence(line.de, word) }
}

const choosePracticeSentence = (word: PracticeWord): PracticeSentence => {
  const index = curriculumIndex()

  if (usableExample(word)) {
    return {
      de: word.exampleDe.trim(),
      en: word.exampleEn.trim(),
    }
  }

  const frames = nounFrames(word)
  if (frames.length > 0) {
    return pickFrame(frames, word.sortOrder)
  }

  if (word.tags.includes('adjective')) {
    return {
      de: withPeriod(`Das finde ich ${word.lemma}`),
      en: `I find that ${plainGloss(word.glossEn)}.`,
    }
  }

  if (
    word.tags.includes('verb') &&
    known('können', word.sortOrder, index) &&
    !COPULA_OR_MODAL.has(word.lemma)
  ) {
    return {
      de: withPeriod(`Ich kann ${word.lemma}`),
      en: `I can ${englishVerb(word.glossEn)}.`,
    }
  }

  const fixed = FIXED[word.lemma]
  if (fixed) {
    return fixed
  }

  const closed = closedClassSentence(word, index)
  if (closed) {
    return closed
  }

  return {
    de: withPeriod(`Das ist ${word.lemma}`),
    en: `That is ${plainGloss(word.glossEn)}.`,
  }
}

const utterance = (lemma: string): string => {
  const trimmed = lemma.trim()
  const capitalized = capitalize(trimmed)
  if (/[.?!]$/u.test(capitalized)) {
    return capitalized
  }
  return `${capitalized}.`
}

/**
 * Short sentences for pronouns, prepositions, adverbs, and other function words.
 * The frames use only the copula and a few anchor nouns from the start of the list.
 */
const closedClassSentence = (
  word: PracticeWord,
  index: Map<string, LemmaEntry>,
): PracticeSentence | null => {
  const lemma = word.lemma
  const gloss = plainGloss(word.glossEn)

  if (word.tags.includes('phrase')) {
    const parts = tokenize(lemma)
    if (parts.length >= 2) {
      return { de: utterance(lemma), en: gloss.charAt(0).toUpperCase() + gloss.slice(1) + '.' }
    }
    return {
      de: `${capitalize(lemma)}, ich bin da.`,
      en: `${gloss.charAt(0).toUpperCase()}${gloss.slice(1)}, I am here.`,
    }
  }

  if (word.tags.includes('question') || lemma === 'woher' || lemma === 'wohin') {
    if (lemma === 'woher') {
      return { de: 'Woher bist du?', en: 'Where are you from?' }
    }
    if (lemma === 'wohin') {
      return { de: 'Wohin gehst du?', en: 'Where are you going?' }
    }
    return { de: `${capitalize(lemma)} ist das?`, en: `${gloss.charAt(0).toUpperCase()}${gloss.slice(1)} is that?` }
  }

  if (word.tags.includes('number')) {
    return { de: withPeriod(`Ich habe ${lemma}`), en: `I have ${gloss}.` }
  }

  if (word.tags.includes('preposition')) {
    const preset = PREPOSITIONS[lemma]
    if (preset) {
      return preset
    }
    if (known('Haus', word.sortOrder, index)) {
      return {
        de: withPeriod(`Ich bin ${lemma} dem Haus`),
        en: `I am ${gloss} the house.`,
      }
    }
  }

  if (word.tags.includes('conjunction')) {
    if (lemma === 'und') {
      return { de: 'Ich und du.', en: 'You and I.' }
    }
    if (lemma === 'oder') {
      return { de: 'Ich oder du.', en: 'You or I.' }
    }
    if (lemma === 'aber') {
      return { de: 'Ich bin da, aber du nicht.', en: 'I am here, but you are not.' }
    }
    if (lemma === 'denn') {
      return { de: 'Denn ich bin da.', en: 'Because I am here.' }
    }
    if (lemma === 'sondern') {
      return { de: 'Nicht ich, sondern du.', en: 'Not me, but you.' }
    }
    if (lemma === 'entweder') {
      return { de: 'Entweder ich oder du.', en: 'Either you or I.' }
    }
    if (lemma === 'weder') {
      return { de: 'Weder ich noch du.', en: 'Neither you nor I.' }
    }
    if (lemma === 'sowohl') {
      return { de: 'Sowohl ich als auch du.', en: 'Both you and I.' }
    }
    if (lemma === 'je') {
      return { de: 'Je mehr ich kann.', en: 'The more I can.' }
    }
    if (lemma === 'desto') {
      return { de: 'Desto besser ist das.', en: 'All the better.' }
    }
    if (SUBORDINATORS.has(lemma)) {
      return { de: withPeriod(`${capitalize(lemma)} ich da bin`), en: `${gloss.charAt(0).toUpperCase()}${gloss.slice(1)} I am here.` }
    }
    return { de: withPeriod(`${capitalize(lemma)} ich da bin`), en: `${gloss.charAt(0).toUpperCase()}${gloss.slice(1)} I am here.` }
  }

  if (word.tags.includes('adverb') || word.tags.includes('particle')) {
    if (PLACE_ADVERBS.has(lemma)) {
      return { de: withPeriod(`Ich bin ${lemma}`), en: `I am ${gloss}.` }
    }
    if (lemma === 'zusammen') {
      return { de: 'Wir sind zusammen.', en: 'We are together.' }
    }
    if (DEGREE_ADVERBS.has(lemma) && known('gut', word.sortOrder, index)) {
      return { de: withPeriod(`Das ist ${lemma} gut`), en: `That is ${gloss} good.` }
    }
    if (lemma === 'doch' || lemma === 'mal' || lemma === 'eben') {
      return { de: `${capitalize(lemma)}, ich bin da.`, en: `${gloss.charAt(0).toUpperCase()}${gloss.slice(1)}, I am here.` }
    }
    return { de: withPeriod(`Ich bin ${lemma} da`), en: `I am here ${gloss}.` }
  }

  if (word.tags.includes('pronoun')) {
    const seen = pronounSentence(lemma)
    if (seen) {
      return seen
    }
  }

  if (word.tags.includes('determiner') || word.tags.includes('quantifier')) {
    return determinerSentence(lemma, gloss)
  }

  return null
}

const pronounSentence = (lemma: string): PracticeSentence | null => {
  const sentences: Record<string, PracticeSentence> = {
    mich: { de: 'Ich sehe mich.', en: 'I see me.' },
    mir: { de: 'Ich helfe mir.', en: 'I help myself.' },
    dich: { de: 'Ich sehe dich.', en: 'I see you.' },
    dir: { de: 'Ich helfe dir.', en: 'I help you.' },
    ihn: { de: 'Ich sehe ihn.', en: 'I see him.' },
    ihm: { de: 'Ich helfe ihm.', en: 'I help him.' },
    uns: { de: 'Ich sehe uns.', en: 'I see us.' },
    euch: { de: 'Ich sehe euch.', en: 'I see you.' },
    ihnen: { de: 'Ich helfe ihnen.', en: 'I help them.' },
    sich: { de: 'Er sieht sich.', en: 'He sees himself.' },
    Sie: { de: 'Ich sehe Sie.', en: 'I see you.' },
    Ihnen: { de: 'Ich helfe Ihnen.', en: 'I help you.' },
    man: { de: 'Man ist da.', en: 'One is here.' },
    etwas: { de: 'Ich sehe etwas.', en: 'I see something.' },
    nichts: { de: 'Ich sehe nichts.', en: 'I see nothing.' },
    jemand: { de: 'Jemand ist da.', en: 'Someone is here.' },
    niemand: { de: 'Niemand ist da.', en: 'Nobody is here.' },
    alles: { de: 'Alles ist gut.', en: 'Everything is good.' },
  }
  return sentences[lemma] ?? null
}

const determinerSentence = (lemma: string, gloss: string): PracticeSentence | null => {
  const sentences: Record<string, PracticeSentence> = {
    mein: { de: 'Das ist mein Haus.', en: 'That is my house.' },
    dein: { de: 'Das ist dein Haus.', en: 'That is your house.' },
    'sein (Possessiv)': { de: 'Das ist sein Haus.', en: 'That is his house.' },
    'ihr (Possessiv)': { de: 'Das ist ihr Haus.', en: 'That is her house.' },
    unser: { de: 'Das ist unser Haus.', en: 'That is our house.' },
    euer: { de: 'Das ist euer Haus.', en: 'That is your house.' },
    Ihr: { de: 'Das ist Ihr Haus.', en: 'That is your house.' },
    dieser: { de: 'Das ist dieser Mann.', en: 'That is this man.' },
    diese: { de: 'Das ist diese Frau.', en: 'That is this woman.' },
    dieses: { de: 'Das ist dieses Haus.', en: 'That is this house.' },
    jeder: { de: 'Das ist jeder Mann.', en: 'That is every man.' },
    jede: { de: 'Das ist jede Frau.', en: 'That is every woman.' },
    beide: { de: 'Beide sind da.', en: 'Both are here.' },
    alle: { de: 'Alle sind da.', en: 'Everyone is here.' },
    viele: { de: 'Viele sind da.', en: 'Many are here.' },
    wenige: { de: 'Wenige sind da.', en: 'Few are here.' },
    viel: { de: 'Ich habe viel.', en: 'I have a lot.' },
    mehr: { de: 'Ich habe mehr.', en: 'I have more.' },
    ein: { de: 'Ich habe ein Haus.', en: 'I have a house.' },
    eine: { de: 'Ich habe eine Frau.', en: 'I have a woman.' },
    einen: { de: 'Ich habe einen Apfel.', en: 'I have an apple.' },
    einem: { de: 'Ich helfe einem Mann.', en: 'I am helping a man.' },
    einer: { de: 'Ich helfe einer Frau.', en: 'I am helping a woman.' },
    eines: { de: 'Ich habe eines.', en: 'I have one.' },
    kein: { de: 'Ich habe kein Haus.', en: 'I have no house.' },
    keine: { de: 'Ich habe keine Zeit.', en: 'I have no time.' },
    keinen: { de: 'Ich habe keinen Apfel.', en: 'I have no apple.' },
    keinem: { de: 'Ich helfe keinem Mann.', en: 'I am not helping any man.' },
    keiner: { de: 'Ich helfe keiner Frau.', en: 'I am not helping any woman.' },
    der: { de: 'Das ist der Mann.', en: 'That is the man.' },
    die: { de: 'Das ist die Frau.', en: 'That is the woman.' },
    das: { de: 'Das ist das Haus.', en: 'That is the house.' },
    den: { de: 'Ich sehe den Mann.', en: 'I see the man.' },
    dem: { de: 'Ich helfe dem Mann.', en: 'I am helping the man.' },
    des: { de: 'Das Haus des Mannes.', en: 'The man’s house.' },
    welcher: { de: 'Welcher Mann ist das?', en: 'Which man is that?' },
    welche: { de: 'Welche Frau ist das?', en: 'Which woman is that?' },
    welches: { de: 'Welches Haus ist das?', en: 'Which house is that?' },
  }
  return (
    sentences[lemma] ?? {
      de: withPeriod(`Das ist ${lemma}`),
      en: `That is ${gloss}.`,
    }
  )
}

const DETERMINERS = new Set([
  'der', 'die', 'das', 'den', 'dem', 'des',
  'ein', 'eine', 'einen', 'einem', 'einer', 'eines',
  'kein', 'keine', 'keinen', 'keinem', 'keiner', 'keines',
  'mein', 'meine', 'meinen', 'meinem', 'meiner', 'meines',
  'dein', 'deine', 'deinen', 'deinem', 'deiner', 'deines',
  'sein', 'seine', 'seinen', 'seinem', 'seiner', 'seines',
  'ihr', 'ihre', 'ihren', 'ihrem', 'ihrer', 'ihres',
  'unser', 'unsere', 'unseren', 'unserem', 'unserer', 'unseres',
  'euer', 'eure', 'euren', 'eurem', 'eurer', 'eures',
])

/** Present-tense forms that a stem match cannot rebuild. */
const INFLECTED: Record<string, readonly string[]> = {
  sein: ['bin', 'bist', 'ist', 'sind', 'seid', 'war', 'wart', 'waren'],
  haben: ['habe', 'hast', 'hat', 'habt'],
  werden: ['werde', 'wirst', 'wird', 'werdet'],
  können: ['kann', 'kannst', 'könnt'],
  müssen: ['muss', 'musst', 'müsst'],
  wollen: ['will', 'willst', 'wollt'],
  mögen: ['mag', 'magst', 'mögt'],
  dürfen: ['darf', 'darfst', 'dürft'],
  sollen: ['soll', 'sollst', 'sollt'],
  gehen: ['gehe', 'gehst', 'geht', 'ging'],
  essen: ['esse', 'isst', 'esst', 'aß'],
  lesen: ['lese', 'liest', 'lest'],
  sehen: ['sehe', 'siehst', 'sieht'],
  sprechen: ['spreche', 'sprichst', 'spricht'],
  nehmen: ['nehme', 'nimmst', 'nimmt'],
  geben: ['gebe', 'gibst', 'gibt'],
  fahren: ['fahre', 'fährst', 'fährt'],
  schlafen: ['schlafe', 'schläfst', 'schläft'],
  tragen: ['trage', 'trägst', 'trägt'],
  helfen: ['helfe', 'hilfst', 'hilft'],
  wissen: ['weiß', 'weißt'],
  kennen: ['kenne', 'kennst', 'kennt'],
}

const INFLECTION = /^(?:e|st|t|en|est|et|te|ten|test|tet)?$/u

type WordSlice = {
  text: string
  start: number
  end: number
}

const coreLemma = (lemma: string): string => lemma.replace(/\s*\([^)]*\)\s*/gu, ' ').trim()

const sameWord = (left: string, right: string): boolean =>
  left.localeCompare(right, 'de', { sensitivity: 'accent' }) === 0

const wordSlices = (sentence: string): WordSlice[] => {
  const pattern = /[\p{L}\p{N}]+(?:['’-]?[\p{L}\p{N}]+)*/gu
  const slices: WordSlice[] = []
  for (const match of sentence.matchAll(pattern)) {
    const text = match[0]
    const start = match.index ?? 0
    slices.push({ text, start, end: start + text.length })
  }
  return slices
}

const findSlice = (slices: WordSlice[], target: string): number =>
  slices.findIndex((slice) => sameWord(slice.text, target))

const stemOf = (lemma: string): string => lemma.replace(/(?:e[lr]|en|n)$/u, '')

/**
 * Replaces the target word in a practice sentence with `_____`.
 * A leading article stays inside the answer, so “den Tisch” is one blank.
 * When the citation form is conjugated, the form in the sentence is used.
 */
export const blankInSentence = (sentence: string, word: PracticeWord): BlankedSentence => {
  const slices = wordSlices(sentence)
  if (slices.length === 0) {
    return { blankDe: '_____', blankAnswer: sentence.trim() }
  }

  const lemma = coreLemma(word.lemma)
  const targets: string[] = []
  const addTarget = (value: string) => {
    const trimmed = value.trim()
    if (trimmed.length === 0 || trimmed === '-') {
      return
    }
    if (targets.some((item) => sameWord(item, trimmed))) {
      return
    }
    targets.push(trimmed)
  }

  addTarget(bareNoun(lemma))
  if (word.plural && word.plural !== '-') {
    addTarget(bareNoun(word.plural))
  }
  addTarget(lemma)

  const spanFor = (index: number, target: string): WordSlice => {
    const current = slices[index]
    if (!current) {
      return slices[0]!
    }
    const previous = index > 0 ? slices[index - 1] : undefined
    const targetIsDeterminer = DETERMINERS.has(target.toLowerCase())
    if (
      previous &&
      !targetIsDeterminer &&
      DETERMINERS.has(previous.text.toLowerCase())
    ) {
      return { text: sentence.slice(previous.start, current.end), start: previous.start, end: current.end }
    }
    return current
  }

  const blankAt = (span: WordSlice): BlankedSentence => ({
    blankDe: `${sentence.slice(0, span.start)}_____${sentence.slice(span.end)}`,
    blankAnswer: sentence.slice(span.start, span.end),
  })

  for (const target of targets) {
    const index = findSlice(slices, target)
    if (index >= 0) {
      return blankAt(spanFor(index, target))
    }
  }

  for (const form of INFLECTED[lemma.toLowerCase()] ?? []) {
    const index = findSlice(slices, form)
    if (index >= 0) {
      return blankAt(spanFor(index, form))
    }
  }

  const stem = stemOf(bareNoun(lemma)).toLowerCase()
  if (stem.length >= 3) {
    const index = slices.findIndex((slice) => {
      const text = slice.text.toLowerCase()
      return text.startsWith(stem) && INFLECTION.test(text.slice(stem.length))
    })
    if (index >= 0) {
      return blankAt(spanFor(index, slices[index]?.text ?? stem))
    }
  }

  const fallback = [...slices].reverse().find((slice) => !DETERMINERS.has(slice.text.toLowerCase()))
  return blankAt(fallback ?? slices[slices.length - 1]!)
}

/**
 * True when the learner still writes the word from its English meaning.
 * A review card skips that step once the interval is a week or longer.
 * The sentence blank stays on every card.
 */
export const cardRecallsWord = (state: number, scheduledDays: number): boolean => {
  if (state !== FSRS_REVIEW_STATE) {
    return true
  }
  return scheduledDays < MATURE_INTERVAL_DAYS
}

/** Older clients still read this flag. It matches `cardRecallsWord`. */
export const cardWritesSentence = cardRecallsWord
