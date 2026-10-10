import { ref, watchEffect } from 'vue'

export type Theme = 'system' | 'light' | 'dark'
const ORDER: Theme[] = ['system', 'light', 'dark']

const load = (): Theme => {
  try {
    const t = localStorage.getItem('theme')
    return t === 'light' || t === 'dark' ? t : 'system'
  } catch {
    return 'system'
  }
}

export const theme = ref<Theme>(load())

watchEffect(() => {
  const t = theme.value
  if (t === 'system') delete document.documentElement.dataset.theme
  else document.documentElement.dataset.theme = t
  try {
    if (t === 'system') localStorage.removeItem('theme')
    else localStorage.setItem('theme', t)
  } catch {
    /* storage can be blocked; the theme still applies for this page */
  }
})

export const cycleTheme = (): void => {
  theme.value = ORDER[(ORDER.indexOf(theme.value) + 1) % ORDER.length]!
}
