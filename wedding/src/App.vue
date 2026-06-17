<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_KEY
)

const PRESET_COLORS = ['#ff6b6b','#ffa94d','#ffd43b','#a9e34b','#69db7c','#38d9a9','#4dabf7','#748ffc','#9775fa','#f783ac','#adb5bd','#495057']
const PRESET_ICONS  = ['💍','🛋️','💎','✈️','📦','👗','🍽️','💐','📸','🎵','💄','👠','🏠','🚗','💌','🎁','💒','🎂','🌸','✨','💳','📋']

// ── 인증 ────────────────────────────────────────────────────
const isAuthorized = ref(false)
const inputPassword = ref('')
const APP_PASSWORD = 'tjdrbsalswl123'

// ── 데이터 ──────────────────────────────────────────────────
const categories = ref([])   // { id, name, color, icon, sort_order }
const items      = ref([])
const checklist  = ref([])
const budget     = ref(30000000)
const catBudgets = ref({})

// ── UI 상태 ─────────────────────────────────────────────────
const tab         = ref('home')
const view        = ref('home')
const currentCat  = ref('')
const editItem    = ref(null)
const showSettings  = ref(false)
const showQuickAdd  = ref(false)
const showCatMgr    = ref(false)
const loading     = ref(true)
const saveStatus  = ref(null)

// ── 폼 ──────────────────────────────────────────────────────
const newItem = ref({ name:'', planned:'', actual:'', paid:false, memo:'', date:'', vendor:'', category:'' })
const newCheckText = ref('')
const newCat  = ref({ name:'', color:'#ff6b6b', icon:'📦' })
const editCat = ref(null)   // 수정 중인 카테고리

let toastTimer = null
const setToast = (s) => {
  saveStatus.value = s
  if (toastTimer) clearTimeout(toastTimer)
  if (s === 'saved' || s === 'error') toastTimer = setTimeout(() => { saveStatus.value = null }, 3000)
}

// ── 로그인 ──────────────────────────────────────────────────
const login = async () => {
  if (inputPassword.value === APP_PASSWORD) { isAuthorized.value = true; await fetchAll() }
  else { alert('비밀번호가 틀렸습니다!'); inputPassword.value = '' }
}

// ── 전체 데이터 불러오기 ─────────────────────────────────────
const fetchAll = async () => {
  loading.value = true
  try {
    // 카테고리 먼저 로드 (catBudgets 초기화에 필요)
    const { data: catData, error: ce } = await supabase.from('wedding_categories').select('*').order('sort_order')
    if (ce) throw ce
    if (catData) categories.value = catData

    const defaultBudgets = Object.fromEntries(categories.value.map(c => [c.name, 0]))

    const [{ data: itemsData, error: e1 }, { data: settingsData, error: e2 }, { data: checkData }] = await Promise.all([
      supabase.from('wedding_items').select('*').order('created_at'),
      supabase.from('wedding_settings').select('*'),
      supabase.from('wedding_checklist').select('*').order('created_at')
    ])
    if (e1) throw e1
    if (e2) throw e2

    if (itemsData) items.value = itemsData
    if (checkData)  checklist.value = checkData
    if (settingsData) settingsData.forEach(({ key, value }) => {
      if (key === 'budget')     budget.value = Number(value)
      if (key === 'catBudgets') catBudgets.value = { ...defaultBudgets, ...value }
    })
    if (!catBudgets.value || !Object.keys(catBudgets.value).length) catBudgets.value = defaultBudgets
  } catch (e) {
    console.error('불러오기 실패:', e)
  }
  loading.value = false
}

// ── 설정 저장 ────────────────────────────────────────────────
const saveSettings = async () => {
  setToast('saving')
  try {
    const [{ error: e1 }, { error: e2 }] = await Promise.all([
      supabase.from('wedding_settings').upsert({ key: 'budget',     value: budget.value },     { onConflict: 'key' }),
      supabase.from('wedding_settings').upsert({ key: 'catBudgets', value: catBudgets.value }, { onConflict: 'key' })
    ])
    if (e1) throw e1
    if (e2) throw e2
    setToast('saved')
  } catch (e) { setToast('error'); alert('설정 저장 실패: ' + e.message) }
}

// ── 카테고리 추가 ────────────────────────────────────────────
const addCategory = async () => {
  if (!newCat.value.name.trim()) return
  setToast('saving')
  const payload = { name: newCat.value.name.trim(), color: newCat.value.color, icon: newCat.value.icon, sort_order: categories.value.length }
  const { data, error } = await supabase.from('wedding_categories').insert(payload).select().single()
  if (!error && data) {
    categories.value.push(data)
    catBudgets.value[data.name] = 0
    await saveSettings()
    newCat.value = { name: '', color: '#ff6b6b', icon: '📦' }
    setToast('saved')
  } else { setToast('error'); alert('추가 실패: ' + error.message) }
}

// ── 카테고리 수정 ────────────────────────────────────────────
const saveEditCat = async () => {
  if (!editCat.value?.name?.trim()) return
  setToast('saving')
  const { id, name, color, icon, sort_order } = editCat.value
  const oldName = categories.value.find(c => c.id === id)?.name
  const { error } = await supabase.from('wedding_categories').update({ name: name.trim(), color, icon, sort_order }).eq('id', id)
  if (!error) {
    const idx = categories.value.findIndex(c => c.id === id)
    if (idx >= 0) categories.value[idx] = { ...categories.value[idx], name: name.trim(), color, icon }
    // 카테고리명 변경 시 items도 같이 업데이트
    if (oldName && oldName !== name.trim()) {
      await supabase.from('wedding_items').update({ category: name.trim() }).eq('category', oldName)
      items.value.forEach(i => { if (i.category === oldName) i.category = name.trim() })
      if (catBudgets.value[oldName] !== undefined) {
        catBudgets.value[name.trim()] = catBudgets.value[oldName]
        delete catBudgets.value[oldName]
        await saveSettings()
      }
    }
    editCat.value = null
    setToast('saved')
  } else { setToast('error'); alert('수정 실패: ' + error.message) }
}

// ── 카테고리 삭제 ────────────────────────────────────────────
const deleteCategory = async (cat) => {
  const count = catItems(cat.name).length
  if (count > 0 && !confirm(`'${cat.name}'에 항목 ${count}개가 있어요. 삭제하면 해당 항목들의 카테고리가 비워집니다. 삭제할까요?`)) return
  if (count === 0 && !confirm(`'${cat.name}' 카테고리를 삭제할까요?`)) return
  setToast('saving')
  const { error } = await supabase.from('wedding_categories').delete().eq('id', cat.id)
  if (!error) {
    categories.value = categories.value.filter(c => c.id !== cat.id)
    delete catBudgets.value[cat.name]
    await saveSettings()
    setToast('saved')
  } else { setToast('error'); alert('삭제 실패: ' + error.message) }
}

// ── 항목 추가 ────────────────────────────────────────────────
const addItem = async () => {
  if (!newItem.value.name.trim()) return
  setToast('saving')
  const payload = {
    name:     newItem.value.name.trim(),
    vendor:   newItem.value.vendor,
    planned:  Number(newItem.value.planned) || 0,
    actual:   Number(newItem.value.actual)  || 0,
    paid:     newItem.value.paid,
    memo:     newItem.value.memo,
    date:     newItem.value.date || null,
    category: view.value === 'detail' ? currentCat.value : newItem.value.category
  }
  const { data, error } = await supabase.from('wedding_items').insert(payload).select().single()
  if (!error && data) {
    items.value.push(data)
    newItem.value = { name:'', planned:'', actual:'', paid:false, memo:'', date:'', vendor:'', category: newItem.value.category }
    showQuickAdd.value = false
    setToast('saved')
  } else { setToast('error'); alert('추가 실패: ' + error.message) }
}

// ── 항목 삭제 ────────────────────────────────────────────────
const deleteItem = async (id) => {
  if (!confirm('삭제할까요?')) return
  setToast('saving')
  const { error } = await supabase.from('wedding_items').delete().eq('id', id)
  if (!error) { items.value = items.value.filter(i => i.id !== id); setToast('saved') }
  else { setToast('error'); alert('삭제 실패: ' + error.message) }
}

// ── 항목 수정 ────────────────────────────────────────────────
const saveEdit = async () => {
  setToast('saving')
  const { id, created_at, ...fields } = editItem.value
  const payload = { ...fields, name: fields.name?.trim(), planned: Number(fields.planned)||0, actual: Number(fields.actual)||0 }
  const { error } = await supabase.from('wedding_items').update(payload).eq('id', id)
  if (!error) {
    const idx = items.value.findIndex(i => i.id === id)
    if (idx >= 0) items.value[idx] = { id, created_at, ...payload }
    setToast('saved'); editItem.value = null
  } else { setToast('error'); alert('수정 실패: ' + error.message) }
}

// ── 결제 토글 ────────────────────────────────────────────────
const togglePaid = async (item) => {
  const newPaid = !item.paid
  const { error } = await supabase.from('wedding_items').update({ paid: newPaid }).eq('id', item.id)
  if (!error) item.paid = newPaid
}

// ── 체크리스트 ───────────────────────────────────────────────
const addCheck = async () => {
  if (!newCheckText.value.trim()) return
  const { data, error } = await supabase.from('wedding_checklist').insert({ text: newCheckText.value.trim(), done: false }).select().single()
  if (!error && data) { checklist.value.push(data); newCheckText.value = '' }
  else alert('추가 실패: ' + error?.message)
}
const toggleCheck = async (item) => {
  const newDone = !item.done
  const { error } = await supabase.from('wedding_checklist').update({ done: newDone }).eq('id', item.id)
  if (!error) item.done = newDone
}
const deleteCheck = async (id) => {
  const { error } = await supabase.from('wedding_checklist').delete().eq('id', id)
  if (!error) checklist.value = checklist.value.filter(c => c.id !== id)
}

// ── 실시간 동기화 ────────────────────────────────────────────
let channel
onMounted(() => {
  channel = supabase.channel('wedding-realtime')
    .on('postgres_changes', { event:'*', schema:'public', table:'wedding_items' }, (p) => {
      if (p.eventType==='INSERT') { if (!items.value.find(i=>i.id===p.new.id)) items.value.push(p.new) }
      else if (p.eventType==='UPDATE') { const i=items.value.findIndex(i=>i.id===p.new.id); if(i>=0) items.value[i]=p.new }
      else if (p.eventType==='DELETE') items.value=items.value.filter(i=>i.id!==p.old.id)
    })
    .on('postgres_changes', { event:'*', schema:'public', table:'wedding_categories' }, () => fetchAll())
    .on('postgres_changes', { event:'*', schema:'public', table:'wedding_settings'   }, () => fetchAll())
    .on('postgres_changes', { event:'*', schema:'public', table:'wedding_checklist'  }, (p) => {
      if (p.eventType==='INSERT') { if (!checklist.value.find(c=>c.id===p.new.id)) checklist.value.push(p.new) }
      else if (p.eventType==='UPDATE') { const i=checklist.value.findIndex(c=>c.id===p.new.id); if(i>=0) checklist.value[i]=p.new }
      else if (p.eventType==='DELETE') checklist.value=checklist.value.filter(c=>c.id!==p.old.id)
    })
    .subscribe()
})
onUnmounted(() => {
  if (channel) supabase.removeChannel(channel)
  if (toastTimer) clearTimeout(toastTimer)
})

// ── 계산 ────────────────────────────────────────────────────
const catItems   = (name) => items.value.filter(i => i.category === name)
const catPlanned = (name) => catItems(name).reduce((s,i) => s+(Number(i.planned)||0), 0)
const catActual  = (name) => catItems(name).reduce((s,i) => s+(Number(i.actual) ||0), 0)
const totalActual  = computed(() => items.value.reduce((s,i) => s+(Number(i.actual) ||0), 0))
const totalPlanned = computed(() => items.value.reduce((s,i) => s+(Number(i.planned)||0), 0))
const balance      = computed(() => budget.value - totalActual.value)
const overBudget   = computed(() => balance.value < 0)
const totalProgress= computed(() => budget.value ? Math.min(totalActual.value/budget.value*100,100) : 0)
const catProgress  = (name) => { const b=catBudgets.value[name]; return b ? Math.min(catActual(name)/b*100,100) : 0 }
const catOver      = (name) => catBudgets.value[name]>0 && catActual(name)>catBudgets.value[name]
const checkDoneCount = computed(() => checklist.value.filter(c=>c.done).length)

const pieData = computed(() => {
  const total = totalActual.value; if (!total) return []
  let angle = 0
  return categories.value.map(cat => {
    const val = catActual(cat.name); if (!val) return null
    const sweep = val/total*360
    const seg = { name:cat.name, val, d:arcPath(100,100,80,angle,angle+sweep), color:cat.color }
    angle += sweep; return seg
  }).filter(Boolean)
})
function arcPath(cx,cy,r,sa,ea) {
  if(ea-sa>=360) ea=sa+359.99
  const rad=a=>(a-90)*Math.PI/180
  const x1=cx+r*Math.cos(rad(sa)),y1=cy+r*Math.sin(rad(sa))
  const x2=cx+r*Math.cos(rad(ea)),y2=cy+r*Math.sin(rad(ea))
  return `M${cx},${cy} L${x1},${y1} A${r},${r} 0 ${ea-sa>180?1:0} 1 ${x2},${y2} Z`
}

const fmt  = n => Number(n||0).toLocaleString()
const pct  = (a,b) => b ? Math.round(a/b*100) : 0
const diff = (a,b) => Number(a||0)-Number(b||0)
</script>

<template>
  <div class="app">
    <!-- 로그인 -->
    <div v-if="!isAuthorized" class="login-screen">
      <div class="login-box">
        <div class="login-icon">💍</div>
        <h2>우리만의 결혼 준비</h2>
        <input v-model="inputPassword" type="password" maxlength="15" placeholder="비밀번호 입력" @keyup.enter="login" class="pw-input" />
        <button @click="login" class="btn-primary">입장하기</button>
      </div>
    </div>

    <template v-else>
      <div v-if="loading" class="loading-screen">
        <div class="spinner"></div><p>불러오는 중...</p>
      </div>

      <template v-else>
        <!-- 헤더 -->
        <header class="app-header">
          <div class="header-inner">
            <button v-if="tab==='home' && view==='detail'" @click="view='home'" class="back-btn">←</button>
            <h1 class="header-title">
              <template v-if="tab==='home' && view==='detail'">{{ currentCat }}</template>
              <template v-else>💍 결혼 준비</template>
            </h1>
            <button v-if="tab==='home' && view==='home'" class="icon-btn" @click="showSettings=!showSettings" :class="{ active: showSettings }">⚙️</button>
            <div v-else class="header-spacer"></div>
          </div>
        </header>

        <!-- 토스트 -->
        <div class="toast" :class="{ visible: saveStatus }">
          <span v-if="saveStatus==='saving'">💾 저장 중...</span>
          <span v-else-if="saveStatus==='saved'">✅ 저장됨</span>
          <span v-else-if="saveStatus==='error'">❌ 저장 실패</span>
        </div>

        <!-- 메인 -->
        <main class="main-content">
          <template v-if="tab==='home'">

            <!-- 홈 뷰 -->
            <div v-if="view==='home'">
              <!-- 설정 패널 -->
              <div v-if="showSettings" class="settings-panel">
                <p class="section-title">총 예산</p>
                <div class="setting-row">
                  <span class="setting-label">전체 예산</span>
                  <div class="setting-input-wrap">
                    <input v-model.number="budget" type="number" class="setting-input" @change="saveSettings" /><span class="won-label">원</span>
                  </div>
                </div>
                <p class="section-title mt12">카테고리별 예산</p>
                <div v-for="cat in categories" :key="cat.id" class="setting-row">
                  <div class="cat-label-wrap">
                    <span class="cat-dot" :style="{ background: cat.color }"></span>
                    <span class="setting-label">{{ cat.icon }} {{ cat.name }}</span>
                  </div>
                  <div class="setting-input-wrap">
                    <input v-model.number="catBudgets[cat.name]" type="number" class="setting-input" @change="saveSettings" /><span class="won-label">원</span>
                  </div>
                </div>
              </div>

              <!-- 예산 카드 -->
              <div class="budget-card" :class="{ over: overBudget }">
                <div class="budget-header">
                  <div>
                    <div class="budget-label">총 예산</div>
                    <div class="budget-amount">{{ fmt(budget) }}원</div>
                  </div>
                  <div class="budget-badge">{{ overBudget ? '⚠️ 초과' : '✅ 여유' }}</div>
                </div>
                <div class="progress-bar">
                  <div class="progress-fill" :style="{ width: totalProgress+'%', background: overBudget?'#ff4757':'#a9e34b' }"></div>
                </div>
                <div class="budget-stats">
                  <div class="stat-item"><div class="stat-label">지출</div><div class="stat-value" :class="{ red: overBudget }">{{ fmt(totalActual) }}원</div></div>
                  <div class="stat-divider"></div>
                  <div class="stat-item"><div class="stat-label">계획</div><div class="stat-value">{{ fmt(totalPlanned) }}원</div></div>
                  <div class="stat-divider"></div>
                  <div class="stat-item"><div class="stat-label">잔액</div><div class="stat-value" :class="overBudget?'red':'green'">{{ fmt(balance) }}원</div></div>
                </div>
              </div>

              <!-- 파이 차트 -->
              <div v-if="totalActual > 0" class="card">
                <p class="section-title">지출 현황</p>
                <div class="chart-wrap">
                  <svg viewBox="0 0 200 200" width="140" height="140">
                    <path v-for="seg in pieData" :key="seg.name" :d="seg.d" :fill="seg.color" stroke="white" stroke-width="2.5" />
                    <circle cx="100" cy="100" r="44" fill="white" />
                    <text x="100" y="96" text-anchor="middle" font-size="10" fill="#888">총지출</text>
                    <text x="100" y="114" text-anchor="middle" font-size="11" fill="#333" font-weight="bold">{{ Math.round(totalActual/10000) }}만원</text>
                  </svg>
                  <div class="legend">
                    <div v-for="cat in categories" :key="cat.id" v-show="catActual(cat.name)>0" class="legend-row">
                      <span class="leg-dot" :style="{ background: cat.color }"></span>
                      <span class="leg-cat">{{ cat.name }}</span>
                      <span class="leg-pct">{{ pct(catActual(cat.name), totalActual) }}%</span>
                    </div>
                  </div>
                </div>
              </div>

              <!-- 카테고리 리스트 -->
              <p class="section-title">카테고리</p>
              <div class="cat-list">
                <div v-for="cat in categories" :key="cat.id"
                  class="cat-card" :class="{ over: catOver(cat.name) }"
                  @click="currentCat=cat.name; view='detail'">
                  <div class="cat-left">
                    <span class="cat-emoji">{{ cat.icon }}</span>
                    <div>
                      <div class="cat-name">{{ cat.name }}</div>
                      <div class="cat-sub">{{ catItems(cat.name).length }}개 항목</div>
                    </div>
                  </div>
                  <div class="cat-right">
                    <div v-if="catOver(cat.name)" class="over-badge">초과!</div>
                    <div class="cat-actual" :class="{ red: catOver(cat.name) }">{{ fmt(catActual(cat.name)) }}원</div>
                    <div class="cat-planned">/ {{ fmt(catPlanned(cat.name)) }}원 계획</div>
                    <div v-if="catBudgets[cat.name]>0" class="mini-bar">
                      <div class="mini-fill" :style="{ width: catProgress(cat.name)+'%', background: catOver(cat.name)?'#ff4757':cat.color }"></div>
                    </div>
                  </div>
                  <span class="cat-arrow">›</span>
                </div>
                <div v-if="categories.length===0" class="empty-state">
                  <div>🏷️</div><p>카테고리를 추가해보세요</p>
                </div>
              </div>
            </div>

            <!-- 상세 뷰 -->
            <div v-else>
              <div class="summary-card" :class="{ over: catOver(currentCat) }">
                <div class="sum-row"><span>계획 합계</span><strong>{{ fmt(catPlanned(currentCat)) }}원</strong></div>
                <div class="sum-row"><span>실제 지출</span><strong :class="{ red: catOver(currentCat) }">{{ fmt(catActual(currentCat)) }}원</strong></div>
                <div class="sum-row">
                  <span>예상 대비</span>
                  <strong :class="diff(catPlanned(currentCat),catActual(currentCat))>=0?'green':'red'">
                    {{ diff(catPlanned(currentCat),catActual(currentCat))>=0?'절약 ':'초과 ' }}{{ fmt(Math.abs(diff(catPlanned(currentCat),catActual(currentCat)))) }}원
                  </strong>
                </div>
                <div v-if="catBudgets[currentCat]>0" class="mt8">
                  <div class="progress-bar mt4"><div class="progress-fill" :style="{ width: catProgress(currentCat)+'%', background: catOver(currentCat)?'#ff4757':'#ff6b6b' }"></div></div>
                  <small class="gray">예산 {{ fmt(catBudgets[currentCat]) }}원 중 {{ Math.round(catProgress(currentCat)) }}% 사용</small>
                </div>
              </div>

              <div class="card">
                <p class="section-title">항목 추가</p>
                <input v-model="newItem.name" placeholder="항목명 *" class="input-field" />
                <input v-model="newItem.vendor" placeholder="업체명" class="input-field" />
                <div class="input-row">
                  <input v-model.number="newItem.planned" type="number" placeholder="예상 금액" class="input-half" />
                  <input v-model.number="newItem.actual"  type="number" placeholder="실제 금액" class="input-half" />
                </div>
                <div class="input-row">
                  <input v-model="newItem.date" type="date" class="input-half" />
                  <label class="paid-label"><input type="checkbox" v-model="newItem.paid" /> 결제완료</label>
                </div>
                <textarea v-model="newItem.memo" placeholder="메모" class="input-field textarea"></textarea>
                <button @click="addItem" class="btn-primary" :disabled="saveStatus==='saving'">+ 추가하기</button>
              </div>

              <p class="section-title">항목 ({{ catItems(currentCat).length }}개)</p>
              <div v-for="item in catItems(currentCat)" :key="item.id" class="item-card" :class="{ paid: item.paid }">
                <div class="item-top">
                  <div class="item-left">
                    <input type="checkbox" :checked="item.paid" @change="togglePaid(item)" class="paid-check" />
                    <div>
                      <div class="item-name" :class="{ strikethrough: item.paid }">{{ item.name }}</div>
                      <div v-if="item.vendor" class="item-vendor">{{ item.vendor }}</div>
                    </div>
                    <span v-if="item.paid" class="paid-tag">결제완료</span>
                  </div>
                  <div class="item-actions">
                    <button @click="editItem={ ...item }" class="btn-icon">✏️</button>
                    <button @click="deleteItem(item.id)" class="btn-icon">🗑️</button>
                  </div>
                </div>
                <div class="item-prices">
                  <span>예상 {{ fmt(item.planned) }}원</span>
                  <span class="price-actual">실제 {{ fmt(item.actual) }}원</span>
                  <span :class="diff(item.planned,item.actual)>=0?'green':'red'">
                    {{ diff(item.planned,item.actual)>=0?'▼':'▲' }}{{ fmt(Math.abs(diff(item.planned,item.actual))) }}원
                  </span>
                </div>
                <div v-if="item.date"  class="item-meta">📅 {{ item.date }}</div>
                <div v-if="item.memo"  class="item-memo">{{ item.memo }}</div>
              </div>
              <div v-if="catItems(currentCat).length===0" class="empty-state">
                <div>📝</div><p>항목을 추가해보세요</p>
              </div>
            </div>
          </template>

          <!-- 체크리스트 탭 -->
          <template v-else>
            <div class="check-header">
              <p class="section-title" style="margin:0">할 일 목록</p>
              <span class="check-count">{{ checkDoneCount }}/{{ checklist.length }} 완료</span>
            </div>
            <div class="check-add-row">
              <input v-model="newCheckText" placeholder="할 일 추가..." class="check-input" @keyup.enter="addCheck" />
              <button @click="addCheck" class="btn-check-add">추가</button>
            </div>
            <div class="check-list">
              <div v-for="item in checklist" :key="item.id" class="check-item" :class="{ done: item.done }">
                <input type="checkbox" :checked="item.done" @change="toggleCheck(item)" class="check-checkbox" />
                <span class="check-text" :class="{ strikethrough: item.done }">{{ item.text }}</span>
                <button @click="deleteCheck(item.id)" class="btn-check-del">✕</button>
              </div>
              <div v-if="checklist.length===0" class="empty-state">
                <div>✅</div><p>할 일을 추가해보세요!</p>
              </div>
            </div>
          </template>
        </main>

        <!-- FAB: 왼쪽=카테고리관리, 오른쪽=항목추가 -->
        <template v-if="tab==='home' && view==='home'">
          <button class="fab fab-left" @click="showCatMgr=true">🏷️</button>
          <button class="fab fab-right" @click="showQuickAdd=true; newItem.category=categories[0]?.name||''">+</button>
        </template>

        <!-- 하단 내비 -->
        <nav class="bottom-nav">
          <button class="nav-btn" :class="{ active: tab==='home' }" @click="tab='home'">
            <span class="nav-icon">🏠</span><span class="nav-label">홈</span>
          </button>
          <button class="nav-btn" :class="{ active: tab==='checklist' }" @click="tab='checklist'">
            <span class="nav-icon">✅</span><span class="nav-label">체크리스트</span>
          </button>
        </nav>

        <!-- ── 카테고리 관리 모달 ── -->
        <div v-if="showCatMgr" class="modal-overlay" @click.self="showCatMgr=false">
          <div class="modal">
            <div class="modal-handle"></div>
            <h3>카테고리 관리</h3>

            <!-- 기존 카테고리 목록 -->
            <div class="cat-mgr-list">
              <div v-for="cat in categories" :key="cat.id" class="cat-mgr-row">
                <span class="cat-mgr-icon" :style="{ background: cat.color }">{{ cat.icon }}</span>
                <span class="cat-mgr-name">{{ cat.name }}</span>
                <span class="cat-mgr-count gray">{{ catItems(cat.name).length }}개</span>
                <button @click="editCat={ ...cat }" class="btn-icon">✏️</button>
                <button @click="deleteCategory(cat)" class="btn-icon">🗑️</button>
              </div>
              <div v-if="categories.length===0" class="empty-state" style="padding:20px">
                <p>카테고리가 없어요</p>
              </div>
            </div>

            <div class="divider"></div>

            <!-- 새 카테고리 추가 -->
            <p class="section-title">새 카테고리 추가</p>
            <input v-model="newCat.name" placeholder="카테고리 이름 *" class="input-field" />
            <p class="picker-label">아이콘</p>
            <div class="icon-grid">
              <button v-for="icon in PRESET_ICONS" :key="icon"
                class="icon-btn-pick" :class="{ active: newCat.icon===icon }"
                @click="newCat.icon=icon">{{ icon }}</button>
            </div>
            <p class="picker-label">색상</p>
            <div class="color-row">
              <button v-for="color in PRESET_COLORS" :key="color"
                class="color-pick" :style="{ background: color }"
                :class="{ active: newCat.color===color }"
                @click="newCat.color=color"></button>
            </div>
            <button @click="addCategory" class="btn-primary mt12" :disabled="saveStatus==='saving'">+ 추가하기</button>
          </div>
        </div>

        <!-- ── 카테고리 수정 모달 ── -->
        <div v-if="editCat" class="modal-overlay" @click.self="editCat=null">
          <div class="modal">
            <div class="modal-handle"></div>
            <h3>카테고리 수정</h3>
            <input v-model="editCat.name" placeholder="카테고리 이름" class="input-field" />
            <p class="picker-label">아이콘</p>
            <div class="icon-grid">
              <button v-for="icon in PRESET_ICONS" :key="icon"
                class="icon-btn-pick" :class="{ active: editCat.icon===icon }"
                @click="editCat.icon=icon">{{ icon }}</button>
            </div>
            <p class="picker-label">색상</p>
            <div class="color-row">
              <button v-for="color in PRESET_COLORS" :key="color"
                class="color-pick" :style="{ background: color }"
                :class="{ active: editCat.color===color }"
                @click="editCat.color=color"></button>
            </div>
            <div class="modal-btns mt12">
              <button @click="editCat=null" class="btn-cancel">취소</button>
              <button @click="saveEditCat" class="btn-primary flex1" :disabled="saveStatus==='saving'">저장</button>
            </div>
          </div>
        </div>

        <!-- ── 빠른 추가 모달 ── -->
        <div v-if="showQuickAdd" class="modal-overlay" @click.self="showQuickAdd=false">
          <div class="modal">
            <div class="modal-handle"></div>
            <h3>항목 빠르게 추가</h3>
            <div class="cat-chips">
              <button v-for="cat in categories" :key="cat.id"
                class="cat-chip" :class="{ active: newItem.category===cat.name }"
                :style="newItem.category===cat.name ? { background: cat.color, color:'white', borderColor: cat.color } : {}"
                @click="newItem.category=cat.name">{{ cat.icon }} {{ cat.name }}</button>
            </div>
            <input v-model="newItem.name" placeholder="항목명 *" class="input-field" />
            <input v-model="newItem.vendor" placeholder="업체명" class="input-field" />
            <div class="input-row">
              <input v-model.number="newItem.planned" type="number" placeholder="예상 금액" class="input-half" />
              <input v-model.number="newItem.actual"  type="number" placeholder="실제 금액" class="input-half" />
            </div>
            <div class="modal-btns">
              <button @click="showQuickAdd=false" class="btn-cancel">취소</button>
              <button @click="addItem" class="btn-primary flex1" :disabled="saveStatus==='saving'">추가</button>
            </div>
          </div>
        </div>

        <!-- ── 항목 수정 모달 ── -->
        <div v-if="editItem" class="modal-overlay" @click.self="editItem=null">
          <div class="modal">
            <div class="modal-handle"></div>
            <h3>항목 수정</h3>
            <input v-model="editItem.name" placeholder="항목명" class="input-field" />
            <input v-model="editItem.vendor" placeholder="업체명" class="input-field" />
            <div class="input-row">
              <input v-model.number="editItem.planned" type="number" placeholder="예상 금액" class="input-half" />
              <input v-model.number="editItem.actual"  type="number" placeholder="실제 금액" class="input-half" />
            </div>
            <input v-model="editItem.date" type="date" class="input-field" />
            <textarea v-model="editItem.memo" placeholder="메모" class="input-field textarea"></textarea>
            <label class="paid-label"><input type="checkbox" v-model="editItem.paid" /> 결제완료</label>
            <div class="modal-btns">
              <button @click="editItem=null" class="btn-cancel">취소</button>
              <button @click="saveEdit" class="btn-primary flex1" :disabled="saveStatus==='saving'">저장</button>
            </div>
          </div>
        </div>

      </template>
    </template>
  </div>
</template>

<style scoped>
* { box-sizing: border-box; margin: 0; padding: 0; }
.app { max-width: 480px; margin: 0 auto; background: #f7f3f3; min-height: 100vh; min-height: 100dvh; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }

/* 헤더 */
.app-header { position: fixed; top: 0; left: 50%; transform: translateX(-50%); width: 100%; max-width: 480px; background: white; z-index: 100; border-bottom: 1px solid #f0e8e8; }
.header-inner { display: flex; align-items: center; justify-content: space-between; padding: 0 16px; height: 56px; }
.header-title { font-size: 17px; font-weight: 700; color: #333; }
.back-btn { background: none; border: none; font-size: 24px; cursor: pointer; color: #ff6b6b; padding: 8px 12px 8px 0; min-width: 44px; min-height: 44px; display: flex; align-items: center; }
.icon-btn { background: none; border: 1px solid #eee; border-radius: 10px; padding: 6px 10px; cursor: pointer; font-size: 18px; min-width: 44px; min-height: 44px; }
.icon-btn.active { background: #fff3f3; border-color: #ff6b6b; }
.header-spacer { width: 44px; }

.main-content { padding: 68px 16px 88px; }

/* 하단 내비 */
.bottom-nav { position: fixed; bottom: 0; left: 50%; transform: translateX(-50%); width: 100%; max-width: 480px; background: white; border-top: 1px solid #f0e8e8; display: flex; padding-bottom: env(safe-area-inset-bottom,0); z-index: 100; }
.nav-btn { flex: 1; display: flex; flex-direction: column; align-items: center; gap: 3px; padding: 10px 0; background: none; border: none; cursor: pointer; color: #ccc; }
.nav-btn.active { color: #ff6b6b; }
.nav-icon { font-size: 22px; }
.nav-label { font-size: 11px; font-weight: 600; }

/* FAB */
.fab { position: fixed; bottom: calc(74px + env(safe-area-inset-bottom,0px)); width: 54px; height: 54px; border-radius: 50%; border: none; cursor: pointer; display: flex; align-items: center; justify-content: center; z-index: 99; font-size: 26px; }
.fab-right { right: max(16px, calc(50% - 224px)); background: #ff6b6b; color: white; box-shadow: 0 4px 18px rgba(255,107,107,0.45); font-size: 30px; }
.fab-left  { left:  max(16px, calc(50% - 224px)); background: white; color: #ff6b6b; box-shadow: 0 4px 14px rgba(0,0,0,0.12); border: 2px solid #ffe0e0; }

/* 토스트 */
.toast { position: fixed; top: 64px; right: 16px; background: white; border-radius: 20px; padding: 7px 16px; font-size: 13px; box-shadow: 0 4px 14px rgba(0,0,0,0.1); opacity: 0; transition: opacity 0.3s; z-index: 200; pointer-events: none; }
.toast.visible { opacity: 1; }

/* 카드 */
.card { background: white; border-radius: 16px; padding: 16px; margin-bottom: 12px; }

/* 예산 카드 */
.budget-card { background: linear-gradient(135deg,#ff6b6b,#ee5a24); color: white; border-radius: 20px; padding: 20px; margin-bottom: 12px; }
.budget-card.over { background: linear-gradient(135deg,#ff4757,#c0392b); }
.budget-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 14px; }
.budget-label { font-size: 12px; opacity: 0.8; margin-bottom: 4px; }
.budget-amount { font-size: 26px; font-weight: 700; }
.budget-badge { border-radius: 20px; padding: 5px 13px; font-size: 13px; font-weight: 700; background: rgba(255,255,255,0.22); }
.budget-stats { display: flex; align-items: center; margin-top: 12px; }
.stat-item { flex: 1; text-align: center; }
.stat-label { font-size: 11px; opacity: 0.75; margin-bottom: 3px; }
.stat-value { font-size: 14px; font-weight: 700; }
.stat-divider { width: 1px; height: 28px; background: rgba(255,255,255,0.3); }
.progress-bar { background: rgba(255,255,255,0.25); border-radius: 10px; height: 6px; overflow: hidden; margin-bottom: 6px; }
.summary-card .progress-bar { background: #f0e6e6; }
.progress-fill { height: 100%; border-radius: 10px; transition: width 0.5s; }
.mt4 { margin-top: 4px; }

/* 설정 */
.settings-panel { background: white; border-radius: 16px; padding: 16px; margin-bottom: 12px; }
.setting-row { display: flex; align-items: center; justify-content: space-between; padding: 9px 0; border-bottom: 1px solid #f8f8f8; }
.setting-row:last-child { border-bottom: none; }
.cat-label-wrap { display: flex; align-items: center; gap: 8px; }
.cat-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.setting-label { font-size: 14px; color: #444; }
.setting-input-wrap { display: flex; align-items: center; gap: 5px; }
.setting-input { width: 110px; padding: 7px 10px; border: 1px solid #eee; border-radius: 8px; font-size: 14px; text-align: right; }
.won-label { font-size: 13px; color: #999; }
.section-title { font-size: 12px; font-weight: 700; color: #aaa; margin-bottom: 10px; letter-spacing: 0.5px; text-transform: uppercase; }
.mt12 { margin-top: 12px; }

/* 카테고리 리스트 */
.cat-list { display: flex; flex-direction: column; gap: 8px; margin-bottom: 16px; }
.cat-card { background: white; border-radius: 14px; padding: 14px 12px 14px 16px; display: flex; align-items: center; gap: 10px; cursor: pointer; border: 2px solid transparent; box-shadow: 0 1px 4px rgba(0,0,0,0.05); transition: 0.15s; }
.cat-card:active { transform: scale(0.98); }
.cat-card.over { border-color: #ff4757; }
.cat-left { display: flex; align-items: center; gap: 12px; flex: 1; }
.cat-emoji { font-size: 24px; }
.cat-name { font-weight: 700; font-size: 14px; color: #333; }
.cat-sub { font-size: 12px; color: #bbb; margin-top: 2px; }
.cat-right { text-align: right; }
.cat-actual { font-size: 15px; font-weight: 700; color: #333; }
.cat-planned { font-size: 11px; color: #bbb; margin-bottom: 5px; }
.mini-bar { height: 4px; background: #f0e6e6; border-radius: 4px; overflow: hidden; width: 72px; margin-left: auto; }
.mini-fill { height: 100%; border-radius: 4px; }
.cat-arrow { font-size: 22px; color: #ddd; flex-shrink: 0; }
.over-badge { background: #ff4757; color: white; font-size: 10px; padding: 2px 7px; border-radius: 8px; margin-bottom: 3px; display: inline-block; }

/* 차트 */
.chart-wrap { display: flex; align-items: center; gap: 16px; }
.legend { flex: 1; }
.legend-row { display: flex; align-items: center; gap: 7px; margin-bottom: 8px; font-size: 13px; }
.leg-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.leg-cat { flex: 1; color: #555; }
.leg-pct { font-weight: 700; color: #333; }

/* 폼 */
.input-field { width: 100%; padding: 13px; border: 1px solid #eee; border-radius: 12px; margin-bottom: 8px; font-size: 15px; background: #fafafa; }
.input-field:focus { outline: none; border-color: #ff6b6b; background: white; }
.input-row { display: flex; gap: 8px; margin-bottom: 8px; }
.input-half { flex: 1; padding: 13px; border: 1px solid #eee; border-radius: 12px; font-size: 15px; background: #fafafa; min-width: 0; }
.input-half:focus { outline: none; border-color: #ff6b6b; background: white; }
.textarea { resize: vertical; min-height: 64px; }
.paid-label { display: flex; align-items: center; gap: 8px; font-size: 14px; color: #555; padding: 10px 0; cursor: pointer; }

/* 버튼 */
.btn-primary { width: 100%; background: #ff6b6b; color: white; border: none; padding: 14px; border-radius: 12px; font-size: 15px; font-weight: 700; cursor: pointer; }
.btn-primary.flex1 { width: auto; flex: 1; }
.btn-primary:disabled { opacity: 0.6; }
.btn-cancel { flex: 1; padding: 14px; border: 1px solid #eee; border-radius: 12px; cursor: pointer; background: white; font-size: 15px; color: #666; }
.btn-icon { background: none; border: none; cursor: pointer; font-size: 18px; padding: 6px; border-radius: 8px; min-width: 36px; min-height: 36px; display: flex; align-items: center; justify-content: center; }
.btn-icon:active { background: #f5f5f5; }

/* 요약 카드 */
.summary-card { background: white; border-radius: 14px; padding: 16px; margin-bottom: 12px; border-left: 4px solid #ff6b6b; }
.summary-card.over { border-left-color: #ff4757; background: #fff5f5; }
.sum-row { display: flex; justify-content: space-between; align-items: center; padding: 6px 0; font-size: 14px; }
.mt8 { margin-top: 8px; }
.gray { font-size: 12px; color: #bbb; }

/* 항목 카드 */
.item-card { background: white; border-radius: 12px; padding: 14px; margin-bottom: 8px; box-shadow: 0 1px 4px rgba(0,0,0,0.04); }
.item-card.paid { opacity: 0.6; }
.item-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 8px; }
.item-left { display: flex; align-items: flex-start; gap: 10px; flex: 1; flex-wrap: wrap; }
.paid-check { width: 18px; height: 18px; accent-color: #ff6b6b; flex-shrink: 0; margin-top: 3px; cursor: pointer; }
.item-name { font-weight: 700; font-size: 15px; color: #333; }
.item-vendor { font-size: 12px; color: #bbb; margin-top: 2px; }
.strikethrough { text-decoration: line-through; color: #bbb; }
.paid-tag { background: #d3f9d8; color: #2f9e44; font-size: 11px; padding: 2px 8px; border-radius: 8px; }
.item-actions { display: flex; gap: 2px; flex-shrink: 0; }
.item-prices { display: flex; flex-wrap: wrap; gap: 8px; font-size: 13px; color: #aaa; }
.price-actual { color: #ff6b6b; font-weight: 700; }
.item-meta { font-size: 12px; color: #ccc; margin-top: 6px; }
.item-memo { font-size: 13px; color: #666; margin-top: 6px; padding: 8px 10px; background: #fafafa; border-radius: 8px; }

/* 체크리스트 */
.check-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
.check-count { font-size: 13px; color: #ff6b6b; font-weight: 700; }
.check-add-row { display: flex; gap: 8px; margin-bottom: 12px; }
.check-input { flex: 1; padding: 13px; border: 1px solid #eee; border-radius: 12px; font-size: 15px; background: white; }
.check-input:focus { outline: none; border-color: #ff6b6b; }
.btn-check-add { background: #ff6b6b; color: white; border: none; border-radius: 12px; padding: 13px 18px; font-size: 15px; font-weight: 700; cursor: pointer; }
.check-list { display: flex; flex-direction: column; gap: 8px; }
.check-item { background: white; border-radius: 12px; padding: 15px; display: flex; align-items: center; gap: 12px; }
.check-item.done { opacity: 0.55; }
.check-checkbox { width: 20px; height: 20px; accent-color: #ff6b6b; cursor: pointer; flex-shrink: 0; }
.check-text { flex: 1; font-size: 15px; color: #333; }
.btn-check-del { background: none; border: none; color: #ddd; font-size: 15px; cursor: pointer; padding: 4px 6px; }
.btn-check-del:active { color: #ff4757; }

/* 카테고리 관리 모달 */
.cat-mgr-list { display: flex; flex-direction: column; gap: 4px; margin-bottom: 8px; }
.cat-mgr-row { display: flex; align-items: center; gap: 10px; padding: 8px 4px; border-bottom: 1px solid #f8f8f8; }
.cat-mgr-icon { width: 36px; height: 36px; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 18px; flex-shrink: 0; }
.cat-mgr-name { flex: 1; font-size: 15px; font-weight: 600; color: #333; }
.cat-mgr-count { font-size: 12px; }
.divider { height: 1px; background: #f0f0f0; margin: 12px 0; }
.picker-label { font-size: 12px; color: #aaa; font-weight: 600; margin-bottom: 8px; margin-top: 4px; }
.icon-grid { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px; }
.icon-btn-pick { width: 40px; height: 40px; border: 2px solid #eee; border-radius: 10px; background: white; font-size: 20px; cursor: pointer; display: flex; align-items: center; justify-content: center; }
.icon-btn-pick.active { border-color: #ff6b6b; background: #fff3f3; }
.color-row { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 4px; }
.color-pick { width: 32px; height: 32px; border-radius: 50%; border: 3px solid transparent; cursor: pointer; }
.color-pick.active { border-color: #333; transform: scale(1.15); }

/* 카테고리 칩 */
.cat-chips { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 16px; }
.cat-chip { padding: 8px 14px; border: 1px solid #eee; border-radius: 20px; font-size: 13px; cursor: pointer; background: white; transition: 0.15s; }

/* 모달 */
.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.5); display: flex; align-items: flex-end; justify-content: center; z-index: 200; }
.modal { background: white; border-radius: 24px 24px 0 0; padding: 20px 20px 32px; width: 100%; max-width: 480px; max-height: 90vh; overflow-y: auto; }
.modal h3 { font-size: 17px; font-weight: 700; margin-bottom: 16px; color: #333; }
.modal-handle { width: 36px; height: 4px; background: #eee; border-radius: 2px; margin: 0 auto 20px; }
.modal-btns { display: flex; gap: 10px; }

/* 공통 */
.empty-state { text-align: center; padding: 40px 20px; color: #ccc; }
.empty-state div { font-size: 36px; margin-bottom: 10px; }
.empty-state p { font-size: 14px; }
.red { color: #ff4757; }
.green { color: #2ed573; }

/* 로그인 */
.login-screen { display: flex; align-items: center; justify-content: center; min-height: 100vh; min-height: 100dvh; background: #fdf5f5; }
.login-box { background: white; padding: 40px 28px; border-radius: 24px; box-shadow: 0 10px 40px rgba(255,107,107,0.1); text-align: center; width: 90%; max-width: 320px; }
.login-icon { font-size: 48px; margin-bottom: 12px; }
.login-box h2 { font-size: 20px; color: #333; margin-bottom: 24px; }
.pw-input { width: 100%; padding: 14px; border: 1px solid #eee; border-radius: 12px; font-size: 16px; text-align: center; margin-bottom: 16px; }
.pw-input:focus { outline: none; border-color: #ff6b6b; }

/* 로딩 */
.loading-screen { display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; color: #aaa; gap: 16px; }
.spinner { width: 36px; height: 36px; border: 3px solid #ffd6d6; border-top-color: #ff6b6b; border-radius: 50%; animation: spin 0.8s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
</style>
