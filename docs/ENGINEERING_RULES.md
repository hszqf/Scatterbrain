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
- **Scene-based Level**：以 `LevelRoot.tscn + LevelCell.tscn` 在编辑器内可视化摆格子的关卡表达。

## 3) 目录结构约定
- `scripts/core/`：纯数据与纯规则，不依赖场景节点。
- `scripts/game/`：游戏流程编排与输入路由。
- `scripts/entities/`：实体 View 的纯表现脚本。
- `scripts/level_editor/`：关卡编辑脚本与关卡数据提取（仅编辑器表现与关卡数据，不含玩法规则）。
- `scenes/game/`：关卡运行时场景。
- `scenes/levels/`：可视化关卡编辑场景（`LevelRoot`、`LevelCell`）。
- `levels/`：旧版关卡资源（Resource），禁止把关卡硬编码到脚本。
- `docs/`：架构与规范文档，改架构必须更新本文件。

## 4) Scene-based 关卡编辑约定
- `LevelRoot` 为 `@tool` 主节点，导出 `grid_size: Vector3i`、`memory_capacity`、`cell_size` 等字段。
- `LevelRoot` 固定网格层级：`Grid/Slice_z/Cell_x_y_z`，即使当前只编辑 `z=0` 也保留切片结构。
- `LevelCell` 为 `@tool` 子节点，维护单格数据：
  - `coord: Vector3i`
  - `has_floor`
  - `content_type`（`EMPTY/WALL/BOX`）
  - `is_player_spawn`
  - `is_exit`
- `LevelCell` 的无地板约束：当 `has_floor=false` 时，内容与出生点/出口会被自动清空。
- 默认建格时铺满地板；内容绘制与坐标标签由 `LevelCell` 负责即时刷新。

## 5) 核心数据流
1. `GameController` 接收输入。
2. 若触发推箱/沉思，构造 `ChangeRecord` 并追加到 `ChangeQueue`。
3. `WorldCompiler` 执行重编译，输出 `CompileResult`。
4. `BoardView` 与 `MemoryQueueView` 使用结果刷新画面。

## 6) 关卡数据入口（双通路）
- 保留旧通路：`LevelDefinition(Resource)` -> `WorldDefaults.from_level()`。
- 新增通路：`LevelRoot(Scene)` -> `build_runtime_data()` -> `LevelRuntimeData` -> `WorldDefaults.from_runtime_data()`。
- `GameController` 可通过 `level_scene` 选择 scene-based 关卡；若未配置则回退到 `level_resource`。

## 7) 关卡校验约束（LevelRoot）
- 必须且只能有 1 个玩家出生点。
- 必须且只能有 1 个出口。
- 无地板格子上不能放置墙/箱子/出生点/出口。
- 校验失败输出明确错误日志，便于编辑器内修正。

## 8) 重编译流程
1. 新变化入列后检查容量。
2. 超容时先挤出最老未钉住变化。
3. 锁定输入并执行完整重编译：
   - 从默认世界重建。
   - 按队列时间顺序应用变化。
4. 冲突时对象幽灵化。
5. 本轮产生的幽灵变化先收集，编译结束后统一追加。
6. 若追加后再次超容，开启下一轮完整重编译。
7. 单次输入最多触发 4 轮编译，超限报错并保留最后稳定结果。

## 9) 变化队列规则
- 队列保存变化事实，不保存推箱动画过程。
- 当前变化类型：
  - `PositionChange` -> `ChangeType.POSITION`
  - `EmptyChange` -> `ChangeType.EMPTY`
  - `GhostChange` -> `ChangeType.GHOST`
- 队列挤出只针对未钉住记录（`pinned=false`）。

## 10) 幽灵生成规则
- 目标格被已落地实体占据，或目标格为玩家格：实体变化变幽灵。
- 幽灵可见、半透明、不阻挡、不参与实体占格冲突。
- 幽灵化会产生新的 `GhostChange` 并延迟追加进队列。

## 11) 场景层与逻辑层边界
- `core` 层禁止依赖 `Node`/`SceneTree`。
- `game/entities` 层只做输入、渲染、同步，不实现核心规则。
- `level_editor` 只维护关卡可视化编辑与关卡数据抽取，不掺入推箱/重编译规则。
- 规则修改必须在 `core` 层完成，再由 `game` 层消费结果。

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

## 14) 新增功能更新约束
- 新增变化类型、冲突规则、执念逻辑时，必须同时更新：
  1. `scripts/core/*` 对应数据结构与编译逻辑
  2. `MemoryQueueView` 展示
  3. 本文档相关章节
- 若有机制偏离，先写入下方 Assumptions / Deviations 再实现。

## Assumptions / Deviations
- 第一版没有伤害、死亡、敌人、机关与门桥系统。
- 第一版未开放执念操作，仅保留队列字段与 UI 展示位。
