<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue'

// 여행 탭. 웨딩앱과 계정·Supabase를 같이 쓰고, 화면과 데이터는 따로 간다.
// 테이블: trips / trip_events / trip_places / trip_expenses / trip_packing (supabase/travel_tables.sql)
//
// 장소와 일정은 한 화면이다. 일정 한 줄(trip_events)이 장소(trip_places)를 가리키고,
// 일정에 안 들어간 장소는 '담아 둔 곳'으로 모인다. 순서는 sort_order, 앞 줄에서 오는
// 구간의 이동 방법·시간은 그 줄의 move_mode / move_min 에 적는다.
const props = defineProps({
  supabase: { type: Object, required: true },
  userId:   { type: String, required: true },
})
const emit = defineEmits(['logout', 'nav'])
const db = props.supabase

// ── 상수 ────────────────────────────────────────────────────
const CATS = {
  move: { label: '이동', color: '#3b82c4' },
  stay: { label: '숙소', color: '#7a5af0' },
  food: { label: '맛집', color: '#e8890c' },
  spot: { label: '명소', color: '#0f7c8c' },
}
const MOVES = {
  walk:    { label: '도보',     icon: '🚶', travel: 'walking' },
  transit: { label: '대중교통', icon: '🚇', travel: 'transit' },
  taxi:    { label: '택시',     icon: '🚕', travel: 'driving' },
  car:     { label: '자동차',   icon: '🚗', travel: 'driving' },
  etc:     { label: '기타',     icon: '➡️', travel: '' },
}
const EXP_CATS = ['숙소', '항공', '교통', '식비', '관광', '쇼핑', '기타']
const EXP_COLORS = { 숙소:'#7a5af0', 항공:'#3b82c4', 교통:'#0f7c8c', 식비:'#e8890c', 관광:'#2f9e44', 쇼핑:'#d6336c', 기타:'#868e96' }
const CURRENCIES = [
  { code:'KRW', name:'원',        sym:'₩' },
  { code:'JPY', name:'엔',        sym:'¥', per:100 },
  { code:'USD', name:'달러',      sym:'$' },
  { code:'EUR', name:'유로',      sym:'€' },
  { code:'VND', name:'동',        sym:'₫', per:100 },
  { code:'THB', name:'바트',      sym:'฿' },
  { code:'TWD', name:'대만달러',  sym:'NT$' },
  { code:'CNY', name:'위안',      sym:'¥' },
  { code:'HKD', name:'홍콩달러',  sym:'HK$' },
  { code:'SGD', name:'싱가포르달러', sym:'S$' },
  { code:'PHP', name:'페소',      sym:'₱' },
  { code:'IDR', name:'루피아',    sym:'Rp', per:100 },
  { code:'AUD', name:'호주달러',  sym:'A$' },
  { code:'GBP', name:'파운드',    sym:'£' },
  { code:'CHF', name:'프랑',      sym:'CHF ' },
]
const curOf = (code) => CURRENCIES.find(c => c.code === code) || { code, name: code, sym: code + ' ' }
const PACK_TEMPLATES = {
  기본:   { 서류: ['신분증', '예약 확인서'], 생활: ['칫솔·치약', '세면도구', '상비약', '속옷', '잠옷'], 전자기기: ['휴대폰 충전기', '보조배터리'] },
  해외:   { 서류: ['여권 (만료일 확인)', '항공권 e티켓', '여행자 보험', '입국 신고 등록'], 돈: ['현지 통화', '해외결제 카드'], 전자기기: ['돼지코 어댑터', 'eSIM·유심'] },
  휴양지: { 물놀이: ['수영복', '래시가드', '선크림', '선글라스', '방수팩', '아쿠아슈즈'], 생활: ['모자', '얇은 겉옷'] },
  겨울:   { 옷: ['패딩', '목도리', '장갑', '내복'], 생활: ['핫팩', '립밤', '보습크림'] },
}

// ── 날짜 도우미 (모두 현지 날짜 문자열 'YYYY-MM-DD') ─────────
const pad = (n) => String(n).padStart(2, '0')
const toYmd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
const parseYmd = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d) }
const todayYmd = () => toYmd(new Date())
const DOW = ['일', '월', '화', '수', '목', '금', '토']
const mmdd = (s) => { const d = parseYmd(s); return `${pad(d.getMonth() + 1)}.${pad(d.getDate())}` }
const daysBetween = (a, b) => Math.round((parseYmd(b) - parseYmd(a)) / 86400000)
const tripDays = (t) => {
  if (!t) return []
  const out = []
  const n = daysBetween(t.start_date, t.end_date)
  for (let i = 0; i <= n; i++) {
    const d = parseYmd(t.start_date); d.setDate(d.getDate() + i)
    out.push({ ymd: toYmd(d), n: i + 1, label: `${mmdd(toYmd(d))} ${DOW[d.getDay()]}` })
  }
  return out
}
const nightsLabel = (t) => { const n = daysBetween(t.start_date, t.end_date); return n > 0 ? `${n}박 ${n + 1}일` : '당일' }
const ddayOf = (t) => {
  const today = todayYmd()
  if (t.end_date < today) return { text: '완료', past: true }
  if (t.start_date <= today) return { text: '여행 중', past: false }
  return { text: `-${daysBetween(today, t.start_date)}`, past: false }
}
const hhmm = (t) => (t ? t.slice(0, 5) : '')
const fmt = (n) => Math.round(Number(n) || 0).toLocaleString()
const minLabel = (m) => { m = Number(m) || 0; return m >= 60 ? `${Math.floor(m / 60)}시간${m % 60 ? ` ${m % 60}분` : ''}` : `${m}분` }

// 브라우저 저장소는 막혀 있을 수 있다 (사생활 보호 모드 등). 실패해도 화면은 돌아가야 한다.
const store = {
  get: (k, d) => { try { const v = localStorage.getItem(k); return v === null ? d : v === '1' } catch { return d } },
  set: (k, v) => { try { localStorage.setItem(k, v ? '1' : '0') } catch { /* 무시 */ } },
}

// ── 화면 폭: 넓으면 웹 모드 ─────────────────────────────────
const WIDE_QUERY = '(min-width: 900px)'
const isWide = ref(typeof window !== 'undefined' && window.matchMedia(WIDE_QUERY).matches)
let wideMq = null
const onWide = (e) => { isWide.value = e.matches }

// ── 상태 ────────────────────────────────────────────────────
const trips   = ref([])
const stats   = ref({})          // trip_id → { events, places, packDone, packAll, used }
const loading = ref(true)
const view    = ref('list')      // list | detail
const tripId  = ref('')
const sub     = ref('plan')      // plan | money | pack
const dayYmd  = ref('')
const places   = ref([])
const events   = ref([])
const expenses = ref([])
const packing  = ref([])
const selId = ref('')            // 지도에서 강조할 일정 id
const busy = ref(false)
const mapOpen    = ref(store.get('trv-map-open', false))   // 휴대폰: 지도 펼침
const mapHidden  = ref(store.get('trv-map-hidden', false)) // 웹: 지도 숨김
const mapAllDays = ref(false)
watch(mapOpen,   (v) => store.set('trv-map-open', v))
watch(mapHidden, (v) => store.set('trv-map-hidden', v))

const trip = computed(() => trips.value.find(t => t.id === tripId.value) || null)
const days = computed(() => tripDays(trip.value))
const dayOf = (ymd) => days.value.find(d => d.ymd === ymd)
const upcoming = computed(() => trips.value.filter(t => t.end_date >= todayYmd()).sort((a, b) => a.start_date.localeCompare(b.start_date)))
const past     = computed(() => trips.value.filter(t => t.end_date <  todayYmd()).sort((a, b) => b.start_date.localeCompare(a.start_date)))
const placeById = (id) => places.value.find(p => p.id === id) || null

// ── 불러오기 ────────────────────────────────────────────────
const fail = (what, error) => { console.error(what, error); alert(`${what} 실패: ${error.message || error}`) }

async function loadTrips() {
  loading.value = true
  const [t, e, p, k, x] = await Promise.all([
    db.from('trips').select('*').order('start_date'),
    db.from('trip_events').select('trip_id'),
    db.from('trip_places').select('trip_id'),
    db.from('trip_packing').select('trip_id, done'),
    db.from('trip_expenses').select('trip_id, amount_krw'),
  ])
  const err = t.error || e.error || p.error || k.error || x.error
  if (err) { loading.value = false; return fail('여행 불러오기', err) }
  trips.value = t.data
  const s = {}
  const at = (id) => (s[id] ||= { events: 0, places: 0, packDone: 0, packAll: 0, used: 0 })
  e.data.forEach(r => at(r.trip_id).events++)
  p.data.forEach(r => at(r.trip_id).places++)
  k.data.forEach(r => { at(r.trip_id).packAll++; if (r.done) at(r.trip_id).packDone++ })
  x.data.forEach(r => { at(r.trip_id).used += Number(r.amount_krw) || 0 })
  stats.value = s
  loading.value = false
}
const statOf = (id) => stats.value[id] || { events: 0, places: 0, packDone: 0, packAll: 0, used: 0 }

async function openTrip(t) {
  tripId.value = t.id
  sub.value = 'plan'
  const today = todayYmd()
  dayYmd.value = (today >= t.start_date && today <= t.end_date) ? today : t.start_date
  selId.value = ''
  mapAllDays.value = false
  places.value = []; events.value = []; expenses.value = []; packing.value = []
  view.value = 'detail'
  await loadDetail()
}
async function loadDetail() {
  const id = tripId.value
  const [p, e, x, k] = await Promise.all([
    db.from('trip_places').select('*').eq('trip_id', id).order('created_at'),
    db.from('trip_events').select('*').eq('trip_id', id).order('created_at'),
    db.from('trip_expenses').select('*').eq('trip_id', id).order('spent_on', { ascending: false }).order('created_at', { ascending: false }),
    db.from('trip_packing').select('*').eq('trip_id', id).order('created_at'),
  ])
  const err = p.error || e.error || x.error || k.error
  if (err) return fail('여행 내용 불러오기', err)
  places.value = p.data; events.value = e.data; expenses.value = x.data; packing.value = k.data
}
function backToList() {
  view.value = 'list'
  destroyMap()
  loadTrips()
}

// ── 여행 추가·수정·삭제 ─────────────────────────────────────
const tripForm = ref(null)
const blankTrip = () => ({ id: null, title: '', emoji: '✈️', origin_code: 'ICN', dest_code: '', start_date: todayYmd(), end_date: todayYmd(), budget: '', currency: 'KRW', fx_input: '' })
const fxUnit = (code) => curOf(code).per || 1
function openTripForm(t) {
  if (!t) { tripForm.value = blankTrip(); return }
  tripForm.value = { ...t, budget: t.budget || '', fx_input: t.fx_rate ? +(Number(t.fx_rate) * fxUnit(t.currency)).toFixed(4) : '' }
}
async function saveTrip() {
  const f = tripForm.value
  if (!f.title.trim()) return alert('여행 이름을 적어 주세요')
  if (!f.start_date || !f.end_date) return alert('날짜를 골라 주세요')
  if (f.end_date < f.start_date) return alert('끝나는 날이 시작하는 날보다 빠릅니다')
  const row = {
    title: f.title.trim(), emoji: f.emoji || '✈️',
    origin_code: (f.origin_code || '').trim().toUpperCase() || null,
    dest_code: (f.dest_code || '').trim().toUpperCase() || null,
    start_date: f.start_date, end_date: f.end_date,
    budget: Number(f.budget) || 0,
    currency: f.currency,
    fx_rate: f.currency === 'KRW' ? 1 : (Number(f.fx_input) ? Number(f.fx_input) / fxUnit(f.currency) : null),
  }
  busy.value = true
  const res = f.id
    ? await db.from('trips').update(row).eq('id', f.id).select().single()
    : await db.from('trips').insert({ ...row, user_id: props.userId }).select().single()
  busy.value = false
  if (res.error) return fail('여행 저장', res.error)
  const i = trips.value.findIndex(t => t.id === res.data.id)
  if (i >= 0) trips.value[i] = res.data; else trips.value.push(res.data)
  tripForm.value = null
  if (view.value === 'detail' && !dayOf(dayYmd.value)) dayYmd.value = res.data.start_date
}
async function deleteTrip() {
  const f = tripForm.value
  if (!confirm(`'${f.title}' 여행을 삭제합니다.\n일정·장소·경비·준비물도 함께 지워지고 되돌릴 수 없습니다.\n\n계속할까요?`)) return
  const { error } = await db.from('trips').delete().eq('id', f.id)
  if (error) return fail('여행 삭제', error)
  trips.value = trips.value.filter(t => t.id !== f.id)
  tripForm.value = null
  backToList()
}

// ── 일정 (장소 포함) ────────────────────────────────────────
// 그날 일정 순서: sort_order → (없으면) 시간 → 만든 순서
const byOrder = (a, b) =>
  (a.sort_order ?? 1e9) - (b.sort_order ?? 1e9) ||
  (a.start_time || '99').localeCompare(b.start_time || '99') ||
  (a.created_at || '').localeCompare(b.created_at || '')
const itemsOf = (ymd) => events.value.filter(e => e.day_date === ymd).slice().sort(byOrder)
const dayItems = computed(() => {
  const list = itemsOf(dayYmd.value)
  let prevTimed = null
  return list.map((e, i) => {
    let warn = ''
    if (prevTimed && e.start_time) {
      if (e.start_time < prevTimed.start_time) warn = `앞 일정(${hhmm(prevTimed.start_time)})보다 이른 시간입니다`
      else if (prevTimed.end_time && e.start_time < prevTimed.end_time) warn = `${hhmm(prevTimed.start_time)} ${prevTimed.title} 일정과 시간이 겹칩니다`
    }
    if (e.start_time) prevTimed = e
    return { ...e, no: i + 1, warn, place: placeById(e.place_id), prev: i > 0 ? list[i - 1] : null }
  })
})
const dayMoveTotal = computed(() => dayItems.value.reduce((s, e) => s + (e.prev && e.move_min ? Number(e.move_min) : 0), 0))
const trayPlaces = computed(() => {
  const used = events.value.map(e => e.place_id).filter(Boolean)
  return places.value.filter(p => !used.includes(p.id))
})

// 바뀐 순서를 저장한다. 한 번에 여러 행을 고치는 API가 없어 바뀐 행만 하나씩 보낸다.
async function saveOrder(list) {
  const jobs = []
  list.forEach((e, i) => {
    const row = events.value.find(x => x.id === e.id)
    if (row && row.sort_order !== i) {
      row.sort_order = i
      jobs.push(db.from('trip_events').update({ sort_order: i }).eq('id', e.id))
    }
  })
  const res = await Promise.all(jobs)
  const bad = res.find(r => r.error)
  if (bad) fail('순서 저장', bad.error)
}
// 시간이 있는 새 일정은 시간에 맞는 자리에, 없으면 맨 끝에 넣는다
function slotFor(list, startTime) {
  if (!startTime) return list.length
  const i = list.findIndex(e => e.start_time && hhmm(e.start_time) > startTime)
  return i < 0 ? list.length : i
}
async function insertEvent(row, at) {
  const list = itemsOf(row.day_date)
  const pos = at ?? slotFor(list, row.start_time)
  const res = await db.from('trip_events').insert({ ...row, sort_order: pos, trip_id: tripId.value, user_id: props.userId }).select().single()
  if (res.error) { fail('일정 저장', res.error); return null }
  events.value.push(res.data)
  list.splice(pos, 0, res.data)
  await saveOrder(list)
  return res.data
}

// 일정 추가·수정 창
const itemForm = ref(null)
function openItemForm(e) {
  if (e) {
    const p = placeById(e.place_id)
    itemForm.value = { ...e, start_time: hhmm(e.start_time), end_time: hhmm(e.end_time), place: p }
  } else {
    itemForm.value = { id: null, day_date: dayYmd.value || days.value[0]?.ymd, start_time: '', end_time: '', title: '', category: 'spot', memo: '', place: null }
  }
}
async function saveItem() {
  const f = itemForm.value
  if (!f.title.trim()) return alert('일정 이름을 적어 주세요')
  if (f.start_time && f.end_time && f.end_time < f.start_time) return alert('끝나는 시각이 시작보다 빠릅니다')
  const row = { day_date: f.day_date, start_time: f.start_time || null, end_time: f.end_time || null, title: f.title.trim(), category: f.category, memo: f.memo?.trim() || null }
  busy.value = true
  try {
    if (!f.id) {
      const made = await insertEvent(row)
      if (made) { dayYmd.value = made.day_date; selId.value = made.id }
    } else {
      const old = events.value.find(x => x.id === f.id)
      const movedDay = old.day_date !== row.day_date
      const res = await db.from('trip_events').update(movedDay ? { ...row, move_mode: null, move_min: null } : row).eq('id', f.id).select().single()
      if (res.error) return fail('일정 저장', res.error)
      Object.assign(old, res.data)
      if (f.place && f.category !== f.place.category) {
        await db.from('trip_places').update({ category: f.category }).eq('id', f.place.id)
        f.place.category = f.category
      }
      if (movedDay) {
        // 다른 날로 옮기면 그날 끝(또는 시간 자리)으로 보내고 두 날 순서를 다시 매긴다
        const target = itemsOf(row.day_date).filter(x => x.id !== old.id)
        target.splice(slotFor(target, row.start_time), 0, old)
        await saveOrder(target)
        await saveOrder(itemsOf(old.day_date === row.day_date ? row.day_date : dayYmd.value))
        dayYmd.value = row.day_date
      }
    }
    itemForm.value = null
  } finally { busy.value = false }
}
// 일정에서 빼서 '담아 둔 곳'으로 (장소는 남김)
async function itemToTray() {
  const f = itemForm.value
  const day = events.value.find(x => x.id === f.id)?.day_date
  const { error } = await db.from('trip_events').delete().eq('id', f.id)
  if (error) return fail('일정에서 빼기', error)
  events.value = events.value.filter(x => x.id !== f.id)
  await saveOrder(itemsOf(day))
  itemForm.value = null
}
async function deleteItem() {
  const f = itemForm.value
  if (!confirm(`'${f.title}' 일정을 삭제할까요?${f.place ? '\n담아 둔 장소 정보도 함께 지워집니다.' : ''}`)) return
  const day = events.value.find(x => x.id === f.id)?.day_date
  const { error } = await db.from('trip_events').delete().eq('id', f.id)
  if (error) return fail('일정 삭제', error)
  events.value = events.value.filter(x => x.id !== f.id)
  if (f.place && !events.value.some(x => x.place_id === f.place.id)) {
    const r = await db.from('trip_places').delete().eq('id', f.place.id)
    if (r.error) fail('장소 삭제', r.error)
    else places.value = places.value.filter(p => p.id !== f.place.id)
  }
  await saveOrder(itemsOf(day))
  itemForm.value = null
}

// 담아 둔 곳 → 그날 일정 끝으로
async function trayToDay(p, at) {
  const made = await insertEvent({ day_date: dayYmd.value, title: p.name, category: p.category, place_id: p.id }, at)
  if (made) selId.value = made.id
}
const placeForm = ref(null)
const openPlaceForm = (p) => { placeForm.value = { ...p } }
async function savePlace() {
  const f = placeForm.value
  if (!f.name.trim()) return alert('장소 이름을 적어 주세요')
  const res = await db.from('trip_places').update({ name: f.name.trim(), category: f.category, memo: f.memo?.trim() || null }).eq('id', f.id).select().single()
  if (res.error) return fail('장소 저장', res.error)
  const i = places.value.findIndex(x => x.id === f.id); if (i >= 0) places.value[i] = res.data
  placeForm.value = null
}
async function deletePlace() {
  const f = placeForm.value
  if (!confirm(`'${f.name}' 장소를 삭제할까요?`)) return
  const { error } = await db.from('trip_places').delete().eq('id', f.id)
  if (error) return fail('장소 삭제', error)
  places.value = places.value.filter(x => x.id !== f.id)
  placeForm.value = null
}

// ── 구간 이동 방법 (직접 고르기) ────────────────────────────
const legForm = ref(null)
function openLegForm(e) { legForm.value = { id: e.id, from: e.prev.title, to: e.title, mode: e.move_mode || 'walk', min: e.move_min || '' } }
async function saveLeg(clear) {
  const f = legForm.value
  const row = clear ? { move_mode: null, move_min: null } : { move_mode: f.mode, move_min: Number(f.min) || null }
  const { error } = await db.from('trip_events').update(row).eq('id', f.id)
  if (error) return fail('이동 방법 저장', error)
  Object.assign(events.value.find(x => x.id === f.id), row)
  legForm.value = null
}
const ptOf = (e) => {
  const p = placeById(e.place_id)
  if (p && p.lat != null) return `${p.lat},${p.lng}`
  return encodeURIComponent(p?.address || p?.name || e.title)
}
// 구글 지도 앱/웹에서 그 구간 길찾기를 연다 (URL만 쓰므로 무료)
function legUrl(e) {
  const tm = MOVES[e.move_mode]?.travel
  return `https://www.google.com/maps/dir/?api=1&origin=${ptOf(e.prev)}&destination=${ptOf(e)}${tm ? `&travelmode=${tm}` : ''}`
}
const dirUrl = (p) => {
  if (!p) return ''
  if (p.lat != null) return `https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}`
  return p.map_url || ''
}

// ── 끌어서 순서 바꾸기 (마우스·손가락 공통: pointer 이벤트) ──
const listEl = ref(null)
const drag = ref(null)   // { id, from, over, dy, startY, mids }
function onGripDown(ev, e, index) {
  ev.preventDefault()
  const rows = [...listEl.value.querySelectorAll('[data-row]')]
  const mids = rows.map(r => { const b = r.getBoundingClientRect(); return b.top + b.height / 2 })
  drag.value = { id: e.id, from: index, over: index, dy: 0, startY: ev.clientY, mids }
  window.addEventListener('pointermove', onDragMove)
  window.addEventListener('pointerup', onDragEnd)
  window.addEventListener('pointercancel', onDragEnd)
}
function onDragMove(ev) {
  const d = drag.value; if (!d) return
  d.dy = ev.clientY - d.startY
  d.over = d.mids.filter((m, i) => i !== d.from && m < ev.clientY).length
}
async function onDragEnd() {
  window.removeEventListener('pointermove', onDragMove)
  window.removeEventListener('pointerup', onDragEnd)
  window.removeEventListener('pointercancel', onDragEnd)
  const d = drag.value; drag.value = null
  if (!d || d.over === d.from) return
  const list = itemsOf(dayYmd.value)
  const [moved] = list.splice(d.from, 1)
  list.splice(d.over, 0, moved)
  // 순서가 바뀌면 앞뒤 구간이 달라지므로, 앞 일정이 바뀐 줄의 이동 방법은 비운다
  const before = itemsOf(dayYmd.value).map(x => x.id)
  await saveOrder(list)
  const clears = []
  list.forEach((x, i) => {
    const prevNow = i > 0 ? list[i - 1].id : null
    const prevThen = before.indexOf(x.id) > 0 ? before[before.indexOf(x.id) - 1] : null
    if (prevNow !== prevThen && (x.move_mode || x.move_min)) {
      x.move_mode = null; x.move_min = null
      clears.push(db.from('trip_events').update({ move_mode: null, move_min: null }).eq('id', x.id))
    }
  })
  await Promise.all(clears)
}
const rankOf = (i) => { const d = drag.value; return i < d.from ? i : i - 1 }
// 웹: 담아 둔 곳을 끌어다 일정에 놓기 (HTML 끌어놓기)
const dropOver = ref(false)
function onTrayDragStart(ev, p) { ev.dataTransfer.setData('text/plain', p.id); ev.dataTransfer.effectAllowed = 'move' }
async function onListDrop(ev) {
  dropOver.value = false
  const p = placeById(ev.dataTransfer.getData('text/plain'))
  if (!p) return
  const rows = [...listEl.value.querySelectorAll('[data-row]')]
  const at = rows.filter(r => { const b = r.getBoundingClientRect(); return b.top + b.height / 2 < ev.clientY }).length
  await trayToDay(p, at)
}

// ── 구글 지도 ───────────────────────────────────────────────
// 키는 .env의 VITE_GOOGLE_MAPS_KEY. 없으면 지도 자리에 안내만 띄우고 나머지는 그대로 쓴다.
// 지도는 보일 때 한 번만 만들고(=과금 1회), Day를 바꾸거나 접었다 펴도 핀만 다시 그린다.
const MAPS_KEY = import.meta.env.VITE_GOOGLE_MAPS_KEY || ''
const mapEl = ref(null)
const mapError = ref('')
let mapsPromise = null
let map = null
let mapMarkers = []
let mapLines = []

function loadMaps() {
  if (!MAPS_KEY) return Promise.resolve(null)
  if (window.google?.maps?.importLibrary) return Promise.resolve(window.google.maps)
  if (!mapsPromise) {
    mapsPromise = new Promise((resolve, reject) => {
      window.__travelMapsReady = () => resolve(window.google.maps)
      const s = document.createElement('script')
      s.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(MAPS_KEY)}&v=weekly&loading=async&language=ko&region=KR&callback=__travelMapsReady`
      s.async = true
      s.onerror = () => { mapsPromise = null; reject(new Error('구글 지도 스크립트를 불러오지 못했습니다')) }
      document.head.appendChild(s)
    })
  }
  return mapsPromise
}
// 키가 틀렸거나 허용 안 된 주소면 구글이 이 함수를 부른다
window.gm_authFailure = () => { mapError.value = '구글 지도 키를 확인해 주세요 (키 제한 또는 API 사용 설정)' }

const mapVisible = computed(() => view.value === 'detail' && sub.value === 'plan' && (isWide.value ? !mapHidden.value : mapOpen.value))
async function ensureMap() {
  if (map || !MAPS_KEY || !mapEl.value) return map
  try {
    const maps = await loadMaps()
    const { Map } = await maps.importLibrary('maps')
    if (!mapEl.value || map) return map
    map = new Map(mapEl.value, {
      center: { lat: 37.5665, lng: 126.978 }, zoom: 12,
      mapTypeControl: false, streetViewControl: false, fullscreenControl: false, clickableIcons: false,
    })
  } catch (e) {
    mapError.value = e.message || String(e)
  }
  return map
}
function clearPins() {
  mapMarkers.forEach(m => m.setMap(null)); mapMarkers = []
  mapLines.forEach(l => l.setMap(null)); mapLines = []
}
function destroyMap() { clearPins(); map = null }
async function drawPins() {
  if (!mapVisible.value) return
  await nextTick()
  const m = await ensureMap()
  if (!m) return
  const g = window.google.maps
  clearPins()
  const groups = mapAllDays.value
    ? days.value.map(d => ({ d, items: itemsOf(d.ymd) }))
    : [{ d: dayOf(dayYmd.value), items: itemsOf(dayYmd.value) }]
  const all = []
  groups.forEach(({ d, items }) => {
    const pts = []
    items.forEach((e, i) => {
      const p = placeById(e.place_id)
      if (!p || p.lat == null) return
      const sel = e.id === selId.value
      const label = mapAllDays.value ? `${d?.n}` : String(i + 1)
      mapMarkers.push(new g.Marker({
        map: m, position: { lat: p.lat, lng: p.lng }, title: `${label}. ${e.title}`,
        label: { text: label, color: '#fff', fontSize: '11px', fontWeight: '700' },
        icon: { path: g.SymbolPath.CIRCLE, scale: sel ? 13 : 10, fillColor: CATS[e.category]?.color || '#16263d', fillOpacity: 1, strokeColor: '#fff', strokeWeight: 2 },
        zIndex: sel ? 10 : 1,
      }))
      pts.push({ lat: p.lat, lng: p.lng })
    })
    if (pts.length > 1) mapLines.push(new g.Polyline({ map: m, path: pts, strokeColor: '#16263d', strokeOpacity: mapAllDays.value ? 0.35 : 0.55, strokeWeight: 3 }))
    all.push(...pts)
  })
  const selItem = events.value.find(e => e.id === selId.value)
  const selP = selItem && placeById(selItem.place_id)
  if (selP && selP.lat != null && !mapAllDays.value) { m.panTo({ lat: selP.lat, lng: selP.lng }); if (m.getZoom() < 14) m.setZoom(15); return }
  if (all.length === 1) { m.setCenter(all[0]); m.setZoom(15) }
  else if (all.length > 1) { const b = new g.LatLngBounds(); all.forEach(p => b.extend(p)); m.fitBounds(b, 40) }
}
const pinCount = computed(() => dayItems.value.filter(e => e.place?.lat != null).length)
watch([mapVisible, dayYmd, selId, mapAllDays, places, events, isWide], drawPins, { deep: true })

// ── 장소 검색 (Places API New: 자동완성 → 고른 장소의 위치·주소만 받음) ──
// 이름·종류는 자동완성 결과에서 쓰고, 상세 조회는 위치·주소만 받아 가장 싼 등급으로 끝낸다.
const query = ref('')
const suggestions = ref([])
const searching = ref(false)
const toTray = ref(false)       // 켜면 일정 대신 '담아 둔 곳'으로
let sessionToken = null
let searchTimer = null
watch(query, (q) => {
  clearTimeout(searchTimer)
  if (!MAPS_KEY || q.trim().length < 2) { suggestions.value = []; return }
  searchTimer = setTimeout(() => searchPlaces(q.trim()), 300)
})
async function searchPlaces(q) {
  try {
    searching.value = true
    const maps = await loadMaps()
    const { AutocompleteSuggestion, AutocompleteSessionToken } = await maps.importLibrary('places')
    if (!sessionToken) sessionToken = new AutocompleteSessionToken()
    const req = { input: q, sessionToken, language: 'ko' }
    if (map) req.locationBias = map.getCenter()
    const { suggestions: list } = await AutocompleteSuggestion.fetchAutocompleteSuggestions(req)
    if (query.value.trim() !== q) return
    suggestions.value = (list || []).filter(s => s.placePrediction).slice(0, 5).map(s => ({
      pred: s.placePrediction,
      main: s.placePrediction.mainText?.text || s.placePrediction.text?.text || '',
      second: s.placePrediction.secondaryText?.text || '',
      types: s.placePrediction.types || [],
    }))
  } catch (e) {
    mapError.value = `장소 검색 실패: ${e.message || e}`
    suggestions.value = []
  } finally {
    searching.value = false
  }
}
function catFromTypes(types) {
  const t = types.join(' ')
  if (/lodging|hotel/.test(t)) return 'stay'
  if (/airport|train_station|subway_station|transit_station|bus_station|ferry/.test(t)) return 'move'
  if (/restaurant|cafe|food|bakery|bar|meal/.test(t)) return 'food'
  return 'spot'
}
async function addPlace(row) {
  const res = await db.from('trip_places').insert({ ...row, trip_id: tripId.value, user_id: props.userId }).select().single()
  if (res.error) { fail('장소 저장', res.error); return null }
  places.value.push(res.data)
  return res.data
}
async function pickSuggestion(s) {
  busy.value = true
  try {
    const place = s.pred.toPlace()
    await place.fetchFields({ fields: ['location', 'formattedAddress'] })
    const pid = place.id || s.pred.placeId
    const p = await addPlace({
      name: s.main, category: catFromTypes(s.types), address: place.formattedAddress || s.second,
      lat: place.location?.lat() ?? null, lng: place.location?.lng() ?? null, place_id: pid,
      map_url: `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(s.main)}&query_place_id=${pid}`,
    })
    if (p && !toTray.value) await trayToDay(p)
  } catch (e) {
    alert(`장소 정보를 받지 못했습니다: ${e.message || e}`)
  } finally {
    sessionToken = null   // 한 장소를 고르면 검색 묶음(세션)을 끝낸다
    query.value = ''; suggestions.value = []
    busy.value = false
  }
}
// 검색 결과를 고르지 않고 Enter: 이름만 있는 일정(또는 담아 두기)으로 넣는다
async function quickAdd() {
  const name = query.value.trim()
  if (!name) return
  if (suggestions.value.length) return pickSuggestion(suggestions.value[0])
  query.value = ''
  if (toTray.value) await addPlace({ name, category: 'spot' })
  else { const made = await insertEvent({ day_date: dayYmd.value, title: name, category: 'spot' }); if (made) selId.value = made.id }
}

// ── 경비 ────────────────────────────────────────────────────
const cur = computed(() => curOf(trip.value?.currency || 'KRW'))
const used = computed(() => expenses.value.reduce((s, x) => s + (Number(x.amount_krw) || 0), 0))
const budgetLeft = computed(() => (Number(trip.value?.budget) || 0) - used.value)
const usedPct = computed(() => trip.value?.budget ? Math.min(100, Math.round(used.value / trip.value.budget * 100)) : 0)
const byCat = computed(() => {
  const m = {}
  expenses.value.forEach(x => { m[x.category] = (m[x.category] || 0) + (Number(x.amount_krw) || 0) })
  return EXP_CATS.filter(c => m[c]).map(c => ({ c, v: m[c], pct: used.value ? Math.round(m[c] / used.value * 100) : 0, color: EXP_COLORS[c] }))
})
const expByDay = computed(() => {
  const groups = []
  expenses.value.forEach(x => {
    const key = x.spent_on || ''
    let g = groups.find(g => g.key === key)
    if (!g) { g = { key, items: [], total: 0 }; groups.push(g) }
    g.items.push(x); g.total += Number(x.amount_krw) || 0
  })
  return groups
})
const dayTitle = (ymd) => {
  if (!ymd) return '날짜 없음'
  const d = dayOf(ymd)
  return d ? `DAY ${d.n} · ${mmdd(ymd)}` : mmdd(ymd)
}
const fxText = computed(() => {
  const t = trip.value
  if (!t || t.currency === 'KRW') return ''
  if (!t.fx_rate) return '환율을 아직 안 넣었습니다'
  const per = fxUnit(t.currency)
  return `${per}${cur.value.name} = ${fmt(t.fx_rate * per)}원`
})
const amountText = (x) => x.currency === 'KRW' ? `${fmt(x.amount)}원` : `${curOf(x.currency).sym}${Number(x.amount).toLocaleString()}`
const expForm = ref(null)
function openExpForm(x) {
  if (x) { expForm.value = { ...x }; return }
  const local = trip.value.currency !== 'KRW' && trip.value.fx_rate
  expForm.value = { id: null, title: '', amount: '', currency: local ? trip.value.currency : 'KRW', category: '식비', spent_on: dayYmd.value || todayYmd() }
}
const expKrwPreview = computed(() => {
  const f = expForm.value
  if (!f || !Number(f.amount)) return 0
  if (f.currency === 'KRW') return Number(f.amount)
  return Number(f.amount) * (Number(trip.value?.fx_rate) || 0)
})
async function saveExp() {
  const f = expForm.value
  if (!f.title.trim()) return alert('어디에 썼는지 적어 주세요')
  if (!Number(f.amount)) return alert('금액을 적어 주세요')
  if (f.currency !== 'KRW' && !trip.value.fx_rate) return alert('여행 설정(⚙️)에서 환율을 먼저 넣어 주세요')
  // 금액·통화를 안 바꿨으면 처음 환산한 원화를 그대로 둔다 (환율을 바꿔도 지난 지출은 그대로)
  const orig = f.id && expenses.value.find(x => x.id === f.id)
  const sameMoney = orig && Number(orig.amount) === Number(f.amount) && orig.currency === f.currency
  const row = { title: f.title.trim(), amount: Number(f.amount), currency: f.currency, category: f.category, spent_on: f.spent_on || null, amount_krw: sameMoney ? orig.amount_krw : Math.round(expKrwPreview.value) }
  busy.value = true
  const res = f.id
    ? await db.from('trip_expenses').update(row).eq('id', f.id).select().single()
    : await db.from('trip_expenses').insert({ ...row, trip_id: tripId.value, user_id: props.userId }).select().single()
  busy.value = false
  if (res.error) return fail('경비 저장', res.error)
  const i = expenses.value.findIndex(x => x.id === res.data.id)
  if (i >= 0) expenses.value[i] = res.data; else expenses.value.unshift(res.data)
  expenses.value.sort((a, b) => (b.spent_on || '').localeCompare(a.spent_on || ''))
  expForm.value = null
}
async function deleteExp() {
  const f = expForm.value
  if (!confirm(`'${f.title}' 지출을 삭제할까요?`)) return
  const { error } = await db.from('trip_expenses').delete().eq('id', f.id)
  if (error) return fail('경비 삭제', error)
  expenses.value = expenses.value.filter(x => x.id !== f.id)
  expForm.value = null
}

// ── 준비물 ──────────────────────────────────────────────────
const packDone = computed(() => packing.value.filter(x => x.done).length)
const packPct = computed(() => packing.value.length ? Math.round(packDone.value / packing.value.length * 100) : 0)
const packGroups = computed(() => {
  const groups = []
  packing.value.forEach(x => {
    let g = groups.find(g => g.name === x.grp)
    if (!g) { g = { name: x.grp, items: [] }; groups.push(g) }
    g.items.push(x)
  })
  return groups
})
const daysToGo = computed(() => trip.value ? daysBetween(todayYmd(), trip.value.start_date) : 0)
async function addTemplate(name) {
  const have = packing.value.map(x => x.text)
  const rows = []
  Object.entries(PACK_TEMPLATES[name]).forEach(([grp, list]) => list.forEach(text => {
    if (!have.includes(text)) rows.push({ grp, text, trip_id: tripId.value, user_id: props.userId })
  }))
  if (!rows.length) return alert(`'${name}' 템플릿 항목은 이미 다 들어 있습니다`)
  const { data, error } = await db.from('trip_packing').insert(rows).select()
  if (error) return fail('준비물 추가', error)
  packing.value.push(...data)
}
const packForm = ref(null)
function openPackForm() { packForm.value = { grp: packGroups.value[0]?.name || '기타', text: '' } }
async function savePack() {
  const f = packForm.value
  if (!f.text.trim()) return
  const { data, error } = await db.from('trip_packing').insert({ grp: f.grp.trim() || '기타', text: f.text.trim(), trip_id: tripId.value, user_id: props.userId }).select().single()
  if (error) return fail('준비물 추가', error)
  packing.value.push(data)
  packForm.value.text = ''
}
async function togglePack(x) {
  const done = !x.done
  x.done = done
  const { error } = await db.from('trip_packing').update({ done }).eq('id', x.id)
  if (error) { x.done = !done; fail('준비물 체크', error) }
}
async function deletePack(x) {
  const { error } = await db.from('trip_packing').delete().eq('id', x.id)
  if (error) return fail('준비물 삭제', error)
  packing.value = packing.value.filter(p => p.id !== x.id)
}

// ── + 버튼 ──────────────────────────────────────────────────
function onFab() {
  if (view.value === 'list') return openTripForm(null)
  if (sub.value === 'plan') return openItemForm(null)
  if (sub.value === 'money') return openExpForm(null)
  return openPackForm()
}
const APP_TABS = [['home', '🏠 홈'], ['checklist', '✅ 체크리스트'], ['realestate', '🏠 부동산']]

onMounted(() => {
  loadTrips()
  wideMq = window.matchMedia(WIDE_QUERY)
  wideMq.addEventListener('change', onWide)
})
onUnmounted(() => {
  wideMq?.removeEventListener('change', onWide)
  window.removeEventListener('pointermove', onDragMove)
  window.removeEventListener('pointerup', onDragEnd)
})
</script>

<template>
  <div class="trv" :class="{ wide: isWide }">
    <!-- 헤더 -->
    <header class="trv-hdr">
      <template v-if="view === 'list'">
        <h1 class="trv-title">✈️ 여행</h1>
      </template>
      <template v-else-if="trip">
        <button class="trv-back" @click="backToList" aria-label="여행 목록으로">←</button>
        <div class="trv-hgrow">
          <h1 class="trv-title">{{ trip.emoji }} {{ trip.title }}</h1>
          <div class="trv-route mono">
            <template v-if="trip.origin_code && trip.dest_code">{{ trip.origin_code }} ✈ {{ trip.dest_code }} · </template>{{ mmdd(trip.start_date) }}–{{ mmdd(trip.end_date) }}<template v-if="isWide"> · {{ nightsLabel(trip) }}</template>
          </div>
        </div>
      </template>
      <nav v-if="isWide" class="trv-appnav">
        <button v-for="[k, l] in APP_TABS" :key="k" @click="emit('nav', k)">{{ l }}</button>
        <button class="on">✈️ 여행</button>
      </nav>
      <button v-if="view === 'detail' && trip" class="trv-ib" @click="openTripForm(trip)" title="여행 설정">⚙️</button>
      <button v-else class="trv-ib" @click="emit('logout')" title="로그아웃">🚪</button>
    </header>

    <!-- ① 여행 목록 -->
    <div v-if="view === 'list'" class="trv-body list-body">
      <div v-if="loading" class="trv-empty">불러오는 중...</div>
      <div v-else-if="!trips.length" class="trv-empty">
        <div style="font-size:34px">🧳</div>
        <p>아직 여행이 없습니다<br>+ 로 첫 여행을 만들어 보세요</p>
      </div>
      <template v-else>
        <p v-if="upcoming.length" class="trv-sec">UPCOMING</p>
        <div class="pass-grid">
          <div v-for="t in upcoming" :key="t.id" class="pass" @click="openTrip(t)">
            <div class="pass-main">
              <div v-if="t.origin_code && t.dest_code" class="codes mono"><b>{{ t.origin_code }}</b><span class="plane"></span><b>{{ t.dest_code }}</b></div>
              <div class="pass-name">{{ t.emoji }} {{ t.title }}</div>
              <div class="pass-meta mono">{{ t.start_date.replaceAll('-', '.') }} – {{ mmdd(t.end_date) }} · {{ nightsLabel(t) }}</div>
              <div v-if="t.budget" class="gauge"><i :style="{ width: Math.min(100, statOf(t.id).used / t.budget * 100) + '%' }"></i></div>
              <div class="pass-mini">
                <span v-if="t.budget">예산 <b class="mono">{{ Math.round(statOf(t.id).used / t.budget * 100) }}%</b></span>
                <span>일정 <b>{{ statOf(t.id).events }}</b></span>
                <span v-if="statOf(t.id).packAll">준비물 <b>{{ statOf(t.id).packDone }}/{{ statOf(t.id).packAll }}</b></span>
              </div>
            </div>
            <div class="pass-stub">
              <span class="stub-lbl">D-DAY</span>
              <span class="dd mono" :class="{ small: ddayOf(t).text === '여행 중' }">{{ ddayOf(t).text }}</span>
            </div>
          </div>
        </div>
        <p v-if="past.length" class="trv-sec" style="margin-top:16px">PAST</p>
        <div class="pass-grid">
          <div v-for="t in past" :key="t.id" class="pass past" @click="openTrip(t)">
            <div class="pass-main">
              <div v-if="t.origin_code && t.dest_code" class="codes mono small"><b>{{ t.origin_code }}</b><span class="plane"></span><b>{{ t.dest_code }}</b></div>
              <div class="pass-name">{{ t.emoji }} {{ t.title }}</div>
              <div class="pass-meta mono">{{ t.start_date.replaceAll('-', '.') }} – {{ mmdd(t.end_date) }}</div>
            </div>
            <div class="pass-stub"><span class="dd past mono">완료</span></div>
          </div>
        </div>
      </template>
    </div>

    <!-- 여행 상세 -->
    <div v-else-if="trip" class="detail" :class="{ 'no-map': !mapVisible }">
      <!-- 웹: 왼쪽 칸 (날짜·경비·준비물·담아 둔 곳) -->
      <aside v-if="isWide" class="side">
        <div class="side-lbl">일정</div>
        <button v-for="d in days" :key="d.ymd" class="side-day" :class="{ on: sub === 'plan' && d.ymd === dayYmd }" @click="sub = 'plan'; dayYmd = d.ymd; selId = ''">
          <b>Day {{ d.n }}</b> {{ d.label }}<span class="cnt">{{ itemsOf(d.ymd).length }}</span>
        </button>
        <button class="side-day" style="margin-top:8px" :class="{ on: sub === 'money' }" @click="sub = 'money'"><b>💰 경비</b><span class="cnt">{{ trip.budget ? usedPct + '%' : fmt(used) }}</span></button>
        <button class="side-day" :class="{ on: sub === 'pack' }" @click="sub = 'pack'"><b>🧳 준비물</b><span class="cnt">{{ packDone }}/{{ packing.length }}</span></button>
        <div class="side-tray">
          <div class="side-lbl"><span>담아 둔 곳</span><span>{{ trayPlaces.length }}</span></div>
          <div v-for="p in trayPlaces" :key="p.id" class="tray-chip" draggable="true" @dragstart="onTrayDragStart($event, p)">
            <i :style="{ background: CATS[p.category]?.color }"></i><span class="tc-name">{{ p.name }}</span>
            <button class="tc-btn" title="이 날 일정에 넣기" @click="sub = 'plan'; trayToDay(p)">＋</button>
            <button class="tc-btn" title="고치기" @click="openPlaceForm(p)">⋯</button>
          </div>
          <div v-if="trayPlaces.length" class="side-hint">끌어서 일정에 놓거나 ＋</div>
          <div v-else class="side-hint">검색 칸의 '담아 두기'를 켜고 고르면 여기 모입니다</div>
        </div>
      </aside>

      <!-- 휴대폰: 탭 -->
      <div v-if="!isWide" class="tabs">
        <button :class="{ on: sub === 'plan' }"  @click="sub = 'plan'">일정</button>
        <button :class="{ on: sub === 'money' }" @click="sub = 'money'">경비</button>
        <button :class="{ on: sub === 'pack' }"  @click="sub = 'pack'">준비물</button>
      </div>

      <!-- 일정 칸 -->
      <section v-if="sub === 'plan'" class="plan-col">
        <div v-if="!isWide" class="days">
          <button v-for="d in days" :key="d.ymd" class="day" :class="{ on: d.ymd === dayYmd }" @click="dayYmd = d.ymd; selId = ''">
            <b>Day {{ d.n }}</b>{{ d.label }}
          </button>
        </div>
        <div v-if="isWide" class="plan-head">
          <h2>Day {{ dayOf(dayYmd)?.n }} · {{ dayOf(dayYmd)?.label }}</h2>
          <span class="meta">일정 {{ dayItems.length }}개{{ dayMoveTotal ? ' · 이동 ' + minLabel(dayMoveTotal) : '' }}</span>
          <button v-if="mapHidden" class="mini-btn" @click="mapHidden = false">🗺️ 지도 보기</button>
        </div>
        <button v-if="!isWide" class="map-toggle" @click="mapOpen = !mapOpen">
          🗺️ 지도 · 장소 {{ pinCount }}곳<template v-if="dayMoveTotal"> · 이동 {{ minLabel(dayMoveTotal) }}</template>
          <b>{{ mapOpen ? '접기 ▴' : '펼치기 ▾' }}</b>
        </button>
        <!-- 휴대폰 지도 자리: 실제 지도 요소는 아래 map-col 하나를 같이 쓴다 -->
        <div class="search-wrap">
          <div class="search" :class="{ tray: toTray }">
            <span>🔍</span>
            <input v-model="query" :placeholder="MAPS_KEY ? (toTray ? '장소 검색 → 담아 두기' : `장소 검색 → Day ${dayOf(dayYmd)?.n}에 추가`) : '일정 이름 입력 후 Enter'" @keyup.enter="quickAdd" />
            <button class="tray-toggle" :class="{ on: toTray }" @click="toTray = !toTray" title="고른 장소를 일정 대신 담아 둡니다">담아 두기</button>
          </div>
          <div v-if="suggestions.length || searching" class="sugg-box">
            <div v-if="searching && !suggestions.length" class="sugg-empty">찾는 중...</div>
            <button v-for="s in suggestions" :key="s.pred.placeId" class="sugg" :disabled="busy" @click="pickSuggestion(s)">
              <b>{{ s.main }}</b><span>{{ s.second }}</span>
            </button>
          </div>
        </div>

        <div ref="listEl" class="rows" :class="{ drop: dropOver }"
             @dragover.prevent="dropOver = true" @dragleave="dropOver = false" @drop.prevent="onListDrop">
          <div v-if="!dayItems.length" class="trv-empty small">이날 일정이 없습니다. 위에서 검색하거나 + 로 추가하세요</div>
          <template v-for="(e, i) in dayItems" :key="e.id">
            <div v-if="drag && i !== drag.from && rankOf(i) === drag.over" class="drop-line"></div>
            <button v-if="e.prev && !drag" class="leg" :class="{ empty: !e.move_mode }" @click="openLegForm(e)">
              <template v-if="e.move_mode">{{ MOVES[e.move_mode].icon }} {{ MOVES[e.move_mode].label + (e.move_min ? ' ' + minLabel(e.move_min) : '') }}</template>
              <template v-else>＋ 이동 방법</template>
              <a v-if="e.place && e.prev.place_id" class="leg-go" :href="legUrl(e)" target="_blank" rel="noopener" @click.stop>경로 ↗</a>
            </button>
            <div data-row class="row" :class="{ sel: e.id === selId, warn: e.warn, dragging: drag && drag.id === e.id }"
                 :style="drag && drag.id === e.id ? { transform: `translateY(${drag.dy}px)` } : null"
                 @click="selId = e.id; openItemForm(e)">
              <span class="grip" title="끌어서 순서 바꾸기" @pointerdown.stop="onGripDown($event, e, i)" @click.stop>⋮⋮</span>
              <span class="r-t mono" :class="{ none: !e.start_time }">{{ e.start_time ? hhmm(e.start_time) : '—' }}</span>
              <span class="r-pin" :style="{ background: CATS[e.category]?.color }">{{ e.no }}</span>
              <span class="r-nm">
                <b>{{ e.title }}</b>
                <small v-if="e.end_time || e.memo || (isWide && e.place?.address)">
                  <template v-if="e.end_time">~{{ hhmm(e.end_time) }}</template><template v-if="e.end_time && (e.memo || e.place?.address)"> · </template>{{ e.memo || (isWide ? e.place?.address : '') }}
                </small>
              </span>
              <a v-if="dirUrl(e.place)" class="r-go" :href="dirUrl(e.place)" target="_blank" rel="noopener" title="여기까지 길찾기" @click.stop>↗</a>
              <span v-if="e.warn" class="r-warn">{{ e.warn }}</span>
            </div>
          </template>
          <div v-if="drag && drag.over === dayItems.length - 1 && drag.from !== dayItems.length - 1" class="drop-line"></div>
        </div>

        <!-- 휴대폰: 담아 둔 곳 -->
        <div v-if="!isWide && trayPlaces.length" class="tray-m">
          <div class="tray-h"><span>담아 둔 곳</span><span>{{ trayPlaces.length }}</span></div>
          <div v-for="p in trayPlaces" :key="p.id" class="tray-it">
            <i :style="{ background: CATS[p.category]?.color }"></i><span class="tc-name" @click="openPlaceForm(p)">{{ p.name }}</span>
            <button @click="trayToDay(p)">Day {{ dayOf(dayYmd)?.n }}에 넣기</button>
          </div>
        </div>
      </section>

      <!-- 지도: 웹은 오른쪽 칸, 휴대폰은 일정 위. 요소 하나를 같이 써서 화면을 바꿔도 다시 만들지 않는다 -->
      <section v-show="mapVisible" class="map-col">
        <div ref="mapEl" class="map-canvas"></div>
        <div v-if="!MAPS_KEY" class="map-off">구글 지도 키를 넣으면 여기에 지도가 보입니다</div>
        <div v-else-if="mapError" class="map-off">{{ mapError }}</div>
        <span v-else class="map-tag">{{ mapAllDays ? '전체 일정' : `Day ${dayOf(dayYmd)?.n} · 장소 ${pinCount}곳` }}</span>
        <div class="map-tools">
          <button @click="mapAllDays = !mapAllDays">{{ mapAllDays ? '이 날만 보기' : '전체 Day 보기' }}</button>
          <button v-if="isWide" @click="mapHidden = true">지도 숨기기</button>
          <button v-else @click="mapOpen = false">접기 ▴</button>
        </div>
      </section>

      <!-- 경비 -->
      <section v-if="sub === 'money'" class="pane">
        <div class="wallet">
          <div class="w-lbl">{{ trip.budget ? '남은 예산' : '쓴 돈' }}</div>
          <div class="w-big mono" :class="{ over: trip.budget && budgetLeft < 0 }">₩{{ fmt(trip.budget ? budgetLeft : used) }}</div>
          <template v-if="trip.budget">
            <div class="gauge dark"><i :style="{ width: usedPct + '%' }"></i></div>
            <div class="w-row mono"><span>예산 {{ fmt(trip.budget) }}</span><span>사용 {{ fmt(used) }}</span></div>
          </template>
        </div>
        <div v-if="fxText" class="fx" @click="openTripForm(trip)">💱 <span class="mono">{{ fxText }}</span><span class="fx-sub">직접 입력</span><span class="fx-edit">바꾸기</span></div>
        <div v-if="byCat.length" class="receipt">
          <div class="r-h"><span>항목별</span><span class="mono">{{ fmt(used) }}원</span></div>
          <div class="stack"><i v-for="b in byCat" :key="b.c" :style="{ flex: b.v, background: b.color }"></i></div>
          <div class="legend"><span v-for="b in byCat" :key="b.c"><i :style="{ background: b.color }"></i>{{ b.c }} {{ b.pct }}%</span></div>
        </div>
        <div v-if="!expenses.length" class="trv-empty small">쓴 돈을 + 로 적어 두세요</div>
        <div v-for="g in expByDay" :key="g.key" class="receipt">
          <div class="r-h"><span>{{ dayTitle(g.key) }}</span><span class="mono">{{ fmt(g.total) }}원</span></div>
          <div v-for="x in g.items" :key="x.id" class="line" @click="openExpForm(x)">
            <span class="k" :style="{ background: EXP_COLORS[x.category] }">{{ x.category }}</span>
            <span class="line-t">{{ x.title }}</span>
            <span class="amt mono">{{ amountText(x) }}<small v-if="x.currency !== 'KRW'">{{ fmt(x.amount_krw) }}원</small></span>
          </div>
        </div>
      </section>

      <!-- 준비물 -->
      <section v-if="sub === 'pack'" class="pane">
        <div class="stamp">
          <div class="ring" :style="{ background: `conic-gradient(var(--lagoon) 0 ${packPct}%, #e8eef1 0)` }"><span class="mono">{{ packPct }}%</span></div>
          <div>
            <div class="stamp-t">{{ packDone }} / {{ packing.length }} 챙김</div>
            <div class="stamp-s">{{ daysToGo > 0 ? `출발까지 ${daysToGo}일` : daysToGo === 0 ? '오늘 출발' : '출발한 여행' }}</div>
          </div>
        </div>
        <p class="trv-sec">템플릿 불러오기</p>
        <div class="tpl"><button v-for="(v, k) in PACK_TEMPLATES" :key="k" @click="addTemplate(k)">+ {{ k }}</button></div>
        <template v-for="g in packGroups" :key="g.name">
          <div class="grp"><span>{{ g.name }}</span><span class="mono">{{ g.items.filter(x => x.done).length }}/{{ g.items.length }}</span></div>
          <div v-for="x in g.items" :key="x.id" class="ck" :class="{ done: x.done }" @click="togglePack(x)">
            <span class="box"></span><span class="ck-t">{{ x.text }}</span>
            <button class="ck-del" @click.stop="deletePack(x)">✕</button>
          </div>
        </template>
      </section>
    </div>

    <button class="trv-fab" @click="onFab" :title="view === 'list' ? '새 여행' : '추가'">+</button>

    <!-- 여행 추가·수정 -->
    <div v-if="tripForm" class="sheet-bg" @click.self="tripForm = null">
      <div class="sheet">
        <h3>{{ tripForm.id ? '여행 설정' : '새 여행' }}</h3>
        <div class="f-row">
          <input v-model="tripForm.emoji" class="f-in" style="width:56px;text-align:center" maxlength="4" />
          <input v-model="tripForm.title" class="f-in" placeholder="여행 이름 (예: 신혼여행 · 하와이)" />
        </div>
        <div class="f-row">
          <label class="f-lab">출발 공항<input v-model="tripForm.origin_code" class="f-in mono" maxlength="3" placeholder="ICN" /></label>
          <label class="f-lab">도착 공항<input v-model="tripForm.dest_code" class="f-in mono" maxlength="3" placeholder="KIX" /></label>
        </div>
        <div class="f-row">
          <label class="f-lab">가는 날<input v-model="tripForm.start_date" type="date" class="f-in" /></label>
          <label class="f-lab">오는 날<input v-model="tripForm.end_date" type="date" class="f-in" /></label>
        </div>
        <label class="f-lab">예산 (원)<input v-model="tripForm.budget" type="number" inputmode="numeric" class="f-in" placeholder="1500000" /></label>
        <div class="f-row">
          <label class="f-lab">현지 통화
            <select v-model="tripForm.currency" class="f-in">
              <option v-for="c in CURRENCIES" :key="c.code" :value="c.code">{{ c.code }} · {{ c.name }}</option>
            </select>
          </label>
          <label v-if="tripForm.currency !== 'KRW'" class="f-lab">{{ fxUnit(tripForm.currency) }}{{ curOf(tripForm.currency).name }} = 몇 원
            <input v-model="tripForm.fx_input" type="number" inputmode="decimal" class="f-in" placeholder="912" />
          </label>
        </div>
        <div class="f-act">
          <button v-if="tripForm.id" class="f-del" @click="deleteTrip">삭제</button>
          <button class="f-cancel" @click="tripForm = null">취소</button>
          <button class="f-ok" :disabled="busy" @click="saveTrip">저장</button>
        </div>
      </div>
    </div>

    <!-- 일정 추가·수정 -->
    <div v-if="itemForm" class="sheet-bg" @click.self="itemForm = null">
      <div class="sheet">
        <h3>{{ itemForm.id ? '일정 고치기' : '일정 추가' }}</h3>
        <input v-model="itemForm.title" class="f-in" placeholder="일정 (예: 라피트 → 난바)" />
        <div v-if="itemForm.place?.address" class="f-note">📍 {{ itemForm.place.address }}</div>
        <div class="f-row">
          <label class="f-lab">날짜
            <select v-model="itemForm.day_date" class="f-in">
              <option v-for="d in days" :key="d.ymd" :value="d.ymd">Day {{ d.n }} · {{ d.label }}</option>
            </select>
          </label>
        </div>
        <div class="f-row">
          <label class="f-lab">시작 (선택)<input v-model="itemForm.start_time" type="time" class="f-in" /></label>
          <label class="f-lab">끝 (선택)<input v-model="itemForm.end_time" type="time" class="f-in" /></label>
        </div>
        <div class="chips">
          <button v-for="(c, k) in CATS" :key="k" :class="{ on: itemForm.category === k }" :style="{ '--c': c.color }" @click="itemForm.category = k">{{ c.label }}</button>
        </div>
        <input v-model="itemForm.memo" class="f-in" placeholder="메모 (예약번호, 요금 등)" />
        <div class="f-act">
          <button v-if="itemForm.id" class="f-del" @click="deleteItem">삭제</button>
          <button v-if="itemForm.id && itemForm.place" class="f-cancel" @click="itemToTray">담아 두기로</button>
          <button class="f-cancel" @click="itemForm = null">취소</button>
          <button class="f-ok" :disabled="busy" @click="saveItem">저장</button>
        </div>
      </div>
    </div>

    <!-- 이동 방법 -->
    <div v-if="legForm" class="sheet-bg" @click.self="legForm = null">
      <div class="sheet">
        <h3>이동 방법</h3>
        <div class="f-note">{{ legForm.from }} → {{ legForm.to }}</div>
        <div class="chips">
          <button v-for="(m, k) in MOVES" :key="k" :class="{ on: legForm.mode === k }" style="--c:#16263d" @click="legForm.mode = k">{{ m.icon }} {{ m.label }}</button>
        </div>
        <label class="f-lab">걸리는 시간 (분, 선택)<input v-model="legForm.min" type="number" inputmode="numeric" class="f-in" placeholder="15" /></label>
        <div class="f-act">
          <button class="f-del" @click="saveLeg(true)">지우기</button>
          <button class="f-cancel" @click="legForm = null">취소</button>
          <button class="f-ok" @click="saveLeg(false)">저장</button>
        </div>
      </div>
    </div>

    <!-- 담아 둔 곳 고치기 -->
    <div v-if="placeForm" class="sheet-bg" @click.self="placeForm = null">
      <div class="sheet">
        <h3>담아 둔 곳</h3>
        <input v-model="placeForm.name" class="f-in" placeholder="장소 이름" />
        <div v-if="placeForm.address" class="f-note">📍 {{ placeForm.address }}</div>
        <div class="chips">
          <button v-for="(c, k) in CATS" :key="k" :class="{ on: placeForm.category === k }" :style="{ '--c': c.color }" @click="placeForm.category = k">{{ c.label }}</button>
        </div>
        <input v-model="placeForm.memo" class="f-in" placeholder="메모 (선택)" />
        <div class="f-act">
          <button class="f-del" @click="deletePlace">삭제</button>
          <button class="f-cancel" @click="placeForm = null">취소</button>
          <button class="f-ok" @click="savePlace">저장</button>
        </div>
      </div>
    </div>

    <!-- 경비 추가·수정 -->
    <div v-if="expForm" class="sheet-bg" @click.self="expForm = null">
      <div class="sheet">
        <h3>{{ expForm.id ? '지출 고치기' : '지출 추가' }}</h3>
        <input v-model="expForm.title" class="f-in" placeholder="어디에 (예: 이치란 도톤보리)" />
        <div class="f-row">
          <input v-model="expForm.amount" type="number" inputmode="decimal" class="f-in mono" placeholder="금액" />
          <select v-model="expForm.currency" class="f-in" style="max-width:120px">
            <option v-if="trip.currency !== 'KRW'" :value="trip.currency">{{ trip.currency }}</option>
            <option value="KRW">KRW</option>
          </select>
        </div>
        <div v-if="expForm.currency !== 'KRW'" class="f-note mono">≈ {{ fmt(expKrwPreview) }}원 ({{ fxText }})</div>
        <div class="chips">
          <button v-for="c in EXP_CATS" :key="c" :class="{ on: expForm.category === c }" :style="{ '--c': EXP_COLORS[c] }" @click="expForm.category = c">{{ c }}</button>
        </div>
        <label class="f-lab">날짜<input v-model="expForm.spent_on" type="date" class="f-in" /></label>
        <div class="f-act">
          <button v-if="expForm.id" class="f-del" @click="deleteExp">삭제</button>
          <button class="f-cancel" @click="expForm = null">취소</button>
          <button class="f-ok" :disabled="busy" @click="saveExp">저장</button>
        </div>
      </div>
    </div>

    <!-- 준비물 추가 -->
    <div v-if="packForm" class="sheet-bg" @click.self="packForm = null">
      <div class="sheet">
        <h3>준비물 추가</h3>
        <input v-model="packForm.grp" class="f-in" placeholder="분류 (예: 서류)" list="trv-pack-groups" />
        <datalist id="trv-pack-groups"><option v-for="g in packGroups" :key="g.name" :value="g.name" /></datalist>
        <input v-model="packForm.text" class="f-in" placeholder="챙길 것" @keyup.enter="savePack" />
        <div class="f-act">
          <button class="f-cancel" @click="packForm = null">닫기</button>
          <button class="f-ok" :disabled="!packForm.text.trim()" @click="savePack">추가</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.trv {
  --ink:#16263d; --lagoon:#0f7c8c; --lagoon-soft:#e3f2f3; --sun:#f0a020; --sun-soft:#fff3dc;
  --bg:#eef2f4; --line:#dde5ea; --sub:#6b7a8a; --faint:#a3afbb; --red:#d9480f; --red-soft:#fff0e8;
  background: var(--bg); min-height: 100vh; min-height: 100dvh; color: var(--ink);
}
/* App.vue의 scoped '*' 규칙은 이 컴포넌트 안까지 닿지 않는다 */
.trv, .trv * { box-sizing: border-box; }
.mono { font-family: ui-monospace, 'SF Mono', 'Cascadia Mono', Consolas, monospace; font-variant-numeric: tabular-nums; }
button { font: inherit; color: inherit; }

/* ── 헤더 ── */
.trv-hdr { position: fixed; top: 0; left: 50%; transform: translateX(-50%); width: 100%; max-width: 480px; z-index: 100;
  background: var(--ink); color: #fff; display: flex; align-items: center; gap: 10px; padding: 0 16px; height: 58px; }
.trv-title { font-size: 16px; font-weight: 700; margin: 0; flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.trv-hgrow { flex: 1; min-width: 0; }
.trv-route { font-size: 11px; opacity: .6; letter-spacing: 1px; margin-top: 2px; }
.trv-back { background: none; border: none; color: #fff; font-size: 22px; min-width: 36px; min-height: 44px; cursor: pointer; opacity: .85; padding: 0; text-align: left; }
.trv-ib { background: none; border: 1px solid rgba(255,255,255,.25); border-radius: 10px; padding: 5px 9px; font-size: 16px; cursor: pointer; min-width: 44px; min-height: 40px; }
.trv-appnav { margin-left: auto; display: flex; gap: 4px; }
.trv-appnav button { background: none; border: none; color: #fff; opacity: .65; font-size: 13px; padding: 7px 11px; border-radius: 8px; cursor: pointer; }
.trv-appnav button:hover { opacity: 1; background: rgba(255,255,255,.08); }
.trv-appnav button.on { opacity: 1; background: rgba(255,255,255,.14); }

.trv-body { padding: 72px 14px 150px; } /* 아래 메뉴 + 버튼에 마지막 줄이 가리지 않게 */
.trv-sec { font-size: 11px; font-weight: 700; color: var(--sub); letter-spacing: 1.2px; margin: 6px 2px 8px; }
.trv-empty { text-align: center; color: var(--sub); padding: 60px 10px; font-size: 14px; line-height: 1.6; }
.trv-empty.small { padding: 22px 10px; font-size: 13px; }
.trv-fab { position: fixed; bottom: calc(74px + env(safe-area-inset-bottom, 0px)); right: max(16px, calc(50% - 224px)); width: 54px; height: 54px;
  border-radius: 16px; border: none; background: var(--lagoon); color: #fff !important; font-size: 28px; cursor: pointer; z-index: 99; box-shadow: 0 6px 18px rgba(15,124,140,.4); }

/* ── 탑승권 카드 ── */
.pass { display: flex; background: #fff; border-radius: 14px; margin-bottom: 12px; box-shadow: 0 2px 8px rgba(22,38,61,.06); overflow: hidden; cursor: pointer; }
.pass-main { flex: 1; min-width: 0; padding: 14px 14px 12px; }
.pass-stub { width: 80px; border-left: 2px dashed var(--line); position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; background: #fbfcfd; }
.pass-stub::before, .pass-stub::after { content: ""; position: absolute; left: -9px; width: 16px; height: 16px; border-radius: 50%; background: var(--bg); }
.pass-stub::before { top: -8px; } .pass-stub::after { bottom: -8px; }
.stub-lbl { font-size: 10px; color: var(--faint); letter-spacing: 1px; }
.codes { display: flex; align-items: center; gap: 8px; margin: 0 0 4px; }
.codes b { font-size: 24px; letter-spacing: 1px; }
.codes.small b { font-size: 18px; }
.plane { flex: 1; height: 1px; background: var(--line); position: relative; }
.plane::after { content: "✈"; position: absolute; left: 50%; top: -10px; transform: translateX(-50%); font-size: 14px; color: var(--lagoon); background: #fff; padding: 0 4px; }
.pass-name { font-size: 14px; font-weight: 700; }
.pass-meta { font-size: 12px; color: var(--sub); margin-top: 2px; }
.pass-mini { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 8px; font-size: 11px; color: var(--sub); }
.pass-mini b { color: var(--ink); }
.dd { font-size: 19px; font-weight: 800; color: var(--sun); }
.dd.small { font-size: 13px; }
.dd.past { color: var(--faint); font-size: 13px; }
.pass.past { opacity: .6; }
.gauge { height: 4px; background: #e8eef1; border-radius: 4px; overflow: hidden; margin-top: 8px; }
.gauge i { display: block; height: 100%; background: var(--lagoon); }
.gauge.dark { background: rgba(255,255,255,.15); } .gauge.dark i { background: var(--sun); }

/* ── 상세 (휴대폰) ── */
.detail { padding: 72px 14px 150px; display: flex; flex-direction: column; }
.tabs { display: flex; gap: 18px; padding: 0 4px; border-bottom: 1px solid var(--line); margin-bottom: 12px; }
.tabs button { background: none; border: none; font-size: 14px; padding: 8px 0 9px; color: var(--sub); cursor: pointer; }
.tabs button.on { color: var(--ink); font-weight: 700; box-shadow: inset 0 -2px 0 var(--lagoon); }
.days { display: flex; gap: 6px; overflow-x: auto; margin-bottom: 10px; padding-bottom: 2px; }
.day { flex-shrink: 0; border-radius: 10px; padding: 6px 11px; font-size: 11px; color: var(--sub); background: #fff; border: 1px solid var(--line); cursor: pointer; text-align: left; }
.day b { display: block; font-size: 13px; color: var(--ink); }
.day.on { background: var(--ink); border-color: var(--ink); color: rgba(255,255,255,.7); }
.day.on b { color: #fff; }
.map-toggle { width: 100%; display: flex; align-items: center; gap: 6px; background: #fff; border: none; border-radius: 11px; padding: 10px 12px; font-size: 13px; margin-bottom: 10px; cursor: pointer; text-align: left; }
.map-toggle b { margin-left: auto; color: var(--lagoon); font-size: 12px; }
/* 휴대폰: 지도 요소는 일정 칸 밖에 하나만 두고, 일정 칸을 풀어(display: contents)
   '지도' 줄과 검색 칸 사이로 끼워 넣는다 */
.trv:not(.wide) .plan-col { display: contents; }
.trv:not(.wide) .tabs { order: 1; }
.trv:not(.wide) .days { order: 2; }
.trv:not(.wide) .map-toggle { order: 3; }
.trv:not(.wide) .map-col { order: 4; }
.trv:not(.wide) .search-wrap { order: 5; }
.trv:not(.wide) .rows { order: 6; }
.trv:not(.wide) .tray-m { order: 7; }
.trv:not(.wide) .pane { order: 8; }
.map-col { position: relative; height: 210px; border-radius: 14px; overflow: hidden; background: #d6e0e6; margin: -2px 0 12px; }
.map-canvas { position: absolute; inset: 0; }
.map-off { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; text-align: center; padding: 20px; font-size: 13px; color: var(--sub); }
.map-tag { position: absolute; left: 8px; top: 8px; background: rgba(22,38,61,.85); color: #fff; font-size: 11px; border-radius: 8px; padding: 4px 8px; pointer-events: none; }
.map-tools { position: absolute; right: 8px; top: 8px; display: flex; gap: 6px; }
.map-tools button { background: #fff; border: none; border-radius: 8px; padding: 5px 9px; font-size: 11px; box-shadow: 0 2px 6px rgba(0,0,0,.15); cursor: pointer; }

.search-wrap { position: relative; margin-bottom: 10px; }
.search { display: flex; align-items: center; gap: 8px; background: #fff; border: 1.5px solid var(--lagoon); border-radius: 12px; padding: 4px 6px 4px 11px; }
.search.tray { border-style: dashed; }
.search input { flex: 1; min-width: 0; border: none; outline: none; font-size: 14px; padding: 7px 0; background: none; color: var(--ink); }
.tray-toggle { border: 1px solid var(--line); background: #fff; border-radius: 8px; font-size: 11px; padding: 5px 8px; color: var(--sub); cursor: pointer; white-space: nowrap; }
.tray-toggle.on { background: var(--sun-soft); border-color: var(--sun); color: #7a5200; font-weight: 700; }
.sugg-box { position: absolute; left: 0; right: 0; top: calc(100% + 4px); background: #fff; border-radius: 12px; box-shadow: 0 8px 24px rgba(22,38,61,.18); z-index: 20; padding: 4px; }
.sugg { display: flex; flex-direction: column; width: 100%; text-align: left; padding: 9px 10px; border-radius: 9px; background: none; border: none; cursor: pointer; }
.sugg:hover { background: #f3f7f9; }
.sugg b { font-size: 14px; } .sugg span { font-size: 12px; color: var(--sub); }
.sugg-empty { font-size: 12px; color: var(--sub); padding: 9px 10px; }

.rows { min-height: 40px; border-radius: 12px; }
.rows.drop { box-shadow: inset 0 0 0 2px var(--lagoon); background: var(--lagoon-soft); }
.row { position: relative; display: grid; grid-template-columns: 18px 42px 24px 1fr auto; align-items: center; gap: 8px; background: #fff; border-radius: 11px; padding: 9px 10px; cursor: pointer; }
.row.sel { box-shadow: inset 0 0 0 2px var(--lagoon); }
.row.warn { box-shadow: inset 0 0 0 2px #ffc9a8; }
.row.dragging { z-index: 5; box-shadow: 0 10px 24px rgba(22,38,61,.25); opacity: .95; }
.grip { color: #b9c5ce; font-size: 13px; letter-spacing: -3px; cursor: grab; touch-action: none; user-select: none; padding: 6px 0; text-align: center; }
.r-t { font-size: 12px; font-weight: 700; }
.r-t.none { color: var(--faint); font-weight: 400; text-align: center; }
.r-pin { width: 22px; height: 22px; border-radius: 50%; color: #fff; font-size: 11px; font-weight: 700; display: flex; align-items: center; justify-content: center; }
.r-nm { min-width: 0; }
.r-nm b { display: block; font-size: 14px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.r-nm small { display: block; font-size: 11px; color: var(--sub); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.r-go { color: var(--lagoon); font-weight: 700; text-decoration: none; padding: 4px 6px; }
.r-warn { grid-column: 3 / -1; font-size: 11px; color: var(--red); background: var(--red-soft); border-radius: 6px; padding: 3px 7px; }
.leg { display: flex; align-items: center; gap: 6px; width: 100%; background: none; border: none; padding: 4px 0 4px 76px; font-size: 12px; color: var(--sub); cursor: pointer; text-align: left; min-height: 28px; }
.leg.empty { color: var(--faint); }
.leg-go { margin-left: auto; margin-right: 8px; font-size: 11px; color: var(--lagoon); font-weight: 700; text-decoration: none; }
.leg:not(:hover) .leg-go { opacity: .8; }
.drop-line { height: 3px; background: var(--lagoon); border-radius: 3px; margin: 3px 0; }
.mini-btn { border: 1px solid var(--line); background: #fff; border-radius: 9px; padding: 6px 10px; font-size: 12px; cursor: pointer; }

.tray-m { margin-top: 12px; background: #fff; border: 1.5px dashed #c6d1d9; border-radius: 12px; padding: 10px 12px; }
.tray-h { display: flex; justify-content: space-between; font-size: 12px; font-weight: 700; color: var(--sub); margin-bottom: 4px; }
.tray-it { display: flex; align-items: center; gap: 8px; font-size: 13px; padding: 6px 0; }
.tray-it i, .tray-chip i { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.tray-it .tc-name { flex: 1; min-width: 0; cursor: pointer; }
.tray-it button { border: none; background: var(--lagoon-soft); color: var(--lagoon); font-weight: 700; font-size: 11px; border-radius: 8px; padding: 5px 8px; cursor: pointer; white-space: nowrap; }

/* ── 경비 ── */
.wallet { background: var(--ink); color: #fff; border-radius: 16px; padding: 16px; margin-bottom: 10px; }
.w-lbl { font-size: 11px; opacity: .6; letter-spacing: 1px; }
.w-big { font-size: 26px; font-weight: 800; margin: 4px 0 6px; }
.w-big.over { color: #ffa8a8; }
.w-row { display: flex; justify-content: space-between; font-size: 12px; opacity: .75; margin-top: 6px; }
.fx { display: flex; align-items: center; gap: 8px; background: var(--sun-soft); border-radius: 12px; padding: 9px 12px; font-size: 12px; color: #7a5200; margin-bottom: 10px; cursor: pointer; }
.fx-sub { color: #b08a3a; } .fx-edit { margin-left: auto; font-weight: 700; }
.receipt { background: #fff; border-radius: 12px; padding: 12px 14px; margin-bottom: 10px; }
.r-h { display: flex; justify-content: space-between; font-size: 11px; color: var(--sub); letter-spacing: 1px; padding-bottom: 8px; border-bottom: 1px dashed var(--line); margin-bottom: 4px; }
.stack { display: flex; height: 8px; border-radius: 6px; overflow: hidden; margin: 6px 0 8px; }
.legend { display: flex; flex-wrap: wrap; gap: 10px; font-size: 11px; color: var(--sub); }
.legend i { display: inline-block; width: 8px; height: 8px; border-radius: 2px; margin-right: 4px; }
.line { display: flex; align-items: baseline; gap: 8px; padding: 7px 0; font-size: 13px; cursor: pointer; }
.k { font-size: 10px; color: #fff; border-radius: 5px; padding: 1px 5px; flex-shrink: 0; }
.line-t { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.amt { margin-left: auto; text-align: right; white-space: nowrap; }
.amt small { display: block; color: var(--faint); font-size: 11px; }

/* ── 준비물 ── */
.stamp { display: flex; align-items: center; gap: 12px; background: #fff; border-radius: 14px; padding: 12px 14px; margin-bottom: 10px; }
.ring { width: 46px; height: 46px; border-radius: 50%; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.ring span { width: 36px; height: 36px; border-radius: 50%; background: #fff; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 800; }
.stamp-t { font-weight: 700; font-size: 14px; } .stamp-s { font-size: 12px; color: var(--sub); }
.tpl { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 8px; }
.tpl button { font-size: 12px; background: #fff; border: 1px solid var(--line); border-radius: 20px; padding: 6px 12px; cursor: pointer; }
.grp { font-size: 11px; font-weight: 700; color: var(--sub); letter-spacing: 1px; display: flex; justify-content: space-between; margin: 14px 2px 6px; }
.ck { background: #fff; border-radius: 10px; padding: 11px 12px; display: flex; align-items: center; gap: 10px; margin-bottom: 5px; font-size: 14px; cursor: pointer; }
.box { width: 18px; height: 18px; border-radius: 50%; border: 2px solid #c6d1d9; flex-shrink: 0; }
.ck.done .box { background: var(--lagoon); border-color: var(--lagoon); }
.ck.done .ck-t { color: var(--faint); text-decoration: line-through; }
.ck-del { margin-left: auto; background: none; border: none; color: #c6d1d9; cursor: pointer; padding: 2px 6px; }

/* ── 웹 모드: 화면 전체를 쓰는 세 칸 ── */
.trv.wide { position: fixed; inset: 0; z-index: 150; overflow: hidden; display: flex; flex-direction: column; }
.trv.wide .trv-hdr { position: static; transform: none; max-width: none; left: auto; flex-shrink: 0; padding: 0 20px; }
.trv.wide .trv-fab { bottom: 24px; right: 24px; }
.trv.wide .list-body { flex: 1; overflow: auto; padding: 24px 24px 100px; }
.trv.wide .list-body > * { max-width: 920px; margin-left: auto; margin-right: auto; }
.trv.wide .pass-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.trv.wide .pass-grid .pass { margin-bottom: 0; }
.trv.wide .detail { flex: 1; min-height: 0; padding: 0; display: grid; grid-template-columns: 210px minmax(380px, 460px) 1fr; }
.trv.wide .detail.no-map { grid-template-columns: 210px minmax(380px, 720px) 1fr; }
.side { border-right: 1px solid var(--line); background: #f6f8f9; padding: 14px 10px; overflow: auto; display: flex; flex-direction: column; gap: 4px; }
.side-lbl { font-size: 11px; font-weight: 700; color: var(--sub); letter-spacing: 1.2px; margin: 2px 6px 4px; display: flex; justify-content: space-between; }
.side-day { display: flex; align-items: center; gap: 8px; width: 100%; background: none; border: none; border-radius: 10px; padding: 9px 10px; font-size: 12px; color: var(--sub); cursor: pointer; text-align: left; }
.side-day b { font-size: 13px; color: var(--ink); }
.side-day:hover { background: #e9eff2; }
.side-day .cnt { margin-left: auto; font-size: 11px; background: #e3e9ed; border-radius: 8px; padding: 1px 7px; }
.side-day.on { background: var(--ink); color: rgba(255,255,255,.7); }
.side-day.on b { color: #fff; } .side-day.on .cnt { background: rgba(255,255,255,.15); color: #fff; }
.side-tray { margin-top: 12px; border-top: 1px dashed var(--line); padding-top: 10px; }
.tray-chip { display: flex; align-items: center; gap: 6px; background: #fff; border: 1px dashed #c6d1d9; border-radius: 9px; padding: 6px 6px 6px 9px; font-size: 12px; margin-bottom: 5px; cursor: grab; }
.tray-chip .tc-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tc-btn { border: none; background: none; color: var(--sub); cursor: pointer; padding: 2px 5px; border-radius: 6px; }
.tc-btn:hover { background: var(--lagoon-soft); color: var(--lagoon); }
.side-hint { font-size: 11px; color: var(--faint); margin: 6px 4px 0; line-height: 1.5; }
.trv.wide .plan-col { overflow: auto; padding: 14px 16px 90px; border-right: 1px solid var(--line); min-height: 0; }
.plan-head { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
.plan-head h2 { margin: 0; font-size: 16px; }
.plan-head .meta { font-size: 12px; color: var(--sub); }
.plan-head .mini-btn { margin-left: auto; }
.trv.wide .map-col { height: auto; margin: 0; border-radius: 0; min-height: 0; }
.trv.wide .map-tag { left: 12px; top: 12px; font-size: 12px; padding: 6px 10px; }
.trv.wide .map-tools { right: 12px; top: 12px; }
.trv.wide .map-tools button { font-size: 12px; padding: 6px 10px; }
.trv.wide .pane { grid-column: 2 / 4; overflow: auto; padding: 18px 24px 90px; min-height: 0; }
.trv.wide .pane > * { max-width: 680px; }
.trv.wide .row { padding: 8px 10px; }

/* ── 시트 ── */
.sheet-bg { position: fixed; inset: 0; background: rgba(22,38,61,.45); z-index: 300; display: flex; align-items: flex-end; justify-content: center; }
.trv.wide .sheet-bg { align-items: center; }
.sheet { background: #fff; width: 100%; max-width: 480px; border-radius: 20px 20px 0 0; padding: 18px 16px calc(18px + env(safe-area-inset-bottom, 0px)); display: flex; flex-direction: column; gap: 10px; max-height: 88vh; overflow-y: auto; }
.trv.wide .sheet { border-radius: 18px; }
.sheet h3 { margin: 0 0 2px; font-size: 16px; }
.f-row { display: flex; gap: 8px; }
.f-lab { flex: 1; display: flex; flex-direction: column; gap: 4px; font-size: 12px; color: var(--sub); min-width: 0; }
.f-in { width: 100%; padding: 11px 12px; border: 1px solid var(--line); border-radius: 10px; font-size: 15px; background: #f8fafb; color: var(--ink); min-width: 0; }
.f-in:focus { outline: none; border-color: var(--lagoon); background: #fff; }
.f-note { font-size: 12px; color: var(--sub); margin-top: -4px; }
.chips { display: flex; gap: 6px; flex-wrap: wrap; }
.chips button { border: 1px solid var(--line); background: #fff; border-radius: 16px; padding: 6px 12px; font-size: 13px; cursor: pointer; }
.chips button.on { background: var(--c); border-color: var(--c); color: #fff; font-weight: 700; }
.f-act { display: flex; gap: 8px; margin-top: 4px; flex-wrap: wrap; }
.f-act button { padding: 13px 14px; border-radius: 12px; font-size: 15px; cursor: pointer; border: 1px solid var(--line); background: #fff; }
.f-cancel { flex: 1; color: var(--sub); }
.f-ok { flex: 2; background: var(--lagoon) !important; color: #fff !important; border-color: var(--lagoon) !important; font-weight: 700; }
.f-ok:disabled { opacity: .5; }
.f-del { color: var(--red); }
button:focus-visible, .f-in:focus-visible, .search input:focus-visible { outline: 2px solid var(--lagoon); outline-offset: 2px; }
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
</style>
