import { expect, test } from 'bun:test'
import { ago, bytes, duration } from './format'

test('ago', () => {
  expect(ago(0)).toBe('just now')
  expect(ago(-5)).toBe('just now')
  expect(ago(42)).toBe('42s ago')
  expect(ago(60)).toBe('1m ago')
  expect(ago(3599)).toBe('59m ago')
  expect(ago(7200)).toBe('2h ago')
  expect(ago(3 * 86400)).toBe('3d ago')
})

test('duration', () => {
  expect(duration(0)).toBe('0s')
  expect(duration(59.9)).toBe('59s')
  expect(duration(61)).toBe('1m 01s')
  expect(duration(3725)).toBe('1h 02m')
})

test('bytes', () => {
  expect(bytes(10)).toBe('10 B')
  expect(bytes(2048)).toBe('2.0 KB')
  expect(bytes(5 * 1048576)).toBe('5.0 MB')
})
