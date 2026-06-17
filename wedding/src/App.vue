<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://wqahhqssawaxynqigwtr.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndxYWhocXNzYXdheHlucWlnd3RyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEzMjMwMjUsImV4cCI6MjA5Njg5OTAyNX0.b8d5YFUG7XSerEuCX0LygAU-JfOuxxB2T03Jaur0JjQ'
)

const CATEGORIES = ['웨딩', '가전/가구', '예물/예단', '신혼여행', '기타']
const CAT_COLORS = ['#ff6b6b', '#ffa94d', '#9775fa', '#4dabf7', '#69db7c']

const items = ref([])
const budget = ref(30000000)
const catBudgets = ref(Object.fromEntries(CATEGORIES.map(c => [c, 0])))
const view = ref('home')
const currentCat = ref('')
const editItem = ref(null)
const showSettings = ref(false)
const loading = ref(true)
const saveStatus = ref(null) // null | 'saving' | 'saved' | 'error'
const newItem = ref({ name: '', planned: '', actual: '', paid: false, memo: '', date: '', vendor: '' })
const APP_PASSWORD = 'tjdrbsalswl123'
const isAuthorized = ref(false)
const inputPassword = ref('')
let toastTimer = null

const setToast = (status) => {
  saveStatus.value = status
  if (toastTimer) clearTimeout(toastTimer)
  if (status === 'saved' || status === 'error') {
    toastTimer = setTimeout(() => { saveStatus.value = null }, 3000)
  }
}

const login = async () => {
  if (inputPassword.value === APP_PASSWORD) {
    isAuthorized.value = true
    await fetchAll()
  } else {
    alert('비밀번호가 틀렸습니다!')
    inputPassword.value = ''
  }
}

// ── 데이터 불러오기 ──────────────────────────────────────────
const fetchAll = async () => {
  loading.value = true
  try {
    const [{ data: itemsData, error: e1 }, { data: settingsData, error: e2 }] = await Promise.all([
      supabase.from('wedding_items').select('*').order('created_at'),
      supabase.from('wedding_settings').select('*')
    ])
    if (e1) throw e1
    if (e2) throw e2
    if (itemsData) items.value = itemsData
    if (settingsData) {
      settingsData.forEach(({ key, value }) => {
        if (key === 'budget') budget.value = Number(value)
        if (key === 'catBudgets') catBudgets.value = { ...Object.fromEntries(CATEGORIES.map(c => [c, 0])), ...value }
      })
    }
  } catch (e) {
    console.error('불러오기 실패:', e)
    alert('데이터 불러오기 실패: ' + e.message)
  }
  loading.value = false
}

// ── 설정 저장 (onConflict: 'key' 필수) ───────────────────────
const saveSettings = async () => {
  setToast('saving')
  try {
    const [{ error: e1 }, { error: e2 }] = await Promise.all([
      supabase.from('wedding_settings').upsert({ key: 'budget', value: budget.value }, { onConflict: 'key' }),
      supabase.from('wedding_settings').upsert({ key: 'catBudgets', value: catBudgets.value }, { onConflict: 'key' })
    ])
    if (e1) throw e1
    if (e2) throw e2
    setToast('saved')
  } catch (e) {
    console.error('설정 저장 실패:', e)
    setToast('error')
    alert('설정 저장 실패: ' + e.message)
  }
}

// ── 항목 추가 ────────────────────────────────────────────────
const addItem = async () => {
  if (!newItem.value.name.trim()) return
  setToast('saving')
  const payload = {
    name: newItem.value.name.trim(),
    vendor: newItem.value.vendor,
    planned: Number(newItem.value.planned) || 0,
    actual: Number(newItem.value.actual) || 0,
    paid: newItem.value.paid,
    memo: newItem.value.memo,
    date: newItem.value.date || null,
    category: currentCat.value
  }
  const { data, error } = await supabase.from('wedding_items').insert(payload).select().single()
  if (!error && data) {
    items.value.push(data)
    newItem.value = { name: '', planned: '', actual: '', paid: false, memo: '', date: '', vendor: '' }
    setToast('saved')
  } else {
    console.error('추가 실패:', error)
    setToast('error')
    alert('추가 실패: ' + error.message)
  }
}

// ── 항목 삭제 ────────────────────────────────────────────────
const deleteItem = async (id) => {
  if (!confirm('삭제할까요?')) return
  setToast('saving')
  const { error } = await supabase.from('wedding_items').delete().eq('id', id)
  if (!error) {
    items.value = items.value.filter(i => i.id !== id)
    setToast('saved')
  } else {
    console.error('삭제 실패:', error)
    setToast('error')
    alert('삭제 실패: ' + error.message)
  }
}

// ── 항목 수정 저장 (시스템 필드 제외, 성공 시에만 닫기) ────────
const saveEdit = async () => {
  setToast('saving')
  const { id, created_at, ...fields } = editItem.value
  const payload = {
    ...fields,
    name: fields.name?.trim(),
    planned: Number(fields.planned) || 0,
    actual: Number(fields.actual) || 0,
  }
  const { error } = await supabase.from('wedding_items').update(payload).eq('id', id)
  if (!error) {
    const idx = items.value.findIndex(i => i.id === id)
    if (idx >= 0) items.value[idx] = { id, created_at, ...payload }
    setToast('saved')
    editItem.value = null
  } else {
    console.error('수정 실패:', error)
    setToast('error')
    alert('수정 실패: ' + error.message)
  }
}

// ── 결제 완료 토글 ────────────────────────────────────────────
const togglePaid = async (item) => {
  const newPaid = !item.paid
  const { error } = await supabase.from('wedding_items').update({ paid: newPaid }).eq('id', item.id)
  if (!error) {
    item.paid = newPaid
  } else {
    alert('상태 변경 실패: ' + error.message)
  }
}

// ── 실시간 동기화 ────────────────────────────────────────────
let channel
onMounted(async () => {
  channel = supabase
    .channel('wedding-realtime')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'wedding_items' },
      (payload) => {
        if (payload.eventType === 'INSERT') {
          if (!items.value.find(i => i.id === payload.new.id))
            items.value.push(payload.new)
        } else if (payload.eventType === 'UPDATE') {
          const idx = items.value.findIndex(i => i.id === payload.new.id)
          if (idx >= 0) items.value[idx] = payload.new
        } else if (payload.eventType === 'DELETE') {
          items.value = items.value.filter(i => i.id !== payload.old.id)
        }
      }
    )
    .on('postgres_changes', { event: '*', schema: 'public', table: 'wedding_settings' },
      () => fetchAll()
    )
    .subscribe()
})
onUnmounted(() => {
  if (channel) supabase.removeChannel(channel)
  if (toastTimer) clearTimeout(toastTimer)
})

// ── 계산 ────────────────────────────────────────────────────
const catItems = (cat) => items.value.filter(i => i.category === cat)
const catPlanned = (cat) => catItems(cat).reduce((s, i) => s + (Number(i.planned) || 0), 0)
const catActual = (cat) => catItems(cat).reduce((s, i) => s + (Number(i.actual) || 0), 0)
const totalActual = computed(() => items.value.reduce((s, i) => s + (Number(i.actual) || 0), 0))
const totalPlanned = computed(() => items.value.reduce((s, i) => s + (Number(i.planned) || 0), 0))
const balance = computed(() => budget.value - totalActual.value)
const overBudget = computed(() => balance.value < 0)
const totalProgress = computed(() => budget.value ? Math.min(totalActual.value / budget.value * 100, 100) : 0)
const catProgress = (cat) => { const b = catBudgets.value[cat]; return b ? Math.min(catActual(cat) / b * 100, 100) : 0 }
const catOver = (cat) => catBudgets.value[cat] > 0 && catActual(cat) > catBudgets.value[cat]

// ── 파이 차트 ────────────────────────────────────────────────
const pieData = computed(() => {
  const total = totalActual.value; if (!total) return []
  let angle = 0
  return CATEGORIES.map((cat, i) => {
    const val = catActual(cat); if (!val) return null
    const sweep = val / total * 360
    const seg = { cat, val, d: arcPath(100, 100, 80, angle, angle + sweep), color: CAT_COLORS[i] }
    angle += sweep; return seg
  }).filter(Boolean)
})
function arcPath(cx, cy, r, sa, ea) {
  if (ea - sa >= 360) ea = sa + 359.99
  const rad = a => (a - 90) * Math.PI / 180
  const x1 = cx + r * Math.cos(rad(sa)), y1 = cy + r * Math.sin(rad(sa))
  const x2 = cx + r * Math.cos(rad(ea)), y2 = cy + r * Math.sin(rad(ea))
  return `M${cx},${cy} L${x1},${y1} A${r},${r} 0 ${ea - sa > 180 ? 1 : 0} 1 ${x2},${y2} Z`
}

const fmt = n => Number(n || 0).toLocaleString()
const pct = (a, b) => b ? Math.round(a / b * 100) : 0
const diff = (a, b) => Number(a || 0) - Number(b || 0)
</script>

<template>
  <div class="app">
    <!-- 로그인 화면 -->
    <div v-if="!isAuthorized" class="login-screen">
      <div class="login-box">
        <h1>💍</h1>
        <h2>우리만의 결혼 준비</h2>
        <input v-model="inputPassword" type="password" maxlength="15" placeholder="비밀번호 입력" @keyup.enter="login" class="pw-input" />
        <button @click="login" class="btn-login">입장하기</button>
      </div>
    </div>

    <template v-else>
      <!-- 로딩 -->
      <div v-if="loading" class="loading-screen">
        <div class="spinner"></div>
        <p>데이터 불러오는 중...</p>
      </div>

      <template v-else>
        <!-- 저장 상태 토스트 -->
        <div class="toast" :class="{ visible: saveStatus }">
          <span v-if="saveStatus === 'saving'">💾 저장 중...</span>
          <span v-else-if="saveStatus === 'saved'">✅ 저장됨</span>
          <span v-else-if="saveStatus === 'error'">❌ 저장 실패</span>
        </div>

        <!-- ───── HOME VIEW ───── -->
        <div v-if="view === 'home'">
          <div class="title-row">
            <h1>💍 결혼 준비</h1>
            <button class="settings-btn" @click="showSettings = !showSettings" :class="{ active: showSettings }">⚙️</button>
          </div>

          <!-- 총 예산 카드 -->
          <div class="budget-card" :class="{ over: overBudget }">
            <div class="budget-top">
              <div>
                <small>총 예산</small>
                <div v-if="showSettings" class="budget-edit-row">
                  <input v-model.number="budget" type="number" class="budget-input" @change="saveSettings" />
                  <span>원</span>
                </div>
                <div v-else class="big-num">{{ fmt(budget) }}원</div>
              </div>
              <span class="badge-label">{{ overBudget ? '⚠️ 초과' : '✅ 여유' }}</span>
            </div>
            <div class="progress-bar">
              <div class="progress-fill" :style="{ width: totalProgress + '%', background: overBudget ? '#ff4757' : '#a9e34b' }"></div>
            </div>
            <div class="budget-stats">
              <div><small>지출</small><span :class="{ red: overBudget }">{{ fmt(totalActual) }}원</span></div>
              <div><small>계획</small><span>{{ fmt(totalPlanned) }}원</span></div>
              <div><small>잔액</small><span :class="overBudget ? 'red' : 'green'">{{ fmt(balance) }}원</span></div>
            </div>
          </div>

          <!-- 카테고리 예산 설정 -->
          <div v-if="showSettings" class="settings-panel">
            <p class="panel-title">카테고리별 예산 설정</p>
            <div v-for="(cat, i) in CATEGORIES" :key="cat" class="setting-row">
              <span class="cat-dot" :style="{ background: CAT_COLORS[i] }"></span>
              <span class="setting-label">{{ cat }}</span>
              <input v-model.number="catBudgets[cat]" type="number" class="setting-input" @change="saveSettings" />
              <span class="won">원</span>
            </div>
            <button class="save-btn" @click="saveSettings">
              {{ saveStatus === 'saving' ? '저장 중...' : '💾 설정 저장' }}
            </button>
          </div>

          <!-- 파이 차트 -->
          <div v-if="totalActual > 0" class="chart-card">
            <p class="panel-title">지출 현황</p>
            <div class="chart-wrap">
              <svg viewBox="0 0 200 200" width="160" height="160">
                <path v-for="seg in pieData" :key="seg.cat" :d="seg.d" :fill="seg.color" stroke="white" stroke-width="2.5" />
                <circle cx="100" cy="100" r="44" fill="white" />
                <text x="100" y="96" text-anchor="middle" font-size="10" fill="#888">총지출</text>
                <text x="100" y="114" text-anchor="middle" font-size="11" fill="#333" font-weight="bold">{{ Math.round(totalActual / 10000) }}만원</text>
              </svg>
              <div class="legend">
                <div v-for="(cat, i) in CATEGORIES" :key="cat" v-show="catActual(cat) > 0" class="legend-row">
                  <span class="leg-dot" :style="{ background: CAT_COLORS[i] }"></span>
                  <span class="leg-cat">{{ cat }}</span>
                  <span class="leg-pct">{{ pct(catActual(cat), totalActual) }}%</span>
                </div>
              </div>
            </div>
          </div>

          <!-- 카테고리 카드 -->
          <p class="panel-title">카테고리별 현황</p>
          <div class="cat-grid">
            <div v-for="(cat, i) in CATEGORIES" :key="cat"
              class="cat-card" :class="{ over: catOver(cat) }"
              @click="currentCat = cat; view = 'detail'">
              <div class="cat-top">
                <span class="cat-icon" :style="{ color: CAT_COLORS[i] }">●</span>
                <span class="cat-name">{{ cat }}</span>
                <span v-if="catOver(cat)" class="over-badge">초과!</span>
              </div>
              <div class="cat-nums">
                <div class="num-row"><span>계획</span><span>{{ fmt(catPlanned(cat)) }}</span></div>
                <div class="num-row"><span>지출</span><span :class="{ red: catOver(cat) }">{{ fmt(catActual(cat)) }}</span></div>
                <div class="num-row diff-row">
                  <span>차이</span>
                  <span :class="diff(catPlanned(cat), catActual(cat)) >= 0 ? 'green' : 'red'">
                    {{ diff(catPlanned(cat), catActual(cat)) >= 0 ? '+' : '' }}{{ fmt(diff(catPlanned(cat), catActual(cat))) }}
                  </span>
                </div>
              </div>
              <div v-if="catBudgets[cat] > 0" class="cat-progress-wrap">
                <div class="progress-bar">
                  <div class="progress-fill" :style="{ width: catProgress(cat) + '%', background: catOver(cat) ? '#ff4757' : CAT_COLORS[i] }"></div>
                </div>
                <small>{{ Math.round(catProgress(cat)) }}% 사용</small>
              </div>
              <small class="item-cnt">{{ catItems(cat).length }}개 항목</small>
            </div>
          </div>
        </div>

        <!-- ───── DETAIL VIEW ───── -->
        <div v-else class="detail-view">
          <div class="detail-header">
            <button @click="view = 'home'" class="back-btn">← 뒤로</button>
            <h2>{{ currentCat }}</h2>
            <span v-if="catOver(currentCat)" class="over-badge">예산 초과!</span>
          </div>

          <div class="summary-card" :class="{ over: catOver(currentCat) }">
            <div class="sum-row"><span>계획 합계</span><strong>{{ fmt(catPlanned(currentCat)) }}원</strong></div>
            <div class="sum-row"><span>실제 지출</span><strong :class="{ red: catOver(currentCat) }">{{ fmt(catActual(currentCat)) }}원</strong></div>
            <div class="sum-row">
              <span>예상 대비</span>
              <strong :class="diff(catPlanned(currentCat), catActual(currentCat)) >= 0 ? 'green' : 'red'">
                {{ diff(catPlanned(currentCat), catActual(currentCat)) >= 0 ? '절약 ' : '초과 ' }}
                {{ fmt(Math.abs(diff(catPlanned(currentCat), catActual(currentCat)))) }}원
              </strong>
            </div>
            <div v-if="catBudgets[currentCat] > 0">
              <div class="progress-bar mt8">
                <div class="progress-fill" :style="{ width: catProgress(currentCat) + '%', background: catOver(currentCat) ? '#ff4757' : '#ff6b6b' }"></div>
              </div>
              <small>예산 {{ fmt(catBudgets[currentCat]) }}원 중 {{ Math.round(catProgress(currentCat)) }}% 사용</small>
            </div>
          </div>

          <!-- 항목 추가 폼 -->
          <div class="add-form">
            <p class="panel-title">항목 추가</p>
            <input v-model="newItem.name" placeholder="항목명 *" class="full-input" />
            <input v-model="newItem.vendor" placeholder="업체명" class="full-input" />
            <div class="row2">
              <input v-model.number="newItem.planned" type="number" placeholder="예상 금액" />
              <input v-model.number="newItem.actual" type="number" placeholder="실제 금액" />
            </div>
            <div class="row2">
              <input v-model="newItem.date" type="date" style="flex:1" />
              <label class="paid-label"><input type="checkbox" v-model="newItem.paid" /> 결제완료</label>
            </div>
            <textarea v-model="newItem.memo" placeholder="메모" class="full-input memo"></textarea>
            <button @click="addItem" class="btn-add" :disabled="saveStatus === 'saving'">
              {{ saveStatus === 'saving' ? '저장 중...' : '+ 추가하기' }}
            </button>
          </div>

          <!-- 항목 목록 -->
          <p class="panel-title">항목 목록 ({{ catItems(currentCat).length }}개)</p>
          <div class="items-list">
            <div v-for="item in catItems(currentCat)" :key="item.id" class="item-card" :class="{ paid: item.paid }">
              <div class="item-top">
                <div class="item-left">
                  <input type="checkbox" :checked="item.paid" @change="togglePaid(item)" class="paid-check" />
                  <span class="item-name" :class="{ strikethrough: item.paid }">{{ item.name }}</span>
                  <span v-if="item.vendor" class="vendor-tag">{{ item.vendor }}</span>
                  <span v-if="item.paid" class="paid-tag">결제완료</span>
                </div>
                <div class="item-actions">
                  <button @click="editItem = { ...item }" class="btn-icon">✏️</button>
                  <button @click="deleteItem(item.id)" class="btn-icon">🗑️</button>
                </div>
              </div>
              <div class="item-prices">
                <span>예상 {{ fmt(item.planned) }}원</span>
                <span class="act-price">지출 {{ fmt(item.actual) }}원</span>
                <span :class="diff(item.planned, item.actual) >= 0 ? 'green' : 'red'">
                  {{ diff(item.planned, item.actual) >= 0 ? '▼절약 ' : '▲초과 ' }}{{ fmt(Math.abs(diff(item.planned, item.actual))) }}원
                </span>
              </div>
              <div v-if="item.date" class="item-meta">📅 {{ item.date }}</div>
              <div v-if="item.memo" class="item-memo">💬 {{ item.memo }}</div>
            </div>
            <div v-if="catItems(currentCat).length === 0" class="empty-state">
              <span>📝</span><p>아직 항목이 없어요. 위에서 추가해보세요!</p>
            </div>
          </div>
        </div>

        <!-- ───── 수정 모달 ───── -->
        <div v-if="editItem" class="modal-overlay" @click.self="editItem = null">
          <div class="modal">
            <h3>항목 수정</h3>
            <input v-model="editItem.name" placeholder="항목명" class="full-input" />
            <input v-model="editItem.vendor" placeholder="업체명" class="full-input" />
            <div class="row2">
              <input v-model.number="editItem.planned" type="number" placeholder="예상 금액" />
              <input v-model.number="editItem.actual" type="number" placeholder="실제 금액" />
            </div>
            <input v-model="editItem.date" type="date" class="full-input" />
            <textarea v-model="editItem.memo" placeholder="메모" class="full-input memo"></textarea>
            <label class="paid-label"><input type="checkbox" v-model="editItem.paid" /> 결제완료</label>
            <div class="modal-btns">
              <button @click="editItem = null" class="btn-cancel">취소</button>
              <button @click="saveEdit" class="btn-save" :disabled="saveStatus === 'saving'">
                {{ saveStatus === 'saving' ? '저장 중...' : '저장' }}
              </button>
            </div>
          </div>
        </div>

      </template>
    </template>
  </div>
</template>

<style scoped>
* { box-sizing: border-box; }
.app { max-width: 480px; margin: 0 auto; background: #fdf5f5; min-height: 100vh; padding: 16px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }

/* 로딩 */
.loading-screen { display: flex; flex-direction: column; align-items: center; justify-content: center; height: 80vh; color: #aaa; gap: 16px; }
.spinner { width: 40px; height: 40px; border: 3px solid #ffd6d6; border-top-color: #ff6b6b; border-radius: 50%; animation: spin 0.8s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

/* 저장 토스트 */
.toast { position: fixed; top: 12px; right: 12px; background: white; border-radius: 20px; padding: 6px 14px; font-size: 13px; box-shadow: 0 4px 12px rgba(0,0,0,0.12); opacity: 0; transition: opacity 0.3s; z-index: 300; pointer-events: none; }
.toast.visible { opacity: 1; }

/* Title */
.title-row { display: flex; justify-content: space-between; align-items: center; }
h1 { margin: 0 0 12px; font-size: 22px; color: #333; }
.settings-btn { background: none; border: 1px solid #ddd; border-radius: 8px; padding: 4px 10px; cursor: pointer; font-size: 18px; }
.settings-btn.active { background: #fff3f3; border-color: #ff6b6b; }

/* Budget Card */
.budget-card { background: linear-gradient(135deg, #ff6b6b, #ee5a24); color: white; border-radius: 20px; padding: 20px; margin-bottom: 16px; }
.budget-card.over { background: linear-gradient(135deg, #ff4757, #c0392b); }
.budget-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px; }
.budget-top small { opacity: 0.8; display: block; font-size: 12px; margin-bottom: 4px; }
.big-num { font-size: 22px; font-weight: bold; }
.budget-edit-row { display: flex; align-items: center; gap: 6px; }
.budget-input { background: rgba(255,255,255,0.25); border: 1px solid rgba(255,255,255,0.4); color: white; border-radius: 8px; padding: 4px 10px; font-size: 16px; width: 140px; }
.badge-label { background: rgba(255,255,255,0.2); border-radius: 20px; padding: 4px 12px; font-size: 13px; font-weight: bold; white-space: nowrap; }
.budget-stats { display: flex; justify-content: space-between; margin-top: 10px; }
.budget-stats div { text-align: center; }
.budget-stats small { display: block; opacity: 0.75; font-size: 11px; margin-bottom: 2px; }
.budget-stats span { font-size: 14px; font-weight: bold; }
.progress-bar { background: rgba(255,255,255,0.25); border-radius: 10px; height: 8px; overflow: hidden; margin-bottom: 4px; }
.detail-view .progress-bar, .summary-card .progress-bar { background: #f0e6e6; }
.progress-fill { height: 100%; border-radius: 10px; transition: width 0.5s ease; }

/* Settings */
.settings-panel { background: white; border-radius: 14px; padding: 16px; margin-bottom: 16px; }
.setting-row { display: flex; align-items: center; gap: 8px; padding: 7px 0; }
.cat-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
.setting-label { flex: 1; font-size: 14px; }
.setting-input { width: 110px; padding: 5px 8px; border: 1px solid #eee; border-radius: 8px; font-size: 14px; text-align: right; }
.won { font-size: 13px; color: #888; }
.save-btn { width: 100%; margin-top: 12px; background: #ff6b6b; color: white; border: none; padding: 11px; border-radius: 10px; font-size: 14px; font-weight: bold; cursor: pointer; }

/* Chart */
.chart-card { background: white; border-radius: 16px; padding: 16px; margin-bottom: 16px; }
.chart-wrap { display: flex; align-items: center; gap: 16px; }
.legend { flex: 1; }
.legend-row { display: flex; align-items: center; gap: 7px; margin-bottom: 8px; font-size: 13px; }
.leg-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
.leg-cat { flex: 1; color: #555; }
.leg-pct { font-weight: bold; color: #333; }
.panel-title { font-weight: bold; color: #666; font-size: 13px; margin: 0 0 10px; }

/* Cat Grid */
.cat-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 20px; }
.cat-card { background: white; border-radius: 14px; padding: 14px; cursor: pointer; transition: 0.2s; box-shadow: 0 2px 8px rgba(0,0,0,0.05); border: 2px solid transparent; }
.cat-card:hover { transform: translateY(-3px); box-shadow: 0 6px 18px rgba(0,0,0,0.1); }
.cat-card.over { border-color: #ff4757; }
.cat-top { display: flex; align-items: center; gap: 6px; margin-bottom: 10px; }
.cat-name { font-weight: bold; font-size: 13px; flex: 1; }
.over-badge { background: #ff4757; color: white; font-size: 9px; padding: 2px 6px; border-radius: 10px; white-space: nowrap; }
.cat-nums { margin-bottom: 8px; }
.num-row { display: flex; justify-content: space-between; font-size: 12px; color: #666; margin-bottom: 4px; }
.diff-row { font-weight: bold; border-top: 1px solid #f0f0f0; padding-top: 4px; margin-top: 2px; }
.cat-progress-wrap { margin-top: 6px; }
.cat-progress-wrap small { font-size: 11px; color: #aaa; }
.item-cnt { display: block; font-size: 11px; color: #bbb; margin-top: 6px; }

/* Detail */
.detail-header { display: flex; align-items: center; gap: 10px; margin-bottom: 16px; }
.detail-header h2 { margin: 0; font-size: 18px; }
.back-btn { background: white; border: 1px solid #ddd; border-radius: 8px; padding: 6px 12px; cursor: pointer; font-size: 13px; }
.summary-card { background: white; border-radius: 14px; padding: 16px; margin-bottom: 16px; border-left: 4px solid #ff6b6b; }
.summary-card.over { border-left-color: #ff4757; background: #fff5f5; }
.sum-row { display: flex; justify-content: space-between; align-items: center; padding: 5px 0; font-size: 14px; }
.mt8 { margin-top: 8px; }

/* Form */
.add-form { background: white; border-radius: 14px; padding: 16px; margin-bottom: 16px; }
.full-input { width: 100%; padding: 10px 12px; border: 1px solid #eee; border-radius: 8px; margin-bottom: 8px; font-size: 14px; }
.full-input:focus { outline: none; border-color: #ff6b6b; }
.row2 { display: flex; gap: 8px; margin-bottom: 8px; }
.row2 input { flex: 1; padding: 10px 12px; border: 1px solid #eee; border-radius: 8px; font-size: 14px; }
.paid-label { display: flex; align-items: center; gap: 6px; font-size: 14px; color: #555; padding: 8px 0; cursor: pointer; }
.memo { resize: vertical; min-height: 64px; }
.btn-add { width: 100%; background: #ff6b6b; color: white; border: none; padding: 13px; border-radius: 10px; font-size: 15px; font-weight: bold; cursor: pointer; }
.btn-add:disabled { opacity: 0.6; cursor: not-allowed; }

/* Items */
.item-card { background: white; border-radius: 12px; padding: 14px; margin-bottom: 10px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); }
.item-card.paid { opacity: 0.65; }
.item-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 8px; }
.item-left { display: flex; align-items: center; gap: 7px; flex-wrap: wrap; flex: 1; }
.paid-check { width: 15px; height: 15px; cursor: pointer; accent-color: #ff6b6b; flex-shrink: 0; }
.item-name { font-weight: bold; font-size: 15px; }
.strikethrough { text-decoration: line-through; color: #aaa; }
.vendor-tag { background: #f1f3f5; color: #666; font-size: 11px; padding: 2px 8px; border-radius: 10px; }
.paid-tag { background: #d3f9d8; color: #2f9e44; font-size: 11px; padding: 2px 8px; border-radius: 10px; }
.item-actions { display: flex; gap: 2px; flex-shrink: 0; }
.btn-icon { background: none; border: none; cursor: pointer; font-size: 16px; padding: 3px 5px; border-radius: 6px; }
.btn-icon:hover { background: #f1f3f5; }
.item-prices { display: flex; flex-wrap: wrap; gap: 10px; font-size: 13px; color: #888; margin-bottom: 4px; }
.act-price { color: #ff6b6b; font-weight: bold; }
.item-meta { font-size: 12px; color: #bbb; margin-top: 4px; }
.item-memo { font-size: 13px; color: #666; margin-top: 6px; background: #fafafa; border-radius: 8px; padding: 7px 10px; }
.empty-state { text-align: center; padding: 40px 20px; color: #ccc; }
.empty-state span { font-size: 32px; display: block; margin-bottom: 10px; }

/* Modal */
.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.55); display: flex; align-items: center; justify-content: center; z-index: 200; padding: 20px; }
.modal { background: white; border-radius: 20px; padding: 24px; width: 100%; max-width: 400px; max-height: 90vh; overflow-y: auto; }
.modal h3 { margin: 0 0 16px; }
.modal-btns { display: flex; gap: 10px; margin-top: 16px; }
.btn-cancel { flex: 1; padding: 12px; border: 1px solid #ddd; border-radius: 10px; cursor: pointer; background: white; }
.btn-save { flex: 1; padding: 12px; background: #ff6b6b; color: white; border: none; border-radius: 10px; cursor: pointer; font-weight: bold; }
.btn-save:disabled { opacity: 0.6; cursor: not-allowed; }

.red { color: #ff4757; }
.green { color: #2ed573; }

.login-screen { display: flex; align-items: center; justify-content: center; height: 90vh; }
.login-box { background: white; padding: 40px 30px; border-radius: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.05); text-align: center; width: 100%; max-width: 320px; margin: 0 auto; }
.login-box h1 { font-size: 40px; margin: 0 0 10px; }
.login-box h2 { font-size: 20px; color: #333; margin: 0 0 20px; }
.pw-input { width: 100%; padding: 12px; border: 1px solid #ddd; border-radius: 10px; font-size: 16px; text-align: center; margin-bottom: 15px; }
.pw-input:focus { outline: none; border-color: #ff6b6b; }
.btn-login { width: 100%; background: #ff6b6b; color: white; border: none; padding: 14px; border-radius: 10px; font-weight: bold; font-size: 16px; cursor: pointer; }
</style>
