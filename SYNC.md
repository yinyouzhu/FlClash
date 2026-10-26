# 上游同步手册

本仓库是 [chen08209/FlClash](https://github.com/chen08209/FlClash) 的二次开发 fork。
目标：上游的功能持续跟进，自己的改动集中、可回滚、冲突可控。

## 分支约定

| 分支 | 含义 | 规则 |
|---|---|---|
| `main` | 上游镜像 | 只 ff-only 合并上游，不放自己的代码 |
| `dev` | 二次开发主线 | 所有自己的提交在这里 |
| `feature/*` | 单个功能 | 从 `dev` 切出，完成后合回 `dev` |

```sh
git diff upstream/main --stat    # 我到底改了什么
git log --oneline upstream/main..dev   # 我的提交列表
```

## 同步

```sh
tool/sync_upstream.sh                 # 跟到 upstream/main
tool/sync_upstream.sh v0.9.3          # 跟到某个发布版本（更稳）
tool/sync_upstream.sh v0.9.3 --build  # 顺带验证 macOS debug 构建
```

脚本做这些事：fetch → 快进 `main` 并推送 → 合并进 `dev` → 更新
`core/Clash.Meta` → `pub get` → `build_runner` → 丢弃纯哈希噪音 →
`flutter analyze`。

有冲突时脚本会停下，解决后重跑即可。

## 冲突处理

| 文件 | 处理方式 |
|---|---|
| `pubspec.yaml` | 手解 |
| `pubspec.lock` | 不手解，`flutter pub get` 重生成 |
| `*.g.dart` / `*.freezed.dart` / drift 产物 | 不手解，`build_runner --delete-conflicting-outputs` 重生成 |
| `arb/*.arb` | 手解；自己的 key 加 `x` 前缀 |
| `changelog.json`、`CHANGELOG.md`、版本号 | 先取上游，再打自己的版本 |
| `.gitmodules`、`core/Clash.Meta` 指针 | 一律取上游，除非决定 fork Core |

## 子模块

`core/Clash.Meta` 是子模块（mihomo）。默认只跟随上游 pin：

```sh
git submodule update --init --recursive
git status              # core/Clash.Meta 不应出现在 modified 里
```

确需改 Core 才 fork `chen08209/Clash.Meta`，并同步修改 `.gitmodules`。
误提交子模块指针会让别人 clone 失败。

## 改动策略

优先新增文件，少改上游文件：

- 新功能放 `lib/features/<名字>/`，通过已有 provider / 路由挂进去
- 不动 `lib/app.dart`、`lib/main.dart`、`lib/providers/**` 这类上游高频区
- 每完成一个功能提交一次，提交信息写清"为什么"

## 发布

```sh
dart setup.dart macos            # 出 dist/FlClash-<版本>-macos-<arch>.dmg
dart setup.dart macos --env stable
```

DMG 是 ad-hoc 签名，对外分发需自备 Developer ID 与公证。

## 许可

GPL-3.0。对外分发必须提供对应源码并保持 GPL-3.0 授权。
