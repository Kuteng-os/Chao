/**
 * 做卡工坊的 Host 半边：把 chao-cards 插件的校验 / 提交能力挂成同源 HTTP 接口，
 * 供右侧栏面板直接调用。卡片逻辑全部复用 chao-cards，本插件不重复实现规则。
 */
import {existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs'
import {homedir} from 'node:os'
import {join} from 'node:path'
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
  const seen = new Set()
  const list = []
  for (const entry of asList(view)) {
    const normalized = {
      id: entry.id ?? entry.keyword_id ?? entry.definition?.id,
      name: entry.name ?? entry.display_name ?? entry.title ?? entry.id ?? entry.keyword_id,
      version: entry.version ?? entry.latest_version ?? entry.definition?.version ?? 1,
      text: entry.text ?? entry.description ?? entry.rules_text ?? '',
    }
    if (typeof normalized.id !== 'string' || !normalized.id.includes('.')) continue
    // 目录里同一词条可能重复出现（同 id 或多条同名自定义词条），只保留第一条。
    const key = `${normalized.id}\u0000${normalized.name}`
    if (seen.has(key)) continue
    seen.add(key)
    list.push(normalized)
  }
  return list
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

let releasesCache

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

async function fetchReleases() {
  if (releasesCache !== undefined && Date.now() - releasesCache.at < RELEASES_TTL) return releasesCache.list
  const response = await fetch(RELEASES_URL, {
    headers: {'user-agent': USER_AGENT, accept: 'application/vnd.github+json'},
    signal: AbortSignal.timeout(15000),
  })
  if (!response.ok) throw new Error(`读取 GitHub Release 失败：HTTP ${response.status}`)
  const payload = await response.json()
  const list = Array.isArray(payload) ? payload.filter(release => release !== null && !release.draft) : []
  releasesCache = {at: Date.now(), list}
  return list
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
如果卡牌 kind 是 counter，能力触发时机用 "on_reveal"，并且要理解卡牌的 counter_trigger 决定了它何时插入结算（敌方部署单位 / 使用指令 / 单位攻击 / 攻击总部）。
只输出这个 JSON 对象本身，不要输出解释、Markdown 或代码围栏。玩家没有描述能力时输出 {"abilities":[],"play_target":null}。描述超出上述 DSL 能力时，只输出 {"unsupported":"具体不支持的部分"}。`

function parseAbilityReply(text) {
  const trimmed = String(text).trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim()
  const start = trimmed.search(/[[{]/)
  if (start < 0) throw new Error('模型没有返回 JSON')
  const candidate = trimmed.slice(start)
  const end = Math.max(candidate.lastIndexOf(']'), candidate.lastIndexOf('}'))
  const parsed = JSON.parse(candidate.slice(0, end + 1))
  if (Array.isArray(parsed)) return {ok: true, abilities: parsed, playTarget: null}
  if (parsed !== null && typeof parsed === 'object') {
    if (typeof parsed.unsupported === 'string') {
      return {ok: false, error: `这个描述里有 DSL 不支持的部分：${parsed.unsupported}`}
    }
    if (Array.isArray(parsed.abilities)) {
      return {ok: true, abilities: parsed.abilities, playTarget: parsed.play_target ?? null}
    }
  }
  throw new Error('模型返回的不是能力对象')
}

async function generateAbilities(ctx, {description, card}) {
  const llm = ctx.get('llm')
  if (llm === undefined) throw new Error('LLM 服务不可用，无法生成能力。')
  const {cards} = await upstream()
  const selection = ctx.get('agentDefaultModel')?.currentSelection?.() ?? {}
  const provider = selection.provider ?? 'deepseek-account'
  const model = selection.model ?? 'deepseek-flash'
  const rules = cards.rulesPage(1)?.text ?? ''
  const system = `${rules}${ABILITY_INSTRUCTION}`
  const context = {
    name: card?.name, kind: card?.kind, unit_class: card?.unit_class,
    cost: card?.cost, operation_cost: card?.operation_cost,
    attack: card?.attack, health: card?.health,
    counter_trigger: card?.counter_trigger ?? null,
    keywords: (card?.keywords ?? []).map(entry => entry.id),
  }
  const messages = [{
    role: 'user',
    content: [{type: 'text', text: `卡牌信息：${JSON.stringify(context)}\n\n玩家描述：${description}`}],
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

export function apply(ctx) {
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

  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: `${PREFIX}/abilities`,
    handler: async (request, response) => {
      if (request.method !== 'POST') return sendJson(response, 405, {ok: false, error: '只支持 POST'})
      try {
        const body = await readJson(request)
        const description = String(body.description ?? '').trim()
        if (description === '') return sendJson(response, 200, {ok: false, error: '请先写下能力描述。'})
        const result = await generateAbilities(ctx, {description, card: body.card ?? {}})
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
        const result = await cards.validateCard(body.card)
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
        const result = await github.submitPr(body.card, body.author)
        sendJson(response, 200, result)
      } catch (error) {
        sendJson(response, 200, {ok: false, errors: [{path: '', message: error.message}]})
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
