# AGENTS.md

## 适用范围与协作

- 本文件适用于整个仓库；子目录存在 `AGENTS.md` 时，遵循其更具体的约定。
- 默认使用中文沟通，说明修改结果、验证结果及未执行检查的原因。
- 修改前检查 `git status --short`，保留已有改动和暂存状态，围绕当前需求做最小必要变更。
- 项目事实以当前源码、`composer.json`、`web/package.json` 和配置文件为准；README 中的版本与目录说明可能滞后。

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->

没有 CodeGraph 索引时，优先使用 `rg` 和 `rg --files` 定位源码；不要为普通代码修改自动建立索引。

## 项目概况

- MineAdmin 是后台管理系统，当前仓库同时包含 PHP 后端与 `web/` 前端。
- 后端使用 PHP **>= 8.2**、Hyperf **3.2**、Swoole **>= 5.0**；扩展要求见 `composer.json`，Swoole 应关闭 short name。
- 后端命令在 Linux、WSL 或项目容器中执行，避免使用不具备 Swoole 环境的 Windows PHP。
- 前端使用 Vue 3、TypeScript、Vite 8、Element Plus、Pinia 和 UnoCSS；Node.js 须同时满足 `web/package.json` 的 `engines` 与当前 Vite 的要求。
- 前端沿用安装命令和 Playwright 配置中的 pnpm。后端通过 `.env` 配置数据库、Redis 等连接；参考 `.env.example`，保留现有本地配置。

## 目录与职责

| 目录或文件 | 职责 |
| --- | --- |
| `app/Http/Admin/` | 管理端控制器、请求校验、中间件和订阅器 |
| `app/Http/Api/` | 对外 API 与版本化接口 |
| `app/Http/Common/` | 公共中间件、请求 traits、响应结构和响应码 |
| `app/Service/` | 业务逻辑和事务编排 |
| `app/Repository/` | 数据访问、查询筛选与排序 |
| `app/Model/` | 数据模型、关联、枚举和类型转换 |
| `app/Schema/` | Swagger/OpenAPI 数据结构 |
| `app/Library/DataPermission/` | 数据范围规则与切面 |
| `app/Command/` | 安装、更新等控制台命令 |
| `config/` | 容器、路由和 `autoload/` 配置 |
| `databases/migrations/`、`databases/seeders/` | 数据库结构迁移与初始化数据 |
| `plugin/` | 后端插件；`web/src/plugins/` 为前端插件 |
| `tests/` | Hyperf/PHPUnit 测试与引导文件 |
| `web/src/modules/` | 按业务组织的 API、页面和语言资源 |
| `web/src/router/`、`web/src/store/`、`web/src/provider/` | 路由、Pinia 状态和服务提供者 |
| `web/src/utils/http.ts`、`web/types/` | HTTP 封装与公共类型 |
| `web/tests/e2e/` | Playwright 端到端测试 |

## 常用命令

后端命令在仓库根目录执行，运行前确保 PHP 扩展和依赖满足要求。

| 命令 | 用途 |
| --- | --- |
| `composer install` | 根据 `composer.lock` 安装依赖 |
| `composer dev` | 启动 Hyperf watcher 开发服务 |
| `composer start` | 启动 Hyperf 服务，HTTP 端口见 `config/autoload/server.php`，当前为 9501 |
| `composer analyse` | PHPStan level 5，检查 `app/` 与 `config/` |
| `vendor/bin/php-cs-fixer fix app --dry-run --diff` | 检查后端格式并显示差异 |
| `composer cs-fix` | 应用 PHP 格式修复；优先把修复限制在本次修改的文件 |
| `composer test` | 先执行 `migrations` 组，再执行其他测试 |
| `composer coverage` | 按相同分组顺序生成测试覆盖率 |

前端命令在 `web/` 目录执行。

| 命令 | 用途 |
| --- | --- |
| `pnpm install` | 安装前端依赖 |
| `pnpm dev` | 启动开发服务，端口由 `VITE_APP_PORT` 控制 |
| `pnpm lint:tsc` | 执行 `vue-tsc --noEmit` 类型检查 |
| `pnpm exec eslint .` | 执行 ESLint 检查，可用本次修改的路径缩小范围 |
| `pnpm exec stylelint 'src/**/*.{css,scss,vue}'` | 执行样式检查，可按修改文件缩小范围 |
| `pnpm build` | 构建前端 |
| `pnpm test:e2e` | 执行 Playwright；配置会启动开发服务，并访问 `http://localhost:2888` |

`pnpm lint`、`pnpm lint:eslint` 和 `pnpm lint:stylelint` 包含自动修复步骤，会修改文件；检查后复核差异。依赖安装使用现有清单和锁文件，依赖升级应属于当前任务范围。

## 实现约定

- PHP 使用 `declare(strict_types=1)`、PSR-4 命名空间与现有文件头；格式以 `.php-cs-fixer.php` 为准。
- 沿用 Controller → Service → Repository → Model 的职责分工，通过构造器注入依赖，参考同业务目录中的现有实现。
- 请求参数由对应 Request 校验，优先使用 `validated()`；接口沿用 `App\Http\Common\Result` 的 `code`、`message`、`data` 结构和 `ResultCode`。
- 管理端接口遵循现有路由 attributes、认证中间件、`Permission` 权限码与操作日志约定；数据访问遵循已有数据权限规则。
- 修改接口时同步核对 Request、Schema、前端 API 类型、权限码以及相关测试；数据库结构通过迁移文件演进。
- Vue 与 TypeScript 使用两空格缩进、UTF-8、LF 和文件末尾换行，遵循 `web/.editorconfig`、`web/eslint.config.js` 与 `web/stylelint.config.js`。
- 前端 API 沿用 `useHttp()` 封装；共享类型放在现有类型文件中，保持 `@`、`#`、`$` 路径别名和自动导入约定。
- 页面、API、语言资源优先归入对应业务模块；复用已有组件、Pinia store 和 provider。
- 配置从环境变量和现有配置层读取；提交内容不得包含本地凭据、令牌或上传数据。
- 不手工修改 `vendor/`、`node_modules/`、`runtime/`、构建产物或生成的 Swagger 文件。

## Git 提交规范

- 提交使用 `acc:acc-commit` 技能的 Conventional Commits 格式：`type(scope): 简洁说明`；`scope` 可省略。本节覆盖 `CONTRIBUTING.md` 中旧的 `文件名: 说明` 格式约定。
- `type` 使用英文：`feat`（功能）、`fix`（修复）、`docs`（文档）、`refactor`（重构）、`perf`（性能）、`test`（测试）、`build`（构建与依赖）、`ci`（流水线）、`chore`（维护）、`revert`（回退）。
- `scope` 使用清晰的模块名，如 `agents`、`server`、`deploy`；默认用中文描述具体改动，避免只写“更新”“修复”等无法说明内容的标题。
- 不兼容变更使用 `type(scope)!: 简洁说明` 或 `BREAKING CHANGE:` 页脚，并说明影响和迁移方式。
- 一个提交围绕一个明确目的；彼此独立的功能、修复、部署配置和文档改动分别提交。
- 暂存前检查 `git status --short`、对应路径的 `git diff`、`git diff --cached` 和近期提交 `git log -5 --oneline`；使用 `git add -- <路径>`，同一文件存在无关改动时使用 `git add -p -- <路径>` 选择本次修改。
- 保留已有无关改动和暂存状态；提交前确认提交范围，不把无关暂存内容并入本次提交。
- 提交前复核 `git diff --cached`，执行 `git diff --cached --check`，并完成与改动类型相符的验证。必要时在提交正文补充修改原因、影响和验证结果；失败或未执行的检查须如实说明。
- 仓库位于 WSL 时使用 WSL Git 执行提交，避免 Windows Git 产生执行权限差异。
- 用户要求提交时执行 `git commit`；推送、打标签和发布按用户授权的范围执行，强制推送或改写历史须有用户明确要求。

提交标题示例：

```text
docs(agents): 统一 ACC Git 提交规范
feat(server): 支持通过环境变量配置 HTTP 监听地址
ci(deploy): 同时发布 ACR 和 GHCR 镜像
```

## 验证与交付

- 修改 PHP 后先对改动文件执行 `php -l`，再运行适用的格式检查、`composer analyse` 和相关测试。
- **后端测试会迁移、写入或删除数据，只能在隔离的测试数据库与 Redis 环境运行。** 参考 `CONTRIBUTING.md` 和 `.github/ci/`，不要使用生产或共享业务连接。
- 定向执行测试前，确保隔离环境已完成 `migrations` 组初始化。例如检查用户数据访问：`vendor/bin/co-phpunit --prepend tests/bootstrap.php --exclude-group=migrations --filter UserRepositoryTest`。
- 修改前端后执行类型检查及相关 lint；涉及构建或页面行为时执行 `pnpm build` 或对应 E2E。E2E 的开发端口配置应与 Playwright 的 2888 保持一致。
- 纯文档修改核对内容、路径和差异即可；检查无法运行时明确说明原因，不把未执行的检查描述为通过。
- 交付前复核本次改动和暂存状态。需要提交时遵循本文件的 Git 提交规范，并说明相关验证结果。
