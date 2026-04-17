# ENGINEERING_RULES

## 1) 项目目标
- 本工程实现《健忘者》第一关可玩原型。
- 核心模型固定为：`默认世界 + 当前记忆队列变化 -> 重编译现实`。
- 第一关要求：玩家到达出口即可通关，玩家移动不入队列，推箱与沉思入队列。

## 2) 术语表
- **变化（Change）**：进入记忆队列的记录，记录“事实结果”。
- **空变化（Empty Change）**：沉思生成的无物理效果变化。
- **重编译（Recompile）**：以默认世界为基准，顺序应用当前队列变化构建现实。
- **幽灵态（Ghost）**：变化无法实体落地时的落地形式，不占实体格。
- **执念（Obsession）**：将变化钉住，使其不被正常挤出（本版仅预留字段/展示）。
- **Scene-based Level**：以 `LevelRootTemplate.tscn + LevelCellTemplate.tscn` 作为编辑模板，在编辑器内可视化摆格子的关卡表达。

## 3) 目录结构约定
- `scripts/core/`：纯数据与纯规则，不依赖场景节点。
- `scripts/game/`：游戏流程编排与输入路由。
- `scripts/entities/`：实体 View 的纯表现脚本。
- `scripts/level_editor/`：关卡编辑脚本与关卡数据提取（仅编辑器表现与关卡数据，不含玩法规则）。
- `scenes/game/`：关卡运行时场景。
- `scenes/levels/`：仅存放实际关卡场景（`LevelNNN.tscn`）。
- `scenes/level_editor/`：关卡编辑器场景与模板资产（如 `LevelRootTemplate`、`LevelCellTemplate`）。
- `levels/`：历史遗留目录，不得作为运行时关卡入口。
- `docs/`：架构与规范文档，改架构必须更新本文件。
- `scripts/tests/`：headless 逻辑测试入口（文本断言，不做画面比较）。

## 4) 单一关卡真源（强约束）
- 现在**只支持** scene-based level editing。
- `LevelRoot` 是唯一合法关卡输入与唯一真源。
- 运行时只允许：`PackedScene(level_scene)` -> `LevelRoot.build_runtime_data()` -> `LevelRuntimeData` -> `WorldDefaults`。
- 严禁新增/恢复 `LevelDefinition` 运行时入口。
- 严禁恢复 `level_scene` / `level_resource` 双通路或任何 fallback。
- 不做旧 Resource 关卡兼容，原因：避免双通路、双语义、双维护成本污染工程。

## 5) Scene-based 关卡编辑约定
- `LevelRoot` 为 `@tool` 主节点，导出 `grid_size: Vector3i`、`memory_capacity`、`cell_size` 等字段。
- `LevelRoot` 固定网格层级：`Grid/Slice_z/Cell_x_y_z`，即使当前只编辑 `z=0` 也保留切片结构。
- `LevelCell` 为 `@tool` 子节点，维护单格数据：
  - `coord: Vector3i`
  - `has_floor`
  - `content_type`（`EMPTY/WALL/BOX`）
  - `is_player_spawn`
  - `is_exit`
- `LevelCell` 的无地板约束：当 `has_floor=false` 时，内容与出生点/出口会被自动清空。

## 6) 编辑器数据到运行时映射
`LevelRuntimeData` 必须作为唯一中间数据，字段如下：
- `grid_size`
- `memory_capacity`
- `player_start`
- `exit_position`
- `floor_cells`
- `walls`
- `boxes`

`WorldDefaults` / `CompiledWorld` 必须完整保留并使用：
- `floor_cells`
- `wall_positions`
- `default_entity_positions`
- `player_start`
- `exit_position`
- `memory_capacity`

## 7) 运行时格子语义（必须一致）
- 玩家可进入格：格内、有地板、不是墙、没有箱子。
- 玩家当前版本不实现掉落死亡；玩家不能进入无地板格。
- 箱子可稳定存在格：格内、有地板、不是墙、没有别的箱子、不是玩家格。
- 推箱目标无地板：允许推动，但箱子掉落并从运行时世界移除。
- 推箱目标越界/墙/箱子：不允许推动。

## 8) 核心数据流
1. `GameController` 读取 `level_scene` 并实例化 `LevelRoot`。
2. `LevelRoot.build_runtime_data()` 生成 `LevelRuntimeData`。
3. `WorldDefaults.from_runtime_data()` 构建默认世界。
4. `GameController.player_memory_slots`（玩家属性，默认 `1`）覆盖 `WorldDefaults.memory_capacity` 后，再交给 `WorldCompiler`。
5. `WorldCompiler` 重编译输出 `CompiledWorld`。
6. `BoardView` / `MemoryQueueView` 仅消费编译结果刷新画面。

## 9) 重编译流程
1. 新变化入列后检查容量。
2. 超容时先挤出最老未钉住变化。
3. 锁定输入并执行完整重编译（两阶段）：
   - 阶段 A（remembered world）：从默认箱子状态出发，仅按 surviving queue 顺序解释 remembered change；此阶段禁止读取当前玩家最终位置。
   - 阶段 A 的 player 时序：先用 live player 位置按 remembered `POSITION.move_delta` 倒序回推 replay 起点；解释每条 remembered `POSITION` 后，replay-time player 同步前进一步；`EMPTY/GHOST` 不推动 player。
   - 阶段 B（projected live world）：把阶段 A 的 remembered 结果投影到当前玩家位置；若 remembered 实体箱子与玩家/实体冲突则投影为 live ghost，不直接删除。
4. `Ghost[AUTO_GHOST]` 是状态事件：只把“当前 remembered 位置”的箱子改为幽灵，不定义新位置；`target_position` 仅允许作为调试元数据。
5. 默认箱子在记忆归零后必须先恢复 remembered 实体；若当前玩家正占默认格，live 投影显示幽灵，不可直接消失。
6. `core` 层编译必须产出 `CompileResult.replay_trace`，该 trace 是 compile/stabilize 的正式过程历史（含 pass_begin / queue_focus / move / ghostify / generated_change / queue_update / queue_restart），禁止在 `game` 层从最终 surviving queue 反推完整 replay。
7. replay 必须消费 `CompileResult.replay_trace` 顺序播放，确保玩家看到的是“本轮编译实际经历的每一步”；`Empty` 仍可作为独立 beat 并触发玩家 pulse。
8. replay payload 的 from-state 必须来自 replay-time state 的前序结果（entity/ghost），禁止按 subject 做最终态 canonical 归约。
9. replay gate 只基于：存在 replayable pushed_out 且 compile trace 含可播放事件（move / ghostify / beat_empty）。
10. replay 微步与 remembered world 解释必须共用同一语义：先 X 后 Y；`Ghost[AUTO_GHOST]` replay step 必须是原地状态变化（`from == to`），禁止单独制造位移。
11. recompile 表现层必须分层：先做 `MemoryQueueView`（evict/append/settle）反馈，再做棋盘 `Board replay` 重建；棋盘层禁止承担 evict 离场表现。
12. `MemoryQueueView` 与 `Board replay` 必须按 compile trace 的同一节拍同步：trace 到 `queue_focus` 时先高亮 slot，再在对应 `move/ghostify/beat_empty` 拍内完成棋盘变化；`queue_restart` 必须可见地进入下一轮 pass。
13. 当 trace 出现 `generated_change` 时，`MemoryQueueView` 必须在同轮通过 `queue_update` 立即播放“新记忆进入队列 + 必要挤出”反馈，再进入 `queue_restart` 的下一轮重放；禁止只在最终 render 时静态刷新。
14. `WorldCompiler` 必须在“每个 entry 执行后”立即检测冲突并产出 generated change；一旦产出，当前 pass 立即结束并写入 `queue_update -> queue_restart`，禁止整轮结束后统一补 ghost。
15. 默认回放节拍为每记忆约 1 秒（prepare/action/tail），优先保证可读性；禁止恢复“上方先播完、下方再整体快放”的解耦节奏。
16. remembered queue 应用（compile/replay）必须维护每个 subject 的“当前 remembered 位置 + 是否幽灵”：
   - `Position`：从当前 remembered 位置位移并更新位置，状态重置为非幽灵；
   - `Ghost`：仅在当前 remembered 位置原地幽灵化（from==to），不得单独制造位移；若前序 surviving 位移已被挤出，则当前位置回落为默认初始位置。
17. 单次输入最多触发 4 轮编译，超限报错并保留最后稳定结果。
18. live append 的队列事务 owner 固定为 pre-recompile 阶段：若 pre-recompile 已完成 incoming + takeover/append + evict + settle，replay 阶段禁止重复播放同一事务；replay 仅保留 queue_focus、queue_restart，以及 compile trace 中真实由 `generated_change` 触发的 `queue_update` 动画。
19. replay 中 `queue_update` 的播放时机必须晚于对应 board item（`move/ghostify/beat_empty`）：先播 board，再播该次 queue_update；禁止 queue_update 先行导致视觉因果倒置。

## 10) 变化队列规则
- 队列保存变化事实，不保存推箱动画过程。
- 当前变化类型：
  - `PositionChange` -> `ChangeType.POSITION`
  - `EmptyChange` -> `ChangeType.EMPTY`
  - `GhostChange` -> `ChangeType.GHOST`
- `Ghost[AUTO_GHOST]` 是正式 remembered memory，不是仅 world 层临时结果；可独立存活，也会像其他 change 一样被正常挤出。
- `Ghost` 记录可保留 `target_position` 作为来源调试信息，但该字段不得被解释为应用落点位置。
- 队列挤出只针对未钉住记录（`pinned=false`）。

## 11) 场景层与逻辑层边界
- `core` 层禁止依赖 `Node`/`SceneTree`。
- `game/entities` 层只做输入、渲染、同步，不实现核心规则。
- `level_editor` 只维护关卡可视化编辑与关卡数据抽取，不掺入推箱/重编译规则。
- 规则修改必须在 `core` 层完成，再由 `game` 层消费结果。
- replay 只允许存在于 `scripts/game/` 与 `scenes/game/`，不得写入 `core` 真相；`core` 只输出编译结果与挤出记录。
- ReplayController 回放必须使用 `ReplayLayer` 上的独立 replay actor；禁止直接复用/位移 `BoardView` live `BoxView` 本体。
- replay 期间 live subject 仅可临时隐藏，回放结束后清理 replay actor 并恢复 live 显示；最终位置始终以 `CompiledWorld` 同步结果为准。

## 12) 命名规范
- 采用 Godot 4 typed GDScript。
- 一类一文件，类名使用 PascalCase，方法/变量 snake_case。
- 禁止 magic string 表示变化类型，统一通过 enum/const。
- 关键流程打印日志前缀：`[Recompile]`。

## 13) 二维编辑与三维预留原则
- 当前编辑和运行画面仍为 2D。
- 关卡坐标、关卡尺寸统一使用 `Vector3i` 进行底层表达。
- 运行时可按需投影到 `Vector2i`（当前仅使用 `z=0` 切片）。
- 禁止把“永远只有二维”写死到关卡数据结构。

## Assumptions / Deviations
- 第一版没有伤害、死亡、敌人、机关与门桥系统。
- 第一版未开放执念操作，仅保留队列字段与 UI 展示位。

## 14) Headless 逻辑测试
- `scripts/tests/headless_logic_harness.gd` 作为可选的历史逻辑测试入口保留。
- 当前默认验证流程不包含 headless harness，不依赖编辑器手动操作。
- 每个 case 必须输出：case name、initial state、action、final state、queue state、PASS/FAIL，并通过进程退出码表达整体成功/失败。
- harness 的职责边界：
  - 覆盖 `LevelRoot.build_runtime_data() -> WorldDefaults.from_runtime_data() -> WorldCompiler.compile()` 的正式数据链路。
  - 覆盖 `CompiledWorld` 的 floor/wall 查询与玩家/箱子语义查询。
  - 覆盖正式玩法路径：移动、阻挡、推箱落地、推箱落空、重编译后玩家位置保持。
- 仅在明确需要排查逻辑回归时，手动运行 `godot --headless --path . --script scripts/tests/headless_logic_harness.gd`。
- 禁止把该可选测试降级成只测 resolver 的局部单测；应保持对生产路径数据构建与重编译步骤的覆盖能力。
- 该 harness 不进行截图或视觉断言，只做文本断言。

## 15) 当前逻辑回归命令
按顺序执行：
1. `godot --version`
2. `godot --headless --import --path .`
3. `godot --headless --path . --quit`

## 16) 竖屏 UI 结构（Web/手机优先）
- 运行时 UI 采用竖屏优先布局：顶部状态与变化队列、中部棋盘、底部操作区。
- 顶部变化队列必须绑定真实 `ChangeQueue` 数据，使用可区分的小方块表达 `Position/Empty/Ghost`。
- 底部操作区提供方向按钮与沉思按钮，必须接入正式输入路径，禁止纯装饰按钮。
- 角落保留“复制日志”按钮，不能遮挡主要玩法区域。

## 17) Debug 复制日志边界
- 复制功能用于排查运行态，不得影响核心流程成功与否。
- 文本构建与复制执行分离：formatter 负责生成文本，UI/控制器负责写剪贴板。
- 日志内容至少包含：玩家/箱子、queue、关卡尺寸、floor/wall 概要、最近重编译原因、最近 replay 摘要。
- 若平台剪贴板失败，允许降级输出到控制台并提示，但不得中断游戏。

## 18) Web / GitHub Pages 发布流程
- Web 导出使用仓库内 `export_presets.cfg` 的 `Web` preset，输出目录 `build/web/`。
- CI workflow 位于 `.github/workflows/deploy-web.yml`：在 `main` 分支 push 后执行导入、Web 导出并发布到 GitHub Pages。
- 发布产物必须是静态目录，不允许人工上传构建文件。

## 19) 版本信息来源（UI Build Info）
- 运行时版本信息统一来自构建时生成文件 `generated/build_info.json`，禁止在场景文本硬编码，也禁止从文档手抄版本。
- `build_info.json` 至少包含：`version`、`short_sha`、`build_date`。
- `BuildInfo.display_text()` 规则：
  - 文件存在且 `short_sha` 有效：显示 `v{version} · {short_sha}`（若 version 为空则显示 `build {short_sha}`）。
  - 文件不存在/内容无效：显示 `dev`。
- GitHub Pages 构建在 `.github/workflows/deploy-web.yml` 的 `Write build metadata` 步骤写入该文件：
  - `short_sha` 使用 `${GITHUB_SHA::7}`；
  - `build_date` 使用 UTC 时间（ISO8601，`YYYY-MM-DDTHH:MM:SSZ`）。
- 因此 Pages 上线产物会反映对应 workflow 构建提交的 short sha，本地未生成文件时稳定显示 `dev` fallback。

## 20) 核心变化解释器（2026-04 重构）
- 记忆队列保存的是**变化**（change record），不是世界快照/最终态。
- `POSITION` 与 `GHOST` 是同层级变化：
  - `POSITION`：基于 subject 当前状态应用位移（优先 `move_delta` 语义）；
  - `GHOST`：只改变幽灵状态，不改变当前位置。
- 重编译统一流程：`defaults -> surviving queue interpret -> generated changes append -> stabilize`。
- 初始化落位失败与运行中落位失败都走统一冲突规则：`ConflictRules -> 产出 GHOST change`，禁止静默消失。
- `WorldCompiler` 只负责编排；变化语义在 `ChangeInterpreter + handlers + rules`。
- replay 主数据源为 `CompileResult.replay_trace`；`ReplayPayloadBuilder` 仅允许作为兼容层，不得再作为正式 replay 真相来源。
- 允许连锁变化：handler 可通过 `CompileContext.add_generated_change()` 产出后续变化；编译器负责多轮收敛与安全上限。


## 21) 关卡编辑器工作流（2026-04）
- 关卡文件统一保存在 `scenes/levels/LevelNNN.tscn`，由 `LevelRootTemplate` 实例化并保存为 `LevelRoot` 根节点。
- 编辑入口场景为 `scenes/level_editor/LevelEditorScene.tscn`：左侧列出现有关卡并提供编辑/删除，底部提供新增关卡。
- 新增关卡使用顺序编号策略：扫描现有 `LevelNNN`，创建 `max+1`（如 `Level003`）。
- 关卡编辑区顶部显示当前关卡名与尺寸；尺寸通过 `X/Y + 更新` 按钮触发 `LevelRoot.rebuild_grid()`。
- 编辑工具分为「放置/删除」模式与工具项（地块/墙/箱子/玩家唯一/过关点唯一）。
- 玩家与过关点属于唯一对象：放置新对象时先清除旧对象，保持运行时语义与编辑器可视状态一致。
- 编辑器保存/导出必须先基于 `LevelRoot.snapshot_level_state()` 提取纯数据快照，再构建干净 `LevelRoot` 副本落盘或导出，禁止直接打包正在编辑中的 live 节点树。
- 编辑器保存必须执行三段 roundtrip 对比：`editor live snapshot -> clean root apply_snapshot snapshot -> saved scene load snapshot`，任一差异都必须报错并输出 `EDITOR_SAVE` 分类日志，禁止静默成功。
- 编辑器导出文本必须基于同一快照数据源，并包含关卡编号、尺寸、memory_capacity、legend 与稳定矩形字符网格（含无地板标记）。
- 编辑器与运行时都允许通过标准信号 `request_main_menu` 回到主菜单；场景子节点不得自行实例化主菜单。
- 运行时仍仅通过 `PackedScene -> LevelRoot.build_runtime_data()` 加载。

## 22) 调试日志分类（2026-04）
- 统一通过 `scripts/debug/debug_log.gd` 输出分类日志，当前分类为：`EDITOR_SAVE`、`LEVEL_LOAD`、`ANIMATION`。
- 默认开关：`EDITOR_SAVE=true`、`LEVEL_LOAD=true`、`ANIMATION=false`。
- 动画/重编译过程诊断日志必须归类到 `ANIMATION`，默认关闭，避免淹没关卡保存与加载排查日志。
- 关卡保存链和进关构建日志必须分别归类到 `EDITOR_SAVE` 与 `LEVEL_LOAD`，并使用统一字符网格语义：`# . B P E _`。
