#!/usr/bin/env bash
# talk-on-canvas 보조 스크립트.
#   bash canvas.sh where                      기본 저장 폴더(<현재 경로>/canvas)와 존재 여부
#   bash canvas.sh open "<제목>" [저장경로]   캔버스 생성 + 로컬 서버 + 브라우저 열기 (저장경로는 파일 또는 폴더)
#   bash canvas.sh list [폴더]                기존 캔버스 목록 (최근 수정순, 이어 쓰기 후보 판단용)
#   bash canvas.sh resume <저장경로>          기존 캔버스를 그대로 두고 서버 + 브라우저만 다시 열기
#   bash canvas.sh stop <저장경로>            해당 캔버스의 로컬 서버 종료
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }

# 기본 저장 폴더는 세션이 시작된 경로의 canvas/ — study-on-canvas 와 같은 폴더를 쓴다
DEFAULT_DIR="$(pwd)/canvas"

find_template() {
  local c
  for c in \
    "$SELF_DIR/../template/canvas.html" \
    "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills/talk-on-canvas/template/canvas.html" \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/talk-on-canvas/template/canvas.html" \
    "$HOME/.claude/skills/talk-on-canvas/template/canvas.html" \
    ".claude/skills/talk-on-canvas/template/canvas.html"
  do
    [ -f "$c" ] && { cd "$(dirname "$c")" && echo "$(pwd)/$(basename "$c")"; return 0; }
  done
  return 1
}

slugify() {
  python3 - "$1" <<'PY'
import re, sys
s = sys.argv[1].strip()
s = re.sub(r'[/\\:*?"<>|]', '', s)
s = re.sub(r'\s+', '-', s)
s = re.sub(r'-{2,}', '-', s).strip('-')
print((s or 'canvas')[:60])
PY
}

cmd_open() {
  local title="${1:-작업 캔버스}" dest="${2:-}"
  local today; today="$(date +%Y-%m-%d)"
  local name="${today}-$(slugify "$title").html"
  [ -n "$dest" ] || dest="$DEFAULT_DIR"
  case "$dest" in /*) ;; *) dest="$(pwd)/$dest" ;; esac
  # 폴더를 주면 그 안에 <날짜>-<제목>.html 로 만든다
  case "$dest" in *.html) ;; *) dest="${dest%/}/$name" ;; esac

  local tpl; tpl="$(find_template)" || die "템플릿(canvas.html)을 찾지 못했습니다."
  mkdir -p "$(dirname "$dest")" || die "폴더를 만들 수 없습니다: $(dirname "$dest")"
  cp "$tpl" "$dest" || die "템플릿 복사 실패"

  python3 - "$dest" "$title" "$(date '+%H:%M')" <<'PY'
import sys, io
path, title, started = sys.argv[1], sys.argv[2], sys.argv[3]
html = io.open(path, encoding='utf-8').read()
esc = title.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
html = html.replace('{{TITLE}}', esc).replace('{{STARTED}}', started).replace('{{LANG}}', 'ko')
io.open(path, 'w', encoding='utf-8').write(html)
PY

  serve_and_open "$dest"
}

cmd_where() {
  echo "DIR=$DEFAULT_DIR"
  [ -d "$DEFAULT_DIR" ] && echo "EXISTS=1" || echo "EXISTS=0"
}

cmd_list() {
  local dir="${1:-$DEFAULT_DIR}"
  [ -d "$dir" ] || { echo "NO_CANVASES"; return 0; }
  python3 - "$dir" <<'PY'
import glob, html, io, os, re, sys, time
d = sys.argv[1]
files = [f for f in glob.glob(os.path.join(d, '*.html')) if not f.endswith('.artifact.html')]
files.sort(key=os.path.getmtime, reverse=True)
if not files:
    print('NO_CANVASES'); sys.exit()
def text(frag):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', frag))).strip()
for f in files[:15]:
    src = io.open(f, encoding='utf-8', errors='replace').read()
    title = re.search(r'<title>(.*?)</title>', src, re.S)
    rev = re.search(r'<html[^>]*data-rev="(\d+)"', src)
    now = re.search(r'<!-- ST:now -->(.*?)<!-- /ST:now -->', src, re.S)
    content = src.split('<!-- SECTIONS_INSERT -->', 1)[-1]
    heads = [text(h) for h in re.findall(r'<section class="card[^"]*"[^>]*>\s*<h2>(.*?)</h2>', content, re.S)]
    print('CANVAS=%s' % f)
    print('  title: %s' % (text(title.group(1)) if title else '?'))
    print('  updated: %s · rev %s' % (time.strftime('%Y-%m-%d %H:%M', time.localtime(os.path.getmtime(f))), rev.group(1) if rev else '?'))
    if now and text(now.group(1)): print('  now: %s' % text(now.group(1))[:160])
    if heads: print('  sections: %s' % ' · '.join(heads))
PY
}

cmd_resume() {
  local dest="${1:-}"; [ -n "$dest" ] || die "경로를 주세요."
  case "$dest" in /*) ;; *) dest="$(pwd)/$dest" ;; esac
  [ -f "$dest" ] || die "캔버스 파일이 없습니다: $dest"
  serve_and_open "$dest"
}

serve_and_open() {
  local dest="$1"
  # 같은 폴더를 이미 서빙 중이면 재사용
  local pidf="${dest}.server"
  if [ -f "$pidf" ]; then
    local opid oport; opid="$(cut -d' ' -f1 "$pidf")"; oport="$(cut -d' ' -f2 "$pidf")"
    if kill -0 "$opid" 2>/dev/null; then
      echo "CANVAS=$dest"; echo "URL=http://127.0.0.1:${oport}/$(basename "$dest")"; echo "MODE=http(reused)"
      open_url "http://127.0.0.1:${oport}/$(basename "$dest")"
      return 0
    fi
  fi

  local port; port="$(python3 - <<'PY'
import socket
for p in range(7420, 7520):
    s = socket.socket()
    try:
        s.bind(('127.0.0.1', p)); s.close(); print(p); break
    except OSError:
        s.close()
PY
)"

  if [ -n "$port" ]; then
    ( cd "$(dirname "$dest")" && nohup python3 -m http.server "$port" -b 127.0.0.1 >/dev/null 2>&1 & echo $! > "$pidf.tmp" )
    sleep 0.4
    local spid; spid="$(cat "$pidf.tmp" 2>/dev/null)"; rm -f "$pidf.tmp"
    if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
      echo "$spid $port" > "$pidf"
      local url="http://127.0.0.1:${port}/$(basename "$dest")"
      echo "CANVAS=$dest"; echo "URL=$url"; echo "MODE=http"
      open_url "$url"
      return 0
    fi
  fi

  # 폴백: file:// — 템플릿이 4초 주기 새로고침 모드로 동작한다
  echo "CANVAS=$dest"; echo "URL=file://$dest"; echo "MODE=file"
  open_url "file://$dest"
}

open_url() {
  [ -n "${LC_NO_OPEN:-}" ] && { echo "OPEN_SKIPPED=1"; return 0; }
  case "$(uname -s)" in
    Darwin) open "$1" >/dev/null 2>&1 ;;
    Linux) xdg-open "$1" >/dev/null 2>&1 & ;;
    MINGW*|MSYS*|CYGWIN*) start "" "$1" ;;
    *) false ;;
  esac || echo "OPEN_FAILED=1"
}

cmd_stop() {
  local dest="${1:-}"; [ -n "$dest" ] || die "경로를 주세요."
  local pidf="${dest}.server"
  [ -f "$pidf" ] || { echo "서버 기록이 없습니다."; return 0; }
  local pid; pid="$(cut -d' ' -f1 "$pidf")"
  kill "$pid" 2>/dev/null && echo "서버 종료 (pid $pid)" || echo "이미 종료됨"
  rm -f "$pidf"
}

case "${1:-}" in
  where) shift; cmd_where "$@" ;;
  open) shift; cmd_open "$@" ;;
  list) shift; cmd_list "$@" ;;
  resume) shift; cmd_resume "$@" ;;
  stop) shift; cmd_stop "$@" ;;
  *) die "사용법: canvas.sh where | open \"<제목>\" [경로] | list [폴더] | resume <경로> | stop <경로>" ;;
esac
