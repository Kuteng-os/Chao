window.__ModuleLoader__.load({
  id: 'dsh-plugin-chao-card-studio',
  factory(require) {
    const React = require('react')
    const h = React.createElement

    const PANEL_ID = 'chao-card-studio'
    const API = '/chao-card-studio/api'

    const TEXT = {
      zh: {
        title: '做卡工坊',
        subtitle: '填表 → 写能力 → 校验 → 提交 PR',
        name: '卡牌名称', author: '署名',
        kind: '卡牌类型', unitClass: '兵种',
        cost: '部署费用', operationCost: '行动费用',
        attack: '攻击力', health: '防御力',
        rarity: '稀有度', faction: '阵营', sin: '罪孽',
        counterSide: '触发方', counterAction: '触发动作',
        counterRow: '所在位置', counterClass: '单位种类', counterUnitAction: '单位动作',
        counterAttackTarget: '攻击对象',
        counterHint: '组合出反制插入结算的时机。',
        counterMaps: label => `提交为「${label}」`,
        counterUnsupported: '当前游戏数据只支持 4 种反制触发：敌方部署单位 / 敌方使用指令 / 敌方单位攻击 / 敌方攻击总部。请调整触发方、触发动作或触发对象。',
        counterFilterHint: '位置 / 单位种类 / 单位动作会写进触发说明，卡牌字段里暂时没有对应项。',
        flavor: '风味文本', displayText: '卡面文本（可选）',
        keywords: '词条', builtin: '内置', custom: '自定义', keywordStack: '层数',
        abilities: '能力描述',
        abilitiesHint: '用中文写清什么时候、对谁、做什么，比如“部署时对所选敌方单位造成2点伤害”。我来编译成规则。',
        gen: '生成能力', generating: '生成中…', generated: '已生成规则，校验时会提交它', generatedShort: '已生成',
        clearAbilities: '清空能力',
        validate: '校验', submit: '校验并提交 PR', reset: '重置',
        idle: '填好字段后点“校验”。', pending: '待校验', working: '处理中…',
        valid: '校验通过', invalid: '校验未通过',
        submitted: '已创建 PR', failed: '提交失败',
        rules: '规则文本', errors: '问题', hash: '指纹',
        open: '打开 PR', needName: '请填写卡牌名称。', needAuthor: '请填写署名（1–64 字）。',
        needAbility: '先写下能力描述。',
        keywordHint: '选中即引用已登记版本，参数保持默认。',
        none: '（不选）', loading: '正在读取阵营与词条…',
        sectionBasic: '基本信息', sectionStats: '数值', sectionText: '文本', sectionKeywords: '词条', sectionAbilities: '能力',
        generatedDetails: '查看生成的规则 JSON',
        clarifyTitle: '模型想问清楚', clarifyHint: '生成能力时，描述含糊或现有机制做不到，模型会先向你追问，回答后继续生成。',
        clarifyPlaceholder: '写清楚你希望的效果，或希望怎么折中…', clarifySend: '回答并继续', clarifyCancel: '先不回答',
        clarifyRounds: count => `已经追问并回答 ${count} 轮`,
        cardPreview: '卡面文本', selectedCount: count => `已选 ${count} 个词条`,
        updateCheck: '检查更新', updateChecking: '检查中…', updateCurrent: '已是最新',
        updateTo: version => `更新到 ${version}`, updateMany: count => `更新 ${count} 项`,
        updateManual: version => `有新版 ${version}`, updateApplying: '更新中…', updateDone: '已更新',
        updateFailed: '更新失败', updateDevHint: '本机目录链接安装，更新请覆盖目录或 git pull',
        updateExternal: '外部安装，只能手动更新', updateReady: '可更新', updateNoAsset: '这个版本没有安装包',
        updateDoneReload: '更新完成，面板会重新加载',
      },
      en: {
        title: 'Card studio',
        subtitle: 'Fill → describe abilities → validate → open PR',
        name: 'Card name', author: 'Author',
        kind: 'Card kind', unitClass: 'Unit class',
        cost: 'Deploy cost', operationCost: 'Action cost',
        attack: 'Attack', health: 'Defense',
        rarity: 'Rarity', faction: 'Faction', sin: 'Sin',
        counterSide: 'Side', counterAction: 'Action',
        counterRow: 'Row', counterClass: 'Unit class', counterUnitAction: 'Unit action',
        counterAttackTarget: 'Attack target',
        counterHint: 'Compose when the counter resolves.',
        counterMaps: label => `Submits as "${label}"`,
        counterUnsupported: 'The game data supports only 4 counter triggers: enemy unit deployed / enemy order played / enemy unit attacked / enemy HQ attacked.',
        counterFilterHint: 'Row / class / unit action are passed to ability generation; the card schema has no fields for them yet.',
        flavor: 'Flavor text', displayText: 'Card-face text (optional)',
        keywords: 'Keywords', builtin: 'Built-in', custom: 'Custom', keywordStack: 'Stacks',
        abilities: 'Ability description',
        abilitiesHint: 'Describe when, whom and what in plain words; the rules are compiled for you.',
        gen: 'Generate abilities', generating: 'Generating…', generated: 'Rules generated; they are submitted with validation', generatedShort: 'Generated',
        clearAbilities: 'Clear abilities',
        validate: 'Validate', submit: 'Validate and submit PR', reset: 'Reset',
        idle: 'Fill the fields, then validate.', pending: 'Not validated', working: 'Working…',
        valid: 'Validation passed', invalid: 'Validation failed',
        submitted: 'Pull request created', failed: 'Submit failed',
        rules: 'Rules text', errors: 'Problems', hash: 'Fingerprint',
        open: 'Open PR', needName: 'Card name is required.', needAuthor: 'Author must be 1–64 characters.',
        needAbility: 'Describe the ability first.',
        keywordHint: 'Registered versions are attached automatically.',
        none: '(none)', loading: 'Loading factions and keywords…',
        sectionBasic: 'Basics', sectionStats: 'Stats', sectionText: 'Text', sectionKeywords: 'Keywords', sectionAbilities: 'Abilities',
        generatedDetails: 'Show generated rules JSON',
        clarifyTitle: 'Needs your input', clarifyHint: 'When the description is ambiguous or the engine cannot express it, the model asks you first.',
        clarifyPlaceholder: 'Describe what you want, or how to approximate…', clarifySend: 'Answer and continue', clarifyCancel: 'Skip',
        clarifyRounds: count => `${count} round(s) answered`,
        cardPreview: 'Card-face text', selectedCount: count => `${count} keyword(s) selected`,
        updateCheck: 'Check updates', updateChecking: 'Checking…', updateCurrent: 'Up to date',
        updateTo: version => `Update to ${version}`, updateMany: count => `Update ${count} items`,
        updateManual: version => `New ${version}`, updateApplying: 'Updating…', updateDone: 'Updated',
        updateFailed: 'Update failed', updateDevHint: 'Linked dev install; overwrite the folder or git pull',
        updateExternal: 'External install; update manually', updateReady: 'Update available', updateNoAsset: 'No package in this release',
        updateDoneReload: 'Updated; the panel reloads itself',
      },
    }

    const KINDS = [
      ['unit', '单位'], ['order', '指令'], ['counter', '反制'], ['field', '场地'], ['hq', '总部'],
    ]
    const RARITIES = [['standard', '普通'], ['limited', '受限'], ['special', '特殊'], ['elite', '精英']]
    const CLASSES = [['infantry', '步兵'], ['tank', '坦克'], ['artillery', '炮兵'], ['fighter', '战斗机'], ['bomber', '轰炸机']]
    const SINS = [['', '无罪孽'], ['wrath', '暴怒'], ['lust', '色欲'], ['sloth', '怠惰'], ['gluttony', '暴食'], ['gloom', '忧郁'], ['pride', '傲慢'], ['envy', '嫉妒']]
    // 反制的触发方式由几部分组成，最后折算成卡牌的 counter_trigger。
    // 目前游戏数据只认 4 个值（见 COUNTER_SUPPORTED），组合不上的会给出提示。
    const COUNTER_SIDES = [['enemy', '敌方'], ['ally', '我方']]
    const COUNTER_ACTIONS = [
      ['deploy_unit', '部署单位'], ['use_unit', '使用单位'],
      ['play_order', '使用指令'], ['place_counter', '放置反制'],
    ]
    const COUNTER_ROWS = [['any', '任意'], ['front', '前线'], ['support', '支援阵线']]
    const COUNTER_CLASSES = [
      ['any', '任意'], ['infantry', '步兵'], ['tank', '坦克'], ['artillery', '炮兵'],
      ['fighter', '战斗机'], ['bomber', '轰炸机'],
    ]
    const COUNTER_UNIT_ACTIONS = [['any', '任意'], ['attack', '攻击'], ['act', '行动'], ['move', '移动']]
    const COUNTER_ATTACK_TARGETS = [['unit', '单位'], ['hq', '总部'], ['any', '任意']]
    const COUNTER_SUPPORTED = [
      ['enemy_unit_deployed', '敌方部署单位'],
      ['enemy_order_played', '敌方使用指令'],
      ['enemy_unit_attacked', '敌方单位攻击'],
      ['enemy_hq_attacked', '敌方攻击总部'],
    ]

    /** 把触发方的几段选择折算成游戏认识的 counter_trigger，组合不支持时返回 null。 */
    function counterTriggerOf(form) {
      if (form.kind !== 'counter') return null
      const {counterSide, counterAction, counterUnitAction, counterAttackTarget} = form
      if (counterSide !== 'enemy') return null
      if (counterAction === 'deploy_unit') return 'enemy_unit_deployed'
      if (counterAction === 'play_order') return 'enemy_order_played'
      if (counterAction === 'use_unit' && counterUnitAction === 'attack') {
        if (counterAttackTarget === 'hq') return 'enemy_hq_attacked'
        if (counterAttackTarget === 'unit') return 'enemy_unit_attacked'
        // 「任意」现在没法同时表达打单位和打总部，等游戏支持结构化触发再说。
        return null
      }
      return null
    }

    /** 旧草稿里只存了一个 counterTrigger，读回来时还原成几段选择。 */
    function legacyCounterParts(trigger) {
      if (trigger === 'enemy_order_played') return {counterAction: 'play_order'}
      if (trigger === 'enemy_unit_attacked') return {counterAction: 'use_unit', counterUnitAction: 'attack', counterAttackTarget: 'unit'}
      if (trigger === 'enemy_hq_attacked') return {counterAction: 'use_unit', counterUnitAction: 'attack', counterAttackTarget: 'hq'}
      return {counterAction: 'deploy_unit'}
    }

    /** 前几版草稿的字段换成现在的几段选择。 */
    function migrateCounterDraft(draft) {
      const action = draft.counterAction
      if (action === 'unit_action') {
        return {
          counterAction: 'use_unit', counterUnitAction: 'attack',
          counterAttackTarget: draft.counterTarget === 'hq' ? 'hq' : 'unit',
        }
      }
      if (action === 'deploy_unit') return {counterAction: 'deploy_unit'}
      if (action === 'use_unit') {
        if (draft.counterUnitAction === 'attack_hq') return {counterAction: 'use_unit', counterUnitAction: 'attack', counterAttackTarget: 'hq'}
        if (draft.counterUnitAction === 'attack') return {counterAction: 'use_unit', counterUnitAction: 'attack', counterAttackTarget: 'unit'}
        // 上一版里「使用单位 + 任意」其实等于部署，挪回部署单位。
        if (draft.counterUnitAction === 'any') return {counterAction: 'deploy_unit'}
      }
      return {}
    }

    /** 给「生成能力」用的触发说明：模型据此写 on_reveal 的前提条件。 */
    function counterPartsOf(form) {
      const label = (list, value) => (list.find(([key]) => key === value) ?? [null, value])[1]
      return {
        side: label(COUNTER_SIDES, form.counterSide),
        action: label(COUNTER_ACTIONS, form.counterAction),
        row: label(COUNTER_ROWS, form.counterRow),
        unit_class: label(COUNTER_CLASSES, form.counterClass),
        unit_action: label(COUNTER_UNIT_ACTIONS, form.counterUnitAction),
        attack_target: label(COUNTER_ATTACK_TARGETS, form.counterAttackTarget),
        counter_trigger: counterTriggerOf(form),
      }
    }

    const INITIAL = {
      name: '', author: '', kind: 'unit', unitClass: 'infantry',
      cost: 1, operationCost: 1, attack: 1, health: 1,
      rarity: 'standard', faction: '', sin: '', flavor: '', displayText: '',
      keywords: [], abilityText: '', abilities: '[]', playTarget: 'null',
      keywordParams: {},
      counterSide: 'enemy', counterAction: 'deploy_unit', counterUnitAction: 'any',
      counterAttackTarget: 'unit', counterRow: 'any', counterClass: 'any',
    }

    function pickText() {
      const lang = navigator.language || 'zh'
      return lang.toLowerCase().startsWith('en') ? TEXT.en : TEXT.zh
    }

    const t = pickText()

    // 窄窗口适配：inline style 没法写媒体查询，这里用类名补几条。
    const STYLE = [
      '.ccs-card,.ccs-card *{box-sizing:border-box}',
      '.ccs-body{scrollbar-gutter:stable}',
      '.ccs-ellipsis{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
      '.ccs-error{overflow-wrap:anywhere}',
      '@media (max-width:640px){',
      '.ccs-header{padding:10px 12px;gap:8px}',
      '.ccs-body{padding:14px 12px 16px;gap:18px}',
      '.ccs-footer{padding:10px 12px 12px}',
      '.ccs-grid{grid-template-columns:minmax(0,1fr)!important;gap:10px}',
      '}',
      '@media (max-width:420px){',
      '.ccs-brand{display:none}',
      '}',
    ].join('')

    // 只使用主题 token（--dsw-alias-*），并给每个 token 一个可读的兜底值，
    // 这样在深色 / 浅色主题、以及壁纸透明面板上都不会出现“白字贴在亮背景上”。
    // 强调色与状态色用固定值：部分壁纸主题会把 brand-primary 覆盖成白色，
    // 跟着 token 走会出现“白底白字”的按钮。
    const C = {
      text: 'var(--dsw-alias-label-primary, #e9edf3)',
      dim: 'var(--dsw-alias-label-secondary, rgba(233,237,243,.74))',
      faint: 'var(--dsw-alias-label-tertiary, rgba(233,237,243,.52))',
      line: 'var(--dsw-alias-border-l1, rgba(148,163,184,.28))',
      lineStrong: 'var(--dsw-alias-border-l2, rgba(148,163,184,.46))',
      accent: '#3f8ee6',
      ok: '#35b06a',
      bad: '#e0605c',
      warn: '#d9a03b',
      surface: 'var(--dsw-alias-bg-overlay, #161b24)',
      surface2: 'var(--dsw-alias-bg-layer-2, rgba(148,163,184,.12))',
    }

    // 半透明毛玻璃面板：壁纸仍然可见，但文字始终落在稳定的底色上。
    // 用 overlay token（浮层底色）而不是 layer-1，避免壁纸主题把底色做成半透明后
    // 表单文字落在亮色壁纸上。
    const glass = color => `color-mix(in srgb, ${color} 94%, transparent)`

    const styles = {
      root: {
        height: '100%', minHeight: 0, boxSizing: 'border-box',
        padding: '12px 18px 16px', display: 'flex', justifyContent: 'center',
        overflow: 'hidden', color: C.text,
      },
      card: {
        width: '100%', maxWidth: 940, height: '100%', minHeight: 0,
        display: 'flex', flexDirection: 'column', overflow: 'hidden',
        borderRadius: 16, border: `1px solid ${C.line}`,
        backgroundColor: C.surface,
        background: glass(C.surface),
        backdropFilter: 'blur(18px) saturate(125%)',
        WebkitBackdropFilter: 'blur(18px) saturate(125%)',
        boxShadow: '0 18px 60px rgba(0,0,0,.34)',
      },
      header: {
        flex: 'none', display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', rowGap: 8,
        padding: '14px 20px', borderBottom: `1px solid ${C.line}`,
      },
      brand: {
        flex: 'none', width: 34, height: 34, borderRadius: 10,
        display: 'grid', placeItems: 'center',
        border: `1px solid ${C.line}`, background: C.surface2,
      },
      title: {fontSize: 15, fontWeight: 600, letterSpacing: 0.2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap'},
      subtitle: {fontSize: 11.5, color: C.dim, marginTop: 3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap'},
      titleBox: {minWidth: 0, flex: '1 1 140px'},
      pill: color => ({
        flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 6,
        padding: '5px 11px', borderRadius: 999, fontSize: 11.5, lineHeight: 1,
        color, border: `1px solid ${color}`, background: 'transparent', whiteSpace: 'nowrap',
      }),
      updateBtn: tone => {
        const filled = tone === 'accent' || tone === 'warn'
        return {
          marginLeft: 'auto', flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 6,
          padding: '5px 12px', borderRadius: 999, fontSize: 11.5, lineHeight: 1, fontFamily: 'inherit',
          whiteSpace: 'nowrap', cursor: 'pointer',
          border: `1px solid ${filled ? 'transparent' : C.line}`,
          background: tone === 'accent' ? C.accent : tone === 'warn' ? C.warn : C.surface2,
          color: filled ? '#fff' : C.dim,
        }
      },
      updateDot: color => ({width: 5, height: 5, borderRadius: 999, background: color, flex: 'none'}),
      dot: color => ({width: 6, height: 6, borderRadius: 999, background: color, flex: 'none'}),
      body: {
        flex: 1, minHeight: 0, overflowY: 'auto', overscrollBehavior: 'contain',
        padding: '18px 20px 22px', display: 'flex', flexDirection: 'column', gap: 22,
      },
      sectionTitle: {
        fontSize: 11.5, fontWeight: 600, letterSpacing: 0.8, textTransform: 'uppercase',
        color: C.dim, marginBottom: 10, display: 'flex', alignItems: 'center', gap: 8,
      },
      grid: {
        display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
        gap: '12px 14px', alignItems: 'start',
      },
      label: {fontSize: 11.5, color: C.dim, marginBottom: 6, display: 'flex', alignItems: 'center', gap: 6},
      hint: {fontSize: 11, color: C.faint, lineHeight: 1.65, marginBottom: 8},
      input: {
        width: '100%', boxSizing: 'border-box', height: 34, padding: '0 10px',
        fontSize: 13, fontFamily: 'inherit', color: 'inherit',
        borderRadius: 9, border: `1px solid ${C.lineStrong}`, background: C.surface2,
        outlineOffset: 2,
      },
      textarea: {
        width: '100%', boxSizing: 'border-box', minHeight: 68, padding: '8px 10px',
        fontSize: 13, fontFamily: 'inherit', color: 'inherit', lineHeight: 1.65,
        borderRadius: 9, border: `1px solid ${C.lineStrong}`, background: C.surface2,
        resize: 'vertical', outlineOffset: 2,
      },
      chip: active => ({
        padding: '4px 10px', fontSize: 12, lineHeight: 1.5, borderRadius: 999, cursor: 'pointer',
        fontFamily: 'inherit', whiteSpace: 'nowrap',
        border: `1px solid ${active ? 'transparent' : C.lineStrong}`,
        background: active ? C.accent : 'transparent',
        color: active ? '#fff' : 'inherit',
      }),
      button: primary => ({
        padding: '7px 16px', minHeight: 34, fontSize: 13, fontFamily: 'inherit',
        borderRadius: 9, cursor: 'pointer', whiteSpace: 'nowrap', fontWeight: primary ? 500 : 400,
        border: `1px solid ${primary ? 'transparent' : C.lineStrong}`,
        background: primary ? C.accent : C.surface2,
        color: primary ? '#fff' : 'inherit',
      }),
      ghost: {padding: '7px 14px', minHeight: 34, fontSize: 13, fontFamily: 'inherit', borderRadius: 9,
        cursor: 'pointer', border: '1px solid transparent', background: 'transparent', color: 'inherit', opacity: 0.72},
      chipWrap: {display: 'flex', flexWrap: 'wrap', gap: 7},
      groupLabel: {fontSize: 11, color: C.faint, margin: '2px 0 7px'},
      footer: {
        flex: 'none', display: 'flex', flexDirection: 'column', gap: 10,
        padding: '12px 20px 14px', borderTop: `1px solid ${C.line}`,
        backgroundColor: C.surface, background: glass(C.surface),
      },
      actions: {display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap'},
      result: {fontSize: 12, lineHeight: 1.7, display: 'flex', flexDirection: 'column', gap: 6},
      resultHead: color => ({color, fontWeight: 600}),
      errorLine: {color: C.dim, display: 'flex', gap: 7, overflowWrap: 'anywhere', minWidth: 0},
      scrollBox: {
        maxHeight: 132, overflow: 'auto', whiteSpace: 'pre-wrap', wordBreak: 'break-word',
        fontSize: 12, lineHeight: 1.65, color: C.dim,
        background: C.surface2, borderRadius: 9, padding: '8px 10px', border: `1px solid ${C.line}`,
      },
      mono: {fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', fontSize: 11, color: C.faint},
      details: {border: `1px solid ${C.line}`, borderRadius: 9, padding: '8px 10px', background: C.surface2},
      summary: {fontSize: 11.5, color: C.dim, cursor: 'pointer'},
    }

    const num = value => {
      const parsed = Number(value)
      return Number.isFinite(parsed) ? Math.trunc(parsed) : 0
    }

    function buildCard(form, keywordIndex) {
      // 非单位卡牌没有行动费用、攻击力和防御力，卡库里这类卡这三个值都是 0；
      // 唯一例外是总部（hq），它有防御力（总部血量）。
      const isUnit = form.kind === 'unit'
      const hasHealth = isUnit || form.kind === 'hq'
      const card = {
        schema_version: '1.0.0',
        ruleset_version: 'frontline-1',
        name: form.name.trim(),
        flavor_text: form.flavor,
        kind: form.kind,
        unit_class: isUnit ? form.unitClass : null,
        cost: num(form.cost),
        operation_cost: isUnit ? num(form.operationCost) : 0,
        attack: isUnit ? num(form.attack) : 0,
        health: hasHealth ? num(form.health) : 0,
        keywords: form.keywords.map(id => ({id, version: keywordIndex.get(id) ?? 1, params: form.keywordParams?.[id] ?? {}})),
        play_target: JSON.parse(form.playTarget.trim() === '' ? 'null' : form.playTarget),
        abilities: [],
        tokens: [],
        appearance: {emblem: form.kind === 'unit' ? form.unitClass : form.kind},
        rarity: form.rarity,
        sin: form.sin === '' ? null : form.sin,
      }
      if (form.faction !== '') card.faction_id = form.faction
      if (form.displayText.trim() !== '') card.display_text = form.displayText
      // 反制牌的触发方式只在反制卡上出现，其他类型不带这个字段。
      if (form.kind === 'counter') card.counter_trigger = counterTriggerOf(form)
      const raw = form.abilities.trim()
      if (raw !== '' && raw !== '[]') {
        const parsed = JSON.parse(raw)
        if (!Array.isArray(parsed)) throw new Error('能力数据格式不对，请重新生成。')
        card.abilities = parsed
      }
      return card
    }

    function Field(props) {
      return h('div', {style: {minWidth: 0}},
        h('label', {style: styles.label}, props.label),
        props.children,
        props.hint ? h('div', {style: {fontSize: 11, color: C.faint, marginTop: 5}}, props.hint) : null)
    }

    function Section({title, children, aside}) {
      return h('section', null,
        h('div', {style: styles.sectionTitle},
          h('span', null, title),
          aside ?? null),
        children)
    }

    function StatusPill({kind}) {
      const map = {
        working: [t.working, C.warn],
        valid: [t.valid, C.ok],
        generated: [t.generatedShort, C.accent],
        invalid: [t.invalid, C.bad],
        submitted: [t.submitted, C.ok],
        failed: [t.failed, C.bad],
      }
      const [label, color] = map[kind] ?? [t.pending, C.faint]
      return h('span', {style: styles.pill(color)},
        h('span', {style: styles.dot(color)}),
        label)
    }

    function ResultBlock({result, t}) {
      if (result.kind === 'idle') return h('div', {style: {fontSize: 12, color: C.faint}}, t.idle)
      if (result.kind === 'working') return h('div', {style: {fontSize: 12, color: C.warn}}, t.working)

      if (result.kind === 'valid') {
        return h('div', {style: styles.result},
          h('div', {style: styles.resultHead(C.ok)}, t.valid),
          result.rules ? h('div', {style: styles.scrollBox}, result.rules) : null,
          result.hash ? h('div', {style: styles.mono}, `${t.hash} ${String(result.hash).slice(0, 12)}`) : null)
      }

      if (result.kind === 'invalid' || result.kind === 'failed') {
        const errors = result.errors ?? []
        return h('div', {style: styles.result},
          h('div', {style: styles.resultHead(C.bad)}, result.kind === 'invalid' ? t.invalid : t.failed),
          ...errors.slice(0, 6).map((error, index) => h('div', {key: index, style: styles.errorLine},
            h('span', {style: {color: C.bad, flex: 'none'}}, '•'),
            h('span', null, (error.path ? `${error.path}：` : '') + (error.message ?? '')))),
          result.link ? h('a', {
            href: result.link, target: '_blank', rel: 'noreferrer',
            style: {color: C.accent, fontSize: 12},
          }, 'GitHub') : null)
      }

      if (result.kind === 'submitted') {
        return h('div', {style: styles.result},
          h('div', {style: styles.resultHead(C.ok)}, `${t.submitted} #${result.prNumber}`),
          h('a', {href: result.prUrl, target: '_blank', rel: 'noreferrer', style: {color: C.accent, fontSize: 12}}, t.open))
      }
      return null
    }

    function Studio() {
      const [form, setForm] = React.useState(INITIAL)
      const [catalog, setCatalog] = React.useState({factions: [], keywords: [], loading: true, error: ''})
      const [busy, setBusy] = React.useState(false)
      const [generating, setGenerating] = React.useState(false)
      const [result, setResult] = React.useState({kind: 'idle'})
      const [update, setUpdate] = React.useState({phase: 'idle'})
      // 生成能力时模型可以反问：待回答的问题 + 追问历史，跟草稿一起存。
      const [clarify, setClarify] = React.useState({rounds: [], question: '', answer: ''})
      const clarifyStateRef = React.useRef(clarify)
      clarifyStateRef.current = clarify
      // 草稿：离开面板（组件卸载）后表单还能回来，存在本机 ~/.dsh/chao-card-studio/draft.json。
      const [draftReady, setDraftReady] = React.useState(false)
      const formRef = React.useRef(form)
      formRef.current = form

      React.useEffect(() => {
        let live = true
        fetch(API + '/catalog', {cache: 'no-store'})
          .then(res => res.json())
          .then(body => {
            if (!live) return
            if (body.ok) setCatalog({factions: body.factions ?? [], keywords: body.keywords ?? [], loading: false, error: ''})
            else setCatalog({factions: [], keywords: [], loading: false, error: body.error ?? ''})
          })
          .catch(error => live && setCatalog({factions: [], keywords: [], loading: false, error: error.message}))
        return () => { live = false }
      }, [])

      // 打开面板先读草稿；读回来之前不自动保存，免得用空表单把草稿盖掉。
      React.useEffect(() => {
        let live = true
        fetch(API + '/draft', {cache: 'no-store'})
          .then(res => res.json())
          .then(body => {
            if (!live) return
            if (body.ok && body.draft !== null && typeof body.draft === 'object') {
              const draft = body.draft
              const {chat: _legacyChat, clarify: savedClarify, ...formDraft} = draft
              if (savedClarify !== null && typeof savedClarify === 'object') {
                setClarify({
                  rounds: Array.isArray(savedClarify.rounds)
                    ? savedClarify.rounds.filter(entry => entry !== null && typeof entry === 'object').slice(-6)
                    : [],
                  question: typeof savedClarify.question === 'string' ? savedClarify.question : '',
                  answer: typeof savedClarify.answer === 'string' ? savedClarify.answer : '',
                })
              }
              setForm(current => ({
                ...INITIAL,
                ...formDraft,
                // 1.1.2 之前的草稿只有 counterTrigger，换成新的几段选择。
                ...(formDraft.counterSide === undefined && typeof formDraft.counterTrigger === 'string'
                  ? legacyCounterParts(formDraft.counterTrigger)
                  : {}),
                ...migrateCounterDraft(formDraft),
                keywords: Array.isArray(formDraft.keywords)
                  ? formDraft.keywords.filter(entry => typeof entry === 'string')
                  : current.keywords,
              }))
            }
            setDraftReady(true)
          })
          .catch(() => { if (live) setDraftReady(true) })
        return () => { live = false }
      }, [])

      // 改动停 400ms 存一次。
      React.useEffect(() => {
        if (!draftReady) return undefined
        const timer = window.setTimeout(() => {
          fetch(API + '/draft', {
            method: 'POST', headers: {'content-type': 'application/json'},
            body: JSON.stringify({draft: {...form, clarify}}),
          }).catch(() => {})
        }, 400)
        return () => window.clearTimeout(timer)
      }, [form, clarify, draftReady])

      // 切走面板会卸载组件，卸载时用 sendBeacon 把最后一次改动补存。
      React.useEffect(() => {
        if (!draftReady) return undefined
        return () => {
          try {
            const blob = new Blob([JSON.stringify({draft: {...formRef.current, clarify: clarifyStateRef.current}})],
              {type: 'application/json'})
            if (typeof navigator !== 'undefined' && typeof navigator.sendBeacon === 'function') navigator.sendBeacon(API + '/draft', blob)
          } catch {
            // 卸载时保存失败就等下一次修改
          }
        }
      }, [draftReady])

      const keywordIndex = React.useMemo(() => {
        const map = new Map()
        for (const entry of catalog.keywords) map.set(entry.id, entry.version ?? 1)
        return map
      }, [catalog.keywords])

      const set = patch => setForm(current => ({...current, ...patch}))

      // 版本检查：打开面板先静默查一次，点「更新」时再查。
      React.useEffect(() => {
        let live = true
        fetch(API + '/version', {cache: 'no-store'})
          .then(res => res.json())
          .then(body => { if (live && body.ok) setUpdate({phase: 'ready', data: body}) })
          .catch(() => {})
        return () => { live = false }
      }, [])

      const sleep = ms => new Promise(resolve => window.setTimeout(resolve, ms))

      async function readVersion() {
        const body = await (await fetch(API + '/version', {cache: 'no-store'})).json()
        if (!body.ok) throw new Error(body.error ?? t.updateFailed)
        return body
      }

      async function checkForUpdates() {
        setUpdate(current => ({phase: 'checking', data: current.data}))
        try {
          setUpdate({phase: 'ready', data: await readVersion()})
        } catch (error) {
          setUpdate(current => ({phase: 'failed', data: current.data, error: error.message}))
        }
      }

      async function applyUpdate() {
        const data = update.data
        if (data === undefined) return checkForUpdates()
        const pending = data.components.filter(entry => entry.newer && entry.updatable)
        if (pending.length === 0) return checkForUpdates()
        setUpdate({phase: 'applying', data})
        for (const entry of pending) {
          try {
            const body = await (await fetch(API + '/update', {
              method: 'POST', headers: {'content-type': 'application/json'},
              body: JSON.stringify({component: entry.component}),
            })).json()
            if (!body.ok) throw new Error(body.error ?? t.updateFailed)
          } catch (error) {
            // 替换工坊自己时这条连接会断，下面等它重新起来再核对版本
          }
          // 安装完等插件重新上线：制卡插件立刻回来，工坊自己会触发一次热重载。
          for (let attempt = 0; attempt < 20; attempt += 1) {
            await sleep(1200)
            try { await readVersion(); break } catch { /* 还没起来 */ }
          }
        }
        try {
          setUpdate({phase: 'done', data: await readVersion()})
        } catch {
          setUpdate({phase: 'done'})
        }
        window.setTimeout(() => checkForUpdates(), 5000)
      }

      const toggleKeyword = id => setForm(current => {
        const selected = current.keywords.includes(id)
        const keywords = selected
          ? current.keywords.filter(entry => entry !== id)
          : [...current.keywords, id]
        let keywordParams = current.keywordParams ?? {}
        if (!selected) {
          // 带参数的词条（重甲 X / 充能 N / 复生 N）选中时给个最小层数。
          const entry = catalog.keywords.find(item => item.id === id)
          const defaults = {}
          for (const [key, schema] of Object.entries(entry?.parameters ?? {})) {
            defaults[key] = Number.isFinite(Number(schema?.minimum)) ? Number(schema.minimum) : 1
          }
          if (Object.keys(defaults).length > 0) keywordParams = {...keywordParams, [id]: defaults}
        }
        return {...current, keywords, keywordParams}
      })

      async function generate(answer) {
        if (form.abilityText.trim() === '') {
          return setResult({kind: 'invalid', errors: [{message: t.needAbility}]})
        }
        // 回答上一轮追问：把这一问一答并进历史，再让模型继续。
        const replied = typeof answer === 'string' && answer.trim() !== '' && clarify.question !== ''
        const rounds = replied
          ? [...clarify.rounds, {question: clarify.question, answer: answer.trim()}].slice(-6)
          : clarify.rounds
        if (replied) setClarify({rounds, question: '', answer: ''})
        setGenerating(true)
        setResult({kind: 'working'})
        try {
          const card = buildCard({...form, abilities: '[]'}, keywordIndex)
          const body = await (await fetch(API + '/abilities', {
            method: 'POST', headers: {'content-type': 'application/json'},
            body: JSON.stringify({
              description: form.abilityText.trim(),
              card,
              counter: form.kind === 'counter' ? counterPartsOf(form) : null,
              clarifications: rounds,
            }),
          })).json()
          if (body.ok) {
            set({
              abilities: JSON.stringify(body.abilities),
              playTarget: JSON.stringify(body.playTarget ?? null),
            })
            setResult({kind: 'generated', abilities: body.abilities, playTarget: body.playTarget ?? null})
            setClarify({rounds: [], question: '', answer: ''})
          } else if (body.needAnswer) {
            setClarify({rounds, question: body.question ?? '', answer: ''})
            setResult({kind: 'idle'})
          } else {
            setResult({kind: 'invalid', errors: [{message: body.error ?? '生成失败'}]})
          }
        } catch (error) {
          setResult({kind: 'invalid', errors: [{message: error.message}]})
        } finally {
          setGenerating(false)
        }
      }


      async function run(mode) {
        if (form.name.trim() === '') return setResult({kind: 'invalid', errors: [{message: t.needName}]})
        if (form.author.trim() === '') return setResult({kind: 'invalid', errors: [{message: t.needAuthor}]})
        if (form.kind === 'counter' && counterTriggerOf(form) === null) {
          return setResult({kind: 'invalid', errors: [{message: t.counterUnsupported}]})
        }
        setBusy(true)
        setResult({kind: 'working'})
        try {
          const card = buildCard(form, keywordIndex)
          if (mode === 'validate') {
            const body = await (await fetch(API + '/validate', {
              method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({card}),
            })).json()
            setResult(body.ok
              ? {kind: 'valid', rules: body.rules_text, hash: body.definition_hash}
              : {kind: 'invalid', errors: body.errors ?? [{message: body.error ?? '校验失败'}]})
          } else {
            const body = await (await fetch(API + '/submit', {
              method: 'POST', headers: {'content-type': 'application/json'},
              body: JSON.stringify({card, author: form.author.trim()}),
            })).json()
            if (body.ok) setResult({kind: 'submitted', prUrl: body.pr_url, prNumber: body.pr_number})
            else if (body.fallback) setResult({kind: 'failed', errors: [{message: body.reason ?? '提交失败'}], link: body.submit_url})
            else setResult({kind: 'invalid', errors: body.errors ?? [{message: body.error ?? '提交失败'}]})
          }
        } catch (error) {
          setResult({kind: 'invalid', errors: [{message: error.message}]})
        } finally {
          setBusy(false)
        }
      }

      // 同一词条在目录里可能出现多条（同 id 或多条同名自定义词条），
      // 这里按 id、再按显示名去重，避免界面上出现“守护 守护”这种重复按钮。
      const keywordList = React.useMemo(() => {
        const seenIds = new Set()
        const seenNames = new Set()
        const list = []
        for (const entry of catalog.keywords) {
          if (!entry || typeof entry.id !== 'string') continue
          if (seenIds.has(entry.id)) continue
          const name = entry.name ?? entry.id
          if (seenNames.has(name)) continue
          seenIds.add(entry.id)
          seenNames.add(name)
          list.push(entry)
        }
        return list
      }, [catalog.keywords])

      const builtinKeywords = keywordList.filter(entry => /^(core|standard)\./.test(entry.id))
      const customKeywords = keywordList.filter(entry => !/^(core|standard)\./.test(entry.id))
      // 已选中、且带参数的词条（重甲 X / 充能 N / 复生 N）需要额外填层数。
      const parametricKeywords = keywordList.filter(entry => form.keywords.includes(entry.id)
        && entry.parameters !== undefined && entry.parameters !== null
        && Object.keys(entry.parameters).length > 0)

      const renderKeywordGroup = (title, list) => list.length === 0 ? null : h('div', {style: {marginBottom: 12}},
        h('div', {style: styles.groupLabel}, title),
        h('div', {style: styles.chipWrap},
          list.map(entry => h('button', {
            key: entry.id,
            type: 'button',
            title: `${entry.name ?? entry.id} · ${entry.id}`,
            style: styles.chip(form.keywords.includes(entry.id)),
            onClick: () => toggleKeyword(entry.id),
          }, entry.name ?? entry.id))))

      const hasAbilities = form.abilities !== '' && form.abilities !== '[]'
      const isUnit = form.kind === 'unit'
      const counterMapped = form.kind === 'counter' ? counterTriggerOf(form) : null
      const counterMappedLabel = counterMapped === null
        ? ''
        : (COUNTER_SUPPORTED.find(([value]) => value === counterMapped) ?? [null, counterMapped])[1]

      const updatePending = (update.data?.components ?? []).filter(entry => entry.newer)
      const updateActionable = updatePending.filter(entry => entry.updatable)
      const updateManual = updatePending.length > 0 && updateActionable.length === 0
      const updateBusy = update.phase === 'checking' || update.phase === 'applying'

      let updateLabel = t.updateCheck
      let updateTone = 'quiet'
      if (update.phase === 'checking') {
        updateLabel = t.updateChecking
      } else if (update.phase === 'applying') {
        updateLabel = t.updateApplying
        updateTone = 'accent'
      } else if (update.phase === 'done') {
        updateLabel = t.updateDone
      } else if (update.phase === 'failed') {
        updateLabel = t.updateFailed
      } else if (update.data !== undefined) {
        if (updatePending.length === 0) {
          updateLabel = t.updateCurrent
        } else if (updateManual) {
          updateLabel = t.updateManual(updatePending[0].latest)
          updateTone = 'warn'
        } else if (updateActionable.length === 1) {
          updateLabel = t.updateTo(updateActionable[0].latest)
          updateTone = 'accent'
        } else {
          updateLabel = t.updateMany(updateActionable.length)
          updateTone = 'accent'
        }
      }

      const updateTitle = update.data === undefined
        ? t.updateCheck
        : update.data.components.map(entry => {
          const state = entry.reason === 'dev-link' ? t.updateDevHint
            : entry.reason === 'external' ? t.updateExternal
            : entry.reason === 'no-asset' ? t.updateNoAsset
            : entry.newer ? t.updateReady
            : t.updateCurrent
          return `${entry.label} ${entry.installed}${entry.newer ? ` → ${entry.latest}` : ''} · ${state}`
        }).join('\n')

      function onUpdateClick() {
        if (updateBusy) return
        if (updatePending.length === 0) return checkForUpdates()
        if (updateManual) {
          window.open(updatePending[0].page, '_blank', 'noreferrer')
          return
        }
        applyUpdate()
      }

      return h('div', {style: styles.root},
        h('style', null, STYLE),
        h('div', {className: 'ccs-card', style: styles.card},

          h('div', {className: 'ccs-header', style: styles.header},
            h('div', {className: 'ccs-brand', style: styles.brand}, h(LauncherIcon, {size: 20})),
            h('div', {style: styles.titleBox},
              h('div', {style: styles.title}, t.title),
              h('div', {style: styles.subtitle}, t.subtitle)),
            h('button', {
              type: 'button',
              style: {...styles.updateBtn(updateTone), opacity: updateBusy ? 0.6 : 1, cursor: updateBusy ? 'default' : 'pointer'},
              title: updateTitle,
              disabled: updateBusy,
              onClick: onUpdateClick,
            }, updateLabel),
            h(StatusPill, {kind: result.kind})),

          h('div', {className: 'ccs-body', style: styles.body},

            h(Section, {title: t.sectionBasic},
              h('div', {className: 'ccs-grid', style: styles.grid},
                h(Field, {label: t.name},
                  h('input', {
                    style: styles.input, value: form.name, placeholder: '例：风暴大师',
                    onChange: event => set({name: event.target.value}),
                  })),
                h(Field, {label: t.author},
                  h('input', {
                    style: styles.input, value: form.author, placeholder: 'Kuteng-os',
                    onChange: event => set({author: event.target.value}),
                  })),
                h(Field, {label: t.kind}, h('select', {
                  style: styles.input, value: form.kind, onChange: event => set({kind: event.target.value}),
                }, KINDS.map(([value, label]) => h('option', {key: value, value}, label)))),
                form.kind === 'unit' ? h(Field, {label: t.unitClass}, h('select', {
                  style: styles.input, value: form.unitClass, onChange: event => set({unitClass: event.target.value}),
                }, CLASSES.map(([value, label]) => h('option', {key: value, value}, label)))) : null,
                h(Field, {label: t.rarity}, h('select', {
                  style: styles.input, value: form.rarity, onChange: event => set({rarity: event.target.value}),
                }, RARITIES.map(([value, label]) => h('option', {key: value, value}, label)))),
                h(Field, {label: t.faction}, h('select', {
                  style: styles.input, value: form.faction, onChange: event => set({faction: event.target.value}),
                }, [h('option', {key: '', value: ''}, catalog.loading ? t.loading : t.none)]
                  .concat(catalog.factions.map(entry => h('option', {key: entry.id, value: entry.id}, entry.name))))),
                h(Field, {label: t.sin}, h('select', {
                  style: styles.input, value: form.sin, onChange: event => set({sin: event.target.value}),
                }, SINS.map(([value, label]) => h('option', {key: value, value}, label)))),
                form.kind === 'counter' ? h(Field, {label: t.counterSide}, h('select', {
                  style: styles.input, value: form.counterSide, onChange: event => set({counterSide: event.target.value}),
                }, COUNTER_SIDES.map(([value, label]) => h('option', {key: value, value}, label)))) : null,
                form.kind === 'counter' ? h(Field, {label: t.counterAction}, h('select', {
                  style: styles.input, value: form.counterAction, onChange: event => set({counterAction: event.target.value}),
                }, COUNTER_ACTIONS.map(([value, label]) => h('option', {key: value, value}, label)))) : null,
                form.kind === 'counter' && form.counterAction === 'deploy_unit' ? h(Field, {label: t.counterRow}, h('select', {
                  style: styles.input, value: form.counterRow, onChange: event => set({counterRow: event.target.value}),
                }, COUNTER_ROWS.map(([value, label]) => h('option', {key: value, value}, label)))) : null,
                form.kind === 'counter' && form.counterAction === 'deploy_unit' ? h(Field, {label: t.counterClass}, h('select', {
                  style: styles.input, value: form.counterClass, onChange: event => set({counterClass: event.target.value}),
                }, COUNTER_CLASSES.map(([value, label]) => h('option', {key: value, value}, label)))) : null,
                form.kind === 'counter' && form.counterAction === 'use_unit' ? h(Field, {label: t.counterUnitAction}, h('select', {
                  style: styles.input, value: form.counterUnitAction, onChange: event => set({counterUnitAction: event.target.value}),
                }, COUNTER_UNIT_ACTIONS.map(([value, label]) => h('option', {key: value, value}, label)))) : null,
                form.kind === 'counter' && form.counterAction === 'use_unit' && form.counterUnitAction === 'attack'
                  ? h(Field, {label: t.counterAttackTarget}, h('select', {
                    style: styles.input, value: form.counterAttackTarget, onChange: event => set({counterAttackTarget: event.target.value}),
                  }, COUNTER_ATTACK_TARGETS.map(([value, label]) => h('option', {key: value, value}, label)))) : null,
                form.kind === 'counter' && form.counterAction === 'use_unit' && form.counterUnitAction === 'attack' && form.counterAttackTarget === 'unit'
                  ? h(Field, {label: t.counterRow}, h('select', {
                    style: styles.input, value: form.counterRow, onChange: event => set({counterRow: event.target.value}),
                  }, COUNTER_ROWS.map(([value, label]) => h('option', {key: value, value}, label)))) : null,
                form.kind === 'counter' && form.counterAction === 'use_unit' && form.counterUnitAction === 'attack' && form.counterAttackTarget === 'unit'
                  ? h(Field, {label: t.counterClass}, h('select', {
                    style: styles.input, value: form.counterClass, onChange: event => set({counterClass: event.target.value}),
                  }, COUNTER_CLASSES.map(([value, label]) => h('option', {key: value, value}, label)))) : null)),
              form.kind === 'counter' ? h('div', {
                style: {marginTop: 10, fontSize: 11, lineHeight: 1.6, color: counterMapped === null ? C.warn : C.ok},
              },
                counterMapped === null
                  ? t.counterUnsupported
                  : t.counterMaps(counterMappedLabel),
                h('div', {style: {color: C.faint, marginTop: 2}}, t.counterFilterHint)) : null,

            h(Section, {title: t.sectionStats},
              h('div', {className: 'ccs-grid', style: styles.grid},
                h(Field, {label: t.cost}, h('input', {
                  style: styles.input, type: 'number', min: 0, max: 12, value: form.cost,
                  onChange: event => set({cost: event.target.value}),
                })),
                isUnit ? h(Field, {label: t.operationCost}, h('input', {
                  style: styles.input, type: 'number', min: 0, max: 4, value: form.operationCost,
                  onChange: event => set({operationCost: event.target.value}),
                })) : null,
                isUnit ? h(Field, {label: t.attack}, h('input', {
                  style: styles.input, type: 'number', min: 0, max: 20, value: form.attack,
                  onChange: event => set({attack: event.target.value}),
                })) : null,
                // 总部不是单位，但有血量，所以防御力对 hq 保留。
                form.kind === 'unit' || form.kind === 'hq' ? h(Field, {label: t.health}, h('input', {
                  style: styles.input, type: 'number', min: 0, max: 100, value: form.health,
                  onChange: event => set({health: event.target.value}),
                })) : null)),

            h(Section, {title: t.sectionText},
              h('div', {className: 'ccs-grid', style: styles.grid},
                h(Field, {label: t.flavor},
                  h('input', {
                    style: styles.input, value: form.flavor, maxLength: 120,
                    onChange: event => set({flavor: event.target.value}),
                  }))),
              h('div', {style: {marginTop: 12}},
                h(Field, {label: t.displayText},
                  h('textarea', {
                    style: styles.textarea, value: form.displayText, maxLength: 2000,
                    onChange: event => set({displayText: event.target.value}),
                  })))),

            h(Section, {title: t.keywords}, 
              h('div', {style: styles.hint},
                form.keywords.length > 0
                  ? `${t.keywordHint} · ${t.selectedCount(form.keywords.length)}`
                  : t.keywordHint),
              renderKeywordGroup(t.builtin, builtinKeywords),
              renderKeywordGroup(t.custom, customKeywords),
              parametricKeywords.length > 0 ? h('div', {style: {marginTop: 2}},
                h('div', {style: styles.groupLabel}, t.keywordStack),
                h('div', {style: {display: 'flex', flexWrap: 'wrap', gap: 14, alignItems: 'center'}},
                  parametricKeywords.map(entry => {
                    const [key, schema] = Object.entries(entry.parameters)[0]
                    const stored = form.keywordParams?.[entry.id]?.[key]
                    const value = Number.isFinite(Number(stored)) ? Number(stored) : (schema?.minimum ?? 1)
                    return h('label', {key: entry.id, style: {display: 'flex', alignItems: 'center', gap: 6, fontSize: 12}},
                      h('span', null, entry.name),
                      h('input', {
                        type: 'number',
                        min: schema?.minimum ?? 1,
                        max: schema?.maximum ?? 20,
                        value,
                        style: {...styles.input, width: 76},
                        onChange: event => {
                          const next = Number(event.target.value)
                          setForm(current => ({
                            ...current,
                            keywordParams: {
                              ...(current.keywordParams ?? {}),
                              [entry.id]: {
                                ...(current.keywordParams?.[entry.id] ?? {}),
                                [key]: Number.isFinite(next) ? next : (schema?.minimum ?? 1),
                              },
                            },
                          }))
                        },
                      }))
                  }))) : null),

            h(Section, {title: t.sectionAbilities},
              h('div', {style: styles.hint}, t.abilitiesHint),
              h('textarea', {
                style: styles.textarea, value: form.abilityText, placeholder: '部署时对所选敌方单位造成 2 点伤害',
                onChange: event => set({abilityText: event.target.value}),
              }),
              h('div', {style: {display: 'flex', gap: 10, marginTop: 10, alignItems: 'center', flexWrap: 'wrap'}},
                h('button', {
                  type: 'button', style: styles.button(false), disabled: generating,
                  onClick: generate,
                }, generating ? t.generating : t.gen),
                hasAbilities ? h('button', {
                  type: 'button', style: styles.ghost,
                  onClick: () => set({abilities: '[]', playTarget: 'null'}),
                }, t.clearAbilities) : null),
              h('div', {style: {fontSize: 11, color: C.faint, marginTop: 6, lineHeight: 1.6}}, t.clarifyHint),
              hasAbilities ? h('details', {style: {...styles.details, marginTop: 10}},
                h('summary', {style: styles.summary}, t.generatedDetails),
                h('pre', {style: {...styles.scrollBox, marginTop: 8, marginBottom: 0}}, form.abilities),
                form.playTarget !== 'null' ? h('div', {style: {marginTop: 6, fontSize: 11, color: C.faint}}, '出牌目标：' + form.playTarget) : null) : null,
              clarify.question !== '' ? h('div', {style: {marginTop: 10, padding: '10px 12px', borderRadius: 9, border: `1px solid ${C.warn}`, background: 'rgba(217,160,59,.10)'}},
                h('div', {style: {fontSize: 11.5, fontWeight: 600, color: C.warn, marginBottom: 6}}, t.clarifyTitle),
                h('div', {style: {fontSize: 12, lineHeight: 1.65, whiteSpace: 'pre-wrap', color: C.text}}, clarify.question),
                clarify.rounds.length > 0 ? h('div', {style: {fontSize: 11, color: C.faint, marginTop: 4}}, t.clarifyRounds(clarify.rounds.length)) : null,
                h('textarea', {
                  style: {...styles.textarea, marginTop: 8, minHeight: 56},
                  value: clarify.answer,
                  placeholder: t.clarifyPlaceholder,
                  onChange: event => setClarify(current => ({...current, answer: event.target.value})),
                }),
                h('div', {style: {display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap'}},
                  h('button', {type: 'button', style: styles.button(true), disabled: generating, onClick: () => generate(clarify.answer)}, generating ? t.generating : t.clarifySend),
                  h('button', {type: 'button', style: styles.ghost, onClick: () => setClarify(current => ({...current, question: '', answer: ''}))}, t.clarifyCancel))) : null,
              catalog.error !== '' ? h('div', {style: {marginTop: 10, fontSize: 12, color: C.bad}}, catalog.error) : null)),

          h('div', {className: 'ccs-footer', style: styles.footer},
            h(ResultBlock, {result, t}),
            h('div', {style: styles.actions},
              h('button', {type: 'button', style: styles.button(true), disabled: busy, onClick: () => run('validate')}, busy ? t.working : t.validate),
              h('button', {type: 'button', style: styles.button(false), disabled: busy, onClick: () => run('submit')}, t.submit),
              h('button', {
                type: 'button',
                style: styles.ghost,
                disabled: busy,
                onClick: () => {
                  setForm(INITIAL)
                  setResult({kind: 'idle'})
                  // 重置也把本机草稿清掉，下次打开是空表单。
                  fetch(API + '/draft', {
                    method: 'POST', headers: {'content-type': 'application/json'},
                    body: JSON.stringify({draft: null}),
                  }).catch(() => {})
                },
              }, t.reset)))))
    }

    function LauncherIcon(owner = {}) {
      const size = owner.size ?? 16
      return h('svg', {viewBox: '0 0 64 64', width: size, height: size, 'aria-hidden': true, style: {display: 'block'}},
        h('rect', {x: 6, y: 10, width: 34, height: 44, rx: 6, fill: '#247bbf'}),
        h('rect', {x: 24, y: 18, width: 34, height: 44, rx: 6, fill: '#f2b134', opacity: 0.92}),
        h('path', {d: 'M41 30v20M31 40h20', stroke: '#3a2a08', strokeWidth: 5, strokeLinecap: 'round'}))
    }

    return {
      inject: ['slots'],
      apply(ctx) {
        // 左侧栏的入口图标：这个 id 对应的就是下面的 main 面板，点击由侧栏自己处理。
        ctx.slots.inject('sidebar.panellist', () => ctx.slots.register({
          name: 'sidebar.panellist', id: PANEL_ID, order: 20, label: () => t.title,
        }, owner => h(LauncherIcon, {size: owner?.size ?? 16})))

        // 主面板：左侧栏图标点开后占满中间区域。
        ctx.slots.inject('main', () => ctx.slots.register({
          name: 'main', key: PANEL_ID, locale: 'chao-card-studio',
        }, Studio))
      },
    }
  },
})
