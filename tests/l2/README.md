# tests/l2 · 阶段四 T4-01 / T4-02 L2 断言

> 本目录只做**纯逻辑层（L2）**断言：`StorageKeys` 的键拼接/解析、`WriteQueue` 的合并/串行/失败保 dirty/写入顺序/块收缩、
> `Serializer` 的分块编解码与三级一致性校验、`SchemaMigration` 的版本链、`StorageDiagnostics` 的环形缓冲。
> 它**不证明**应用在设备上落盘成功，也不代替 L4（模拟器/真机）验证。结论以命令原文为准。

## 为什么不能直接跑 `.ets`

`entry/src/main/ets/**` 是 ArkTS 子集（`.ets`），Node 侧无法直接 `require`：

- `node --experimental-transform-types` 会擦掉 `interface` 声明、**但保留导入语句里的具名绑定**，
  ESM 链接期报 `does not provide an export named ...`（阶段三 `design/任务列表-第三阶段.md` §5.1.1 注 ① 已实测）；
- 用 DevEco 自带 tsc 做**类型级导入消解**，才正确擦除纯类型导入。

因此 `gen.js` 把整棵 `ets/` 按原目录结构复制成 `.ts`（**只改扩展名，不改任何 import 说明符**），
再由 `tsconfig.json` 指定的入口（`store/StorageKeys.ts`、`store/WriteQueue.ts`）编译出依赖闭包。

## 运行

```bash
node tests/l2/run.js
```

三步：① `gen.js` 生成 `tests/l2/.gen/src`；② tsc（DevEco 自带 4.9.5，`strict`）编译到 `.gen/out`；③ 依次执行断言。

`.gen/` 已由本目录 `.gitignore` 排除，不入库。

## 文件

| 文件 | 作用 |
| --- | --- |
| `gen.js` | `.ets` → `.ts` 复制（仅改扩展名） |
| `tsconfig.json` | `files` 显式列出被测入口，`strict` / `commonjs` / `ES2021` |
| `run.js` | 三步编排 + 汇总退出码 |
| `assert.js` | 极简断言器（PASS/FAIL 原文输出，便于贴证据） |
| `t401_keys.js` | 判据 **A2**：`chunkKey` / `chunkIndexOf` / `baseOfPartition` / `isChunked` / 键长预算 |
| `t401_queue.js` | 判据 **A3 / A4 / A7 / A8**：合并、重入去重、失败保 dirty、写入顺序、块收缩 |
| `t402_serializer.js` | 判据 **B2 / B3 / B4 / B5 / B6 / B9 / B10 / B11 / B12 / B13 + E1 / E2**：块长上限、逐条往返、单条守卫边界、块数一致性①②③、坏数据逐分区独立、版本号解析、加载期守卫 |
| `t402_migration.js` | 判据 **B7**：同版本直通、v0→v1 链式、版本倒退保留数据不降级、字段兜底、不删合法数据 |
| `t402_diagnostics.js` | 判据 **B8**：60 条写入后容量 50、`seq` 升序、首条 `seq = 11`、副本语义、`clear()` 后 `seq` 不回零 |

当前合计 **227 条断言**（A2 40 / A3-A8 35 / B 系 152）。

## 两个刻意的取舍

1. **`new WriteQueue()` 直接构造**：ArkTS 的 `private constructor` 只是编译期约束，运行时可用 `new`；
   用它取独立实例，避免单例状态在用例间串味。生产路径 `getInstance()` 返回的也是同一个类。
2. **fake `PartitionWriter` 自己实现 `trimChunks` 语义**（删索引 ≥ `keepCount` 的残块、幂等）：
   这是 §4.2 契约里**写面实现方**的责任，A8 断言的是「队列把正确的 `keepCount` 传下去 + 写面照约收缩」这一对行为。
3. **T4-02 的块字符串一律由被测的 `encodePartition` / `encodeHeader` 生成**（B12 除外——那条必须手工造
   「块内混入超长条目」的旧格式块），避免测试自己造一套格式而与实现漂移。

## 未覆盖（如实标注）

| 项 | 原因 |
| --- | --- |
| `PreferencesStore` 全部行为（判据 A5 / A6） | 依赖系统偏好能力，Node 侧无法解析；只能 L4（模拟器/真机）验证 |
| 真实分块落盘、`flush()` 批次效果、重启恢复 | 同上，L4，且需 T4-03 接线后才具备条件 |
| A5 的「非法 context」分支 | 无法合法构造非法 `Context`；T4-03 按「`init` 前 `isReady() === false`」+ 代码走查处理，并在报告标注「非法 context 分支未在设备上构造」 |
