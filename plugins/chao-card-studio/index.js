/**
 * 做卡工坊的 Host 半边：把 chao-cards 插件的校验 / 提交能力挂成同源 HTTP 接口，
 * 供右侧栏面板直接调用。卡片逻辑全部复用 chao-cards，本插件不重复实现规则。
 */
import {existsSync, readdirSync} from 'node:fs'
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

const ABILITY_INSTRUCTION = `

【本次任务】玩家会用自然语言描述一张卡牌的能力。请把描述编译成这张卡牌的能力与出牌目标，只输出一个 JSON 对象：
{"abilities":[...],"play_target":<对象或 null>}
其中 abilities 是能力数组（形如 [{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]），play_target 在需要选目标时才填写（形如 {"side":"enemy","row":"any"}），否则为 null。
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
}
