/**
 * 做卡工坊的 Host 半边：把 chao-cards 插件的校验 / 提交能力挂成同源 HTTP 接口，
 * 供右侧栏面板直接调用。卡片逻辑全部复用 chao-cards，本插件不重复实现规则。
 */
import {execFile} from 'node:child_process'
import {existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs'
import {homedir} from 'node:os'
import {basename, join} from 'node:path'
import {pathToFileURL} from 'node:url'

export const name = 'chao-card-studio'
export const inject = ['webServer']

const PREFIX = '/chao-card-studio/api'
const MAX_BODY = 2 * 1024 * 1024
const UPSTREAM = 'dsh-plugin-chao-cards'

let loaded

/** 列出所有可能的 profile 根目录（环境变量优先，其次扫描 ~/.dsh/profiles）。 */
function profileRoots() {
  const roots = []
  const push = value => { if (typeof value === 'string' && value !== '' && !roots.includes(value)) roots.push(value) }
  push(process.env.DSH_PROFILE_DIR)
  const base = join(homedir(), '.dsh', 'profiles')
  try {
    for (const entry of readdirSync(base)) push(join(base, entry))
  } catch {
    // 没有多 profile 目录时忽略
  }
  return roots
}

/**
 * 这个包以目录链接的方式装进 profile，本文件因此位于工作区，裸包名解析不到
 * chao-cards；按 profile 的 node_modules 绝对路径解析，最后再退回裸包名。
 */
function candidates(file) {
  const list = []
  for (const root of profileRoots()) {
    const resolved = join(root, 'node_modules', UPSTREAM, 'lib', file)
    if (existsSync(resolved)) list.push(pathToFileURL(resolved).href)
  }
  list.push(`${UPSTREAM}/lib/${file}`)
  return list
}

async function loadModule(file) {
  let lastError
  for (const specifier of candidates(file)) {
    try {
      return await import(specifier)
    } catch (error) {
      lastError = error
    }
  }
  throw lastError ?? new Error(`无法加载 ${UPSTREAM}/lib/${file}`)
}

/** 延迟加载：chao-cards 未安装时插件仍能启动，接口返回明确的错误。 */
async function upstream() {
  if (loaded === undefined) {
    try {
      loaded = {
        cards: await loadModule('cards.mjs'),
        github: await loadModule('github.mjs'),
      }
    } catch (error) {
      throw new Error(`找不到已安装的 ${UPSTREAM} 插件（${error.message}）。请先安装并启用它。`)
    }
  }
  return loaded
}

// 线上卡库走 gh（已登录，比匿名 raw/CDN 稳）。插件自带的卡库快照只当兜底，
// 但 raw.githubusercontent / jsdelivr 在本机经常超时，所以这里主动用 gh 拉一次。
const CATALOG_CONTENTS = 'repos/xiangwu738-design/Chao/contents/data/catalog.json'

function ghCatalogFetch() {
  return new Promise((resolve, reject) => {
    execFile('gh', ['api', CATALOG_CONTENTS], {timeout: 20000, maxBuffer: 32 * 1024 * 1024, windowsHide: true}, (error, stdout) => {
      if (error) {
        reject(new Error(String(error.message).slice(0, 200)))
        return
      }
      try {
        const payload = JSON.parse(stdout)
        const text = Buffer.from(String(payload.content ?? '').replace(/\s+/g, ''), 'base64').toString('utf8')
        resolve({ok: true, json: async () => JSON.parse(text)})
      } catch (failure) {
        reject(failure)
      }
    })
  })
}

let catalogRefreshedAt = 0

/** 让 chao-cards 的卡库缓存换成 gh 拉到的最新版本（60 秒内不重复拉）。 */
async function refreshCatalog() {
  if (Date.now() - catalogRefreshedAt < 60 * 1000) return
  catalogRefreshedAt = Date.now()
  try {
    const {cards} = await upstream()
    cards.resetCatalogCache?.()
    return await cards.currentCatalog({urls: ['gh://catalog'], fetchImpl: ghCatalogFetch})
  } catch {
    return undefined
  }
}

function sendJson(response, status, body) {
  const text = JSON.stringify(body)
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  })
  response.end(text)
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let size = 0
    const chunks = []
    request.on('data', chunk => {
      size += chunk.length
      if (size > MAX_BODY) {
        reject(new Error('请求体过大'))
        request.destroy()
        return
      }
      chunks.push(chunk)
    })
    request.on('end', () => {
      const text = Buffer.concat(chunks).toString('utf8')
      if (text.trim() === '') return resolve({})
      try {
        resolve(JSON.parse(text))
      } catch (error) {
        reject(new Error(`JSON 解析失败：${error.message}`))
      }
    })
    request.on('error', reject)
  })
}

const asList = value => (Array.isArray(value) ? value : Array.isArray(value?.items) ? value.items : [])

function normalizeKeywords(view) {
  const latest = new Map()
  for (const entry of asList(view)) {
    const normalized = {
      id: entry.id ?? entry.keyword_id ?? entry.definition?.id,
      name: entry.name ?? entry.display_name ?? entry.title ?? entry.id ?? entry.keyword_id,
      version: entry.version ?? entry.latest_version ?? entry.definition?.version ?? 1,
      text: entry.text ?? entry.description ?? entry.rules_text ?? '',
      // 带参数的词条（重甲 X、充能 N、复生 N）把参数表一起给面板，好让玩家填层数。
      parameters: entry.parameters ?? entry.definition?.parameters ?? {},
    }
    if (typeof normalized.id !== 'string' || !normalized.id.includes('.')) continue
    // 同一个 id 只留最高版本，参数上限跟着最新版走（重甲 v1 是 10，v2 是 100）。
    const current = latest.get(normalized.id)
    if (current === undefined || Number(normalized.version) > Number(current.version)) latest.set(normalized.id, normalized)
  }
  return [...latest.values()]
}

function normalizeFactions(view) {
  return asList(view)
    .map(entry => ({id: entry.faction_id ?? entry.id, name: entry.name ?? entry.faction_id ?? entry.id}))
    .filter(entry => typeof entry.id === 'string' && entry.id.length === 36)
    .sort((left, right) => String(left.name).localeCompare(String(right.name), 'zh-Hans-CN'))
}

// ───────────────────────── 更新 ─────────────────────────
// 工坊和制卡插件都以 GitHub Release 的形式发布在巢战仓库里：
// studio-v* 是工坊，plugin-v* 是制卡插件（卡牌规则跟着它走）。
// 「更新」按钮先查最新 tag，再把 tgz 交给 DSH 的 pluginManager 安装。

const STUDIO_PACKAGE = 'dsh-plugin-chao-card-studio'
const REPO = 'xiangwu738-design/Chao'
const RELEASES_URL = `https://api.github.com/repos/${REPO}/releases?per_page=40`
const RELEASE_PAGE = `https://github.com/${REPO}/releases`
const USER_AGENT = `${STUDIO_PACKAGE}-updater`
const RELEASES_TTL = 10 * 60 * 1000

const STUDIO_VERSION = (() => {
  try {
    return JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8')).version ?? '0.0.0'
  } catch {
    return '0.0.0'
  }
})()

const DRAFT_DIR = join(homedir(), '.dsh', 'chao-card-studio')
const DRAFT_FILE = join(DRAFT_DIR, 'draft.json')
const SETTINGS_FILE = join(DRAFT_DIR, 'settings.json')
const PACK_FILE = join(DRAFT_DIR, 'pack.json')
const MAX_PACK_CARDS = 20

function readSettings() {
  try {
    const raw = JSON.parse(readFileSync(SETTINGS_FILE, 'utf8'))
    return {
      autoPublish: raw?.autoPublish === true,
      authors: Array.isArray(raw?.authors)
        ? raw.authors.filter(name => typeof name === 'string' && name.trim() !== '').map(name => name.trim()).slice(0, 8)
        : [],
    }
  } catch {
    return {autoPublish: false, authors: []}
  }
}

/** 记住用过的署名：最近用过的排最前，最多 8 个。 */
function rememberAuthor(author) {
  const value = String(author ?? '').trim()
  if (value === '') return readSettings()
  const current = readSettings()
  const authors = [value, ...current.authors.filter(name => name !== value)].slice(0, 8)
  const settings = {...current, authors}
  mkdirSync(DRAFT_DIR, {recursive: true})
  writeFileSync(SETTINGS_FILE, JSON.stringify(settings))
  return settings
}

/** 本机卡包：新卡校验通过后先收进这里，攒够再一次性提交卡包 PR。 */
function normalizePack(value) {
  const pack = value !== null && typeof value === 'object' ? value : {}
  const cards = Array.isArray(pack.cards) ? pack.cards : []
  return {
    name: typeof pack.name === 'string' ? pack.name.slice(0, 32) : '',
    description: typeof pack.description === 'string' ? pack.description.slice(0, 300) : '',
    cards: cards
      .filter(entry => entry !== null && typeof entry === 'object' && entry.card !== null && typeof entry.card === 'object')
      .slice(0, MAX_PACK_CARDS)
      .map(entry => ({
        card: entry.card,
        ...(entry.replaces !== null && typeof entry.replaces === 'object' ? {replaces: entry.replaces} : {}),
      })),
  }
}

function readPack() {
  try {
    return normalizePack(JSON.parse(readFileSync(PACK_FILE, 'utf8')))
  } catch {
    return {name: '', description: '', cards: []}
  }
}

function writePack(pack) {
  mkdirSync(DRAFT_DIR, {recursive: true})
  writeFileSync(PACK_FILE, JSON.stringify(normalizePack(pack)))
  return readPack()
}

/** 比较版本号：数字段逐段比，带后缀的预发布版本视为更小。 */
function compareVersions(left, right) {
  const parse = value => {
    const text = String(value ?? '').replace(/^v/i, '')
    const [core, suffix] = text.split('-', 2)
    const parts = core.split('.').map(part => Number.parseInt(part, 10) || 0)
    while (parts.length < 3) parts.push(0)
    return {parts, suffix: suffix ?? ''}
  }
  const a = parse(left)
  const b = parse(right)
  for (let index = 0; index < 3; index += 1) {
    if (a.parts[index] !== b.parts[index]) return a.parts[index] < b.parts[index] ? -1 : 1
  }
  if (a.suffix === b.suffix) return 0
  if (a.suffix === '') return 1
  if (b.suffix === '') return -1
  return a.suffix < b.suffix ? -1 : 1
}

// 优先走已登录的 gh（额度 5000/小时），没有 gh 再退回匿名 HTTP（只有 60/小时，容易 403）。
function ghReleases() {
  return new Promise((resolve, reject) => {
    execFile('gh', ['api', RELEASES_URL], {
      timeout: 20000, maxBuffer: 8 * 1024 * 1024, windowsHide: true,
    }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(String(stderr ?? '').trim().slice(0, 200) || error.message))
        return
      }
      try {
        const parsed = JSON.parse(stdout)
        if (!Array.isArray(parsed)) throw new Error('gh 返回的不是数组')
        resolve(parsed)
      } catch (failure) {
        reject(new Error(`gh 输出解析失败：${failure.message}`))
      }
    })
  })
}

let releasesCache
let releasesFailure

async function fetchReleases() {
  if (releasesCache !== undefined && Date.now() - releasesCache.at < RELEASES_TTL) return releasesCache.list
  // 失败也别每次点都打一遍接口，3 分钟内直接复用错误。
  if (releasesFailure !== undefined && Date.now() - releasesFailure.at < 3 * 60 * 1000) throw releasesFailure.error
  try {
    let list
    try {
      list = await ghReleases()
    } catch {
      const response = await fetch(RELEASES_URL, {
        headers: {'user-agent': USER_AGENT, accept: 'application/vnd.github+json'},
        signal: AbortSignal.timeout(15000),
      })
      if (!response.ok) {
        const hint = response.status === 403
          ? '（GitHub 接口限流或拒绝，稍后再试；装好并登录 gh 能提到 5000 次/小时）'
          : ''
        throw new Error(`读取 GitHub Release 失败：HTTP ${response.status}${hint}`)
      }
      const payload = await response.json()
      list = Array.isArray(payload) ? payload : []
    }
    releasesCache = {at: Date.now(), list: list.filter(release => release !== null && !release.draft)}
    releasesFailure = undefined
    return releasesCache.list
  } catch (error) {
    releasesFailure = {at: Date.now(), error}
    throw error
  }
}

/** 同一仓库里按 tag 前缀区分发布，取版本号最大的那条。 */
function pickRelease(list, prefix) {
  let best = null
  for (const release of list) {
    const tag = String(release.tag_name ?? '')
    if (!tag.startsWith(prefix)) continue
    if (best === null || compareVersions(tag.slice(prefix.length), String(best.tag_name).slice(prefix.length)) > 0) best = release
  }
  return best
}

function releaseAsset(release) {
  const asset = (release?.assets ?? []).find(entry => typeof entry.name === 'string' && entry.name.endsWith('.tgz'))
  return asset === undefined ? null : {name: asset.name, url: asset.browser_download_url, size: asset.size ?? 0}
}

/** 在 profile 的 package.json 里找这个包是怎么装的（link 表示本机目录开发安装）。 */
function dependencyOf(packageName) {
  for (const root of profileRoots()) {
    try {
      const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
      const spec = pkg?.dependencies?.[packageName]
      if (typeof spec !== 'string') continue
      return {root, spec, linked: spec.startsWith('link:')}
    } catch {
      // 这个 profile 没有 package.json，看下一个
    }
  }
  return null
}

function installedVersionOf(packageName, fallback) {
  if (packageName === STUDIO_PACKAGE) return STUDIO_VERSION
  for (const root of profileRoots()) {
    try {
      const raw = readFileSync(join(root, 'node_modules', packageName, 'package.json'), 'utf8')
      return JSON.parse(raw).version ?? fallback
    } catch {
      // 没装就继续找
    }
  }
  return fallback
}

/** 当前版本 vs 仓库最新发布；updatable 为 false 时 reason 说明原因。 */
async function updateState() {
  const releases = await fetchReleases()
  const components = [
    {component: 'studio', package: STUDIO_PACKAGE, label: '做卡工坊', prefix: 'studio-v'},
    {component: 'cards', package: UPSTREAM, label: '制卡插件', prefix: 'plugin-v'},
  ].map(entry => {
    const release = pickRelease(releases, entry.prefix)
    const dependency = dependencyOf(entry.package)
    const installed = installedVersionOf(entry.package, '0.0.0')
    const latest = release === null ? null : String(release.tag_name).slice(entry.prefix.length)
    const asset = releaseAsset(release)
    const newer = latest !== null && compareVersions(latest, installed) > 0
    const linked = dependency?.linked === true
    let reason = null
    if (!newer) reason = 'current'
    else if (dependency === null) reason = 'external'
    else if (linked) reason = 'dev-link'
    else if (asset === null) reason = 'no-asset'
    return {
      component: entry.component,
      label: entry.label,
      package: entry.package,
      installed,
      latest,
      newer,
      updatable: reason === null,
      reason,
      asset,
      tag: release?.tag_name ?? null,
      page: release === null ? RELEASE_PAGE : `${RELEASE_PAGE}/tag/${release.tag_name}`,
      publishedAt: release?.published_at ?? null,
    }
  })
  return {ok: true, repo: REPO, checkedAt: new Date().toISOString(), components}
}

/** 下载最新 tgz 到 ~/.dsh/chao-card-studio/updates，再交给插件管理器安装。 */
async function installUpdate(ctx, component) {
  const state = await updateState()
  const target = state.components.find(entry => entry.component === component)
  if (target === undefined) throw new Error(`没有叫 ${component} 的组件`)
  if (!target.newer) throw new Error(`${target.label} 已经是最新版本（${target.installed}）。`)
  if (target.reason === 'dev-link') throw new Error(`${target.label} 是本机目录链接安装，请在目录里覆盖文件或 git pull，不要用自动更新。`)
  if (target.reason === 'external') throw new Error(`没在 profile 的依赖里找到 ${target.package}，只能手动安装。`)
  if (target.asset === null) throw new Error(`${target.latest} 这个版本没有可下载的 tgz。`)
  const manager = ctx.get('pluginManager')
  if (manager === undefined) throw new Error('当前 DSH 没有插件管理服务，无法自动更新。')

  const dir = join(homedir(), '.dsh', 'chao-card-studio', 'updates')
  mkdirSync(dir, {recursive: true})
  const file = join(dir, target.asset.name)
  const response = await fetch(target.asset.url, {
    headers: {'user-agent': USER_AGENT},
    signal: AbortSignal.timeout(120000),
  })
  if (!response.ok) throw new Error(`下载安装包失败：HTTP ${response.status}`)
  writeFileSync(file, Buffer.from(await response.arrayBuffer()))

  const result = await manager.installBundle(file, {enabled: true})
  // 换掉 chao-cards 之后，内存里缓存的旧模块要丢掉，下一次调用才会 import 新版本。
  loaded = undefined
  return {
    ok: result?.application !== 'failed',
    component: target.component,
    label: target.label,
    from: target.installed,
    to: target.latest,
    file,
    application: result?.application ?? 'unknown',
    error: result?.error?.code ?? result?.error?.message ?? null,
  }
}

const ABILITY_INSTRUCTION = `

【本次任务】玩家会用自然语言描述一张卡牌的能力。请把描述编译成这张卡牌的能力与出牌目标，只输出一个 JSON 对象：
{"abilities":[...],"play_target":<对象或 null>}
其中 abilities 是能力数组（形如 [{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]），play_target 在需要选目标时才填写（形如 {"side":"enemy","row":"any"}），否则为 null。
如果卡牌 kind 是 counter，能力触发时机用 "on_reveal"，并且要理解卡牌的 counter_trigger 决定了它何时插入结算。游戏 0.7.0 支持的取值：enemy_unit_deployed（对方部署单位后）、enemy_order_played（对方打出指令时）、enemy_unit_attacked（对方攻击友方单位时）、enemy_hq_attacked（对方攻击己方总部时）、enemy_unit_acted（对方单位主动攻击或移动后）、enemy_unit_moved_to_front（对方单位主动移动到前线后）、enemy_unit_ability_triggered（对方单位能力结算后）、unit_attack_changed（单位攻击力变化时，可带 counter_filter 写阵营/位置/方向）。如果给了 counter_trigger_detail，它说明玩家想要的触发方、触发动作、单位动作、攻击对象、所在位置、单位种类，以及攻击力变化的过滤条件；能用前提条件（premise / event_filter）表达的筛选条件就写进去，表达不了的按最接近的方式写。
只输出这个 JSON 对象本身，不要输出解释、Markdown 或代码围栏。玩家没有描述能力时输出 {"abilities":[],"play_target":null}。
遇到下面两种情况，不要猜、也不要直接说做不到，而是先向玩家提问，只输出 {"ask":"要问玩家的具体问题"}：
1. 描述含糊，几个合理理解会产生不同实现；
2. 现有机制表达不了玩家想要的效果——这时要说明卡在哪里，并问玩家希望怎么折中或替代。
玩家对追问的回答会附在「已知追问」里；回答后如果还缺信息，可以继续 ask。只有信息齐全时才输出 abilities。
如果效果要按阵营筛选（例如「选择一个【暗礁】单位」），用卡牌信息里 factions 的 faction_id：选一个目标就写进 play_target.faction_id，一片单位就写进 unit_filter.faction_id。
需要一次选多个单位（例如「依次选择两个单位」「消灭两个【某阵营】单位」）时，用一条 select_units 效果：{"op":"select_units","side":"ally","min":2,"max":2,"unit_filter":{"faction_id":"…"}}。同组后面用 {"op":"destroy","target":"selected_units"} 处理选中的单位（目前只有 destroy 支持 selected_units），需要按数量结算时用 {"stat":"selected_destroyed_count"}。每组最多一条 select_units，min 不能大于 max。
要生成/召唤卡牌信息 tokens 里的衍生卡时，用其中的 token_id：加入手牌用 {"op":"create_card","token_id":"…","amount":1,"player":"owner"}，直接召唤用 {"op":"summon","token_id":"…","amount":1,"row":"support"}（召唤必须带 row:"support"）。
注意：引擎会把 select_units 的 min 夹到实际候选数（凑不够时仍会继续结算），这是现有规则的限制，不要因此拒绝写卡，按 min/max 如实写即可。`

function parseAbilityReply(text) {
  const trimmed = String(text).trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim()
  const start = trimmed.search(/[[{]/)
  if (start < 0) throw new Error('模型没有返回 JSON')
  const candidate = trimmed.slice(start)
  const end = Math.max(candidate.lastIndexOf(']'), candidate.lastIndexOf('}'))
  const parsed = JSON.parse(candidate.slice(0, end + 1))
  if (Array.isArray(parsed)) return {ok: true, abilities: parsed, playTarget: null}
  if (parsed !== null && typeof parsed === 'object') {
    if (typeof parsed.ask === 'string' && parsed.ask.trim() !== '') {
      return {ok: false, needAnswer: true, question: parsed.ask.trim()}
    }
    if (typeof parsed.unsupported === 'string') {
      return {
        ok: false,
        needAnswer: true,
        question: `现有机制表达不了「${parsed.unsupported}」。你希望怎么折中或替代？`,
      }
    }
    if (Array.isArray(parsed.abilities) || (parsed.abilities !== null && typeof parsed.abilities === 'object')) {
      const abilities = Array.isArray(parsed.abilities) ? parsed.abilities : [parsed.abilities]
      return {ok: true, abilities, playTarget: parsed.play_target ?? null}
    }
  }
  throw new Error('模型返回的不是能力对象')
}

async function generateAbilities(ctx, {description, card, counter, clarifications}) {
  const llm = ctx.get('llm')
  if (llm === undefined) throw new Error('LLM 服务不可用，无法生成能力。')
  const {cards} = await upstream()
  const selection = ctx.get('agentDefaultModel')?.currentSelection?.() ?? {}
  const provider = selection.provider ?? 'deepseek-account'
  const model = selection.model ?? 'deepseek-flash'
  const rules = cards.rulesPage(1)?.text ?? ''
  const system = `${rules}${ABILITY_INSTRUCTION}`
  const factions = await cards.catalogView('factions').catch(() => [])
  const context = {
    name: card?.name, kind: card?.kind, unit_class: card?.unit_class,
    cost: card?.cost, operation_cost: card?.operation_cost,
    attack: card?.attack, health: card?.health,
    counter_trigger: card?.counter_trigger ?? null,
    counter_trigger_detail: counter ?? null,
    keywords: (card?.keywords ?? []).map(entry => entry.id),
    factions: (Array.isArray(factions) ? factions : []).map(entry => ({name: entry.name, faction_id: entry.faction_id})),
    tokens: (Array.isArray(card?.tokens) ? card.tokens : []).map(entry => ({token_id: entry.token_id, name: entry.name, kind: entry.kind})),
  }
  const asked = Array.isArray(clarifications)
    ? clarifications
      .filter(entry => entry !== null && typeof entry === 'object' && typeof entry.answer === 'string' && entry.answer.trim() !== '')
      .slice(-6)
      .map((entry, index) => `追问${index + 1}：${String(entry.question ?? '').trim()}\n玩家回答：${entry.answer.trim()}`)
      .join('\n\n')
    : ''
  const prompt = `卡牌信息：${JSON.stringify(context)}\n\n玩家描述：${description}`
    + (asked === '' ? '' : `\n\n已知追问：\n${asked}`)
  const messages = [{
    role: 'user',
    content: [{type: 'text', text: prompt}],
  }]
  let text = ''
  for await (const chunk of llm.stream({provider, model, system, messages, maxTokens: 2048})) {
    if (chunk.type === 'text-delta') text += chunk.text
    else if (chunk.type === 'finish' && chunk.reason.kind === 'error') {
      throw new Error(chunk.reason.failure?.message ?? '模型调用失败')
    } else if (chunk.type === 'finish' && chunk.reason.kind === 'aborted') {
      throw new Error('模型调用被取消')
    }
  }
  return parseAbilityReply(text)
}

/** 维护者自动发布：等 PR 校验通过 → 合并 → 写进卡库推给所有玩家。 */
async function autoPublish(prNumber) {
  try {
    const review = await loadModule('review.mjs')
    // prStatus 在 github.mjs 里，review.mjs 没有导出它。
    const {github} = await upstream()
    const status = await github.prStatus(prNumber, {wait: true, maxWaitMs: 240000})
    if (status?.validation !== 'ok') {
      return {
        ok: false,
        merged: false,
        pr_number: prNumber,
        validation: status?.validation ?? 'unknown',
        details: status?.details ?? null,
        reason: status?.validation === 'pending'
          ? 'GitHub 校验还没完成，稍后可以用「发布已合并投稿」重试。'
          : 'GitHub 校验没有通过，去看 PR 里的报错。',
      }
    }
    let approved = await review.approvePr(prNumber)
    // GitHub 计算 mergeable 有延迟，刚建好的 PR 直接合并常被拒；非硬性拦截就等几秒重试。
    for (let attempt = 0; attempt < 3 && approved && approved.ok !== true && approved.merged !== true && approved.blocked !== true; attempt += 1) {
      await new Promise(resolve => setTimeout(resolve, 5000))
      approved = await review.approvePr(prNumber)
    }
    // 合并成功但入库失败（常见是网络/接口抖动）时，立刻补一次入库，避免卡停在 inbox。
    if (approved && approved.merged === true && approved.ok !== true) {
      const retry = await review.publishInbox()
      if (retry && retry.ok === true) return {...retry, merged: true, pr_number: prNumber, pr_url: approved.pr_url}
      const extra = retry?.reason ? '；补入库也失败：' + retry.reason : ''
      return {...approved, reason: (approved.reason ?? '') + extra}
    }
    return approved
  } catch (error) {
    return {ok: false, merged: false, pr_number: prNumber, reason: error.message}
  }
}

export function apply(ctx) {
  // 启动时先用 gh 拉一次线上卡库，内置快照过期时也能纠正。
  ctx.effect(() => {
    refreshCatalog().catch(() => {})
  })

  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/health`,
    handler: (request, response) => {
      const roots = profileRoots()
      const probes = []
      for (const root of roots) {
        const file = join(root, 'node_modules', UPSTREAM, 'lib', 'cards.mjs')
        probes.push({root, file, exists: existsSync(file)})
      }
      sendJson(response, 200, {
        ok: true,
        home: homedir(),
        envProfileDir: process.env.DSH_PROFILE_DIR ?? null,
        envProfile: process.env.DSH_PROFILE ?? null,
        roots,
        probes,
      })
    },
  }))

  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/catalog`,
    handler: async (request, response) => {
      if (request.method !== 'GET') return sendJson(response, 405, {ok: false, error: '只支持 GET'})
      try {
        await refreshCatalog()
        const {cards} = await upstream()
        // 阵营刚登记时 chao-cards 的模块级缓存可能还是旧的，这里强制重读一次。
        if (request.url?.includes('refresh=1')) cards.resetCatalogCache?.()
        const [factions, keywords] = await Promise.all([
          cards.catalogView('factions').catch(() => []),
          cards.catalogView('keywords').catch(() => []),
        ])
        sendJson(response, 200, {
          ok: true,
          factions: normalizeFactions(factions),
          keywords: normalizeKeywords(keywords),
        })
      } catch (error) {
        sendJson(response, 500, {ok: false, error: error.message})
      }
    },
  }))

  // 按卡名搜现有卡（衍生卡可以直接复用现成卡的定义）。
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/cards`,
    handler: async (request, response) => {
      if (request.method !== 'GET') return sendJson(response, 405, {ok: false, error: '只支持 GET'})
      try {
        await refreshCatalog()
        const {cards} = await upstream()
        const query = new URL(request.url ?? '/', 'http://localhost').searchParams.get('query') ?? ''
        const view = await cards.catalogView('cards', query)
        sendJson(response, 200, {
          ok: true,
          total: view.total ?? 0,
          cards: (view.cards ?? []).map(entry => ({
            card_id: entry.card_id,
            name: entry.name,
            kind: entry.kind,
            cost: entry.cost,
            author: entry.author ?? '',
            derived: Boolean(entry.derived),
            rules_text: entry.rules_text ?? '',
          })),
        })
      } catch (error) {
        sendJson(response, 200, {ok: false, error: error.message})
      }
    },
  }))

  // 读一张卡的完整定义，用来填衍生卡。
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/card`,
    handler: async (request, response) => {
      if (request.method !== 'GET') return sendJson(response, 405, {ok: false, error: '只支持 GET'})
      try {
        const {cards} = await upstream()
        const id = new URL(request.url ?? '/', 'http://localhost').searchParams.get('id') ?? ''
        if (id === '') return sendJson(response, 200, {ok: false, error: '缺少卡牌 id'})
        const found = await cards.getCard({cardId: id})
        if (!found.ok) {
          return sendJson(response, 200, {
            ok: false,
            error: found.errors?.[0]?.message ?? found.message ?? '读取卡牌失败',
          })
        }
        sendJson(response, 200, {ok: true, card: found.card, name: found.card?.name ?? '', rules_text: found.rules_text ?? ''})
      } catch (error) {
        sendJson(response, 200, {ok: false, error: error.message})
      }
    },
  }))

  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/abilities`,
    handler: async (request, response) => {
      if (request.method !== 'POST') return sendJson(response, 405, {ok: false, error: '只支持 POST'})
      try {
        const body = await readJson(request)
        const description = String(body.description ?? '').trim()
        if (description === '') return sendJson(response, 200, {ok: false, error: '请先写下能力描述。'})
        const result = await generateAbilities(ctx, {
          description,
          card: body.card ?? {},
          counter: body.counter ?? null,
          clarifications: body.clarifications ?? [],
        })
        sendJson(response, 200, result)
      } catch (error) {
        sendJson(response, 200, {ok: false, error: error.message})
      }
    },
  }))

  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/validate`,
    handler: async (request, response) => {
      if (request.method !== 'POST') return sendJson(response, 405, {ok: false, error: '只支持 POST'})
      try {
        const body = await readJson(request)
        const {cards} = await upstream()
        // 改旧卡时把 replaces 一起传进去，校验才会按旧卡的版本和作者判断。
        const result = await cards.validateCard(body.card, body.replaces ? {replaces: body.replaces} : undefined)
        sendJson(response, 200, result)
      } catch (error) {
        sendJson(response, 200, {ok: false, errors: [{path: '', message: error.message}]})
      }
    },
  }))

  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/submit`,
    handler: async (request, response) => {
      if (request.method !== 'POST') return sendJson(response, 405, {ok: false, error: '只支持 POST'})
      try {
        const body = await readJson(request)
        const {github} = await upstream()
        // 0.6.0 起单卡提交也走卡包：一张卡就是一个只有一张的卡包。
        const name = String(body.card?.name ?? '单卡').trim().slice(0, 32) || '单卡'
        const result = await github.submitPack({
          name,
          author: String(body.author ?? '').trim(),
          cards: [{card: body.card, ...(body.replaces ? {replaces: body.replaces} : {})}],
        })
        if (result.ok) rememberAuthor(body.author)
        if (result.ok && body.autoPublish === true) {
          result.publish = await autoPublish(result.pr_number)
        }
        sendJson(response, 200, result)
      } catch (error) {
        sendJson(response, 200, {ok: false, errors: [{path: '', message: error.message}]})
      }
    },
  }))

  // 本机卡包：GET 读取、POST 保存。
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/pack`,
    handler: async (request, response) => {
      if (request.method === 'GET') return sendJson(response, 200, {ok: true, pack: readPack()})
      if (request.method !== 'POST') return sendJson(response, 405, {ok: false, error: '只支持 GET / POST'})
      try {
        const body = await readJson(request)
        sendJson(response, 200, {ok: true, pack: writePack(body?.pack ?? body)})
      } catch (error) {
        sendJson(response, 200, {ok: false, error: error.message})
      }
    },
  }))

  // 提交卡包 PR（一次最多 20 张）。
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/pack/submit`,
    handler: async (request, response) => {
      if (request.method !== 'POST') return sendJson(response, 405, {ok: false, error: '只支持 POST'})
      try {
        const body = await readJson(request)
        const {github} = await upstream()
        const pack = normalizePack(body?.pack)
        if (pack.cards.length === 0) {
          return sendJson(response, 200, {ok: false, errors: [{path: '', message: '卡包里还没有卡。'}]})
        }
        const result = await github.submitPack({
          name: String(body?.name ?? pack.name ?? '').trim() || '未命名卡包',
          author: String(body?.author ?? '').trim(),
          description: String(body?.description ?? pack.description ?? '').trim(),
          cards: pack.cards,
        })
        if (result.ok) rememberAuthor(body?.author)
        if (result.ok && body?.autoPublish === true) {
          result.publish = await autoPublish(result.pr_number)
        }
        sendJson(response, 200, result)
      } catch (error) {
        sendJson(response, 200, {ok: false, errors: [{path: '', message: error.message}]})
      }
    },
  }))

  // 载入已有卡（改旧卡用）。
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/load`,
    handler: async (request, response) => {
      if (request.method !== 'GET') return sendJson(response, 405, {ok: false, error: '只支持 GET'})
      try {
        await refreshCatalog()
        const {cards} = await upstream()
        const url = new URL(request.url ?? '/', 'http://localhost')
        const id = url.searchParams.get('id') ?? ''
        const query = url.searchParams.get('query') ?? ''
        const found = await cards.getCard(id !== '' ? {cardId: id} : {name: query})
        if (!found.ok) {
          return sendJson(response, 200, {
            ok: false,
            needChoice: found.need_choice === true,
            matches: found.matches ?? [],
            error: found.errors?.[0]?.message ?? found.message ?? '没有找到这张卡。',
          })
        }
        sendJson(response, 200, {
          ok: true,
          card: found.card,
          replaces: found.replaces,
          name: found.card?.name ?? '',
          rules_text: found.rules_text ?? '',
        })
      } catch (error) {
        sendJson(response, 200, {ok: false, error: error.message})
      }
    },
  }))

  // 面板设置：目前只有「提交后自动合并并发布」。
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/settings`,
    handler: async (request, response) => {
      if (request.method === 'GET') return sendJson(response, 200, {ok: true, settings: readSettings()})
      if (request.method !== 'POST') return sendJson(response, 405, {ok: false, error: '只支持 GET / POST'})
      try {
        const body = await readJson(request)
        const current = readSettings()
        const settings = {
          autoPublish: body?.autoPublish === undefined ? current.autoPublish : body.autoPublish === true,
          authors: Array.isArray(body?.authors)
            ? [...new Set([...body.authors.filter(name => typeof name === 'string' && name.trim() !== '').map(name => name.trim()), ...current.authors])].slice(0, 8)
            : current.authors,
        }
        mkdirSync(DRAFT_DIR, {recursive: true})
        writeFileSync(SETTINGS_FILE, JSON.stringify(settings))
        sendJson(response, 200, {ok: true, settings})
      } catch (error) {
        sendJson(response, 200, {ok: false, error: error.message})
      }
    },
  }))

  // 版本检查：面板打开时顺带查一次，点「更新」时再查一次。
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/version`,
    handler: async (request, response) => {
      if (request.method !== 'GET') return sendJson(response, 405, {ok: false, error: '只支持 GET'})
      try {
        sendJson(response, 200, await updateState())
      } catch (error) {
        sendJson(response, 200, {ok: false, error: error.message})
      }
    },
  }))

  // 更新：下载最新 tgz，交给 pluginManager 安装；安装工坊自己时会重载本插件。
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/update`,
    handler: async (request, response) => {
      if (request.method !== 'POST') return sendJson(response, 405, {ok: false, error: '只支持 POST'})
      try {
        const body = await readJson(request)
        sendJson(response, 200, await installUpdate(ctx, String(body.component ?? 'studio')))
      } catch (error) {
        sendJson(response, 200, {ok: false, error: error.message})
      }
    },
  }))

  // 草稿：离开面板时把填了一半的表单留在 ~/.dsh/chao-card-studio/draft.json，
  // 下次打开自动恢复。放在本机而不是浏览器里，换端口、重启应用都还在。
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/draft`,
    handler: async (request, response) => {
      if (request.method === 'GET') {
        try {
          const draft = JSON.parse(readFileSync(DRAFT_FILE, 'utf8'))
          sendJson(response, 200, {ok: true, draft: draft === null || typeof draft !== 'object' ? null : draft})
        } catch {
          sendJson(response, 200, {ok: true, draft: null})
        }
        return
      }
      if (request.method !== 'POST') return sendJson(response, 405, {ok: false, error: '只支持 GET / POST'})
      try {
        const body = await readJson(request)
        if (body?.draft === null || body?.draft === undefined) {
          rmSync(DRAFT_FILE, {force: true})
          sendJson(response, 200, {ok: true, cleared: true})
          return
        }
        mkdirSync(DRAFT_DIR, {recursive: true})
        writeFileSync(DRAFT_FILE, JSON.stringify(body.draft))
        sendJson(response, 200, {ok: true, saved: true})
      } catch (error) {
        sendJson(response, 200, {ok: false, error: error.message})
      }
    },
  }))
}
