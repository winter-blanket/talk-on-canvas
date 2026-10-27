# talk-on-canvas

[한국어](README.md) · [English](README.en.md)

- A Claude Code plugin that keeps a single **HTML canvas** open in your browser and updates it at the speed of the conversation, instead of dumping answers into the terminal.

> Why this exists
> - Long terminal output stops being read. Tables break, code and prose blur together, and whatever you agreed on ten minutes ago is buried somewhere up the scrollback.
> - "What did we decide to do?" and "why did you say that wouldn't work?" take a long scroll to recover. So you end up asking the same thing again.
> - So the conversation gets its own screen next to the terminal, and the LLM rewrites that screen every turn. The terminal becomes the place you type; everything you read lives on the canvas.

Unlike [study-on-canvas](https://github.com/winter-blanket/study-on-canvas), which has one fixed purpose (learning concepts) and one fixed layout, this plugin has **no predetermined content structure**. A design discussion gets design tables; debugging gets hypotheses and evidence; planning gets screen flows. Deciding "what block does this conversation need right now" is the plugin's actual job.

### Supported LLMs

- Claude Code

## Usage

### 1. Invoke the slash command and describe what you're working on.

```plain_text
/talk-on-canvas:talk-on-canvas We're switching our login flow to social login — let's work out what order to do it in.
```

- Natural-language invocation ("let's use a canvas", "summarize this") is not supported. The slash command is the only entry point.
  - "Summarize this" or "give me an HTML file" is a one-off file request, not a conversation canvas. If the plugin hijacked those, it would start a server and take on an update obligation for the rest of the session that you never asked for.

### 2. The canvas is created and your browser opens automatically.

- If the directory you ran it from has a `canvas` folder, canvases go there; otherwise it asks where to save (default `<that directory>/canvas/`). [study-on-canvas](https://github.com/winter-blanket/study-on-canvas) uses the same folder.
- Before creating a new one, it looks in that folder for a **canvas you already started on the same topic**. If one looks like a match (by title and section headings), it asks whether to continue in that file or start a new one.
- Files are named `<date>-<title>.html`. Inside a git repo, add `canvas/` to `.gitignore` if you don't want to commit them.
- Want it somewhere else? Say so when you invoke it.
- Whatever you discussed *before* invoking the plugin is read and backfilled, so you start with a populated canvas rather than a blank one.

### 3. From there, just talk.

- The terminal only gets 2–4 lines saying what changed. Conclusions, reasoning, tables, and code all live on the canvas.
- The browser polls every 1.2 seconds and swaps **only the changed parts** — no flicker, no scroll jumps, no refresh needed.
- Anything *you* need to do goes into the **to-do list** pinned at the top of the canvas, as checkboxes. Done and blocked states are kept current as the conversation goes.

## Layout

| Area | Role |
|------|------|
| At a glance (right drawer) | `Now` · `Next` · `Decided` · `Open questions`. Holds the things that otherwise vanish into scrollback. Open it with the `한 눈에 보기` button; drag its left edge to resize (35% of the screen by default) |
| To-do list | Only actions *you* must take. The `3 / 7 done` counter is computed automatically. Hides itself when empty |
| Sections | One per topic. Revisiting a topic rewrites its section rather than stacking a new one |
| Table of contents (left) | Section list, newest first — same order as the cards. A `NEW` badge marks whatever was updated this turn; the `«` button collapses it |
| Theme · back to top | The sun/moon icon switches light/dark (follows the system until you pick). Once you scroll down, a floating `↑` button appears bottom-right |

The canvas is **current state**, not a conversation log. It grows in accuracy, not in length.

## Customizing

The installed plugin lives at `~/.claude/plugins/cache/talk-on-canvas/talk-on-canvas/` (or under your `CLAUDE_CONFIG_DIR` if you've changed it).

### HTML/UI design

- Edit the `<style>` block in `skills/talk-on-canvas/template/canvas.html`.
- Colors are CSS variables on `:root`; light and dark split on `prefers-color-scheme`.

### How much goes to the terminal

- The default is "2–4 pointer lines, everything else on the canvas."
- Want summaries in the terminal too? Edit the "터미널에 무엇을 쓰는가" (What goes in the terminal) section of `SKILL.md`.

### Turning off the to-do list

- Delete the "할 일 목록 운영" (To-do list) section of `SKILL.md` and leave the template's `<!-- TODO -->` region empty — it hides itself.

## Installation

```plain_text
/plugin marketplace add winter-blanket/talk-on-canvas
/plugin install talk-on-canvas@talk-on-canvas
```

## How it works

- A local HTTP server bound to `127.0.0.1` serves the canvas folder, and the page compares `data-rev` values to detect updates.
- Without python3, or if the port can't be bound, it falls back to `file://` mode and refreshes with full reloads. It never reloads while you are scrolling or selecting (it waits for 5 seconds of idle), and backs off from 4 s up to 60 s while the content stays the same. Scroll position is restored per tab.
- A `<filename>.server` file (pid and port) sits next to the canvas and is removed when the server stops.

## Language

- Korean. UI labels are hardcoded in Korean — swap the label strings in the template to run it in English.

## File structure

```plain_text
talk-on-canvas/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── skills/
│   └── talk-on-canvas/
│       ├── SKILL.md                 # The skill — canvas operating rules
│       ├── template/
│       │   └── canvas.html          # Canvas template (styles and script included)
│       └── scripts/
│           └── canvas.sh            # Create / list / resume canvas, run local server, open browser
├── LICENSE
├── README.md
└── README.en.md
```

## License

MIT
