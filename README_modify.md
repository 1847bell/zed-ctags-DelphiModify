# README 修改版（README_modify.md）

本文件说明**本 fork 相对原版做了哪些修改、为什么改、以及如何在本地使用**。原版英文说明见 [README.md](README.md)。

> 本项目是 [mazurel/zed-ctags](https://github.com/mazurel/zed-ctags) 的本地定制版，面向 **Windows + Delphi/Pascal** 开发场景。上游基于 [netmute/ctags-lsp](https://github.com/netmute/ctags-lsp)。

---

## 一、这个项目是什么

一个 Zed 编辑器扩展，把 Universal Ctags 包装成 LSP 服务器，提供：

- 跳转到定义（go to definition）
- 工作区/文档符号搜索
- 代码补全（符号名前缀匹配）

分两部分：

| 部分 | 位置 | 说明 |
|---|---|---|
| 扩展本体（Rust → wasm） | `src/`、`extension.toml` | 非常小，只负责找到服务端二进制并启动它 |
| LSP 服务器（Go，预编译 exe） | `server/ctags-lsp.exe` | **打过补丁的本地构建**，直接提交在仓库里 |

---

## 二、相对上游的修改

### 1. 预置服务端二进制，不再运行时下载

上游扩展首次启动时从 GitHub Releases 下载 ctags-lsp。本 fork：

- 把编译好的 `ctags-lsp.exe` 直接放在 `server/` 目录并提交
- 扩展启动时检查 `ctags-lsp-project/ctags-lsp.exe` 是否存在，不存在则报安装错误（提示重跑安装脚本）
- 好处：离线可用、版本完全可控、不依赖 GitHub 连通性

### 2. Pascal/Delphi 支持

- `extension.toml` 启用语言列表加入 `Pascal`（同时支持 C、C++、Python）
- 服务端补丁：**Pascal 变量只与当前 .pas 文件关联**。
  - ctags 扫描工作区时会跳过所有 Pascal 变量条目（不进全局索引）
  - 跳转定义时，只对当前文件做变量声明扫描；当前文件命中就直接返回，避免多个 .pas 里同名变量导致的多重定位
  - 带 LRU 缓存（最近 10 个文件），文件修改后自动失效
- 另有 Pascal 限定名（`procedure TClass.Foo`）声明→实现跳转支持

### 3. 磁盘索引（减少内存占用）

上游把全部符号索引放内存，大工程（百万级符号）会占用 1 GB 以上内存。本 fork 的服务端默认改为**磁盘索引**：

- 位置：`<工作区根目录>\.ctags-lsp\index\`，分 `names/`（符号名桶）、`prefix/`（首字母桶）、`files/`（每文件记录）、`meta/`（代数）四类
- 重启 Zed 后直接复用磁盘索引，不重新扫描
- 文件保存时只增量重扫该文件
- 可用 `--index-dir` 参数或 `CTAGS_LSP_INDEX_DIR` 环境变量改位置（绝对路径，或相对工作区）
- 配套内存优化：
  - 文件内容缓存改为 LRU（上限 32 个文件 / 20 万行）
  - 跳转定义单次最多返回 50 个位置；工作区符号最多 500 条；补全每次最多 200 条
  - GC 调优（GOGC 40 + 512 MiB 软上限）

> `.ctags-lsp\` 在项目根目录下，建议加入项目自身的 `.gitignore`/SVN 忽略列表。

### 4. Windows 路径修复

修复了 Windows 下盘符 file URI 解析错误（`/C:/...` → `C:/...`），中文路径全链路（URI 编解码、ctags 输出、文件读取）验证可用。ctags 对文件类型 tag 输出 `"pattern": false` 导致整个扫描中止的问题也已修复。

### 5. ctags 二进制配置

- 优先读环境变量 `CTAGS_BIN`
- 未设置时 Windows 默认 `D:\Tools\ctags\ctags.exe`，其它平台 `ctags`
- 要求 Universal Ctags 且支持 `--output-format=json`

---

## 三、安装使用（本地）

### 前置条件

- [Universal Ctags](https://github.com/universal-ctags/ctags)（JSON 输出支持），本机默认路径 `D:\Tools\ctags\ctags.exe`
- Zed 编辑器

### 安装步骤

仓库无 CI 后，手动打包/安装：

1. 构建扩展 wasm（需要 `rustup target add wasm32-wasip1` 和 `cargo install cargo-component --locked`）：

   ```sh
   cargo component build --release --target wasm32-wasip1
   ```

2. 组装扩展目录：

   ```
   ctags/                          # 任意临时目录
   ├── extension.toml              # 根目录复制
   ├── extension.wasm              # target/wasm32-wasip1/release/zed_ctags*.wasm
   └── server/
       └── ctags-lsp.exe           # server/ctags-lsp.exe
   ```

3. 拷贝到 Zed 扩展目录：

   ```powershell
   $dst = "$env:LOCALAPPDATA\Zed\extensions\installed\ctags"
   New-Item -ItemType Directory -Force -Path $dst | Out-Null
   Copy-Item extension.toml,extension.wasm $dst

   $work = "$env:LOCALAPPDATA\Zed\extensions\work\ctags\ctags-lsp-project"
   New-Item -ItemType Directory -Force -Path $work | Out-Null
   Copy-Item server\ctags-lsp.exe $work
   ```

4. 重启 Zed。

### 启用

`settings.json`（全局 `%APPDATA%\Zed\settings.json` 或项目 `.zed/settings.json`）：

```jsonc
"languages": {
  "Pascal": {
    // "!omnipascal" 表示显式停用 omnipascal；若无需共存可去掉
    "language_servers": ["ctags-lsp", "!omnipascal"]
  }
}
```

验证：`zed: open log` 里应能看到 ctags-lsp 启动记录；状态栏/语言服务器菜单显示 Universal Ctags LSP。

---

## 四、服务端参数速查（`ctags-lsp.exe --help`）

| 参数 | 说明 | 默认 |
|---|---|---|
| `--ctags-bin <name>` | ctags 可执行文件路径 | `ctags`（扩展会传 `CTAGS_BIN` 或 `D:\Tools\ctags\ctags.exe`） |
| `--tagfile <path>` | 使用现成 tags 文件而非扫描 | 未使用（扩展当前不传） |
| `--languages <value>` | 传递给 ctags 的语言过滤 | 全部 |
| `--jobs <value>` | ctags 并发进程数 | 8 |
| `--index-mode <value>` | `disk` / `memory` | `disk` |
| `--index-dir <path>` | 磁盘索引目录（绝对或相对工作区） | `.ctags-lsp/index` |
| `--log-file <path>` | 诊断日志路径；仅 diagnostic 构建默认写 | 未开启 |

---

## 四点五、CPU / 内存占用的取舍说明

本服务端在启动索引阶段和 GC 行为上有意做了一些取舍，遇到 CPU 占用偏高时按下面的说明判断是否正常、如何调：

### 正常的 CPU 高峰（不需要处理）

- **首次打开工作区**（或 `.ctags-lsp\index` 不存在时）：服务端会启动最多 `--jobs`（默认 **8**）个 ctags 进程并行扫描全部源文件，期间 CPU 多核占用接近满载是预期行为。扫描完成后回落到接近 0。HIS 这类几千文件的工程通常几秒到几十秒内完成。
- **保存单个文件**：只重扫该文件，CPU 波动很小。

### 有意的 GC 调优（省内存、多花一点 CPU）

服务端启动时设置了 `debug.SetGCPercent(40)` 和 `debug.SetMemoryLimit(512MiB)`（见 `main.go` 的 `main()`）：

- `SetGCPercent(40)`：堆增长到原来的 1.4 倍就触发 GC（Go 默认 2 倍）。**GC 更频繁 → 后台 CPU 略高，常驻内存明显更低**。这是为了把内存从最初的 ~1 GB 压下来，属于"用 CPU 换内存"的主动选择。
- `SetMemoryLimit(512MiB)`：软上限，堆接近 512 MiB 时 GC 全力回收。只影响 Go 堆（符号索引、缓存），不含 ctags 子进程。
- 如果你的机器内存充裕、更在意 CPU，可以改回默认：删掉 `main()` 里这两行重新编译即可。

### CPU 持续偏高的排查顺序

1. **索引是否在反复重建**：`.ctags-lsp\index` 目录的时间戳反复刷新、或 Zed 日志里反复出现 `scan workspace start`，说明索引没有成功落盘（多半是权限/杀毒软件拦截写入），服务端每次启动都全量重扫。
2. **`--jobs` 调低**：扩展目前固定不传 `--jobs`，默认 8 并发。低配机器可在扩展启动参数里加 `--jobs 2`（改 `src/ctags_lsp.rs` 的 `get_ctags_lsp_args` 后重编 wasm）。
3. **排除无关语言**：只关心 Pascal 时，加 `--languages Pascal` 让 ctags 跳过其他语言的解析（同样是改 `get_ctags_lsp_args`）。
4. **确认用的是磁盘索引模式**：`--index-mode memory`（上游默认行为）会把百万级符号常驻内存且每次启动全量重扫，CPU 和内存双高。当前版本默认 `disk`，除非显式传参否则不应该是这个原因。
5. **ctags 进程残留**：任务管理器里看到多个 `ctags.exe` 常驻不退出属于异常（正常扫描完就退出），先杀掉 `ctags-lsp.exe` 和 `ctags.exe` 再重启 Zed。

---

## 五、开发说明

- **改 Rust 扩展**：`cargo component build --release --target wasm32-wasip1` 后需重新安装/拷贝 wasm，Zed 里才生效；格式检查 `cargo fmt -- --check`
- **改 Go 服务端**：源码在另一仓库（`ctags-lsp-src`，推送至 `git.1847bell.xyz/1847bell/zed-ctags-lsp-local-save.git`，`memory-optimization` 分支含全部服务端改动）。构建：

  ```sh
  go test ./...
  go build -ldflags "-X main.version=<本地版本号>" -o ctags-lsp.exe .
  ```

  然后把新 exe 覆盖 `server/ctags-lsp.exe` 和 Zed work 目录两处。**不要**用上游 release 的二进制覆盖——必须是本补丁版
- 旧版本服务端备份以 `server/ctags-lsp.pre-*.exe` 命名保留，不再需要时可删

---

## 六、致谢

- [Universal Ctags](https://github.com/universal-ctags/ctags)
- [netmute/ctags-lsp](https://github.com/netmute/ctags-lsp)
- [mazurel/zed-ctags](https://github.com/mazurel/zed-ctags)
- [Zed](https://zed.dev)
