# 独立关键词注册规范

版本：1.0.0 · 规则集：`frontline-1` · 状态：注册服务和运行时已实现；当前能力边界见 [机制支持范围](MECHANICS_SUPPORT.md)。

本文是 [CARD_INTEGRATION.md](CARD_INTEGRATION.md) 的规范性补充，供生成后端、Godot 规则引擎和执行 agent 使用。
关键词必须独立注册；卡牌只能引用已经获准的精确关键词版本。模型可以提出新关键词，不能自行批准或安装行为。
用户选择的默认流程是：模板词条经多轮澄清和预览，由玩家确认精确候选，再由服务端自动校验登记，无需维护者逐项人工审批。
本文不建立生产卡池；下文“补给”仅说明注册数据的形式，不自动创建可用关键词或卡牌。

## 1. 三种对象必须分开

| 对象 | 用途 | 是否可用于对局 |
| --- | --- | --- |
| KeywordProposal | 玩家意图、问题答案、模型提出的候选定义 | 否 |
| KeywordDefinition | 已验证的不可变名称、参数与行为定义 | 只有注册记录为 approved 且规则环境支持时可以 |
| KeywordRef | 卡牌内的 `{id,version,params}` 引用 | 必须先解析、验证和编译 |

提案不是注册成功，Schema 通过也不是注册成功；模板只有在玩家确认后的自动校验事务成功时才成为 approved。
注册状态、创建者、approval_source、校验版本、确认时间、失败理由和审计日志属于注册记录，不进入模型可写的定义对象。
模型输出的 `approved`、可信标志、审核人、实现路径、签名或 hash 必须拒绝，不能通过删字段后默默采纳。

## 2. 不可变标识与版本

关键词以 `id + version` 唯一确定：例如 `core.blitz@1`、`core.guard@1`。
`id` 使用命名空间和 ASCII 小写标识；`core.*` 仅供开发者维护。名称、别名和中文解释均不是执行标识。
`version` 为正整数；精确数值必须出现在卡牌中，不接受 `latest`、范围、浮动别名或仅名称引用。
批准后的定义不可修改：参数、默认意义、别名、说明或行为变化均创建新版本。旧版本保留供冻结对局和回放使用。
注册服务分配 ID、递增版本并防止抢占保留命名空间；模型和玩家不能指定最终身份、覆盖他人的 ID 或改写已批准版本。
别名只能用于编辑时检索。同一命名空间内，一个别名不能无歧义地指向不同 ID；有冲突必须澄清。
同一 ID 的多个版本可以沿用别名；目录明确推荐版本，编译结果仍必须写出选中的具体版本。

## 3. KeywordDefinition 合同

字段以 [keyword.schema.json](keyword.schema.json) 为结构依据；本节定义用途和必需的语义检查。

| 字段 | 含义 |
| --- | --- |
| schema_version / ruleset_version | 当前固定为 `1.0.0` / `frontline-1` |
| id / version | 稳定标识和不可变版本 |
| name / aliases | 展示名称与检索别名；名称可本地化，但不直接驱动行为 |
| description | 人类可读的准确规则说明；不能作为运行时表达式执行 |
| parameters | 参数名到整数参数描述符的映射；无参数时为空对象 |
| implementation | `builtin` 或 `template` 的受限实现声明 |

每个参数描述符为 `{type:"integer",minimum:整数,maximum:整数}`；两个边界均在 -5 至 10 内，且 minimum ≤ maximum。
v1 不允许可选参数、隐式默认值、字符串参数、浮点数、数组参数、公式参数或任意 JSON 参数。
所有声明参数都必填；多余参数拒绝。实参必须为 -5 至 10 内且满足声明范围的整数。参数名是稳定的 ASCII 标识，不能依赖中文别名定位。
名称、别名和说明作为纯文本渲染；禁止将其解释为 BBCode、HTML、文件路径或脚本。
参数范围不能扩大底层操作允许的范围。例如 draw.amount 的参数最大值不能超过该规则集的抽牌数量上限。

## 4. 两种实现来源

### 4.1 开发者内置规则 builtin

`implementation` 只引用开发者已经实现并允许的固定 `builtin_id`，不包含代码正文、类名、资源路径或下载地址。
首版内置实现只允许 `{kind:"builtin",builtin_id:"core.blitz.v1"}` 或 `{kind:"builtin",builtin_id:"core.guard.v1"}`。
`core.blitz@1` 和 `core.guard@1` 为首版内置项，`parameters` 均为空对象，卡牌引用的 `params` 也必须为空对象。
内置 ID 到 Godot 行为的映射由可信代码维护，后端与对战节点同时声明支持的版本和语义。
语义校验必须强制 core.blitz@1 → core.blitz.v1、core.guard@1 → core.guard.v1 的固定对应，拒绝调换实现或给其它 ID 冒用 builtin；Schema 类型通过不代表这项检查完成。
`core.blitz@1` 影响部署时的行动准备；后来授予它不能重置已经消耗的行动，具体行为以主规范为准。
`core.guard@1` 参与普通攻击目标检查，不能阻挡声明式技能伤害。
模型提出“穿甲”等新内置规则时，只能记录提案和未实现要求；不得假装存在相应 builtin_id。
开发者必须补齐引擎、校验器、文本渲染和测试并发布支持版本，之后才能通过开发者发布流程登记；玩家确认不能新增引擎能力。
首版 core 内置项由开发者初始化注册；模板的自动登记接口不能创建、更新或冒用 builtin 实现。

### 4.2 可信模板 template

`implementation` 为 `{kind:"template",abilities:[...]}`，复用卡牌 DSL 的触发器、目标和操作语义。
模板在导入编译阶段展开为普通 abilities，对局中不查模型、不执行模板语言、不进行字符串替换。
整数叶字段允许使用唯一占位形式 `{param:"参数名"}`；不能把占位符放到 op、trigger、target、duration、键名或引用 ID 中。
占位符替换必须操作 JSON 语法树；不得用正则拼 JSON，不得执行表达式，不允许 `{param:"amount*2"}`。
参数必须已声明且至少被引用一次；占位参数名称未知、参数未使用、重复声明或值越界都拒绝。
同一个参数用于多个整数位置时，其声明范围必须落在全部位置允许范围的交集中。
模板不能引用或嵌套其它关键词，不能携带二级关键词表，也不能通过任意字符串间接查找行为。
v1 模板禁止 `grant_keyword` 和 `summon`；其它操作仍受 CardSpec DSL 的白名单约束。
能力修订 `mechanics-2` 增加 `set_attack_limit`、`destroy` 和 `modify_operation_cost`；均可用于模板。攻击总上限参数必须完整落在1–4，行动费增减参数必须完整落在-4…-1或1…4，不能跨越零。`examples/keywords/example_fight.json` 是“奋战”的测试示例，不自动登记；模型不应再将明确的“每回合可攻击两次”判成待实现。
模板没有独立的胜负、资源、时间、随机源或网络权限，不能覆盖解释器的基本规则。
模板候选通过预检后进入 ready_to_register。玩家确认精确修订与候选 hash，服务端重新完成全部校验并原子登记，不要求维护者手工批准。
模型输出 candidate 只表示提出候选，不能代替玩家确认、自动校验结果或登记事务；只有后端写入 approval_source:"automatic_validation"。

## 5. “补给”参数模板示意

以下片段仅展示行为定义；完整登记仍需要服务端分配的标识、版本、名称、说明、玩家确认记录及完整自动校验。

```json
{
  "parameters": {
    "amount": {"type": "integer", "minimum": 1, "maximum": 3}
  },
  "implementation": {
    "kind": "template",
    "abilities": [
      {
        "trigger": "on_play",
        "effects": [
          {"op": "draw", "player": "owner", "amount": {"param": "amount"}}
        ]
      }
    ]
  }
}
```

假设服务端分配 `custom.supply@1`，并在玩家确认后成功自动登记，引用形状才可以是 `{"id":"custom.supply","version":1,"params":{"amount":2}}`。
其含义固定为打出时由控制者抽 2 张牌；“补给”这个词本身不会自动推导回血、加资源或每回合抽牌。
如果玩家想表达其它含义，必须澄清并提出不同定义或新版本，不能覆盖已经获准的语义。

## 6. 卡牌引用、展开与顺序

CardSpec 的 `keywords` 改为 KeywordRef 数组；不接受 `"blitz"`、`"guard"` 或其它自由字符串。
内置引用示例：`{"id":"core.guard","version":1,"params":{}}`。附属 token 的关键词也必须使用同一引用形状。
同一张牌或同一 token 中，重复出现同一个关键词 ID 必须拒绝，不能利用不同版本或参数堆叠同一项。
每个引用必须在当前后端目录中存在、获准、版本完全匹配，并被目标 ruleset/interpreter 支持。
v1 无技能 token 只允许引用无参数的内置关键词；引用 template 会产生能力，因此必须拒绝。
编译先保留卡牌显式 abilities，再按 keywords 数组顺序展开模板，模板内部按 abilities/effects 的声明顺序展开。
同触发器的先后顺序由上述展平顺序决定，不能按本地显示名称排序。改变顺序会改变编译内容和 hash。
展开结果必须重新执行完整 CardSpec 语义校验：牌种允许的触发器、self/chosen 限制、play_target 配对等全部适用。
例如指令牌引用 own_turn_start 模板必须拒绝；产生 chosen 的模板必须与该卡唯一的 play_target 一致。
模板不得因为来源是已批准目录而绕过当前卡牌的目标限制、总操作数量或大小上限。
内置关键词保留为已验证的内置标志；模板引用保留作来源记录，但运行时只执行编译后的普通效果。

## 7. 动态授予规则

`grant_keyword` 的关键字段为 `keyword_id` 和 `keyword_version`，不再接收自由字符串 `keyword`。
v1 只能授予已实现的 `core.blitz@1` 或 `core.guard@1`，不得授予模板关键词，也不得传入动态参数。
操作仍需要合法的单位目标和 `duration`；总部目标、未知版本或非内置 ID 在导入时拒绝。
每次授予创建独立来源层；过期只移除该层，不删除基础关键词或其它永久、临时来源。
授予守护立即影响后续普通攻击选择；授予突击不补回已花费的行动或资源。
新增其它可动态授予的内置项必须升级规则合同及测试，不能单靠往注册表写记录开放。

## 8. 生命周期和登记责任

| 状态 | 允许的下一步 | 可否用于新卡编译 |
| --- | --- | --- |
| proposed | 意图清楚则生成候选并预检；否则提出问题 | 否 |
| needs_clarification | 玩家补充后回到 proposed，可多轮 | 否 |
| ready_to_register | 已有可表达且通过预检的模板候选，等待玩家确认精确修订与 hash | 否 |
| pending_implementation | 现有 DSL 不支持，等待开发者补齐引擎实现、版本和测试 | 否 |
| approved | 冻结定义；以后可标记 deprecated | 是 |
| deprecated | 保留旧定义和冻结引用，不再推荐或用于新导入 | 否 |

正常模板流程为 proposed → needs_clarification（可反复）→ ready_to_register → 玩家确认 → 自动验证事务 → approved；无歧义时可以跳过 needs_clarification。
`pending_implementation` 不用于等待模板人工审批；它只表示确实缺少已实现的引擎能力，不能伪造近似行为绕过。
普通玩家有权确认自己提案的精确候选，后端据此自动登记符合约束的模板；玩家和模型都不能直接写 approved 或跳过验证。
玩家可以提交、修改尚未批准的提案、回答问题和撤回提案，但不能直接更改已注册定义或历史登记审计记录。
校验失败必须返回具体原因并保留提案，不写入可用目录，也不能自行换成近似效果。需要修正的候选回到 proposed 或 needs_clarification，新候选须重新预览确认。
模板登记成功记录 approval_source:"automatic_validation"、owner、确认的 revision/hash、验证器版本及检查报告摘要；这些均由服务端生成。
管理权限仅用于开发者 builtin 发布、废弃和运维；人工审核可以作为未来明确启用的独立模式，不能成为默认模板登记的等待步骤。
废弃不改变旧版本内容。既有冻结对局和回放继续解析原版本；新导入要求使用可用版本或先完成迁移预览。
若出现必须紧急停用的实现缺陷，按主规范的对局故障流程处理，不能静默热改某一方的规则。

## 9. 提案接口与多轮澄清

`POST /v1/keyword-proposals` 创建独立关键词提案；提交 request_id、玩家原文、名称建议及相关生成任务关联 ID。
服务端从鉴权上下文决定 owner，生成 proposal_id；请求不能自行指定审核权限、批准状态或可信实现来源。
接口须鉴权、限流、幂等和版本冲突检查；同一 request_id 重试返回原提案，不创建重复记录。
`GET /v1/keyword-proposals/{id}` 返回有权查看的状态、问题、已确认语义及自动校验或开发处理结果；隐藏内部密钥与管理凭证。
`POST /v1/keyword-proposals/{id}/answers` 提交 expected_revision、question_id 与答案，创建下一轮修订。
不匹配的修订、重复或未知 question_id 拒绝；取消提案的迟到模型结果不得复活提案或覆盖新答案。
每轮最多提出 3 个必要问题；例如“补给何时触发”“谁抽牌”“数量固定还是每张卡提供参数”。
界面问题必须标明作用域：`keyword` 问共享定义，`card` 问当前卡的费用、攻防或参数取值。scope 是后端根据所属接口/任务附加的 UI 元数据，不是 generation.schema.json 允许模型输出的字段；模型仍只输出 id/question/options。
关键词语义和卡牌参数不能混问：确认“补给在打出时抽牌”并不意味着当前卡的 amount 已确定。
用户已回答的问题不得无故反复询问；如果新答案与旧答案冲突，应明确指出冲突并只澄清受影响部分。
模型可以反复返回 needs_clarification，但不能在玩家未回答关键语义时自行结束澄清或批准定义。
同一提案每轮上游调用预算沿用主规范；等待玩家期间不轮询模型、不累计后台自动生成请求。
模板注册使用独立的玩家 confirm 接口；回答澄清问题或确认导入卡牌都不能隐式确认一个尚未展示的关键词候选。
预览必须明确说明：确认登记后，关键词的名称、别名、说明、参数和规则定义将进入公共目录；原始问答与账号信息不随目录公开。

### 9.1 精确请求与响应

以下是项目后端接口；所有对象拒绝未知字段，输入/输出大小、错误信封、限流和幂等沿用主规范。`UUID` 是服务端校验的小写UUID，`Revision` 为正整数；显示名称1–32码点，描述最多2,000码点。

```text
POST /v1/keyword-proposals
{request_id:UUID, source_text:string, suggested_name:string, related_generation_id:UUID|null}
→ 202 {proposal_id:UUID, revision:1, status:"proposed", generation_job_id:UUID}

GET /v1/keyword-proposals/{id}
→ {proposal_id:UUID, revision:Revision, status:ProposalStatus,
   assigned_id:string, assigned_version:Revision, confirmed_intent:string,
   questions:Question[], candidate:KeywordDefinition|null, candidate_hash:Hash|null,
   missing_capabilities:string[], review_message:string|null}

POST /v1/keyword-proposals/{id}/answers
{request_id:UUID, expected_revision:Revision,
 answers:[{question_id:string,answer:string}]}
→ 202 {proposal_id:UUID, revision:Revision, generation_job_id:UUID}

POST /v1/keyword-proposals/{id}/confirm
{request_id:UUID, expected_revision:Revision, candidate_hash:Hash}
→ 201 {definition:KeywordDefinition, definition_hash:Hash,
       registry_status:"approved", approval_source:"automatic_validation"}

DELETE /v1/keyword-proposals/{id}
→ {proposal_id:UUID, status:"withdrawn"}

POST /v1/admin/keyword-proposals/{id}/approve
{request_id:UUID, expected_revision:Revision, candidate_hash:Hash}
→ 201 {definition:KeywordDefinition, definition_hash:Hash, registry_status:"approved"}

POST /v1/admin/keyword-proposals/{id}/reject
{request_id:UUID, expected_revision:Revision, reason:string}
→ {proposal_id:UUID, status:"rejected", review_message:string}

GET /v1/keywords?registry_hash=<Hash-or-omitted>
→ {keyword_registry_hash:Hash, definitions:[{definition_hash:Hash,definition:KeywordDefinition}]}
```

Question 精确结构为 `{id,question,options}`，同 generation.schema.json；answers每轮1–3项，每答案1–500码点。POST关联任务必须属于本人；不相关时null。ProposalStatus包含proposed/needs_clarification/ready_to_register/pending_implementation/approved/rejected/withdrawn；deprecated属于已批准注册项的后续状态，不能由普通提案改写。

服务端先分配 `custom.kw_<稳定小写标识>` 及version，并把 assigned_id/assigned_version固定传给词条生成器；模型不得更换。core命名空间和新builtin只能由开发者维护。预览的 candidate_hash 是完整规范化候选定义的哈希，覆盖已分配的 ID、版本、参数及实现。

confirm 使用普通 owner 鉴权，只接受 ready_to_register、当前 expected_revision 和完全相同的 candidate_hash。服务端不得在确认时重新调用模型或悄悄替换候选。校验范围包括严格结构、所有参数组合、语义、模板禁用指令、整体预算、运行时支持、命名空间和 ID/version 唯一性。

自动登记事务同时保存不可变定义与哈希、确认及检查记录、approved 状态和目录新版本；任何检查失败均不得部分发布。数据库唯一键与 CAS 防止并发确认覆盖定义。同 request_id 同内容重试返回原结果，改变内容返回409；修订、hash 或命名空间冲突必须明确返回，不能自动更换候选后继续登记。

admin approve 仅用于已完成开发与测试的 builtin 发布，或未来显式启用的人工模式；默认模板流程不调用它、不等待管理员队列。admin approve/reject 均须独立管理员鉴权，接口路径本身不是权限保证。

词条生成任务复用generation_jobs基础设施，但`kind=keyword`且输出遵循 [keyword-generation.schema.json](keyword-generation.schema.json)，不冒充卡牌的`ready`。正常输出为candidate（服务端预检后待玩家确认）、needs_clarification、requires_engine_extension；最后一种记录missing_capabilities并保持pending_implementation，不生成虚假builtin ID。

proposal_id与generation_job_id是不同对象；GET提案返回最近已提交且revision一致的生成结果。每次answers按CAS增长revision，旧job晚到只入审计。相同request_id+同请求体重试返回原结果；不同内容409。新一轮澄清不会绕过每轮上游次数和会话长度上限。

approved提案不能DELETE，返回409；未批准提案撤回为终态withdrawn，迟到结果不再改变它。rejected/withdrawn保留历史，再次尝试新建提案。废弃操作使用受保护的 `POST /v1/admin/keywords/{id}/versions/{version}/deprecate`，请求 `{request_id,reason}`，只改变注册状态；新目录hash改变，但已冻结对局仍使用其旧目录快照。

GET目录默认返回当前全量已批准公共目录，包括成功自动登记的模板；携带已知hash可读取该历史冻结目录，受限于规则版本兼容性。一个目录绑定固定schema/ruleset/compiler/interpreter部署版本，返回的定义和哈希按主规范排序。UI的提案状态轮询只访问项目后端，不重新请求模型。
新目录在后续对局选牌之前向双方完整公开，与具体牌组选择无关；自动登记不得热更新进行中对局的目录或改变其已冻结规则。

## 10. 未知关键词与暂停卡牌生成

模型遇到未知关键词必须返回 `needs_keyword_registration`，包含关键词提案和未解决意图，不能返回可运行卡牌。未解决意图由 proposals[].requested_behavior 及 questions 表达，不新增 unresolved_intent 字段。
该结果可以保留卡牌已确认的字段作为编辑上下文，但不能提供可确认导入的 draft_id/draft_hash。
禁止把未知关键词塞进 description、悄悄改成无关键词卡，或直接生成另一个行为假装等价。
后端保存 pending card generation 与 proposal_id 的关联，记录编辑修订、玩家已答问题及待解析引用。
同名已批准关键词有多个候选语义时先问玩家选择；不能只按第一个搜索结果绑定。
模板候选可表达时，界面展示预览与玩家确认入口；玩家确认到自动登记事务成功之间仍显示处理中。缺少引擎能力则明确展示 pending_implementation，不能暗示确认即可实现。
只有全部依赖已经自动登记成功或由开发者发布后，才能恢复该卡生成；后端绑定精确版本与 hash，重新解析参数、展开、校验和生成预览。
恢复任务还须原子核对 pending generation 所记录的 editor_revision 仍是当前修订；已经修改或取消的卡牌不自动恢复，不替换编辑内容。
恢复必须绑定精确关键词版本；迟到的批准通知不能覆盖玩家后来修改、取消或删除的草稿。
若仍缺卡牌参数则继续询问 card 作用域问题，不重复共享关键词的已确认定义。
提案被拒绝、废弃或存在不可表达语义时，保留原意并向玩家解释；替代方案必须由玩家明确选择。

## 11. 结构边界与语义验证分工

结构校验负责必填字段、联合类型、未知字段、整数类型、数组长度、文本长度以及占位对象唯一形状。
关键词定义结构上限：name 32 个 Unicode 码点、description 512 个码点、8 个别名且每个 1–32 个码点、4 个整数参数。
模板最多 4 个能力、每能力最多 4 个效果；合计最多 12 个效果由语义校验执行，不能只检查各数组长度。
卡牌关键词引用数量和字节上限以对应 CardSpec Schema 为准；任何模板上限都不是新增的额外卡牌预算。
语义校验负责注册状态、版本支持、命名冲突、参数实际用途、范围交集、模板禁用操作及引用权限。
编译后还必须检查整张卡的能力数量、总操作数、合法目标、总字节数和所有基础引擎约束。
不能仅检查某次参数实例恰好合法：预检与确认后的自动登记校验都必须证明声明参数的全部允许取值均满足对应操作的结构边界。
证明同时覆盖语义约束，例如 modify_stats 的参数组合不能允许两个 delta 同时为0。最多4个参数、每个范围最多16种取值，可穷举不超过65,536个组合或使用等价区间证明；不能只试最小/最大值就宣称所有语义合法。
运行期仍使用主规范的单行动队列、随机次数、属性层和清理预算；模板来源不获得独立额度。
对局异常必须按同一事务规则回滚状态和 RNG；不能跳过失败关键词、部分执行或调用模型修复正在进行的对局。

## 12. 哈希、同步和验收

冻结包必须包含精确 KeywordDefinition 版本及其规范化 hash、规则集版本、编译器版本和编译产物 hash。
CardSpec 的 definition_hash 仍按主规范计算；它不能单独证明所引用关键词的实现相同，必须同时校验冻结包。
所有 hash 由后端按主规范的规范化编码计算，不接受模型提供的值；编译缓存键必须包含依赖版本及 hash。
客户端和权威节点缺少任何冻结依赖时，必须拒绝进入对局并指出缺失项，不能自动替换成更新版本。
关键词注册表不能泄露对手隐藏卡牌的使用情况；冻结定义和来源信息的可见性遵循 [NETWORK_PROTOCOL.md](NETWORK_PROTOCOL.md)。
生成提示词只接收获准目录及参数边界；待提案名称可以作为未解决上下文，但不能混进可调用能力目录。
验收必须覆盖：未知关键词阻断、跨轮澄清、模板经玩家确认自动登记、无确认或越权确认失败、精确版本绑定、非法参数、范围交集及模板展开超额。
还须验证确认时 hash/修订冲突、重复确认幂等、模型伪造 approval_source 被拒绝、并发注册原子性，以及 builtin 仍等待真实引擎实现。
还应覆盖：token 引用模板拒绝、动态授予模板拒绝、过期关键词层保留基础层、废弃版本回放以及恢复任务的修订冲突。
同一冻结包、相同初始状态与行动序列必须得到相同领域事件和最终状态；不同显示名称不能改变执行排序。
