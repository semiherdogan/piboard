# PiBoard V1 Technical Spec (original)

This is a Markdown conversion of the original V1 technical spec, `PiBoard_v1_project.docx`, written in Turkish. The text below is kept in Turkish as in the source. The docx itself was removed from the working tree in commit `2f4e6d3`; read it with `git show 2f4e6d3^:PiBoard_v1_project.docx > /tmp/spec.docx`.

Where this spec and the code differ, the code wins. Deliberate V1 deviations:

| Spec says | Shipped V1 |
| --- | --- |
| Bundled Node.js 22.19+ (section 5, 6) | Bundled Node 24 (`scripts/fetch-node.sh` pins 24.21.0) |
| Keyboard shortcuts table (section 27) | No keyboard shortcuts in V1; every action is reachable from visible UI (matches section 42.1 and 42.18) |
| SwiftUI drag/drop (section 12, 35) | Custom board drag (`BoardDragController`) instead of system drag-and-drop |
| Separate beta and stable feeds (section 42.14) | One `appcast.xml`; beta items carry `<sparkle:channel>beta</sparkle:channel>` |
| Current macOS, architecture unspecified | macOS 26, arm64 only (the bundled Node binary is arm64) |
| Developer ID sign, notarize, staple (section 42.14) | Free Apple account, so releases are ad-hoc signed and not notarized; Developer ID path exists but is optional |
| Open in VS Code only (section 26) | `ExternalAppService` with VS Code, Cursor, Zed, Terminal, iTerm, Warp and Finder |

Other differences are listed in [architecture.md](architecture.md) where they matter. The one-to-one conversion starts below.

---

# PiBoard

**V1 Teknik Proje Dokümanı**

Native macOS Kanban + Pi Agent Workspace

Durum: V1 scope freeze / implementasyona hazır taslak

- Hedef platform: Güncel macOS
- Ana teknoloji: Swift + SwiftUI + SQLite + PTY
- Agent: earendil-works/pi

## 1. Yönetici Özeti

PiBoard, proje bazlı çalışan native bir macOS uygulamasıdır. Kullanıcı projelerini yerel klasör path'leriyle tanımlar, her proje için bağımsız bir Kanban board kullanır ve task'ları Backlog, In Progress ve Done kolonları arasında yönetir. Bir task In Progress'e alındığında Pi otomatik başlamaz. Önce task prompt'u düzenlenebilir bir hazırlık ekranında açılır. Kullanıcı current working tree veya izole bir Git worktree seçer ve ardından Pi session'ını başlatır.

PiBoard ayrı bir chat arayüzü üretmez. Pi'nin interaktif terminal arayüzü gerçek bir PTY üzerinden uygulamanın içine gömülür. Kullanıcı agent çıktısını izleyebilir, istediği anda terminale yazabilir ve aynı Pi session'ını daha sonra devam ettirebilir. Done durumu hiçbir zaman agent tarafından otomatik verilmez; son karar kullanıcıya aittir.

## 2. Ürün İlkeleri ve V1 Sınırı

- Project birinci sınıf entity'dir. Project değişince board ve task listesi tamamen değişir.
- Workflow state ile process state ayrıdır. In Progress, Pi'nin çalışıyor olduğu anlamına gelmez.
- PiBoard Pi'nin yerine geçmez. Pi'yi başlatır, bağlamını yönetir ve terminalini sunar.
- Pi session history PiBoard tarafından kopyalanmaz. Pi kendi session formatının source of truth'udur.
- Kullanıcının `~/.pi/agent` alanı PiBoard tarafından sahiplenilmez veya taşınmaz.
- Done insan kararıdır. Agent exit olduğunda task otomatik Done olmaz.
- Git operasyonları V1'de minimum tutulur. Worktree yaratılır, ancak merge/rebase/cherry-pick UI yapılmaz.
- Sadece güncel macOS hedeflenir. Eski macOS compatibility için UI veya mimari taviz verilmez.

## 3. V1 Kullanıcı Akışı

```
Project seç
  -> Task oluştur / sırala
  -> Backlog -> In Progress
  -> Prompt'u gözden geçir ve düzenle
  -> Current Working Tree [default] veya New Worktree
  -> Güvenlik kontrolleri
  -> Start Pi
  -> Canlı PTY terminal
  -> Pi ile konuş / yönlendir / devral
  -> Pi exit ederse gerektiğinde Resume
  -> Kullanıcı task'ı Done'a taşır
```

## 4. Bilgi Mimarisi

```
PiBoard
├── Projects
│   └── Project Board
│       ├── Backlog
│       ├── In Progress
│       └── Done
├── Task Detail / Preparation
├── Terminal Workspace
└── Settings
    ├── Pi Runtime
    └── App Preferences
```

## 5. Teknoloji Yığını

| Katman | Seçim | Not |
| --- | --- | --- |
| Platform | macOS, güncel sürüm | Native desktop uygulaması |
| Dil | Swift | Ana uygulama ve servis katmanı |
| UI | SwiftUI | NavigationSplitView, Inspector, Sheets, Settings |
| Terminal | PTY + terminal view | Gerçek interaktif TTY davranışı |
| Persistence | SQLite | Project/task/app metadata |
| Agent runtime | Pi | Uygulamadan bağımsız güncellenebilir |
| JS runtime | Bundled Node.js 22.19+ | Sistem Node'una bağımlılık yok |
| Git | /usr/bin/git veya resolved git | Status ve worktree operasyonları |
| Editor integration | VS Code | Project/task working directory açma |

## 6. Pi Entegrasyonu: Doğrulanmış Davranışlar

Pi CLI güncel kaynaklarında interactive mode, session persistence, project trust, package update ve resource discovery için PiBoard'un ihtiyaç duyduğu primitive'leri sağlıyor. V1 aşağıdaki davranışlara dayanır.

| Konu | Doğrulanan davranış | PiBoard kararı |
| --- | --- | --- |
| Node | Pi Node.js 22.19+ gerektiriyor. | Node PiBoard ile bundle edilir. |
| Yeni session | `--session-id <id>` exact project session ID kullanır, yoksa oluşturabilir. | PiBoard UUID üretir ve task'a launch öncesi kaydeder. |
| Resume | `--session <path\|id>` belirli session'ı açar. `-r` picker açar. | Otomatik resume için `-r` kullanılmaz. |
| Session storage | Varsayılan `~/.pi/agent/sessions` altında cwd bazlıdır. | Varsayılan Pi session storage korunur. |
| Global config | `PI_CODING_AGENT_DIR` varsayılanı `~/.pi/agent`. | PiBoard override etmez. |
| Project config | `.pi/settings.json` ve project resources desteklenir. | Pi'nin kendi discovery ve trust sistemi kullanılır. |
| Skills/extensions | Global ve project kaynakları Pi settings/resource sistemiyle yüklenir. | V1'de PiBoard manager yazılmaz. |
| Update | Pi update/package mekanizması mevcut. | V1 runtime manager atomik version install/rollback yapar. |

## 7. Runtime Dağıtım Stratejisi

V1'de Node uygulamanın içine gömülür. Pi ise uygulama bundle'ının içine sabitlenmez. PiBoard, Application Support altında versioned bir Pi installation yönetir. Böylece Pi güncellemesi için App Store veya PiBoard release'i beklemek gerekmez.

```
PiBoard.app/
└── Contents/Resources/runtime/
    ├── node/bin/node
    └── npm/...

~/Library/Application Support/PiBoard/
├── piboard.sqlite
├── runtime/
│   └── pi/
│       ├── versions/
│       │   ├── <version-A>/
│       │   └── <version-B>/
│       └── current.json
└── worktrees/
```

Önerilen update mekanizması Pi'nin kendi executable'ını in-place değiştirmesine dayanmaz. PiBoard yeni Pi paketini yeni bir version directory'ye kurar, doğrular ve yalnızca başarılıysa current pointer'ını değiştirir. Bu yaklaşım custom npm prefix self-update edge case'lerini ve signed app bundle'a yazma sorunlarını ortadan kaldırır.

- **Install:** bundled Node/npm ile `@earendil-works/pi-coding-agent`'ın hedef versiyonunu version directory'ye kur.
- **Verify:** `pi --version` çalıştır, exit code ve beklenen version'ı doğrula.
- **Activate:** `current.json` içindeki `activeVersion` değerini atomik değiştir.
- **Rollback:** önceki version directory korunuyorsa pointer'ı geri al.
- **Running session:** update mevcut process'i etkilemez; yeni launch yeni active version'ı kullanır.

## 8. ~/.pi ve Project Resource Politikası

PiBoard, `PI_CODING_AGENT_DIR` değerini değiştirmemelidir. Böylece normal terminalden çalıştırılan Pi ile PiBoard içinden çalıştırılan Pi aynı global config, auth, skills, extensions, prompts ve trust kararlarını kullanır.

```
~/.pi/agent/
├── settings.json
├── auth.json
├── trust.json
├── sessions/
├── skills / configured skill paths
├── extensions / configured extension paths
└── prompts / themes / context

<Project>/.pi/
├── settings.json
├── skills/
├── extensions/
└── ...
```

Project-local protected resources için Pi'nin trust prompt'u korunur. PiBoard bu kararı bypass etmemelidir. Kullanıcı terminal içinde Pi'nin native trust akışını görür. Bu, PiBoard'un güvenlik modelini Pi'nin davranışından koparmamasını sağlar.

## 9. Domain Model

| Entity | Alanlar | Açıklama |
| --- | --- | --- |
| Project | id, name, path, createdAt, updatedAt | Board'un üst scope'u. |
| Task | id, projectId, title, prompt, status, position, piSessionId?, runContext?, worktreePath?, worktreeBranch?, timestamps | Kanban kartı ve Pi session referansı. |
| AppSetting | key, value | Runtime version, küçük app tercihleri. |

## 10. Task State Modeli

### 10.1 Workflow state

```
backlog
inProgress
done
```

Workflow state kalıcıdır ve kullanıcı hareketleriyle değişir.

### 10.2 Runtime state

```
notStarted
starting
running
exited(exitCode)
failed(reason)
stopping
```

Runtime state process'e aittir ve çoğunlukla memory'de tutulur. App yeniden açıldığında daha önce çalışan process yoktur; In Progress task runtime açısından exited/not running olarak gösterilir ve Resume sunulur.

### 10.3 Önemli invariant'lar

- Done != Pi exited.
- In Progress != Pi running.
- Terminal panelinin kapanması process'i öldürmez.
- Aynı project current working tree üzerinde aynı anda en fazla bir aktif Pi session'ına izin verilir.
- Worktree session'ları birbirinden izole oldukları için paralel çalışabilir.
- Task Pi başladıktan sonra piSessionId kaybetmemelidir.

## 11. SQLite Şeması

```
projects
--------
id TEXT PRIMARY KEY
name TEXT NOT NULL
path TEXT NOT NULL
created_at TEXT NOT NULL
updated_at TEXT NOT NULL

tasks
-----
id TEXT PRIMARY KEY
project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE
title TEXT NOT NULL
prompt TEXT NOT NULL DEFAULT ''
status TEXT NOT NULL CHECK(status IN ('backlog','in_progress','done'))
position INTEGER NOT NULL
pi_session_id TEXT NULL
run_context TEXT NULL CHECK(run_context IN ('current','worktree') OR run_context IS NULL)
worktree_path TEXT NULL
worktree_branch TEXT NULL
created_at TEXT NOT NULL
updated_at TEXT NOT NULL

settings
--------
key TEXT PRIMARY KEY
value TEXT NOT NULL
```

V1'de ayrı sessions tablosu önerilmez. Bir task'ın devam ettirilen ana Pi conversation'ı `task.pi_session_id` ile temsil edilir. İleride bir task için çoklu session history ürün gereksinimi oluşursa migration ile sessions tablosu eklenebilir.

## 12. Task Sıralama Algoritması

Task'lar aynı kolon içinde ve kolonlar arasında drag/drop ile sıralanabilir. V1 için integer position yeterlidir. Drop sonrası hedef kolondaki task'lar 0..N-1 şeklinde normalize edilerek tek transaction içinde yazılır. Board boyutu küçük olacağı için fractional indexing gereksizdir.

- Drag başında source status + index tutulur.
- Drop'ta target status + target index hesaplanır.
- UI optimistic olarak animasyonla güncellenir.
- SQLite transaction başarısız olursa snapshot geri yüklenir.
- Backlog -> In Progress geçişi Pi'yi başlatmaz; preparation view açar.

## 13. Project Yönetimi

- Create Project: name + folder picker.
- Edit Project: name ve path değiştirilebilir.
- Path missing: project açılır ancak board üstünde Path Missing banner gösterilir; Locate Folder aksiyonu sunulur.
- Aktif current-tree process varken project path değiştirme engellenir.
- Project delete: task metadata silinir; external repo ve `~/.pi` verilerine dokunulmaz.
- Export/Import: JSON üzerinden project + task metadata taşınır.

## 14. Export / Import Formatı

```json
{
  "formatVersion": 1,
  "project": {
    "name": "My App",
    "path": "~/Developer/my-app"
  },
  "tasks": [
    {
      "title": "Fix authentication",
      "prompt": "Investigate the redirect issue...",
      "status": "backlog",
      "position": 0
    }
  ]
}
```

Export dosyası taşınabilir workflow verisidir. piSessionId, PID, runtime state ve worktree path gibi makineye bağlı alanlar export edilmez. Import edilen project path mevcut değilse import yine tamamlanır ve kullanıcıdan Locate Folder istenir.

## 15. Run Preparation Akışı

```
Backlog -> In Progress
        |
        v
Task Preparation
  Initial Prompt [editable]
  Run In:
    (*) Current Working Tree
    ( ) New Worktree
        |
        v
Preflight
        |
        v
Start Pi
```

Current Working Tree her açılışta default seçilidir. Kullanıcı tercihi saklanmaz. Prompt Pi başlamadan önce düzenlenebilir. Pi başladıktan sonra ilk prompt task briefing olarak read-only gösterilebilir; sonraki yönlendirme terminal üzerinden yapılır.

## 16. Current Working Tree Preflight

1. Project path mevcut ve directory mi kontrol et.
2. Git repository olup olmadığını kontrol et. Git değilse worktree seçeneğini disable et, current mode yine kullanılabilir.
3. Aynı canonical working directory için aktif Pi process var mı kontrol et.
4. Varsa current mode hard block. Open Task ve Run in Worktree seçenekleri sun.
5. `git status --porcelain` çalıştır.
6. Dirty ise değişen dosyaları göster ve Cancel / Use Worktree Instead / Run Anyway sun.
7. Temiz veya Run Anyway ise Pi launch et.

## 17. Worktree Akışı

Worktree V1'de opt-in izolasyon mekanizmasıdır. Base mevcut HEAD'dir. Kullanıcıdan branch/base seçimi istemek V1 kapsamı dışındadır.

```
Project repo
  HEAD
   |
   +--> git worktree add -b piboard/<task-id-short>-<slug> <managed-path> HEAD
          |
          +--> Pi cwd = <managed-path>
```

- Managed path: `~/Library/Application Support/PiBoard/worktrees/<project-id>/<task-id>/`
- Branch name deterministic ve çakışmaya dayanıklı olmalı.
- Worktree yaratma başarısızsa task In Progress kalır, Pi başlamaz.
- Done olmak worktree'yi otomatik silmez.
- V1'de Remove Worktree explicit aksiyondur ve dirty worktree için hard warning verir.
- Merge/rebase/cherry-pick kullanıcı veya Pi tarafından yapılır; PiBoard Git merge UI sağlamaz.

## 18. Pi Session Lifecycle

PiBoard ilk launch'tan önce UUID üretir ve `task.pi_session_id` alanını SQLite'a yazar. Böylece app launch ile DB write arasında crash olsa bile session kimliği deterministiktir.

```
FIRST START
task.piSessionId = UUID
commit DB
spawn:
  pi --session-id <UUID> "<initial prompt>"

RESUME
spawn:
  pi --session <UUID>

FRESH START (future/optional V1 action)
generate new UUID
replace task.piSessionId after explicit confirmation
```

Resume için `-r` kullanılmaz çünkü `-r` interactive picker davranışıdır. Belirli task session'ını açmak için `--session` veya exact ID oluşturma için `--session-id` kullanılır.

## 19. PTY ve Process Mimarisi

```
SwiftUI
  |
TaskTerminalView
  |
TerminalHost (NSViewRepresentable)
  |
PTYSession
  |-- master fd
  |-- child pid
  |-- resize
  |-- stdin write
  |-- stdout/stderr stream
  |
bundled node -> managed Pi CLI
```

Pi interaktif TUI olduğu için stdout pipe yeterli değildir. Child process gerçek PTY slave üzerinde başlatılmalıdır. TERM, window size ve resize event'leri doğru iletilmelidir. Terminal view kapanınca PTYSession yaşamaya devam eder; task/session manager process'in sahibidir.

## 20. ProcessManager Sorumlulukları

- Task ID -> live process map tutmak.
- Canonical cwd -> active current-tree task map tutmak.
- Spawn, terminate, interrupt ve exit observation.
- App termination sırasında aktif Pi process'lerini kontrollü sonlandırmak.
- Task Done'a taşınırken aktif process varsa confirmation akışını tetiklemek.
- Terminal view attach/detach lifecycle'ını process lifecycle'dan ayırmak.

## 21. App Kapanışı ve Crash Recovery

V1'de PiBoard background daemon değildir. Normal app quit sırasında aktif Pi process'leri kullanıcıya toplu confirmation sonrası terminate edilir. Force quit/crash durumunda process ownership davranışı PTY implementation'a bağlı olarak test edilmelidir; V1 hedefi orphan process bırakmamaktır.

- DB'deki workflow state değiştirilmez.
- App yeniden açıldığında In Progress task'lar Pi Running varsayılmaz.
- piSessionId varsa Resume Pi sunulur.
- Worktree path varsa existence doğrulanır.
- Original worktree yoksa sessizce project root'a resume edilmez; kullanıcıya hata ve seçenek gösterilir.

## 22. UI Mimarisi

```
MainWindow
├── ProjectSidebar
├── BoardView
│   ├── BacklogColumn
│   ├── InProgressColumn
│   └── DoneColumn
├── TaskInspector
└── Toolbar

Task Flow
├── TaskPreparationView
└── TerminalWorkspaceView

SettingsWindow
└── PiRuntimeSettingsView
```

UI SwiftUI-first olmalıdır. AppKit yalnızca terminal/PTY veya SwiftUI'nin eksik kaldığı native entegrasyon noktalarında kullanılmalıdır.

## 23. Ana Ekran UX

```
┌──────────────┬──────────────────────────────────────────────────────┐
│ PROJECTS     │ My App                         Open in VS Code  +Task │
│              │ ~/Developer/my-app                                  │
│ ● My App     │                                                      │
│   Website    │ BACKLOG        IN PROGRESS       DONE                │
│   API        │                                                      │
│              │ Fix auth       Refactor API      Setup DB            │
│ + Project    │ UI cleanup     ● Pi running                          │
│              │                                                      │
│ Settings     │                                                      │
└──────────────┴──────────────────────────────────────────────────────┘
```

Kartlar minimal tutulur. Kart üzerinde title, kısa prompt preview ve gerekiyorsa Pi/worktree status indicator bulunur. Branch, session ID, Pi version gibi teknik detaylar karta doldurulmaz.

## 24. Task Preparation UX

```
Fix Authentication

INITIAL PROMPT
┌──────────────────────────────────────────────────┐
│ Investigate the authentication redirect issue.  │
│ Explain the cause before large changes.          │
└──────────────────────────────────────────────────┘

Run in
(*) Current Working Tree
( ) New Worktree

                                      [Start Pi]
```

In Progress'e sürükleme ile bu ekran açılır. Kullanıcı Cancel ederse task yine In Progress kalabilir; çünkü In Progress workflow kararıdır. Alternatif olarak ilk drag sırasında cancel ile Backlog'a rollback etmek UX testinde değerlendirilebilir. Önerilen V1 davranışı: kolon değişikliği kalıcı olsun, preparation ayrı bir adımdır.

## 25. Terminal Workspace UX

```
Fix Authentication                                  ● Pi Running
~/Developer/my-app                    main · Current Working Tree
──────────────────────────────────────────────────────────────────

> Investigate the authentication redirect issue...

I'll inspect the authentication flow first...

...

> █
```

- Terminal ana çalışma alanını kaplayacak kadar geniş olmalı.
- Board'a geri dönüş process'i durdurmamalı.
- Task title, cwd, branch/run context ve process status header'da görünmeli.
- Open in VS Code task context'te aktif working directory'yi açmalı.
- Stop Pi kontrollü aksiyon olarak toolbar/context menu'de bulunmalı.

## 26. Open in VS Code

Project seviyesindeki Open in VS Code `project.path`'i açar. Task seviyesinde task worktree ile çalışıyorsa `worktreePath`, aksi halde `project.path` açılır. V1 UI yalnızca VS Code sunabilir; içeride küçük bir ExternalEditorService interface'i gelecekte Cursor/Zed eklenmesini kolaylaştırır.

```
ExternalEditorService
  openProject(path)
  isAvailable()

VSCodeEditorService
  resolve: /usr/local/bin/code, /opt/homebrew/bin/code, app bundle lookup
  fallback: NSWorkspace openApplication with folder URL
```

CLI `code` bulunmaması feature'ı bozmamalıdır. macOS NSWorkspace üzerinden Visual Studio Code uygulamasına folder URL açtırmak tercih edilen fallback'tir.

## 27. Keyboard ve Native macOS Davranışları

| Shortcut | Aksiyon |
| --- | --- |
| ⌘N | New Task |
| ⌘⇧N | New Project |
| ⌘K | Project/task quick search, V1'de basit olabilir |
| ⌘, | Settings |
| Return | Selected task aç |
| Esc | Inspector/preparation dismiss, bağlama göre |
| ⌘↩ | Preparation ekranında Start Pi |

Terminal focus olduğunda app-level shortcuts Pi/TUI keybindings ile çakışmamalıdır. Shortcut routing terminal focus state'ini dikkate almalıdır.

## 28. Error Handling Matrisi

| Durum | Davranış |
| --- | --- |
| Project path missing | Banner + Locate Folder. Pi launch disabled. |
| Git dirty, current mode | Warning + Run Anyway / Worktree / Cancel. |
| Current tree başka task tarafından kullanılıyor | Hard block + Open Task / Worktree. |
| Worktree create fail | Task In Progress kalır, error gösterilir, Pi başlamaz. |
| Pi runtime missing | Runtime install CTA. Task state değişmez. |
| Pi spawn fail | Runtime state Failed, retry sun. |
| Pi exits non-zero | Task In Progress kalır, exit code göster, Resume/Restart seçenekleri. |
| Session not found | Açık hata. Start Fresh explicit confirmation. |
| Stored worktree missing | Project root'a otomatik geçme. Locate/Start Fresh/Cancel. |
| Pi update fail | Active version korunur. |
| VS Code unavailable | Open in VS Code disabled veya install hint. |

## 29. Güvenlik ve Sandbox Kararları

Pi kullanıcı yetkileriyle filesystem, process ve network erişimine sahip olabilir. Pi'nin kendi dokümantasyonu built-in permission sandbox sunmadığını belirtir. PiBoard V1 bunu gizlememeli veya sahte bir güvenlik sınırı izlenimi vermemelidir.

- Pi child process kullanıcı yetkileriyle çalışır.
- Project trust Pi'nin native mekanizmasına bırakılır.
- PiBoard `auth.json` veya provider credential içeriklerini parse etmez.
- Export project dosyası Pi transcript veya credential içermez.
- Runtime download/install bütünlüğü için mümkün olduğunda package/version doğrulaması yapılır.
- App Sandbox seçimi PTY, child process, arbitrary project folder ve Git gereksinimleri nedeniyle implementasyon spike'ında doğrulanmalıdır.

## 30. Pi Runtime Settings

```
Pi Runtime

Status       Ready
Installed    <version>
Latest       <version>

[Check for Updates]   [Update]

Previous Versions
<version>             [Rollback]

User Environment
~/.pi/agent           Detected
[Open Folder]
```

V1 extension/skill manager içermez. Settings yalnızca runtime health/version/update/rollback ve kullanıcı Pi config path'ine hızlı erişim sunar. Extension manager daha sonraki sürüm için ayrı feature set'tir.

## 31. Önerilen Swift Modül Yapısı

```
PiBoardApp
├── App
│   ├── PiBoardApp.swift
│   └── AppEnvironment.swift
├── Domain
│   ├── Project.swift
│   ├── Task.swift
│   └── TaskStatus.swift
├── Persistence
│   ├── Database.swift
│   ├── ProjectRepository.swift
│   ├── TaskRepository.swift
│   └── Migrations/
├── Services
│   ├── PiRuntimeManager.swift
│   ├── PiProcessManager.swift
│   ├── PTYSession.swift
│   ├── GitService.swift
│   ├── WorktreeService.swift
│   ├── ProjectPathService.swift
│   └── ExternalEditorService.swift
├── Features
│   ├── Projects/
│   ├── Board/
│   ├── TaskDetail/
│   ├── Preparation/
│   ├── Terminal/
│   └── Settings/
└── Shared
    ├── Components/
    └── Utilities/
```

## 32. Servis Kontratları

### 32.1 PiRuntimeManager

```swift
protocol PiRuntimeManaging {
    func activeVersion() async throws -> PiVersion
    func checkLatestVersion() async throws -> PiVersion
    func install(version: PiVersion) async throws
    func activate(version: PiVersion) async throws
    func rollback(to version: PiVersion) async throws
    func executable() throws -> URL
}
```

### 32.2 GitService

```swift
protocol GitServicing {
    func repositoryInfo(at path: URL) async throws -> RepositoryInfo
    func status(at path: URL) async throws -> [GitChange]
    func currentBranch(at path: URL) async throws -> String?
}
```

### 32.3 WorktreeService

```swift
protocol WorktreeServicing {
    func create(for task: Task, project: Project) async throws -> WorktreeInfo
    func validate(_ info: WorktreeInfo) async -> WorktreeValidation
    func remove(_ info: WorktreeInfo) async throws
}
```

## 33. Launch Command Construction

Shell string birleştirmek yerine executable + argument array kullanılmalıdır. Prompt shell quoting'e sokulmamalıdır.

```
New:
node <managed-pi-entry> --session-id <uuid> --name <task-title> <initial-prompt>

Resume:
node <managed-pi-entry> --session <uuid>

cwd:
current mode  -> project.path
worktree mode -> task.worktreePath

environment:
inherit user environment
do not override PI_CODING_AGENT_DIR
prepend bundled Node/npm paths only where required
```

## 34. Testing Stratejisi

| Seviye | Testler |
| --- | --- |
| Unit | Position reorder, state transitions, command args, path canonicalization, branch slug, import validation. |
| Service integration | git status, worktree create/remove, Pi runtime version verify, SQLite migrations. |
| PTY integration | Interactive input/output, resize, unicode, ANSI, Ctrl+C, process exit. |
| UI | Drag/drop, preparation flow, dirty warning, current-tree collision, terminal attach/detach. |
| Recovery | App restart with In Progress task, missing path, missing worktree, missing Pi session. |
| Update | Install new Pi, failed install keeps old active, rollback. |

## 35. Implementasyon Milestone'ları

| Milestone | Çıktı |
| --- | --- |
| M0 - Technical spikes | PTY içinde Pi TUI çalıştırma; bundled Node ile managed Pi çalıştırma; SwiftUI drag/drop prototype; Git worktree prototype. |
| M1 - Data + Projects | SQLite/migrations; project CRUD; path picker; project sidebar; missing path recovery. |
| M2 - Kanban | 3 kolon; task CRUD; reorder; cross-column drag/drop; persistence. |
| M3 - Preparation + Git preflight | Prompt editor; current/worktree choice; dirty status warning; concurrent current-tree block. |
| M4 - Pi runtime | Install/verify/activate/version UI; bundled Node; launch command builder. |
| M5 - Terminal + Sessions | PTY terminal workspace; `--session-id` first launch; `--session` resume; process manager; exit handling. |
| M6 - Worktree productionization | Managed paths; validation; explicit cleanup; task working directory resolution. |
| M7 - Integrations + portability | Open in VS Code; Finder/copy path; JSON export/import. |
| M8 - Hardening | Crash/restart recovery; error states; keyboard shortcuts; accessibility; dark/light; QA. |

## 36. V1 Acceptance Criteria

- Kullanıcı birden fazla project ekleyebilir ve project değişince yalnız o project'in task'larını görür.
- Project path sonradan değiştirilebilir ve kayıp path yeniden locate edilebilir.
- Task'lar üç kolon arasında ve kolon içinde drag/drop ile kalıcı şekilde sıralanabilir.
- Backlog -> In Progress Pi'yi otomatik başlatmaz.
- In Progress task prompt'u launch öncesi düzenlenebilir.
- Current Working Tree default seçilidir.
- Dirty current tree kullanıcıya dosya listeli warning gösterir.
- Aynı current tree'de ikinci aktif Pi task hard block edilir.
- Worktree seçildiğinde izole worktree oluşturulur ve Pi orada çalışır.
- Pi gerçek PTY içinde interaktif olarak kullanılabilir.
- Task terminali kapatılsa bile aktif process yaşamaya devam eder.
- Task'ın Pi session ID'si saklanır ve session yeniden açılabilir.
- Pi exit olduğunda task otomatik Done olmaz.
- Pi runtime PiBoard update'inden bağımsız update ve rollback edilebilir.
- `~/.pi/agent` kullanıcı environment'ı korunur.
- Project ve task working directory VS Code'da açılabilir.
- Project JSON export/import çalışır.

## 37. V1 Dışı

- Pi extension manager
- Skill manager/editor
- Multi-agent/provider desteği
- Cloud sync ve collaboration
- Git diff/merge/rebase UI
- Automatic Done
- Token/cost dashboard
- AI task generation
- Background daemon / app kapalıyken agent çalıştırma
- Notifications
- Task başına çoklu Pi session history UI
- Complex branch/base selector

## 38. V1 Sonrası Doğal Genişleme Alanları

V1 stabil olduktan sonra en doğal ikinci faz Pi Runtime & Extensions ekranıdır. Pi zaten package install/remove/update/config primitive'leri sağladığı için extension manager, PiBoard'un agent sistemini yeniden yazmadan Pi'nin package modelinin native macOS yönetim yüzeyi olabilir. Daha sonraki fazlarda task session history, diff preview ve editor seçimi eklenebilir.

## 39. Açık Teknik Spike'lar

- Hangi terminal component'in güncel macOS, SwiftUI bridge, IME, mouse ve Pi TUI keybindings açısından en sorunsuz olduğu.
- Mac App Sandbox ile arbitrary project path, child process, PTY ve Git gereksinimlerinin dağıtım modeline etkisi.
- Managed Pi npm installation için package entrypoint ve update doğrulama detayları.
- App normal quit/crash sırasında PTY child process orphan davranışı.
- VS Code folder opening için NSWorkspace tabanlı en sağlam yöntem.

## 40. Kaynak Doğrulama Notları

Bu dokümandaki Pi'ye özgü kararlar 5 Ekim 2026 itibarıyla earendil-works/pi repository'sinin güncel README, CLI args, settings, sessions, security ve session-manager kaynakları üzerinden doğrulanmıştır.

| Kaynak | URL |
| --- | --- |
| Pi repository | https://github.com/earendil-works/pi |
| CLI args | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/cli/args.ts |
| Sessions documentation | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sessions.md |
| Settings documentation | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/settings.md |
| Security documentation | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/security.md |
| Session manager | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/core/session-manager.ts |
| Package/update CLI | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/package-manager-cli.ts |

## 41. Nihai V1 Tanımı

PiBoard V1, project bazlı native macOS Kanban ile Pi'nin gerçek interaktif terminal session'ını birleştiren yerel bir agent workspace'tir. Kullanıcı task'ı In Progress'e alır, prompt'u hazırlar, current tree veya worktree seçer, Pi'yi başlatır, terminal üzerinden agent ile çalışır ve task'ın ne zaman Done olduğuna kendisi karar verir.

## 42. Ayrıntılı Implementation Planı

V1 scope freeze sonrası uygulanabilir geliştirme sırası. İki ana kalite barı eşit önceliklidir: terminal güvenilirliği ve ilk açılışta premium native macOS kullanıcı deneyimi. Yeni talepler implementation sırasında backlog issue olarak tutulur; V1 scope kendiliğinden genişletilmez.

### 42.1 UI ve ürün kalite barı

- UI polish release sonuna bırakılmaz. M0'dan itibaren acceptance criterion'dır.
- Native macOS navigation, window ve input davranışları korunur; görünüm default SwiftUI kontrollerinin yan yana dizilmesi seviyesinde bırakılmaz.
- Board workflow/control yüzeyidir. Terminal gerçek çalışma yüzeyidir ve gerektiğinde ana content'i tamamen devralır.
- Trello/web-dashboard estetiğinden kaçınılır. Typography, spacing, hierarchy, hover, selection, empty/error states ve terminal chrome özel olarak tasarlanır.
- Keyboard shortcut V1 kapsamı dışındadır. Uygulama aksiyonları görünür UI ile erişilir.

### 42.2 Görsel sistem

- System typography ve semantic colors temel alınır; light/dark otomatik ve tutarlı çalışır.
- 8 pt tabanlı spacing ritmi; ana bölgelerde 16 ile 24 pt, kart içlerinde 10 ile 14 pt arası nefes alanı hedeflenir.
- Kartlarda title primary, prompt preview secondary, runtime/worktree metadata tertiary seviyededir.
- Selected/running/exited/error durumları yalnız renkle anlatılmaz; icon, shape ve text desteği kullanılır.
- Animation kısa ve işlevseldir: drag reorder, presentation transition, terminal focus. Decorative animation yapılmaz.
- First project, empty board, missing path, missing Pi runtime ve inactive terminal için ayrı kaliteli empty state tasarlanır.

### 42.3 Terminal kalite barı

- Gerçek PTY, user default shell ve interactive startup. zsh kullanıcısında `~/.zshrc` yüklenir.
- Shell environment korunur, ancak PiBoard-managed Node/Pi executable seçimi PATH'e bırakılmaz.
- ANSI, 256-color, true-color, Unicode/emoji, alternate screen buffer, mouse reporting ve resize test edilir.
- Ctrl+C/D/Z, Option/Meta, selection, copy/paste ve IME davranışı test edilir.
- Pi, tmux, vim/neovim, git, npm ve uzun-running CLI'lar smoke test kapsamındadır.
- Scrollback default 100,000 satır ve configurable olur. Çok yüksek limitlerde memory pressure ölçülür.
- Font family, font size, line height, cursor ve scrollback Settings > Terminal altında değiştirilebilir.
- Terminal detach/reattach process'i etkilemez. Pi exit olduktan sonra normal shell prompt kullanılmaya devam eder.
- Floating expand control ile Focus Terminal moduna geçilir. Aynı PTY, scrollback ve process korunur.

### 42.4 M0 - Terminal ve high-fidelity UI spike

- Xcode/SwiftUI app skeleton oluştur.
- PTY + terminal component prototype ile user shell ve `~/.zshrc` doğrula.
- Bundled Node 24 ile managed Pi launch et; Pi TUI input/output/resize/exit continuity doğrula.
- 100k scrollback ile performans ve memory ölç.
- Normal workspace ile Focus Terminal arasında aynı PTY instance'ını koru.
- Project sidebar, board, preparation ve terminal için high-fidelity ana pencere prototype üret.
- Gate: terminal günlük kullanımı engelleyen input/render problemi taşımıyorsa ve UI müşteriye gösterilebilir seviyedeyse M1'e geç.

### 42.5 M1 - Foundation ve design system

- AppEnvironment/dependency composition ve Domain/Persistence/Services/Features sınırlarını kur.
- SQLite migration runner ve repository layer kur.
- Window, sidebar, toolbar, inspector/sheet ve Settings shell oluştur.
- Spacing, typography, card surface, status indicator, banner, empty/loading/error component'lerini standardize et.
- Light/dark ve temel accessibility QA yap.

### 42.6 M2 - Projects ve persistence

- Project CRUD, native folder picker, canonical path ve missing-path recovery.
- Project switch ile tam board scope izolasyonu.
- Active session sırasında path mutation guard.
- Open in Finder ve Copy Path.
- App restart sonrası project state recovery testleri.

### 42.7 M3 - Kanban ve task UX

- Task CRUD; Backlog/In Progress/Done.
- Column içi reorder ve cross-column drag/drop.
- Optimistic UI + SQLite transaction rollback.
- Minimal kart hierarchy ve runtime/worktree indicators.
- Done yalnız kullanıcı kontrollü.
- 100+ task ile board performance testi.

### 42.8 M4 - Preparation ve Git safety

- In Progress preparation state ve editable initial prompt.
- Current Working Tree her seferinde default; New Worktree alternatifi.
- `git status --porcelain` ile dirty file warning.
- Canonical cwd active-session lock; aynı direct working tree'de ikinci Pi hard block.
- Git olmayan project davranışı ve worktree create/validation.
- Gate: hiçbir UI yolu iki direct agent'ı aynı cwd'ye başlatamamalı.

### 42.9 M5 - Pi sessions ve process lifecycle

- Launch öncesi UUID session ID üret ve transaction ile task'a kaydet.
- İlk run için `--session-id`, resume için exact `--session` kullan.
- PiProcessManager task->process ve cwd->active task map'lerini yönetir.
- Starting/running/stopping/exited/failed runtime state'lerini UI'a bağla.
- Active task Done/Backlog hareketinde stop confirmation.
- App quit shutdown ve crash/restart recovery.
- Gate: session resume transcript duplication olmadan güvenilir çalışmalı.

### 42.10 M6 - Terminal productization

- Terminal preferences: font, size, line height, cursor, scrollback, Option/Meta.
- Selection/copy/paste, mouse ve IME polish.
- tmux/vim/Pi alternate-screen regression testleri.
- Large-output stress, memory pressure, sleep/wake, network loss, Pi/shell crash senaryoları.
- Floating Focus Terminal presentation ve task/cwd/branch/runtime header.
- Gate: terminal PiBoard'un en güvenilir feature'larından biri olmalı.

### 42.11 M7 - Worktree lifecycle ve external apps

- Worktree existence/branch validation ve missing-worktree recovery.
- Explicit Remove Worktree; dirty durumda güçlü warning; otomatik cleanup yok.
- ExternalAppService oluştur.
- Open in VS Code, iTerm, Warp ve Finder.
- Task-level action active working directory'yi; project-level action project root'u açar.

### 42.12 M8 - Pi runtime

- Node 24 app bundle içine dahil edilir ve signing pipeline'a girer.
- Pi Application Support altında versioned install edilir.
- Install -> verify -> activate atomik akışı; failure aktif version'ı değiştirmez.
- Rollback pointer değişimiyle yapılır; running Pi update yüzünden öldürülmez.
- `~/.pi/agent` ve project `.pi` discovery override edilmez.
- Gate: sistemde Node/pi bulunmayan temiz kullanıcı hesabında PiBoard Pi başlatabilmeli.

### 42.13 M9 - Import/export ve recovery

- formatVersion=1 project JSON export/import.
- Machine-specific live process/worktree runtime state taşınmaz.
- Missing project path ile import başarılı olur ve Locate Folder sunulur.
- Malformed/unsupported format güvenli hata verir.
- External repo/worktree deletion recovery testleri.

### 42.14 M10 - PiBoard GitHub release ve self-update

- GitHub Actions workflow_dispatch ile manuel Release PiBoard workflow.
- Input: version, stable/beta channel, source ref ve release notes.
- Clean macOS runner: test -> archive -> Developer ID sign -> notarize -> staple -> package.
- Sparkle EdDSA signing ve appcast üretimi.
- Artifact GitHub Release'e yüklenir; appcast HTTPS üzerinden sabit bir endpoint'te yayınlanır.
- Beta ve stable update feed/channel ayrımı.
- Settings > General içinde Check for Updates, release notes ve Install Update.
- GitHub Secrets: signing certificate, notarization credentials, Sparkle private key. Secret repository'ye yazılmaz.
- Failed test/sign/notarization release publish etmez.
- Gate: eski notarized beta build'den yeni beta build'e uygulama içinden update başarıyla tamamlanmalı.

### 42.15 M11 - Release hardening

- Accessibility labels/VoiceOver temel navigation ve contrast QA.
- Light/dark, farklı window sizes ve Retina scaling.
- Cold start, DB load, 100+ task ve büyük terminal output performance.
- Normal quit, force quit, crash recovery.
- Pi runtime missing/corrupt/update failure.
- Fresh macOS user account clean-install test.
- Code signing/notarization verification.
- Gate: terminal veya data-loss alanında bilinen blocker/critical issue kalmamalı.

### 42.16 Önerilen geliştirme sırası

1. Repo/Xcode skeleton.
2. Terminal feasibility spike.
3. High-fidelity main-window prototype.
4. SQLite + projects.
5. Board/tasks.
6. Git/worktrees.
7. Pi sessions/process manager.
8. Terminal productization.
9. External apps.
10. Pi runtime manager.
11. Import/export.
12. GitHub release + Sparkle updater.
13. Recovery/stress/accessibility/release QA.

### 42.17 Definition of Done

- Feature compile olmasıyla tamamlanmış sayılmaz.
- Gerekli unit/integration test eklenmiş olmalı.
- Loading/empty/error state tasarlanmış olmalı.
- Light/dark kontrol edilmiş olmalı.
- Data mutation transaction/recovery davranışı belirlenmiş olmalı.
- Process/terminal değişikliğinde detach/exit/crash test edilmiş olmalı.
- UI değişikliği native macOS visual quality barını düşürmemeli.
- Acceptance criterion manuel olarak doğrulanmış olmalı.

### 42.18 V1 dışında

- Keyboard shortcuts.
- Pi extension/skill manager.
- Git diff/merge/rebase/cherry-pick UI.
- Background daemon.
- Cloud sync/collaboration.
- Multi-agent/provider abstraction.
- Analytics/token/cost UI.
- Automatic Done ve speculative waiting-for-user detection.

## 43. Ana Başarı Ölçütü

PiBoard açıldığında müşteriyi UI kalitesi yakalamalı; kullanmaya başladığında terminal güvenilirliği tutmalı. Board iş akışını görünür kılar, terminal ise işin gerçekten yapıldığı yerdir.
