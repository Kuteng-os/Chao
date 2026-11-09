# 自定义卡牌联机协议 v1

本文件规定自定义卡牌进入 Godot 对局时的权威边界、同步、隐私及重连行为。
规范入口为 [CARD_INTEGRATION.md](./CARD_INTEGRATION.md)，卡牌定义必须通过 [card.schema.json](./card.schema.json)。
“必须”“禁止”为实现要求，“建议”为可调整的实现选择；示例中的类型名不是允许直接发送的字符串。
本协议不重复定义效果语义、事件预算或确定性算法；相关要求以主规范为唯一依据。

## 1. 部署与信任边界

- 生成后端调用 DeepSeek V4.1Flash，API 模型标识为 `deepseek-flash`；配置和能力检查由主规范约束。
- 生成后端持有模型 API Key，在玩家确认后完成自动校验登记与不可变卡牌入库；Godot 客户端不得持有运营方密钥。
- 无窗口 Godot 对局服务器执行回合与规则，不调用语言模型，不等待生成任务，也不接受模型直接下发的行动。
- 两个服务职责独立；对局服务器通过内部接口读取已发布定义，使用自己的服务凭证，不能复用模型密钥。
- 客户端只提交卡牌引用和行动意图；服务器决定卡牌是否可用、行动是否合法及最终结果。
- 公开公平匹配必须采用独立权威服务器；局域网房主模式只在双方信任房主诚实运行时成立。
- v1 不包含主机迁移。房主进程退出等同权威服务消失，不得声称还能可信裁定胜负。
- 公网业务令牌和重连令牌必须经加密通道传输；裸 ENet 仅用于受控局域网开发，公网需加密传输或可信隧道。
- 客户端不能通过 RPC 导入 GDScript、运行表达式、访问文件、请求任意 URL 或修改服务器注册表。

## 2. 基础类型与严格解码

- `UUID`：小写、带连字符的 UUID 文本；`Hash`：64 个小写十六进制字符，表示 SHA-256。
- `Slot`：整数 `0` 或 `1`；`Seq`：非负整数；`Revision`：大于等于 `1` 的整数。
- `EntityId`：服务器分配、对局内单调递增的正整数；`SignedInt`：`-2147483648..2147483647` 内整数，用于可低于零的总部生命。
- 除时间戳外，本文件定义的计数整数必须位于 `0..2147483647`；CardDefinition 数值遵循卡牌 schema。有限、数学上为整数且在范围内的数值（包括 `1.0`）先验证再规范化为整型；拒绝数字字符串、布尔值和带小数部分的数值。
- `TimestampMs`：`0..9007199254740991` 内的 Unix 毫秒整数，仅用于显示截止时间；服务器实际宽限计时使用单调时钟。
- `Token`：服务器生成的至少 256 位随机不透明令牌，以 base64url 编码；不得由玩家名或 peer ID 派生。
- 每条消息都是 JSON 对象，必须且只能包含对应消息形状列出的字段；嵌套对象同样拒绝未知字段。
- 禁止重复 JSON 键、NaN、Infinity、对象实例反序列化和隐式类型转换；字段不能省略，允许空值处显式使用 `null`。
- 传输层必须禁用 Godot 远程对象解码；如果 ENet 使用 Variant 编码，仍必须逐层执行相同白名单检查。
- 本文件的 `T[]` 表示数组，`A | B` 表示封闭联合类型；错误消息不得回显任意玩家输入。
- 客户端控制消息解码前上限为 16 KiB；公共能力目录消息上限为 1 MiB，其他服务器定义与快照消息上限为 4 MiB，以容纳累计公开的双方卡牌和目录依赖；超限拒绝，不允许无界分片累积。
- 限额属于传输防护，不能扩大主规范对卡牌、牌组、效果、目标数量或事件数量的限制。
- 同一连接每秒最多处理 20 条客户端控制消息；超过后返回 `RATE_LIMITED`，持续超限关闭连接。
- 消息必须经可靠有序通道发送；心跳与重连不能绕过身份和版本检查。

## 3. 卡牌身份、冻结与版本

`CardRef` 的精确形状：

```text
{card_id: UUID, revision: Revision, definition_hash: Hash}
```

`CardEnvelope` 的精确形状：

```text
{card_id: UUID, revision: Revision, definition_hash: Hash, interpreter_version: "interpreter-1", compiler_version:"card-compiler-1", keyword_bindings:KeywordBinding[], compiled_program_hash:Hash, definition: CardDefinition}
KeywordRef = {id:string, version:Revision, params:KeywordParams}
KeywordBinding = {id:string, version:Revision, definition_hash:Hash}
KeywordEnvelope = {definition_hash:Hash, definition:KeywordDefinition}
```

- `CardDefinition` 就是 schema 校验的完整对象；其根字段必须包含 `schema_version: "1.0.0"` 和 `ruleset_version: "frontline-1"`。
- 关键词独立注册；例如 `{id:"core.blitz",version:1,params:{}}` 与 `{id:"core.guard",version:1,params:{}}`，不是任意枚举字符串。
- KeywordDefinition 必须通过 [keyword.schema.json](./keyword.schema.json)；DSL 模板经玩家确认、服务端自动校验登记后即为 approved，可绑定其不可变版本，无须人工审核。新 builtin 仍须开发者实现后才能登记；批准状态由服务端维护，不属于模型生成的定义。KeywordParams 只允许所引用版本的 parameters 声明的键、类型与范围。
- keyword_bindings 必须覆盖 CardSpec、token 和授予效果引用的完整依赖，按 id/version 排序；同一 id/version 不得绑定不同定义哈希。
- compiled_program_hash 固定绑定主规范的 CompiledCard，包括 compiler_version；服务端用 `card-compiler-1` 和精确关键词版本重新编译核验，不查找“最新版”。
- `card_id`、`revision`、`definition_hash` 由生成后端签发；模型不能选择身份，客户端也不能覆盖。
- `definition_hash = SHA256(UTF8(canonical_json_v1(definition)))`；规范化函数及测试向量遵循主规范，不能各端自行实现不同规则。
- 对局服务器必须从可信卡牌存储按完整 `CardRef` 读取并重新校验哈希，不得相信客户端附带的卡牌定义。
- 修改任何定义字段必须发布新 revision；旧 revision 不可覆盖或删除正在进行的对局所需数据。
- 相同哈希的不同身份不自动互换；对局和回放始终保存完整 `CardRef`。
- 对局开始前冻结 schema、ruleset、interpreter、compiler 版本、双方完整卡牌引用、各牌 compiled_program_hash、精确关键词版本及 keyword_registry_hash；开始后禁止新增或热更新。
- 服务升级必须允许已有对局继续使用其冻结版本；不能把旧对局自动切换到新解释器。
- 定义只能由白名单 DSL 解释器执行，不能因通过哈希校验就跳过 schema、语义和预算验证。

## 4. 会话建立与身份绑定

客户端与服务器必须使用相同协议 `net-1`。下列形状列出了每个消息允许的全部字段：

```text
HELLO {type:"hello", protocol_version:"net-1", match_id:UUID, join_token:Token, schema_version:"1.0.0", ruleset_version:"frontline-1", interpreter_version:"interpreter-1", compiler_version:"card-compiler-1"}
WELCOME {type:"welcome", match_id:UUID, slot:Slot, session_id:UUID, resume_token:Token, state_seq:Seq}
CAPABILITY_CATALOG {type:"capability_catalog", match_id:UUID, keyword_registry_hash:Hash, definitions:KeywordEnvelope[]}
ERROR {type:"error", match_id:UUID|null, action_id:UUID|null, code:ErrorCode, retryable:bool, message:string}
```

- `join_token` 由可信大厅或房主会话服务签发，绑定比赛、席位和有效期；不得从玩家提交的 `slot` 选择身份。
- 服务器把当前真实连接/ENet peer ID 映射到 `session_id + match_id + slot`；所有后续消息使用该映射授权。
- 玩家不能通过修改 `match_id` 访问其他比赛；HELLO 前只允许 HELLO，重连连接只允许 RESUME。
- `WELCOME` 必须只发给对应连接；`resume_token` 不得广播、进入战斗回放或写入一般日志。
- 版本任一不匹配立即返回 `VERSION_MISMATCH`，关闭本次握手；不允许降级或自动映射未知版本。
- 加入令牌只允许成功消费一次；同一席位不得同时存在两个活动连接。
- 握手截止时间为 10 秒；未完成握手不占用正式席位，也不能触发开局。
- v1 必须在双方选牌前发送同一 approved 公共能力目录，approved 指已完成上述确认与服务端校验登记；它与实际牌组选择无关，不能根据对手选牌补发目录或只列对手正在使用的关键词。
- keyword_registry_hash 为完整公共目录的 KeywordBinding 数组按 id/version 排序、canonical_json_v1 编码后求 SHA-256；definition_hash 先按完整 KeywordDefinition 计算。
- 双方校验整个公共目录后才能选牌；不在该目录中的未发布/私有模板在 v1 拒绝，未来支持必须扩展协议，不能临时广播对手独有定义。
- 房间可在选牌前固定获准公共目录的子集；目录编码超过 1 MiB 时拒绝创建该配置，不得等对局中才裁剪，也不得根据玩家牌组选择目录子集。

## 5. 牌组装载、隐藏定义与准备

```text
DECK_SUBMIT {type:"deck_submit", match_id:UUID, refs:CardRef[]}
DECK_ACCEPTED {type:"deck_accepted", match_id:UUID, own_definitions:CardEnvelope[], own_refs:CardRef[], own_keyword_definitions:KeywordEnvelope[]}
ROSTER_LOCKED {type:"roster_locked", match_id:UUID, roster_hash:Hash, keyword_registry_hash:Hash, schema_version:"1.0.0", ruleset_version:"frontline-1", interpreter_version:"interpreter-1", compiler_version:"card-compiler-1"}
READY {type:"ready", match_id:UUID, roster_hash:Hash, keyword_registry_hash:Hash, own_definition_hashes:Hash[], own_compiled_program_hashes:Hash[]}
MATCH_STARTED {type:"match_started", match_id:UUID, roster_hash:Hash, keyword_registry_hash:Hash, state_seq:Seq}
```

- 玩家只能在准备阶段提交 refs；服务端检查所有权/可使用权限、发布状态、版本、定义合法性及主规范中的牌组限制。
- `refs` 中重复引用表示多张副本，必须保留其次数；`own_definitions` 按唯一 `CardRef` 去重。
- 服务器只把每名玩家自己的完整定义发给该玩家；另一名玩家只能得知准备状态和不透明 `roster_hash`。
- own_keyword_definitions 只标识自身卡牌依赖；即使目录内容公开，对手实际使用哪些唯一模板及其 id/version/哈希也可能泄漏牌组，禁止广播对手依赖子集。
- keyword_registry_hash 对应选牌前完整公共目录，不对应本局实际使用子集；服务端另存每张牌的精确 keyword_bindings 和 compiled_program_hash，但只向持有者或按公开时机发送。
- 自定义卡牌可能全局唯一；广播双方完整注册表、CardRef 列表或逐卡哈希，即使隐藏手牌实例也会泄漏对手牌组，必须禁止。
- `roster_hash` 是双方冻结牌组的带秘密随机盐承诺；不能直接对可猜测牌组或逐卡哈希求无盐哈希。
- 具体承诺输入为 `{match_id, compiler_version:"card-compiler-1", keyword_registry_hash, players:[{slot:0,refs:[...]},{slot:1,refs:[...]}], nonce}`，使用 canonical_json_v1 后求 SHA-256。
- `nonce` 为服务器随机生成的 64 字符小写十六进制文本，表示 32 字节；refs 按 card_id、revision、definition_hash 依次排序并保留重复。
- 盐、对手 refs 和未公开定义不向客户端发布；该承诺用于一致性绑定，不代表客户端已审阅对手牌组。
- 双方牌组验证完成后才能发送 ROSTER_LOCKED；锁定后禁止更换 refs，修改需取消本局准备并重新建立比赛。
- READY 的哈希数组必须恰为 own_definitions 中 definition_hash 的去重集合、按字典序排序，并与服务器记录一致。
- READY 的 own_compiled_program_hashes 同样为自身编译程序哈希的排序去重集合；两个会话哈希须与 ROSTER_LOCKED 一致，客户端核验自身关键词依赖及编译输出后才可 READY。
- 两名玩家均 READY 后才能创建初始局面；发送 MATCH_STARTED 后，服务器分别发送各自视角的 SNAPSHOT。
- 初始洗牌种子、牌库顺序和未公开随机状态不得放入上述任何消息。
- 牌组装载内部读取失败返回 `CARD_STORE_UNAVAILABLE`，本局不得部分开局；双方准备等待总上限为 120 秒。

## 6. 行动合同与幂等

```text
ACTION {type:"action", match_id:UUID, action_id:UUID, expected_state_seq:Seq, command:Command}
ACTION_RESULT {type:"action_result", match_id:UUID, action_id:UUID, accepted:bool, state_seq:Seq, code:ErrorCode|null}
```

`Command` 是下列精确形状的联合，禁止出现额外字段或自带结算结果：

```text
{kind:"play_card", hand_instance_id:UUID, targets:UnitTarget[]}
{kind:"attack", attacker_id:EntityId, target:TargetRef}
{kind:"advance", unit_id:EntityId}
{kind:"end_turn"}
{kind:"concede"}
UnitTarget = {kind:"unit", entity_id:EntityId}
TargetRef = UnitTarget | {kind:"headquarters", owner:Slot}
```

- play_card.targets 必须为空或恰有一个单位目标，与 CardSpec.play_target 一致；不能手选总部、多个目标或部署位置。单位自动进入自己的 support，指令无部署位置。
- play_card、attack、advance、end_turn 只能由当前回合玩家提交并操作其自有对象；concede 在 active 状态允许任一玩家提交，立即判提交者负，对手胜。暂停及终局仍适用下述统一拒绝规则。
- Command 仅规定线格式；目标、费用、移动、攻击与投降条件必须由冻结规则引擎验证，不能从字段存在推断合法。
- ACTION 不包含玩家编号、随机结果、伤害值或卡牌定义；服务器从连接身份确定玩家，并自行计算全部结果。
- 服务器先检查消息结构和身份，再查幂等记录，再检查序列、对局状态和规则，最后原子提交。
- 幂等索引为 `(match_id, session_id, action_id)`；记录额外绑定原始 `expected_state_seq` 和规范化 Command 哈希。
- 完全相同的重试必须返回原始 ACTION_RESULT，不再次扣费、抽牌、产生事件或推进回合。
- 同一 action_id 改变序列或 Command 必须拒绝为 `ACTION_ID_CONFLICT`；不同连接不能复用他人的幂等记录。
- session_id 在合法重连后不变，但必须重新绑定真实 peer；不能只按可变的 ENet peer ID 保存幂等记录。
- 幂等检查必须先于陈旧序列检查，否则成功后丢失回执的正常重试会被误判为过期操作。
- 非重复行动的 expected_state_seq 必须等于当前序列，否则返回 `STALE_STATE` 并补发该玩家视角快照。
- 暂停、未开局和已结束时分别拒绝 `MATCH_SUSPENDED`、`MATCH_NOT_STARTED`、`MATCH_ENDED`，不得推进时钟或规则。
- 非法行动 accepted=false 不改变战斗状态；运行期预算故障按主规范回滚并中止，返回 RULE_BUDGET_EXCEEDED。accepted=true 后统一提交结果、事件与序列，再发回执和快照。
- 幂等记录至少保存至比赛结束后 120 秒；重试必须保留 action_id、原始序列及 Command，不得偷偷生成新 ID。
- 客户端等待 3 秒未收回执可用完全相同的 ACTION 重试，最多 2 次；随后请求重连快照，禁止持续重复发送。

## 7. 玩家视角快照与公开定义

```text
SNAPSHOT {type:"snapshot", match_id:UUID, state_seq:Seq, roster_hash:Hash, keyword_registry_hash:Hash, viewer:Slot, state:ViewerState, revealed_definitions:CardEnvelope[], revealed_keyword_definitions:KeywordEnvelope[]}
SYNC_REQUEST {type:"sync_request", match_id:UUID, last_state_seq:Seq}
```

`ViewerState` 是展示状态，精确字段如下；它不替代服务器内部规则状态，也不新增战斗规则：

```text
ViewerState = {status:"active"|"suspended"|"ended"|"aborted", turn_number:Seq, active_player:Slot|null, players:PlayerView[], board:UnitView[], own_hand:HandView[], public_discards:DiscardView[], winner:Slot|null}
PlayerView = {slot:Slot, headquarters_health:SignedInt, headquarters_max_health:Seq, credits:Seq, max_credits:Seq, hand_count:Seq, deck_count:Seq}
HandView = {instance_id:UUID, card:CardRef}
UnitView = {entity_id:EntityId, owner:Slot, source:CardSource, zone:"support"|"front", attack:Seq, health:Seq, max_health:Seq, can_attack:bool, can_advance:bool, keywords:KeywordRef[]}
DiscardView = {owner:Slot, card:CardRef}
CardSource = {kind:"card", card:CardRef} | {kind:"token", parent:CardRef, token_id:string}
```

- players 必须恰有两项并按 slot 排序；own_hand.length 必须等于玩家自身 hand_count；board 不得含重复 entity_id。
- UnitView.keywords 是当前实际生效的 KeywordRef 集合，包含有效 params，不是裸关键词名称；参数校验、去重和叠加语义遵循主规范；token_id 必须匹配 parent.tokens 中的标识。
- source 只能引用服务器已装载的定义；卡牌实体与 token 实体身份必须唯一，禁止把数组下标当稳定 ID。
- 已死亡单位完成其原子结算后移出 board；展示 health 不传负数；其他数值含义、上限、行动能力均由主规范的规则推导。
- can_attack / can_advance 只表示该单位当前可尝试该类动作，不能代替具体目标、资源或回合验证。
- v1 public_discards 按弃置发生顺序列出已打出的指令及从公开战场死亡的非 token 卡牌；保留重复副本，不含 token 或从隐藏牌库烧毁的牌，禁止因此公开未打出的定义。
- DTO 和所有消息必须实现对应严格校验器；禁止把服务器内部 state 字典直接填入 ViewerState。
- viewer 由服务器身份映射填入，客户端不能请求他人视角；SYNC_REQUEST 只触发请求者自己的过滤快照。
- 隐藏手牌不得含对手实例 ID、CardRef、定义哈希、卡名、费用或占位对象中的真实信息；只传规则允许公开的计数。
- 隐藏牌库不得含卡牌身份、顺序、随机种子、随机生成器内部状态或可推断下一次随机结果的数据。
- 第一次公开卡牌时，同一快照提供 CardEnvelope 及此前隐藏的实际关键词绑定；依赖定义须来自既定公共目录，验证精确版本、定义哈希和 compiled_program_hash 后才能渲染规则文本。
- 公开召唤物引用其父卡冻结定义中的 token；不得在对局中由客户端临时生成新定义。
- revealed_definitions 必须包含截至该序列已公开定义的完整去重集合；不能只发送可能丢失的增量，也不能含未公开定义。
- revealed_keyword_definitions 同样只标识截至该序列因公开卡牌/效果而公开的依赖集合；不能夹带尚未公开卡牌的独有依赖关系或编译程序。
- 已公开定义的历史缓存不应随卡牌回到手牌而删除，但不代表其当前隐藏位置公开。
- 公共弃牌堆仅在规则明确公开时同步身份；服务器日志、回放、调试 RPC 也必须遵守同样的观察权限。
- state_seq 在每次原子战斗提交及暂停、恢复、结束等生命周期变化后递增；客户端忽略旧快照，同一视角同序列快照必须一致。
- 服务器必须为两个视角分别构造快照，禁止先广播全量状态再让客户端隐藏 UI。
- 客户端展示动画可以预测，但正式资源、胜负和后续合法输入必须依据已确认的快照。

## 8. 断线、暂停、重连与结果

```text
HEARTBEAT {type:"heartbeat", match_id:UUID, nonce:UUID}
HEARTBEAT_ACK {type:"heartbeat_ack", match_id:UUID, nonce:UUID}
RESUME {type:"resume", protocol_version:"net-1", match_id:UUID, session_id:UUID, resume_token:Token, last_state_seq:Seq, roster_hash:Hash, keyword_registry_hash:Hash, schema_version:"1.0.0", ruleset_version:"frontline-1", interpreter_version:"interpreter-1", compiler_version:"card-compiler-1"}
RESUMED {type:"resumed", match_id:UUID, session_id:UUID, resume_token:Token, state_seq:Seq, roster_hash:Hash, keyword_registry_hash:Hash, compiler_version:"card-compiler-1", own_definitions:CardEnvelope[], own_keyword_definitions:KeywordEnvelope[]}
CONNECTION_STATE {type:"connection_state", match_id:UUID, state_seq:Seq, status:"active"|"suspended"|"ended"|"aborted", absent_slots:Slot[], deadline_unix_ms:TimestampMs|null, winner:Slot|null, reason:"started"|"peer_offline"|"both_offline"|"resumed"|"disconnect_forfeit"|"both_offline_timeout"|"rules_result"|"rule_budget_exceeded"}
```

- 心跳间隔 5 秒；连续 20 秒无有效传输或底层报告断线时，服务器确认该玩家掉线，开始宽限计时。
- 一名玩家掉线，比赛立刻 suspended，暂停回合及效果时钟，不再接受新行动；已开始的原子行动完整提交后暂停。
- 仅一名玩家掉线时宽限为 30 秒墙钟时间；截止仍未归来则判其负，另一名玩家胜，并记录 `disconnect_forfeit`。
- 双方都掉线时，服务器从第二人掉线起保留对局 120 秒；这一状态覆盖之前的单人 30 秒判负计时。
- 双方均未返回且 120 秒到期，比赛 aborted，winner=null，记录 `both_offline_timeout`，不得生成获胜奖励或排名结果。
- 在双方离线保留期内仅一人返回，进入单人缺席状态，给仍离线玩家新的 30 秒宽限；双方都返回则恢复比赛。
- RESUME 必须验证比赛、session_id、令牌、有效期及全部冻结版本（包括 compiler_version）；不能仅凭 peer ID、玩家名、IP 或旧快照恢复身份。
- 重连必须仍使用冻结的关键词版本、registry hash 和每卡编译哈希；可重发原公共目录，但实际使用绑定仅重发自身及已公开部分，不能用最新目录或服务端使用子集修复缓存。
- 恢复成功后原子失效旧令牌、生成新令牌、重绑真实 peer；发送 RESUMED 后补发完整玩家视角快照及可见定义。
- 为防 RESUMED 丢失，保存成功 RESUME 的规范请求摘要、旧令牌摘要及原回执 30 秒：同一完整请求可重试并返回同一新令牌；新的重连事务成功后立即删除上一事务缓存，禁止旧请求回滚会话。
- 同一 session 的重复连接不能同时操作；验证成功的新连接替换旧连接，旧连接立即失效。
- 暂停期间不补算回合时钟或效果 tick；只有回到 active 才从暂停前剩余时长继续。
- 已结束对局重连只读查看结果，不能重开行动；独立服务器结束后至少保存结果与幂等记录 120 秒。
- 房主客户端和权威进程同在时，房主进程消失无法执行上述服务端计时；幸存客户端显示“对局中止”，不自行签发权威胜负。
- 服务器进程崩溃且无持久恢复能力也按中止处理；v1 不包含主机迁移、自动接管或跨版本恢复。

## 9. 错误、审计与验收

- `ErrorCode` 是封闭枚举：`INVALID_MESSAGE`、`UNAUTHORIZED`、`VERSION_MISMATCH`、`RATE_LIMITED`、`CARD_NOT_FOUND`、`CARD_NOT_ALLOWED`、`CARD_HASH_MISMATCH`、`KEYWORD_NOT_APPROVED`、`KEYWORD_VERSION_MISMATCH`、`KEYWORD_REGISTRY_MISMATCH`、`COMPILED_PROGRAM_MISMATCH`、`INVALID_DECK`、`CARD_STORE_UNAVAILABLE`、`PREPARATION_TIMEOUT`、`ACTION_ID_CONFLICT`、`STALE_STATE`、`ILLEGAL_ACTION`、`MATCH_NOT_STARTED`、`MATCH_SUSPENDED`、`MATCH_ENDED`、`RULE_BUDGET_EXCEEDED`、`RESUME_EXPIRED`、`INTERNAL_ERROR`。
- ERROR.message 长度不超过 200 个 Unicode 标量，面向玩家使用中文；不得包含密钥、令牌、未公开卡牌、供应商原始响应或内部堆栈。
- 生成错误由生成后端接口处理，不得伪装成对局行动结果；生成任务失败不改变已冻结对局。
- 服务端记录 match_id、session_id、action_id、规则版本、卡牌引用、行动与确定性事件；敏感定义按权限隔离。
- 记录不能包含模型 API Key、join_token 或 resume_token；客户端可下载的回放必须按主规范的观察权限过滤。
- 验收必须覆盖伪造玩家、未知字段、重复键、错误类型、重复行动、同 ID 篡改、旧序列、过期令牌和版本不符。
- 验收必须证明抓取任一玩家收到的完整流量，仍不能直接获得对手尚未公开的定义、手牌、牌库顺序或随机状态。
- 验收还需覆盖未公开关键词使用子集泄漏、同 id/version 内容被替换、参数超界、编译哈希不符，以及注册表更新后老对局/重连仍使用旧冻结版本。
- 验收必须覆盖重复 READY、未齐准备开局、准备超时、定义存储故障、断线30秒判负、双离线120秒无胜者、重新连接与房主退出。
- 验收必须重放相同冻结定义和事件输入得到相同结局；事件上限和递归终止测试遵循主规范，不在本协议另设规则。
