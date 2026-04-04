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
- `scenes/levels/`：可视化关卡编辑场景（`LevelRoot`、`LevelCell` 与具体关卡场景）。
- `levels/`：历史遗留目录，不得作为运行时关卡入口。
- `docs/`：架构与规范文档，改架构必须更新本文件。

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
4. `WorldCompiler` 重编译输出 `CompiledWorld`。
5. `BoardView` / `MemoryQueueView` 仅消费编译结果刷新画面。

## 9) 重编译流程
1. 新变化入列后检查容量。
2. 超容时先挤出最老未钉住变化。
3. 锁定输入并执行完整重编译：
   - 从默认世界重建（含 floor/wall/box/player/exit）。
   - 按队列时间顺序应用变化。
4. 冲突时对象幽灵化；无地板/越界/墙目标不会落地为实体。
5. 本轮产生的幽灵变化先收集，编译结束后统一追加。
6. 若追加后再次超容，开启下一轮完整重编译。
7. 单次输入最多触发 4 轮编译，超限报错并保留最后稳定结果。

## 10) 变化队列规则
- 队列保存变化事实，不保存推箱动画过程。
- 当前变化类型：
  - `PositionChange` -> `ChangeType.POSITION`
  - `EmptyChange` -> `ChangeType.EMPTY`
  - `GhostChange` -> `ChangeType.GHOST`
- 队列挤出只针对未钉住记录（`pinned=false`）。

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

## Assumptions / Deviations
- 第一版没有伤害、死亡、敌人、机关与门桥系统。
- 第一版未开放执念操作，仅保留队列字段与 UI 展示位。
