import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vitejs.dev/config/
export default defineConfig({
  base: '/wedding-plan/',
  plugins: [
    vue(),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  // 여행 앱 주소(/wedding-plan/travel/)도 실제 파일로 만들어 새로고침해도 열리게 한다
  build: {
    rollupOptions: {
      input: {
        main:   fileURLToPath(new URL('./index.html', import.meta.url)),
        travel: fileURLToPath(new URL('./travel/index.html', import.meta.url)),
      }
    }
  }
})