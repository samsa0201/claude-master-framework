import { createApp } from 'vue'
import App from './App.vue'
import './style.css'
import './theme'
import { startPolling } from './store'

createApp(App).mount('#app')
startPolling()
