# Omarchy Project Manager

An [Omarchy](https://omarchy.org/) shell plugin for working across your
[`brd`](https://github.com/paulomtts/brd) projects, right from the bar. Pick a
project in the sidebar, then browse its kanban **Board**, its milestone
**Graph**, its Markdown **Documents** (with typed badges you can assign), the
**Memories** Claude Code keeps for it, which you can read, edit, create and
delete, its brd **Issues**, and the **Runs** the `am` orchestrator makes on every registered project (watched, and paused, resumed, cancelled or started from the panel). Cards and issues are read-only; the plugin's
writes are limited to a document's frontmatter `tag:`, a project's Claude memory
notes, the **New milestone** run (a coding agent writes cards to brd on your
behalf) and removing a whole project from brd (each described below, each with a
backup or snapshot).

The panel is a centered popup (about 80% of the screen), with a sidebar on the
left (project dropdown, section navigation, Delete project...) and, on the
right, a fixed toolbar above the scrolling content.

Formerly named brd-viewer (`paulomtts.brd-viewer`). Data written under the old
name stays where it is: the remembered project is read from the old location
until it is next saved, and existing snapshots and backups are left in their
`brd-viewer` folders.

## Features

- **Project dropdown** - the sidebar's top button shows the current project;
  click it or press **Ctrl+P** to open a searchable list of every project
  `brd` has registered (`brd projects`). Up/Down move, Enter or click selects.
- **Remembered project** - the panel reopens on the project you last viewed,
  also after a shell restart. It is stored in
  `~/.local/state/omarchy-project-manager/state.json` (`$XDG_STATE_HOME` is respected). If
  that project is no longer registered, the first one is shown.
- **Sections** - **Board** (**Ctrl+1**), **Graph** (**Ctrl+2**), **Documents**
  (**Ctrl+3**), **Memories** (**Ctrl+4**), **Issues** (**Ctrl+5**) and **Runs** (**Ctrl+6**), also
  reachable from the sidebar with the mouse, where each one carries its own
  icon. The digits follow the order the sidebar lists the sections in.
- **Board** - top-level cards in three status sections (Todo / In Progress /
  Done), each showing a done/total progress badge for its subtasks. A card
  reporting as blocked (derived status) appears in Todo, flagged in orange, and
  when open brd issues are what block it the flag is followed by "N open
  issue(s)".
- **Graph** (Ctrl+2) - a pan/zoom canvas with one node per milestone (title,
  status colour, done/total progress, and a flag with the count when open brd
  issues block it) and an arrow for each `blocked_by` link between
  milestones, laid out left to right. Arrow keys move the selection to
  the nearest node in that direction and the view follows; Enter or a click
  opens the milestone's card, and Back returns to the graph. The canvas also
  has mouse pan/zoom, `+`/`-` and on-screen zoom/organize/fit buttons. On a
  touchpad, two fingers moving the SAME way pan the canvas and a pinch zooms it;
  Ctrl with either zooms about the pointer. (If a slide does not pan on your
  machine, start the shell with `OPM_DEBUG_WHEEL=1` and scroll over the graph:
  every wheel event it sees is logged as `[opm wheel] …` with its device, pixel
  and angle deltas, phase, modifiers and inverted flag, which is what a bug
  report about this needs.) Nodes can
  be dragged for a look around, but the graph never creates or removes links.
  A **Milestone | Story** switch in the toolbar picks the view (Milestone is
  the default; the choice is remembered for the session and survives a project
  switch). **Story** shows one node per story of *every* milestone at once,
  each milestone's stories inside a box labelled with its title (a milestone
  with no stories draws no box), and an arrow for each `blocked_by` link
  between two stories — one that crosses two milestones simply draws across
  their boxes. Behind them, a thicker, fainter curve joins the **boxes**
  themselves, so milestone-level dependency reads here as it does in the
  Milestone view: one box edge per pair, drawn when brd says one milestone is
  blocked by the other *or* when any story in one is blocked by a story in the
  other. A story node keeps the title, status colour and open-issue flag,
  and replaces the done/total text with **pips**: one small circle per subtask
  in its status colour (todo / in progress / blocked / done, a subtask blocked
  by an open issue counted as blocked), the in-progress ones gently pulsing.
  More subtasks than fit collapse into a `+N`. Arrow keys, Enter, a click and
  Back work exactly as they do in the milestone view, on the story's own card.
  A box is always exactly its own stories' bounding box: drag a story and its
  box grows, shrinks or moves to keep containing it, and no other milestone's
  box ever adopts it. Drag a box by its **label strip** to move the whole group
  — every story inside goes with it, the box edges follow, and the selection and
  arrow keys are unaffected. **Organize** lays each milestone's stories out
  inside its own box and then arranges the boxes by their dependency, so every
  story is back in its box and no two boxes overlap; **Fit** frames the boxes,
  not just the nodes. An arrangement lasts until the board changes, exactly as a
  dragged node's position does in the Milestone view.
- **Memories** (Ctrl+4) - the project's Claude Code memory notes, from
  `~/.claude/projects/<slug>/memory/` (the slug is the project path with every
  non-alphanumeric character turned into `-`; if that folder is missing, a
  project whose session transcripts record this path is used). Each note shows
  its name, description and a type badge (User, Feedback, Project, Reference,
  Other) that filters like the Documents badges; search matches name,
  description and file name. Open a note to read it, then **Edit** (Ctrl+E) to
  change its raw text (Ctrl+S saves, Escape leaves a clean editor and never
  discards unsaved changes), **Delete** (type `delete`), or **＋ New** (Ctrl+N)
  to create one. Every change goes through `core/backend/memories/memory-op.py`, which first copies the
  note and `MEMORY.md` to `~/.cache/omarchy-project-manager/memory-backups/`, replaces files
  atomically, and keeps the note's `- [Title](file.md) - hook` line in
  `MEMORY.md` in sync (name and description come from the note's frontmatter).
  A project that was renamed since Claude Code stored its memory will show none,
  because Claude Code keys memory by path; nothing is lost on disk.
- **New milestone** - in the Board list, **＋ New milestone** opens a modal that
  builds one from a spec. Pick one of the project's Markdown documents (the
  Specs ones lead the list; search by title or path) and your default coding
  agent reads it and builds the milestone, story and subtask cards with `brd`,
  unattended. The agent is whatever `omarchy-default-agent` reports; the
  dialog names it and says how it will run, and refuses to start when no
  default agent is set, it is not installed, or it has no supported
  unattended mode. Supported: `claude`, `codex`, `crush`, `copilot`, `pi`,
  `hermes`, `gemini`, `opencode`, `cursor-agent`, `grok`, `omp`, `muse`.
  **Only `claude` is restricted** (it runs with `--allowedTools
  "Read Glob Grep Bash(brd *)"`, i.e. reading the project and running `brd`);
  every other agent runs with its own full auto-approval flags, which is
  stated in the dialog before you start.
  - While it runs, a toolbar indicator replaces the button with the elapsed
    time and a **Cancel** (which kills the agent's whole process group), and at
    the end it reports how many cards appeared, or why the run failed, plus the
    log path. The agent's output is written to
    `~/.local/state/omarchy-project-manager/agent-logs/<utc>-<project>.log`
    (`$XDG_STATE_HOME` is respected; the directory is `0700` and the file
    `0600`).
  - Limits: **one job at a time**, per shell - a second Start is refused with a
    note in the dialog, also when the run belongs to another project. The job
    is a child of the shell, so restarting the shell (or logging out) ends it;
    the cards already created stay. A run gives up after 30 minutes
    (`OPM_AGENT_TIMEOUT_SECONDS`). That shutdown kills the agent's whole
    process group - but if the shell itself is killed outright (`SIGKILL`, a
    crash) the agent is orphaned and keeps writing cards until it finishes or
    the time limit ends it; the log file is how you see what it did. The job keeps running when you switch
    project, but only its own project's Board shows it. Nothing the agent does
    is reviewed by the plugin - it writes cards to `brd` on your behalf.
- **Archive finished** - in the Board list, **Archive finished (N)** appears
  when N milestones are done with: not archived yet, at least one card under
  them, every card at any depth done, merged, canceled or archived, and nothing
  in the milestone or its cards updated in the last 2 days. Click it to review
  the list (title, idle days, card count); **Archive all** then runs
  `brd update <id> --status archived` on each milestone card only - its stories
  and subtasks are left alone. Cancel, Escape or a click on the backdrop writes
  nothing. A milestone that fails is named in the dialog, which stays open; the
  others stay archived. Like New milestone, this is a write the plugin does on
  your behalf, and only after that click.
- **Card detail** - kind and status badges (Milestone / Story / Subtask by
  depth; Todo / In progress / Done / Blocked), full description, a parent link
  and clickable blocked-by/children lists, resolving ids to titles. A blocker
  that is a brd issue shows its title and `Issue · open` / `Issue · closed`
  (closed ones dimmed) and opens in the Issues section. A blocked card also
  carries an "N open issues" badge next to Blocked. Below everything, the card's
  brd comments (author, relative time, body, oldest first), or "No comments."
  They are read-only: the panel never writes a comment. When am runs touch the card, a **RUNS** section lists them (newest first: state glyph, short id, title, phase, age); a click opens Run detail, and Back returns to the card.
- **Issues** (Ctrl+5) - brd's issues, open first and then closed, each group
  newest-updated first. A row shows a status badge, the title, how many cards
  the issue blocks and how many comments it has. **Open**/**Closed** filter
  chips carry their counts; clicking the active one shows everything again, and
  the search box matches an issue's title, body and id. Enter or a click opens
  the issue: its status and close reason, its body as Markdown, the cards it
  blocks, its explicit references and what explicitly references it - each
  navigable when the target is a card of this board or another issue - and its
  comments. Only references written with brd's `--ref` are listed: `brd export`
  does not carry the ones a `[[wikilink]]` in a body creates. Read-only: the
  panel never opens, closes or comments on an issue.
- **Runs** (Ctrl+6) - the runs the `am` orchestrator has made on every project `brd` has registered, reachable from the sidebar with or without a project open (Run detail too). The plugin asks `am` for each registered project's runs on its own (`am runs --repo-dir <project>`) and lists them grouped by project, each group under a header with the project's name and its live, parked and needs-attention counts; each project lists its non-terminal runs plus its 10 newest terminal ones, and runs of a repository `brd` has not registered never appear. A project that cannot be read (its folder is gone, `am` timed out or refused) shows why under its header and keeps the runs it had; the other projects are unaffected. With no project registered the list says `No projects registered.` A project chip row - **All projects**, **This project** while a project is open, and one chip per other project with runs, each with its run count - narrows the list to one project, shown flat; the chosen project survives a section or project switch, goes back to All projects when the panel closes, and is never saved. The panel watches the runs and can start them on the open project (see **Dispatch** below); a run of any registered project can also be paused, resumed or cancelled from the panel, which acts on the run's own repository whatever project is open, and the row under the cursor offers **Open project** for a run of another registered project, which opens that project. Each row shows the run's state glyph, short id, title (its milestone id), done/total subtasks, current phase and age; a dead run says `dead - lease lost <age> ago`, and an escalated one says why. **Needs attention** (escalated or dead), **Live** (running), **Parked** and **All** chips carry their counts within the chosen project, clicking the active one shows All again, and the search box matches a run's id, title, current phase and state. The footer reads `am <version> · schema <N> · watching` (or `not watching`), the version and schema shown once the watch's hello is known. Enter or a click opens **Run detail**: state, milestone, branch prefix, base and lease; the story > subtask > phase > attempt tree (plus the orchestrator's own Integrate / Bases / Base rows); and an output pane holding one attempt's `am logs` snapshot, labelled `snapshot <age> ago` and `· last 200 lines` when it was cut. It is never a live tail: **Refresh** fetches it again, and a failed fetch says why and keeps the last text. For an escalated, parked, dead or cancelled run, a **Why it stopped** block shows a headline, the detail, a dead run's last heartbeat, `am`'s own note from the card's comments, the parked cards, **Open card** and **Relaunch**. `am`'s note is shown only for runs of the open project; for another project, **Open card** and **Relaunch** are disabled until that project is opened. The output pane opens on the attempt that failed, or on a step's newest output. **Resume** of a milestone run with no saved verify commands opens a Resume dialog; its commands, or **run without any verification**, are saved for the project and reused by later resumes and dispatches. A cancelled run and an escalated card run cannot be resumed: **Relaunch** opens the dispatch dialog prefilled with the run's branch prefix and base, and nothing starts until **Start run**. Relaunch is also offered after `am` refuses a resume as not resumable or as checkpoint-mismatched. Run state is its own channel, never brd's status: a glyph in a ring -- running ⟳, parked ⏸, escalated ‼, dead ✖, cancelled ⊘, done ✔ -- never colour alone. The same marks appear on **Board** cards, **Graph** nodes (a story node's pips are ringed for the subtasks a run is working on now) and in a card's RUNS section. A finished run speaking for a card, or run data with no good snapshot for 30 s, is drawn dimmed, and merged, canceled and archived cards get no live mark. The toolbar's run indicator (`⟳N ⏸N ‼N`, counted over every registered project; a click opens the Runs list on All projects with that chip) and the sidebar's Runs row, which shows `‼N` while N runs are escalated or dead, count every registered project, whatever the Runs list's filters. While the panel is open, a run of any registered project that newly escalates or dies gets a toast naming the run and its project, with **Open** and **Dismiss**. **Notify on escalation**, under the Runs list, is one switch for the whole viewer: with it on, each such toast also raises a desktop notification. Nothing polls while the panel is closed. Requirements and failure modes are under Install.
- **Dispatch** - the panel starts `am` runs at four levels: a subtask (`am run --card`), a story (`--story`), a milestone (`--milestone`) or the whole board (`--board`). Three entry points open the dispatch dialog, and none of them starts anything: a card's **▶ Dispatch** in card detail; a bare `d` on the board list's cursor card (while the search is empty) or on the open card; and the Runs toolbar's **▶ Start run**, which opens on the whole board with a row of `Whole board` plus each milestone that can be dispatched. All three are disabled while `am` is missing, and **▶ Start run**, shown on the Runs list with or without a project, is disabled with `Open a project to dispatch` while no project is open. The dialog names the target (a story reads `Story "<title>" (milestone "<title>")`) and has Base, Prefix, Verify (or `run without any verification`) and Parallel. A milestone, a story or the whole board gets an `am` dry-run preview before **Start run**; a story's reads `N subtasks · rooted on <branch>`. A subtask has no preview, and its Start takes two clicks. A done, merged, canceled or archived card is refused with `The card is <status>`. A story whose blocker stories are not finished is refused by `am`, from the preview or from Start, and the dialog offers **Dispatch the milestone instead**; any other `am` refusal is shown verbatim. The prefix defaults to the branch prefix of the newest run of the target's milestone in the Runs list, else the last prefix used for that milestone from the panel, else the last prefix used at all, else a stem of the milestone's title, and it can be edited. After a successful start the panel shows the Runs list and opens the new run once `am` lists it, and it remembers the verify commands, the parallelism and the prefix for the project. Starting runs needs an `am` with `am run --story` (see Install).
- **Documents** - lists every `.md` file under `docs/` (at most 500; a note says
  when the list was cut off). Each document has one type: Architecture, Specs,
  Standards, Audits, or Other. Set it with a `tag:` line in the file's YAML
  frontmatter (`tag: spec`, `standard`, `audit`, `architecture`; case and
  singular/plural do not matter); without one the folder decides
  (`docs/architecture`, `docs/specs` and `docs/superpowers/specs`,
  `docs/standards`, `docs/audits`), and anything else is Other. Badges in the
  fixed toolbar show counts; click one to filter, click it again to clear. An
  open document keeps its path and its type picker in that toolbar too, so only
  the document body scrolls. The filter
  combines with the search box, and each row carries its badge. The frontmatter
  block is not shown when a document is opened.
  A file that brd has registered also carries a **brd** badge, in the warning
  colour when brd's copy is out of step with the file on disk, and brd's own
  tags on a separate line - **brd tags are not the document type the picker
  edits**; the two are never merged. An open document's header says
  "Registered in brd", plus brd's state for it when its backup no longer matches
  the file. A registration whose file is gone is still listed, dimmed, as
  "missing on disk" so its backup stays discoverable; opening it shows "This
  document is not on disk." instead of a body. Opening the Documents section
  runs `brd doc list`, which syncs (writes) brd's backups - the one thing in the
  panel that is not a pure read of brd besides New milestone and Archive finished.
  Documents over 1 MB (1048576 bytes) are not displayed. A document is
  rendered as Markdown and reloads live when the file changes; links are not
  clickable, and a document that references remote images may cause them to be
  fetched when it is displayed. With none
  found the list says "No Markdown documents found in this project."
- **Status colors** - done is green, in progress is blue, blocked is orange;
  todo follows the theme's dim color.
- **Live refresh** - watches the selected project's `brd` database file
  and re-fetches automatically when it changes on disk (e.g. an agent
  updates the board while the panel is open), plus a manual refresh
  button. The watch is debounced, so a burst of writes costs one refetch.
- **Breadcrumbs** - the toolbar always leads with the trail to where you are:
  `Board`, or `Board › Milestone › Story › Subtask` inside a card (`Graph ›` …
  when the card was opened from the graph, `Issues ›` when it was opened from an
  issue), `Documents › <title>`, `Memories › <note>` and
  `Issues › <issue title>` and `Runs › …<last 8 characters of the run id>`. Click the section crumb to go back the way the old
  "Back" did, or an ancestor crumb to open that card; the last crumb is where
  you are.
- **Keyboard navigation** - Up/Down moves the highlight (the panel scrolls to
  keep it visible) through Board cards, documents, issues or runs and, inside a card
  or an issue, its links (a card's parent/blocked-by/children, an issue's
  blocked cards/references/referenced-by); Enter or Right-at-end opens the
  highlighted item. A card, document or issue without links scrolls with
  Up/Down. Tab switches bar panels. Left goes Back from a card, document or
  issue.
- **Escape** closes the project dropdown first; otherwise, from a card,
  document or issue, goes Back; from a section list, closes the panel. If you have
  typed a search, Escape clears it first. Going Back restores the list
  highlight and scroll position you left.
- **Delete a project** - click **Delete project...** in the sidebar footer,
  then type `delete` in the confirmation dialog (a modal over a dimmed backdrop; Escape or a click outside cancels) to confirm, as in the Claude Memory plugin. This runs
  `brd forget`, which removes the project's board from brd. Your project's
  files are not touched. **A snapshot is always saved first**, to
  `~/Snapshots/omarchy-project-manager/<name>-<timestamp>/` (override with
  `OMARCHY_PROJECT_MANAGER_SNAPSHOT_DIR`), and if a snapshot can't be saved the project is
  not removed. Each snapshot holds `export.json` (`brd export`: the whole
  board - cards, issues, documents, comments, tags and refs) and a
  `RESTORE.txt` with the exact commands (`brd init`, then
  `brd import export.json`). If `brd export` can't run (e.g. the project
  directory is gone), the snapshot holds a raw copy of the project database
  instead, plus its `.docs/` document backups when they exist.
- No card, issue or comment is ever created or edited from the panel (the
  New-milestone agent is the one exception, and it writes through `brd` itself).

The plugin runs `brd` (`brd projects`, `brd tree`, `brd issue list` - an older
brd without issues simply shows none - plus one `brd export` with each board
refresh, for the issue bodies, comments and refs, and `brd doc list` when the
Documents section opens, which is the only one of these that writes: it syncs
brd's document backups. A brd too old for `export` or `doc list` simply shows no
comments, no issue details and no brd badges), plus small helpers in its
`core/backend/<domain>/` folders: `projects/resolve-db-path.py`,
`projects/viewer-state.py` (remembers the last project),
`documents/list-docs.py` (lists a project's documents),
`projects/snapshot-and-forget.py` (the delete flow), and the New-milestone
helper `milestones/run-setup-milestone.py` (the unattended agent run, plus
`--describe` for which agent the dialog will use), which builds its prompt from
`milestones/setup-milestone.md` and resolves the agent's argv through
`milestones/agents.py`. For the run monitor it runs only `am` (`am runs --repo-dir R` for each registered project, `am status`, `am watch --all-projects --follow` and `am logs`) through the helpers in `core/backend/runs/` (`runs/runs-snapshot-all.py`, `runs/runs-watch.py`, `runs/runs-logs.py`), and never reads am's SQLite database. am finds its journals under its own data dir, so the `XDG_DATA_HOME` the shell passes on to it matters.

## Install

```bash
git clone https://github.com/paulomtts/omarchy-project-manager.git
cd omarchy-project-manager
./install.sh              # links the plugin, rescans, enables it
./install.sh --with-brd   # ...and installs the brd CLI first if it is missing
```

The plugin reads from `brd` (`brd doc list`, which syncs brd's own document
backups, and the New-milestone agent are the only things that write), and the
two are separate projects, so installing `brd` is optional: without `--with-brd` (or `--no-brd`) you are
asked when it is missing, and a non-interactive run skips it. `--with-brd` uses
`uv tool install` (or `pipx`) on `git+https://github.com/paulomtts/brd.git`, so
it needs access to that repository; if the install fails the plugin is still
installed. Set `BRD_SOURCE` to install `brd` from somewhere else. Use
`--dry-run` to see what would happen. The installer links the checkout instead
of copying it, so `git pull` updates the plugin (then run
`omarchy-restart-shell`).

Requires `brd` on `PATH` to show anything. See <https://github.com/paulomtts/brd>.

The run monitor also needs `am` on `PATH`. It is optional: without it the Runs screen says "am is not installed or not on PATH" and no run marks appear anywhere. The run monitor needs an `am` whose `am runs` and `am status` carry `as_of_seq` and whose watch hello carries `head` (agent-manager 0.2.0). With an older `am` each project's snapshot fails with `SchemaMismatch`: its group on the Runs screen shows an error under its header saying the plugin needs the newer am (the footer says it too when no project could be read); a watch whose hello lacks `head` shows a schema-mismatch banner and the runs are polled every 5 s instead of watched. A corrupt journal shows a warning line and falls back to the same poll. If no good snapshot arrives for 30 s while the panel is open, the Runs screen says "Run data is out of date" and every run mark is dimmed. Starting runs from the panel needs an `am` whose `am run` supports `--story`: `am run --help` must list it. `am` is installed as a `uv` tool; unless it is an editable install, update it after pulling agent-manager by running `uv tool install --reinstall .` in a clean checkout of agent-manager. `tests/contract/test_am_shapes.py` fails when the installed `am` lacks `--story`.

## Keybinding (optional)

Add to `~/.config/hypr/bindings.lua` (Hyprland reloads it on save):

```lua
o.bind("CTRL + SUPER + J", "Omarchy Project Manager", "omarchy-shell shell toggle paulomtts.omarchy-project-manager")
```

`CTRL + SUPER + J` is free in a stock Omarchy setup (check yours with
`hyprctl binds`); pick another key if it clashes.

## Uninstall

```bash
omarchy plugin disable paulomtts.omarchy-project-manager
rm -rf ~/.config/omarchy/plugins/paulomtts.omarchy-project-manager
```

## Development

Layout (details and rules in `docs/architecture.md`):

```
manifest.json          entryPoints.barWidget -> ui/Panel.qml
install.sh             installer (the only source file at the root)
core/domain/           pure JavaScript rules and parsers
core/backend/<domain>/ Python helpers (one JSON line each) + common/
core/stores/           non-visual QML state and workflows (App composes them)
ui/                    Panel, Shortcuts, Navigator, screens/, components/, theme/
vendor/canvas/         vendored canvas plugin (see VENDORED.md)
tests/                 core/, ui/, architecture/, contract/, helpers/, stubs/
```

Data flow: `Panel` creates one `App`; stores run `brd` and the helpers and
expose properties; screens and components bind to them. `ui/` may use `core/`,
never the reverse.

## Tests

```bash
bash tests/run.sh [filter]   # pytest, then every QML test (optional path filter)
./run-tests.sh               # thin delegate to tests/run.sh
python3 -m pytest tests/contract -q   # brd's and am's JSON shapes, against the installed CLIs
bash tests/live-check.sh     # restarts the real shell; needs the desktop session
```

`tests/contract` runs the installed `brd` in a throwaway project with its own
`HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME`, so your real boards are never touched;
it fails when brd's JSON drifts from what the plugin parses, and is skipped when
`brd` is not installed. `tests/run.sh` already includes it.
`tests/contract/test_am_shapes.py` does the same for `am`: with its own `HOME`, `XDG_DATA_HOME` and `XDG_STATE_HOME`, it seeds a real story run through `am` commands alone and pins the `am runs`, `am status` and `am watch` shapes the run helpers parse; it is skipped when `am` is not installed, and its story tests fail, rather than skip, when the installed `am` has no `am run --story`, or when brd or git is missing. `tests/contract/test_am_fixtures.py` pins the committed `am` captures in `tests/fixtures/am/` and checks the installed `am`, in a scratch data dir, against them; it fails when that `am` lacks `as_of_seq` in `am runs` or `head` in its watch hello.

See `docs/architecture.md` and the specs in `docs/superpowers/specs/`
(board viewer, sidebar and documents, core/ui architecture) for the design.
