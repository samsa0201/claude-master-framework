import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// `bun run dev` proxies the API to a running `team ui` (default port 7777)
export default defineConfig({
  plugins: [vue()],
  build: { outDir: '../dist', emptyOutDir: true, target: 'es2022' },
  server: { proxy: { '/api': 'http://127.0.0.1:7777' } },
})
