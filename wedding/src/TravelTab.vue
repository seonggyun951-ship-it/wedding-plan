<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue'

// 여행 탭. 웨딩앱과 계정·Supabase를 같이 쓰고, 화면과 데이터는 따로 간다.
// 테이블: trips / trip_events / trip_places / trip_expenses / trip_packing (supabase/travel_tables.sql)
const props = defineProps({
  supabase: { type: Object, required: true },
  userId:   { type: String, required: true },
})
const emit = defineEmits(['logout'])
const db = props.supabase

// ── 상수 ────────────────────────────────────────────────────
const CATS = {
  move: { label: '이동', color: '#3b82c4' },
  stay: { label: '숙소', color: '#7a5af0' },
  food: { label: '맛집', color: '#e8890c' },
  spot: { label: '명소', color: '#0f7c8c' },
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

// ── 상태 ────────────────────────────────────────────────────
const trips   = ref([])
const stats   = ref({})          // trip_id → { events, places, packDone, packAll, used }
const loading = ref(true)
const view    = ref('list')      // list | detail
const tripId  = ref('')
const sub     = ref('plan')      // plan | places | money | pack
const dayYmd  = ref('')
const places   = ref([])
const events   = ref([])
const expenses = ref([])
const packing  = ref([])
const selPlaceId = ref('')
const busy = ref(false)

const trip = computed(() => trips.value.find(t => t.id === tripId.value) || null)
const days = computed(() => tripDays(trip.value))
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
  selPlaceId.value = ''
  places.value = []; events.value = []; expenses.value = []; packing.value = []
  view.value = 'detail'
  await loadDetail()
}
async function loadDetail() {
  const id = tripId.value
  const [p, e, x, k] = await Promise.all([
    db.from('trip_places').select('*').eq('trip_id', id).order('created_at'),
    db.from('trip_events').select('*').eq('trip_id', id).order('day_date').order('start_time', { nullsFirst: false }),
    db.from('trip_expenses').select('*').eq('trip_id', id).order('spent_on', { ascending: false }).order('created_at', { ascending: false }),
    db.from('trip_packing').select('*').eq('trip_id', id).order('created_at'),
  ])
  const err = p.error || e.error || x.error || k.error
  if (err) return fail('여행 내용 불러오기', err)
  places.value = p.data; events.value = e.data; expenses.value = x.data; packing.value = k.data
}
function backToList() {
  view.value = 'list'
  map = null; mapMarkers = []; mapLine = null
  loadTrips()
}

// ── 여행 추가·수정·삭제 ─────────────────────────────────────
const tripForm = ref(null)   // null이면 닫힘
const blankTrip = () => ({ id: null, title: '', emoji: '✈️', origin_code: 'ICN', dest_code: '', start_date: todayYmd(), end_date: todayYmd(), budget: '', currency: 'KRW', fx_input: '' })
const fxUnit = (code) => curOf(code).per || 1
function openTripForm(t) {
  if (!t) { tripForm.value = blankTrip(); return }
  tripForm.value = {
    ...t,
    budget: t.budget || '',
    fx_input: t.fx_rate ? +(Number(t.fx_rate) * fxUnit(t.currency)).toFixed(4) : '',
  }
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
  if (view.value === 'detail' && !days.value.find(d => d.ymd === dayYmd.value)) dayYmd.value = res.data.start_date
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

// ── 일정 ────────────────────────────────────────────────────
const dayEvents = computed(() => {
  const list = events.value.filter(e => e.day_date === dayYmd.value)
    .slice().sort((a, b) => (a.start_time || '99').localeCompare(b.start_time || '99'))
  // 앞 일정이 끝나기 전에 다음 일정이 시작하면 겹친다고 알린다
  return list.map((e, i) => {
    const prev = list[i - 1]
    const clash = prev && prev.end_time && e.start_time && e.start_time < prev.end_time
    return { ...e, clash: clash ? `${hhmm(prev.start_time)} ${prev.title} 일정과 시간이 겹칩니다` : '' }
  })
})
const eventForm = ref(null)
function openEventForm(e, fromPlace) {
  if (e) { eventForm.value = { ...e, start_time: hhmm(e.start_time), end_time: hhmm(e.end_time), place_id: e.place_id || '' }; return }
  eventForm.value = {
    id: null, day_date: dayYmd.value || days.value[0]?.ymd, start_time: '', end_time: '',
    title: fromPlace?.name || '', category: fromPlace?.category || 'spot', place_id: fromPlace?.id || '', memo: '',
  }
}
function onEventPlace() {
  const p = placeById(eventForm.value.place_id)
  if (p) { if (!eventForm.value.title) eventForm.value.title = p.name; eventForm.value.category = p.category }
}
async function saveEvent() {
  const f = eventForm.value
  if (!f.title.trim()) return alert('일정 이름을 적어 주세요')
  if (f.start_time && f.end_time && f.end_time < f.start_time) return alert('끝나는 시각이 시작보다 빠릅니다')
  const row = {
    day_date: f.day_date, start_time: f.start_time || null, end_time: f.end_time || null,
    title: f.title.trim(), category: f.category, place_id: f.place_id || null, memo: f.memo?.trim() || null,
  }
  busy.value = true
  const res = f.id
    ? await db.from('trip_events').update(row).eq('id', f.id).select().single()
    : await db.from('trip_events').insert({ ...row, trip_id: tripId.value, user_id: props.userId }).select().single()
  busy.value = false
  if (res.error) return fail('일정 저장', res.error)
  const i = events.value.findIndex(x => x.id === res.data.id)
  if (i >= 0) events.value[i] = res.data; else events.value.push(res.data)
  eventForm.value = null
  dayYmd.value = res.data.day_date
  if (sub.value !== 'plan') sub.value = 'plan'
}
async function deleteEvent() {
  const f = eventForm.value
  if (!confirm(`'${f.title}' 일정을 삭제할까요?`)) return
  const { error } = await db.from('trip_events').delete().eq('id', f.id)
  if (error) return fail('일정 삭제', error)
  events.value = events.value.filter(x => x.id !== f.id)
  eventForm.value = null
}
const dirUrl = (p) => {
  if (!p) return ''
  if (p.lat != null && p.lng != null) return `https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}`
  return p.map_url || ''
}

// ── 장소 ────────────────────────────────────────────────────
const assignedIds = computed(() => events.value.map(e => e.place_id).filter(Boolean))
const placeDays = (id) => {
  const ns = [...new Set(events.value.filter(e => e.place_id === id).map(e => days.value.find(d => d.ymd === e.day_date)?.n).filter(Boolean))].sort((a, b) => a - b)
  if (!ns.length) return ''
  return ns.length > 2 && ns[ns.length - 1] - ns[0] === ns.length - 1 ? `Day ${ns[0]}–${ns[ns.length - 1]}` : ns.map(n => `Day ${n}`).join(', ')
}
const freePlaces  = computed(() => places.value.filter(p => !assignedIds.value.includes(p.id)))
const usedPlaces  = computed(() => places.value.filter(p =>  assignedIds.value.includes(p.id)))
const placeNo = (id) => places.value.findIndex(p => p.id === id) + 1

const placeForm = ref(null)
function openPlaceForm(p) {
  placeForm.value = p
    ? { ...p }
    : { id: null, name: '', category: 'spot', address: '', lat: null, lng: null, place_id: null, map_url: '', memo: '' }
  query.value = ''; suggestions.value = []
}
// 구글 지도 링크에서 좌표를 꺼낸다. 짧은 공유 링크(maps.app.goo.gl)는 좌표가 안 들어 있어 못 꺼낸다.
function coordsFromUrl(url) {
  const pats = [/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/, /@(-?\d+\.\d+),(-?\d+\.\d+)/, /[?&](?:q|query|destination|ll)=(-?\d+\.\d+),\s*(-?\d+\.\d+)/]
  for (const re of pats) { const m = (url || '').match(re); if (m) return { lat: Number(m[1]), lng: Number(m[2]) } }
  return null
}
function onPlaceUrl() {
  const c = coordsFromUrl(placeForm.value.map_url)
  if (c) { placeForm.value.lat = c.lat; placeForm.value.lng = c.lng }
}
async function savePlace() {
  const f = placeForm.value
  if (!f.name.trim()) return alert('장소 이름을 적어 주세요')
  const row = {
    name: f.name.trim(), category: f.category, address: f.address || null,
    lat: f.lat, lng: f.lng, place_id: f.place_id, map_url: f.map_url?.trim() || null, memo: f.memo?.trim() || null,
  }
  busy.value = true
  const res = f.id
    ? await db.from('trip_places').update(row).eq('id', f.id).select().single()
    : await db.from('trip_places').insert({ ...row, trip_id: tripId.value, user_id: props.userId }).select().single()
  busy.value = false
  if (res.error) return fail('장소 저장', res.error)
  const i = places.value.findIndex(x => x.id === res.data.id)
  if (i >= 0) places.value[i] = res.data; else places.value.push(res.data)
  placeForm.value = null
  selPlaceId.value = res.data.id
}
async function deletePlace() {
  const f = placeForm.value
  const n = events.value.filter(e => e.place_id === f.id).length
  if (!confirm(`'${f.name}' 장소를 삭제할까요?${n ? `\n일정 ${n}개는 남고 장소 연결만 풀립니다.` : ''}`)) return
  const { error } = await db.from('trip_places').delete().eq('id', f.id)
  if (error) return fail('장소 삭제', error)
  places.value = places.value.filter(x => x.id !== f.id)
  events.value = events.value.map(e => e.place_id === f.id ? { ...e, place_id: null } : e)
  placeForm.value = null
}

// ── 구글 지도 ───────────────────────────────────────────────
// 키는 .env의 VITE_GOOGLE_MAPS_KEY. 없으면 지도 자리에 안내만 띄우고 나머지는 그대로 쓴다.
// 지도는 여행 화면에 들어갈 때 한 번만 만들고(=1회 과금 단위), Day·탭을 바꿀 땐 핀만 다시 그린다.
const MAPS_KEY = import.meta.env.VITE_GOOGLE_MAPS_KEY || ''
const mapEl = ref(null)
const mapError = ref('')
let mapsPromise = null
let map = null
let mapMarkers = []
let mapLine = null

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
// 키가 틀렸거나 API가 꺼져 있으면 구글이 이 함수를 부른다
window.gm_authFailure = () => { mapError.value = '구글 지도 키를 확인해 주세요 (키 제한 또는 API 사용 설정)' }

async function ensureMap() {
  if (map || !MAPS_KEY || !mapEl.value) return map
  try {
    const maps = await loadMaps()
    const { Map } = await maps.importLibrary('maps')
    if (!mapEl.value) return null
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
  if (mapLine) { mapLine.setMap(null); mapLine = null }
}
async function drawPins() {
  if (view.value !== 'detail' || !(sub.value === 'plan' || sub.value === 'places')) return
  await nextTick()
  const m = await ensureMap()
  if (!m) return
  const g = window.google.maps
  clearPins()
  let pts = []
  if (sub.value === 'plan') {
    pts = dayEvents.value.map(e => placeById(e.place_id)).filter(p => p && p.lat != null)
      .map((p, i) => ({ p, label: String(i + 1) }))
  } else {
    pts = places.value.filter(p => p.lat != null).map(p => ({ p, label: String(placeNo(p.id)) }))
  }
  pts.forEach(({ p, label }) => {
    const sel = sub.value === 'places' && p.id === selPlaceId.value
    mapMarkers.push(new g.Marker({
      map: m, position: { lat: p.lat, lng: p.lng }, title: p.name,
      label: { text: label, color: '#fff', fontSize: '11px', fontWeight: '700' },
      icon: { path: g.SymbolPath.CIRCLE, scale: sel ? 13 : 10, fillColor: CATS[p.category]?.color || '#16263d', fillOpacity: 1, strokeColor: '#fff', strokeWeight: 2 },
      zIndex: sel ? 10 : 1,
    }))
  })
  if (sub.value === 'plan' && pts.length > 1) {
    mapLine = new g.Polyline({ map: m, path: pts.map(({ p }) => ({ lat: p.lat, lng: p.lng })), strokeColor: '#16263d', strokeOpacity: 0.55, strokeWeight: 3 })
  }
  const sel = sub.value === 'places' && placeById(selPlaceId.value)
  if (sel && sel.lat != null) { m.panTo({ lat: sel.lat, lng: sel.lng }); m.setZoom(15); return }
  if (pts.length === 1) { m.setCenter({ lat: pts[0].p.lat, lng: pts[0].p.lng }); m.setZoom(15) }
  else if (pts.length > 1) { const b = new g.LatLngBounds(); pts.forEach(({ p }) => b.extend({ lat: p.lat, lng: p.lng })); m.fitBounds(b, 40) }
}
const pinCount = computed(() => sub.value === 'plan'
  ? dayEvents.value.filter(e => placeById(e.place_id)?.lat != null).length
  : places.value.filter(p => p.lat != null).length)
watch([view, sub, dayYmd, selPlaceId, places, events], drawPins, { deep: true })

// ── 장소 검색 (Places API New: 자동완성 → 고른 장소의 위치·주소만 받음) ──
// 이름은 자동완성 결과에서 쓰고, 상세 조회는 위치·주소만 받아 가장 싼 등급으로 끝낸다.
const query = ref('')
const suggestions = ref([])
const searching = ref(false)
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
    }))
  } catch (e) {
    mapError.value = `장소 검색 실패: ${e.message || e}`
    suggestions.value = []
  } finally {
    searching.value = false
  }
}
async function pickSuggestion(s) {
  try {
    const place = s.pred.toPlace()
    await place.fetchFields({ fields: ['location', 'formattedAddress'] })
    const f = placeForm.value
    f.name = s.main
    f.address = place.formattedAddress || s.second
    f.lat = place.location?.lat() ?? null
    f.lng = place.location?.lng() ?? null
    f.place_id = place.id || s.pred.placeId
    f.map_url = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(s.main)}&query_place_id=${f.place_id}`
  } catch (e) {
    alert(`장소 정보를 받지 못했습니다: ${e.message || e}`)
  } finally {
    sessionToken = null   // 한 장소를 고르면 검색 묶음(세션)을 끝낸다
    query.value = ''; suggestions.value = []
  }
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
  const d = days.value.find(d => d.ymd === ymd)
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
  // 수정할 때 금액·통화를 안 바꿨으면 처음 환산한 원화를 그대로 둔다 (환율을 바꿔도 지난 지출은 그대로)
  const orig = f.id && expenses.value.find(x => x.id === f.id)
  const sameMoney = orig && Number(orig.amount) === Number(f.amount) && orig.currency === f.currency
  const row = {
    title: f.title.trim(), amount: Number(f.amount), currency: f.currency, category: f.category,
    spent_on: f.spent_on || null, amount_krw: sameMoney ? orig.amount_krw : Math.round(expKrwPreview.value),
  }
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

// ── FAB ─────────────────────────────────────────────────────
function onFab() {
  if (view.value === 'list') return openTripForm(null)
  if (sub.value === 'plan') return openEventForm(null)
  if (sub.value === 'places') return openPlaceForm(null)
  if (sub.value === 'money') return openExpForm(null)
  return openPackForm()
}

onMounted(loadTrips)
</script>

<template>
  <div class="trv">
    <!-- 헤더 -->
    <header class="trv-hdr">
      <template v-if="view === 'list'">
        <h1 class="trv-title">✈️ 여행</h1>
        <button class="trv-ib" @click="emit('logout')" title="로그아웃">🚪</button>
      </template>
      <template v-else-if="trip">
        <button class="trv-back" @click="backToList">←</button>
        <div class="trv-hgrow">
          <h1 class="trv-title">{{ trip.title }}</h1>
          <div class="trv-route mono">
            <template v-if="trip.origin_code && trip.dest_code">{{ trip.origin_code }} ✈ {{ trip.dest_code }} · </template>{{ mmdd(trip.start_date) }}–{{ mmdd(trip.end_date) }}
          </div>
        </div>
        <button class="trv-ib" @click="openTripForm(trip)" title="여행 설정">⚙️</button>
      </template>
    </header>

    <div class="trv-body">
      <!-- ① 여행 목록 -->
      <template v-if="view === 'list'">
        <div v-if="loading" class="trv-empty">불러오는 중...</div>
        <div v-else-if="!trips.length" class="trv-empty">
          <div style="font-size:34px">🧳</div>
          <p>아직 여행이 없습니다<br>오른쪽 아래 + 로 첫 여행을 만들어 보세요</p>
        </div>
        <template v-else>
          <p v-if="upcoming.length" class="trv-sec">UPCOMING</p>
          <div v-for="t in upcoming" :key="t.id" class="pass" @click="openTrip(t)">
            <div class="pass-main">
              <div v-if="t.origin_code && t.dest_code" class="codes mono"><b>{{ t.origin_code }}</b><span class="plane"></span><b>{{ t.dest_code }}</b></div>
              <div class="pass-name">{{ t.emoji }} {{ t.title }}</div>
              <div class="pass-meta mono">{{ t.start_date.replaceAll('-', '.') }} – {{ mmdd(t.end_date) }} · {{ nightsLabel(t) }}</div>
              <div v-if="t.budget" class="gauge"><i :style="{ width: Math.min(100, statOf(t.id).used / t.budget * 100) + '%' }"></i></div>
              <div class="pass-mini">
                <span v-if="t.budget">예산 <b class="mono">{{ Math.round(statOf(t.id).used / t.budget * 100) }}%</b></span>
                <span>일정 <b>{{ statOf(t.id).events }}</b></span>
                <span>장소 <b>{{ statOf(t.id).places }}</b></span>
                <span v-if="statOf(t.id).packAll">준비물 <b>{{ statOf(t.id).packDone }}/{{ statOf(t.id).packAll }}</b></span>
              </div>
            </div>
            <div class="pass-stub">
              <span class="stub-lbl">D-DAY</span>
              <span class="dd mono" :class="{ small: ddayOf(t).text === '여행 중' }">{{ ddayOf(t).text }}</span>
            </div>
          </div>
          <p v-if="past.length" class="trv-sec" style="margin-top:16px">PAST</p>
          <div v-for="t in past" :key="t.id" class="pass past" @click="openTrip(t)">
            <div class="pass-main">
              <div v-if="t.origin_code && t.dest_code" class="codes mono small"><b>{{ t.origin_code }}</b><span class="plane"></span><b>{{ t.dest_code }}</b></div>
              <div class="pass-name">{{ t.emoji }} {{ t.title }}</div>
              <div class="pass-meta mono">{{ t.start_date.replaceAll('-', '.') }} – {{ mmdd(t.end_date) }}</div>
            </div>
            <div class="pass-stub"><span class="dd past mono">완료</span></div>
          </div>
        </template>
      </template>

      <!-- 여행 상세 -->
      <template v-else-if="trip">
        <div class="tabs">
          <button :class="{ on: sub === 'plan' }"   @click="sub = 'plan'">일정</button>
          <button :class="{ on: sub === 'places' }" @click="sub = 'places'">장소</button>
          <button :class="{ on: sub === 'money' }"  @click="sub = 'money'">경비</button>
          <button :class="{ on: sub === 'pack' }"   @click="sub = 'pack'">준비물</button>
        </div>

        <div v-if="sub === 'plan'" class="days">
          <button v-for="d in days" :key="d.ymd" class="day" :class="{ on: d.ymd === dayYmd }" @click="dayYmd = d.ymd">
            <b>Day {{ d.n }}</b>{{ d.label }}
          </button>
        </div>

        <!-- 지도: 일정·장소 탭이 같이 쓴다. 탭을 바꿔도 지도를 새로 만들지 않도록 v-show -->
        <div v-show="sub === 'plan' || sub === 'places'" class="map">
          <div ref="mapEl" class="map-canvas"></div>
          <div v-if="!MAPS_KEY" class="map-off">구글 지도 키를 넣으면 여기에 지도가 보입니다</div>
          <div v-else-if="mapError" class="map-off">{{ mapError }}</div>
          <span v-else-if="sub === 'plan'" class="map-tag">Day {{ days.find(d => d.ymd === dayYmd)?.n }} 동선 · 장소 {{ pinCount }}곳</span>
        </div>

        <!-- ② 일정 -->
        <template v-if="sub === 'plan'">
          <div v-if="!dayEvents.length" class="trv-empty small">이날 일정이 없습니다. + 로 추가하세요</div>
          <div v-else class="tl">
            <div v-for="e in dayEvents" :key="e.id" class="ev" :class="[e.category, { clash: e.clash }]" :style="{ '--c': CATS[e.category]?.color }" @click="openEventForm(e)">
              <span class="ev-t mono">{{ hhmm(e.start_time) }}</span>
              <div class="ev-title">
                <span>{{ e.title }}</span>
                <a v-if="dirUrl(placeById(e.place_id))" class="go" :href="dirUrl(placeById(e.place_id))" target="_blank" rel="noopener" @click.stop>길찾기 ↗</a>
              </div>
              <div v-if="e.end_time || e.memo" class="ev-sub">
                <template v-if="e.end_time">~{{ hhmm(e.end_time) }}</template><template v-if="e.end_time && e.memo"> · </template>{{ e.memo }}
              </div>
              <div v-if="e.clash" class="warn">{{ e.clash }}</div>
            </div>
          </div>
        </template>

        <!-- ③ 장소 -->
        <template v-else-if="sub === 'places'">
          <div v-if="!places.length" class="trv-empty small">가고 싶은 곳을 + 로 담아 두세요</div>
          <p v-if="freePlaces.length" class="trv-sec">아직 날짜 안 정한 곳</p>
          <div v-for="p in freePlaces" :key="p.id" class="place" :class="{ sel: p.id === selPlaceId }" @click="selPlaceId = p.id">
            <span class="pin" :style="{ background: CATS[p.category]?.color }"><span>{{ placeNo(p.id) }}</span></span>
            <div class="place-txt"><div class="place-nm">{{ p.name }}</div><div class="place-src">{{ CATS[p.category]?.label }}<template v-if="p.lat == null"> · 위치 없음</template></div></div>
            <button class="assign none" @click.stop="openEventForm(null, p)">Day 고르기</button>
            <button class="mini-edit" @click.stop="openPlaceForm(p)">⋯</button>
          </div>
          <p v-if="usedPlaces.length" class="trv-sec" style="margin-top:12px">일정에 넣은 곳</p>
          <div v-for="p in usedPlaces" :key="p.id" class="place" :class="{ sel: p.id === selPlaceId }" @click="selPlaceId = p.id">
            <span class="pin" :style="{ background: CATS[p.category]?.color }"><span>{{ placeNo(p.id) }}</span></span>
            <div class="place-txt"><div class="place-nm">{{ p.name }}</div><div class="place-src">{{ CATS[p.category]?.label }}<template v-if="p.lat == null"> · 위치 없음</template></div></div>
            <span class="assign set">{{ placeDays(p.id) }}</span>
            <button class="mini-edit" @click.stop="openPlaceForm(p)">⋯</button>
          </div>
        </template>

        <!-- ④ 경비 -->
        <template v-else-if="sub === 'money'">
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
        </template>

        <!-- ⑤ 준비물 -->
        <template v-else>
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
        </template>
      </template>
    </div>

    <button class="trv-fab" @click="onFab">+</button>

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
    <div v-if="eventForm" class="sheet-bg" @click.self="eventForm = null">
      <div class="sheet">
        <h3>{{ eventForm.id ? '일정 고치기' : '일정 추가' }}</h3>
        <label class="f-lab">날짜
          <select v-model="eventForm.day_date" class="f-in">
            <option v-for="d in days" :key="d.ymd" :value="d.ymd">Day {{ d.n }} · {{ d.label }}</option>
          </select>
        </label>
        <div class="f-row">
          <label class="f-lab">시작<input v-model="eventForm.start_time" type="time" class="f-in" /></label>
          <label class="f-lab">끝 (선택)<input v-model="eventForm.end_time" type="time" class="f-in" /></label>
        </div>
        <label v-if="places.length" class="f-lab">장소 (선택)
          <select v-model="eventForm.place_id" class="f-in" @change="onEventPlace">
            <option value="">장소 없음</option>
            <option v-for="p in places" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
        </label>
        <input v-model="eventForm.title" class="f-in" placeholder="일정 (예: 라피트 → 난바)" />
        <div class="chips">
          <button v-for="(c, k) in CATS" :key="k" :class="{ on: eventForm.category === k }" :style="{ '--c': c.color }" @click="eventForm.category = k">{{ c.label }}</button>
        </div>
        <input v-model="eventForm.memo" class="f-in" placeholder="메모 (예약번호, 요금 등)" />
        <div class="f-act">
          <button v-if="eventForm.id" class="f-del" @click="deleteEvent">삭제</button>
          <button class="f-cancel" @click="eventForm = null">취소</button>
          <button class="f-ok" :disabled="busy" @click="saveEvent">저장</button>
        </div>
      </div>
    </div>

    <!-- 장소 추가·수정 -->
    <div v-if="placeForm" class="sheet-bg" @click.self="placeForm = null">
      <div class="sheet">
        <h3>{{ placeForm.id ? '장소 고치기' : '장소 추가' }}</h3>
        <template v-if="MAPS_KEY && !placeForm.id">
          <input v-model="query" class="f-in" placeholder="🔍 장소 이름으로 검색" />
          <div v-if="searching" class="sugg-empty">찾는 중...</div>
          <div v-for="s in suggestions" :key="s.pred.placeId" class="sugg" @click="pickSuggestion(s)">
            <b>{{ s.main }}</b><span>{{ s.second }}</span>
          </div>
        </template>
        <input v-model="placeForm.name" class="f-in" placeholder="장소 이름" />
        <div v-if="placeForm.address" class="f-note">{{ placeForm.address }}</div>
        <input v-model="placeForm.map_url" class="f-in" placeholder="구글 지도 링크 (선택)" @change="onPlaceUrl" />
        <div class="f-note">
          <template v-if="placeForm.lat != null">📍 위치 있음 · 지도에 표시됩니다</template>
          <template v-else>위치 없음 · {{ MAPS_KEY ? '검색으로 고르거나' : '' }} 좌표가 든 지도 링크(@37.5,126.9 형태)를 넣으면 지도에 표시됩니다</template>
        </div>
        <div class="chips">
          <button v-for="(c, k) in CATS" :key="k" :class="{ on: placeForm.category === k }" :style="{ '--c': c.color }" @click="placeForm.category = k">{{ c.label }}</button>
        </div>
        <input v-model="placeForm.memo" class="f-in" placeholder="메모 (선택)" />
        <div class="f-act">
          <button v-if="placeForm.id" class="f-del" @click="deletePlace">삭제</button>
          <button class="f-cancel" @click="placeForm = null">취소</button>
          <button class="f-ok" :disabled="busy" @click="savePlace">저장</button>
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

.trv-hdr { position: fixed; top: 0; left: 50%; transform: translateX(-50%); width: 100%; max-width: 480px; z-index: 100;
  background: var(--ink); color: #fff; display: flex; align-items: center; gap: 10px; padding: 0 16px; height: 58px; }
.trv-title { font-size: 16px; font-weight: 700; margin: 0; flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.trv-hgrow { flex: 1; min-width: 0; }
.trv-route { font-size: 11px; opacity: .6; letter-spacing: 1px; margin-top: 2px; }
.trv-back { background: none; border: none; color: #fff; font-size: 22px; min-width: 36px; min-height: 44px; cursor: pointer; opacity: .85; padding: 0; text-align: left; }
.trv-ib { background: none; border: 1px solid rgba(255,255,255,.25); border-radius: 10px; padding: 5px 9px; font-size: 16px; cursor: pointer; min-width: 44px; min-height: 40px; }
.trv-body { padding: 72px 14px 150px; } /* 아래 메뉴 + 버튼에 마지막 줄이 가리지 않게 */
.trv-sec { font-size: 11px; font-weight: 700; color: var(--sub); letter-spacing: 1.2px; margin: 6px 2px 8px; }
.trv-empty { text-align: center; color: var(--sub); padding: 60px 10px; font-size: 14px; line-height: 1.6; }
.trv-empty.small { padding: 22px 10px; font-size: 13px; }
.trv-fab { position: fixed; bottom: calc(74px + env(safe-area-inset-bottom, 0px)); right: max(16px, calc(50% - 224px)); width: 54px; height: 54px;
  border-radius: 16px; border: none; background: var(--lagoon); color: #fff !important; font-size: 28px; cursor: pointer; z-index: 99; box-shadow: 0 6px 18px rgba(15,124,140,.4); }

/* 탑승권 카드 */
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

/* 상세 */
.tabs { display: flex; gap: 18px; padding: 0 4px; border-bottom: 1px solid var(--line); margin-bottom: 12px; }
.tabs button { background: none; border: none; font-size: 14px; padding: 8px 0 9px; color: var(--sub); cursor: pointer; }
.tabs button.on { color: var(--ink); font-weight: 700; box-shadow: inset 0 -2px 0 var(--lagoon); }
.days { display: flex; gap: 6px; overflow-x: auto; margin-bottom: 12px; padding-bottom: 2px; }
.day { flex-shrink: 0; border-radius: 10px; padding: 6px 11px; font-size: 11px; color: var(--sub); background: #fff; border: 1px solid var(--line); cursor: pointer; }
.day b { display: block; font-size: 13px; color: var(--ink); }
.day.on { background: var(--ink); border-color: var(--ink); color: rgba(255,255,255,.7); }
.day.on b { color: #fff; }
.map { border-radius: 14px; overflow: hidden; height: 200px; background: #d6e0e6; margin-bottom: 12px; position: relative; }
.map-canvas { position: absolute; inset: 0; }
.map-off { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; text-align: center; padding: 20px; font-size: 13px; color: var(--sub); }
.map-tag { position: absolute; left: 8px; top: 8px; background: rgba(22,38,61,.85); color: #fff; font-size: 11px; border-radius: 8px; padding: 4px 8px; pointer-events: none; }

.tl { position: relative; margin-left: 52px; }
.tl::before { content: ""; position: absolute; left: -14px; top: 6px; bottom: 6px; width: 2px; background: var(--line); }
.ev { position: relative; background: #fff; border-radius: 12px; padding: 10px 12px; margin-bottom: 8px; cursor: pointer; }
.ev::before { content: ""; position: absolute; left: -19px; top: 14px; width: 10px; height: 10px; border-radius: 50%; background: var(--c, #999); box-shadow: 0 0 0 3px var(--bg); }
.ev-t { position: absolute; left: -66px; top: 10px; width: 40px; text-align: right; font-size: 12px; font-weight: 700; }
.ev-title { font-size: 14px; font-weight: 600; display: flex; align-items: center; gap: 6px; }
.ev-sub { font-size: 12px; color: var(--sub); margin-top: 3px; }
.go { margin-left: auto; font-size: 11px; color: var(--lagoon); font-weight: 700; white-space: nowrap; text-decoration: none; }
.ev.clash { box-shadow: inset 0 0 0 2px #ffc9a8; }
.warn { font-size: 12px; color: var(--red); background: var(--red-soft); border-radius: 8px; padding: 5px 8px; margin-top: 6px; }

.place { display: flex; align-items: center; gap: 10px; background: #fff; border-radius: 12px; padding: 10px 12px; margin-bottom: 7px; cursor: pointer; }
.place.sel { box-shadow: inset 0 0 0 2px var(--lagoon); }
.pin { width: 26px; height: 26px; border-radius: 50% 50% 50% 0; transform: rotate(-45deg); display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.pin span { transform: rotate(45deg); font-size: 11px; color: #fff; font-weight: 700; }
.place-txt { min-width: 0; flex: 1; }
.place-nm { font-size: 14px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.place-src { font-size: 11px; color: var(--faint); margin-top: 2px; }
.assign { font-size: 11px; border-radius: 8px; padding: 4px 8px; white-space: nowrap; background: none; }
.assign.set { background: var(--lagoon-soft); color: var(--lagoon); font-weight: 700; }
.assign.none { border: 1px dashed #c6d1d9; color: var(--sub); cursor: pointer; }
.mini-edit { background: none; border: none; color: var(--faint); font-size: 16px; cursor: pointer; padding: 4px; }

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

/* 시트 */
.sheet-bg { position: fixed; inset: 0; background: rgba(22,38,61,.45); z-index: 300; display: flex; align-items: flex-end; justify-content: center; }
.sheet { background: #fff; width: 100%; max-width: 480px; border-radius: 20px 20px 0 0; padding: 18px 16px calc(18px + env(safe-area-inset-bottom, 0px)); display: flex; flex-direction: column; gap: 10px; max-height: 88vh; overflow-y: auto; }
.sheet h3 { margin: 0 0 2px; font-size: 16px; }
.f-row { display: flex; gap: 8px; }
.f-lab { flex: 1; display: flex; flex-direction: column; gap: 4px; font-size: 12px; color: var(--sub); min-width: 0; }
.f-in { width: 100%; padding: 11px 12px; border: 1px solid var(--line); border-radius: 10px; font-size: 15px; background: #f8fafb; color: var(--ink); min-width: 0; }
.f-in:focus { outline: none; border-color: var(--lagoon); background: #fff; }
.f-note { font-size: 12px; color: var(--sub); margin-top: -4px; }
.chips { display: flex; gap: 6px; flex-wrap: wrap; }
.chips button { border: 1px solid var(--line); background: #fff; border-radius: 16px; padding: 6px 12px; font-size: 13px; cursor: pointer; }
.chips button.on { background: var(--c); border-color: var(--c); color: #fff; font-weight: 700; }
.sugg { display: flex; flex-direction: column; padding: 9px 10px; border-radius: 10px; background: #f3f7f9; cursor: pointer; margin-top: -4px; }
.sugg b { font-size: 14px; } .sugg span { font-size: 12px; color: var(--sub); }
.sugg-empty { font-size: 12px; color: var(--sub); }
.f-act { display: flex; gap: 8px; margin-top: 4px; }
.f-act button { padding: 13px 14px; border-radius: 12px; font-size: 15px; cursor: pointer; border: 1px solid var(--line); background: #fff; }
.f-cancel { flex: 1; color: var(--sub); }
.f-ok { flex: 2; background: var(--lagoon) !important; color: #fff !important; border-color: var(--lagoon) !important; font-weight: 700; }
.f-ok:disabled { opacity: .5; }
.f-del { color: var(--red); }
button:focus-visible, .f-in:focus-visible { outline: 2px solid var(--lagoon); outline-offset: 2px; }
</style>
