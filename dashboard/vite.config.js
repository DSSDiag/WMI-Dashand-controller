import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  test: {
    pool: 'threads',
    minWorkers: 1,
    maxWorkers: 1,
    testTimeout: 30000,
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/setupTests.js',
  },
})
