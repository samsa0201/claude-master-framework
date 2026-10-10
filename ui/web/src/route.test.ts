import { expect, test } from 'bun:test'

// route.ts touches `location` at import; stub it before loading
Object.assign(globalThis, { location: { hash: '' }, addEventListener: () => {} })
const { parseHash, buildHash } = await import('./route')

test('parseHash', () => {
  expect(parseHash('')).toEqual({ project: '', tab: 'overview', arg: '' })
  expect(parseHash('#/demo')).toEqual({ project: 'demo', tab: 'overview', arg: '' })
  expect(parseHash('#/demo/docs/docs%2Fprd.md')).toEqual({ project: 'demo', tab: 'docs', arg: 'docs/prd.md' })
  expect(parseHash('#/demo/nope')).toMatchObject({ tab: 'overview' })
  expect(parseHash('#/%E0%A4%A')).toMatchObject({ project: '%E0%A4%A' }) // malformed escape must not throw
})

test('buildHash round-trips', () => {
  for (const r of [
    { project: 'demo', tab: 'overview' as const, arg: '' },
    { project: 'demo', tab: 'overview' as const, arg: 'demo-dev-120000' },
    { project: 'my app', tab: 'docs' as const, arg: 'docs/a b.md' },
    { project: 'demo', tab: 'terminal' as const, arg: 'demo-dev-2' },
  ]) expect(parseHash(buildHash(r))).toEqual(r)
  expect(buildHash({ project: 'demo' })).toBe('#/demo')
})
