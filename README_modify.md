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
