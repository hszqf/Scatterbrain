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

## 3) 目录结构约定
- `scripts/core/`：纯数据与纯规则，不依赖场景节点。
- `scripts/game/`：游戏流程编排与输入路由。
- `scripts/entities/`：实体 View 的纯表现脚本。
- `scenes/game/`：关卡运行时场景。
- `levels/`：关卡资源（Resource），禁止把关卡硬编码到脚本。
- `docs/`：架构与规范文档，改架构必须更新本文件。

## 4) 核心数据流
1. `GameController` 接收输入。
2. 若触发推箱/沉思，构造 `ChangeRecord` 并追加到 `ChangeQueue`。
3. `WorldCompiler` 执行重编译，输出 `CompileResult`。
4. `BoardView` 与 `MemoryQueueView` 使用结果刷新画面。

## 5) 重编译流程
1. 新变化入列后检查容量。
2. 超容时先挤出最老未钉住变化。
3. 锁定输入并执行完整重编译：
   - 从默认世界重建。
   - 按队列时间顺序应用变化。
4. 冲突时对象幽灵化。
5. 本轮产生的幽灵变化先收集，编译结束后统一追加。
6. 若追加后再次超容，开启下一轮完整重编译。
7. 单次输入最多触发 4 轮编译，超限报错并保留最后稳定结果。

## 6) 变化队列规则
- 队列保存变化事实，不保存推箱动画过程。
- 当前变化类型：
  - `PositionChange` -> `ChangeType.POSITION`
  - `EmptyChange` -> `ChangeType.EMPTY`
  - `GhostChange` -> `ChangeType.GHOST`
- 队列挤出只针对未钉住记录（`pinned=false`）。

## 7) 幽灵生成规则
- 目标格被已落地实体占据，或目标格为玩家格：实体变化变幽灵。
- 幽灵可见、半透明、不阻挡、不参与实体占格冲突。
- 幽灵化会产生新的 `GhostChange` 并延迟追加进队列。

## 8) 场景层与逻辑层边界
- `core` 层禁止依赖 `Node`/`SceneTree`。
- `game/entities` 层只做输入、渲染、同步，不实现核心规则。
- 规则修改必须在 `core` 层完成，再由 `game` 层消费结果。

## 9) 命名规范
- 采用 Godot 4 typed GDScript。
- 一类一文件，类名使用 PascalCase，方法/变量 snake_case。
- 禁止 magic string 表示变化类型，统一通过 enum/const。
- 关键流程打印日志前缀：`[Recompile]`。

## 10) 新增功能更新约束
- 新增变化类型、冲突规则、执念逻辑时，必须同时更新：
  1. `scripts/core/*` 对应数据结构与编译逻辑
  2. `MemoryQueueView` 展示
  3. 本文档相关章节
- 若有机制偏离，先写入下方 Assumptions / Deviations 再实现。

## Assumptions / Deviations
- 第一版没有伤害、死亡、敌人、机关与门桥系统。
- 第一版未开放执念操作，仅保留队列字段与 UI 展示位。
