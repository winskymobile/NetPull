#!/usr/bin/env python3
"""Local intranet file server with a compact listing."""

from __future__ import annotations

import argparse
import datetime as dt
import html
import os
import re
import urllib.parse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

KIND_BY_EXT = {
    ".pdf": ("PDF", "pdf"),
    ".doc": ("Word", "doc"),
    ".docx": ("Word", "doc"),
    ".xls": ("Excel", "sheet"),
    ".xlsx": ("Excel", "sheet"),
    ".ppt": ("PowerPoint", "slide"),
    ".pptx": ("PowerPoint", "slide"),
    ".txt": ("文本", "text"),
    ".md": ("Markdown", "text"),
    ".csv": ("表格", "sheet"),
    ".json": ("JSON", "code"),
    ".xml": ("XML", "code"),
    ".html": ("HTML", "code"),
    ".css": ("CSS", "code"),
    ".js": ("JavaScript", "code"),
    ".ts": ("TypeScript", "code"),
    ".py": ("Python", "code"),
    ".zip": ("ZIP", "archive"),
    ".rar": ("RAR", "archive"),
    ".7z": ("7z", "archive"),
    ".tar": ("TAR", "archive"),
    ".gz": ("Gzip", "archive"),
    ".png": ("PNG", "image"),
    ".jpg": ("JPEG", "image"),
    ".jpeg": ("JPEG", "image"),
    ".gif": ("GIF", "image"),
    ".webp": ("WebP", "image"),
    ".svg": ("SVG", "image"),
    ".heic": ("HEIC", "image"),
    ".mp4": ("影片", "video"),
    ".mov": ("影片", "video"),
    ".mkv": ("影片", "video"),
    ".mp3": ("音频", "audio"),
    ".wav": ("音频", "audio"),
    ".aac": ("音频", "audio"),
    ".m4a": ("音频", "audio"),
    ".dmg": ("磁盘映像", "disk"),
    ".iso": ("磁盘映像", "disk"),
    ".pkg": ("安装包", "disk"),
    ".ipa": ("iOS 应用", "app"),
    ".apk": ("Android 应用", "app"),
}


def human_size(num: int) -> str:
    units = ["字节", "KB", "MB", "GB", "TB"]
    size = float(num)
    for unit in units:
        if size < 1024 or unit == units[-1]:
            if unit == "字节":
                return f"{int(size)} {unit}"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{num} 字节"


def file_kind(name: str, is_dir: bool) -> tuple[str, str]:
    if is_dir:
        return "文件夹", "folder"
    ext = Path(name).suffix.lower()
    return KIND_BY_EXT.get(ext, ("文件", "file"))


def icon_svg(kind: str) -> str:
    stroke = 'fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"'
    icons = {
        "folder": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><path {stroke} d="M5.5 10.5h7.2l2.1 2.2H26.5v11.3a2 2 0 0 1-2 2H7.5a2 2 0 0 1-2-2V10.5z"/><path {stroke} d="M5.5 10.5V8.7a2 2 0 0 1 2-2h5.1l2.1 2.2"/></svg>',
        "image": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><rect {stroke} x="6" y="8" width="20" height="16" rx="2.4"/><circle {stroke} cx="12.2" cy="13.4" r="1.6"/><path {stroke} d="m8.5 21.2 5.2-5.4 3.4 3.4 2.4-2.5 4 4.5"/></svg>',
        "video": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><rect {stroke} x="5.5" y="8" width="21" height="16" rx="2.4"/><path {stroke} d="m13.4 12.4 7.2 3.6-7.2 3.6z"/></svg>',
        "audio": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><path {stroke} d="M12.5 13.2v8.2"/><path {stroke} d="M12.5 13.2 21 11v8.4"/><circle {stroke} cx="10.6" cy="21.4" r="2"/><circle {stroke} cx="19.1" cy="19.4" r="2"/></svg>',
        "pdf": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><path {stroke} d="M10 6.5h8.2L25.5 14V24a2 2 0 0 1-2 2h-13.5a2 2 0 0 1-2-2V8.5a2 2 0 0 1 2-2z"/><path {stroke} d="M18.2 6.6V13h6.6"/><path {stroke} d="M11.6 19.2h8.8M11.6 22.4h6.2"/></svg>',
        "doc": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><path {stroke} d="M10 6.5h8.2L25.5 14V24a2 2 0 0 1-2 2h-13.5a2 2 0 0 1-2-2V8.5a2 2 0 0 1 2-2z"/><path {stroke} d="M18.2 6.6V13h6.6"/><path {stroke} d="M11.6 18.4h8.8M11.6 21.6h6.2"/></svg>',
        "sheet": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><rect {stroke} x="7" y="7" width="18" height="18" rx="2"/><path {stroke} d="M7 13.2h18M7 18.8h18M13.2 7v18"/></svg>',
        "slide": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><rect {stroke} x="6.5" y="9" width="19" height="13" rx="2"/><path {stroke} d="M12 25.2h8M16 22v3.2"/></svg>',
        "archive": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><path {stroke} d="M7 9.2h18v14.3a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V9.2z"/><path {stroke} d="M7 9.2 8.6 6.5h14.8L25 9.2"/><path {stroke} d="M14.4 14.2h3.2v4.4h-3.2z"/></svg>',
        "code": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><path {stroke} d="m11.2 12.4-4.4 3.6 4.4 3.6M20.8 12.4l4.4 3.6-4.4 3.6M17.4 11.2l-2.8 9.6"/></svg>',
        "text": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><path {stroke} d="M10 6.5h8.2L25.5 14V24a2 2 0 0 1-2 2h-13.5a2 2 0 0 1-2-2V8.5a2 2 0 0 1 2-2z"/><path {stroke} d="M18.2 6.6V13h6.6"/><path {stroke} d="M11.6 18h8.8M11.6 21.2h6"/></svg>',
        "disk": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><rect {stroke} x="7" y="8" width="18" height="16" rx="2.4"/><circle {stroke} cx="16" cy="16" r="3.4"/></svg>',
        "app": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><rect {stroke} x="7.5" y="7.5" width="17" height="17" rx="4.4"/></svg>',
        "file": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><path {stroke} d="M10 6.5h8.2L25.5 14V24a2 2 0 0 1-2 2h-13.5a2 2 0 0 1-2-2V8.5a2 2 0 0 1 2-2z"/><path {stroke} d="M18.2 6.6V13h6.6"/></svg>',
        "up": f'<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><path {stroke} d="M14 7h-8v8"/><path {stroke} d="M6 7 16.5 17.5"/><path {stroke} d="M16 25h8.5a2 2 0 0 0 2-2V14"/></svg>',
    }
    return icons.get(kind, icons["file"])


STYLE = """
:root {
  color-scheme: light dark;
  --bg: #e8edf2;
  --ink: #121820;
  --muted: #5b6673;
  --line: rgba(18,24,32,.08);
  --surface: #f7f9fb;
  --panel: #ffffff;
  --hover: #f2f5f8;
  --action: #121820;
  --action-text: #ffffff;
  --pad: clamp(20px, 5vw, 72px);
  --ease: cubic-bezier(.22,1,.36,1);
  --focus: 0 0 0 4px rgba(18,24,32,.16);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0e1216;
    --ink: #eef2f6;
    --muted: #9aa6b2;
    --line: rgba(255,255,255,.08);
    --surface: #151b21;
    --panel: #1b222a;
    --hover: #222b34;
    --action: #eef2f6;
    --action-text: #121820;
  }
}
* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; }
body {
  min-height: 100dvh;
  font-family: "SF Pro Display", "SF Pro Text", -apple-system, BlinkMacSystemFont,
    "PingFang SC", "Hiragino Sans GB", sans-serif;
  background:
    radial-gradient(1200px 480px at 12% -10%, rgba(255,255,255,.7), transparent 60%),
    var(--bg);
  color: var(--ink);
  -webkit-font-smoothing: antialiased;
}
:focus-visible { outline: none; box-shadow: var(--focus); }
a { color: inherit; }
.page {
  width: min(1180px, 100%);
  margin: 0 auto;
  padding: clamp(28px, 5vh, 64px) var(--pad) 80px;
}
.mast {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  gap: 20px 32px;
  margin-bottom: clamp(28px, 4vh, 40px);
}
.hero {
  min-width: 0;
  flex: 1;
}
.search {
  display: flex;
  align-items: center;
  gap: 12px;
  flex: 0 0 auto;
  width: min(420px, 42vw);
  height: 48px;
  padding: 0 16px 0 14px;
  border: 1px solid var(--line);
  border-radius: 16px;
  background: var(--panel);
  box-shadow: 0 12px 32px rgba(18,24,32,.04);
  transition: border-color .2s var(--ease), box-shadow .2s var(--ease);
}
.search svg {
  width: 20px;
  height: 20px;
  flex: none;
  color: var(--muted);
}
.search input {
  width: 100%;
  min-width: 0;
  border: 0;
  background: transparent;
  color: var(--ink);
  font: inherit;
  font-size: 16px;
  outline: none;
  appearance: none;
}
.search input::-webkit-search-decoration,
.search input::-webkit-search-cancel-button {
  -webkit-appearance: none;
}
.search input::placeholder { color: var(--muted); }
.search:focus-within {
  border-color: rgba(18,24,32,.22);
  box-shadow: var(--focus), 0 12px 32px rgba(18,24,32,.06);
}
.search-hint {
  flex: none;
  padding: 3px 8px;
  border: 1px solid var(--line);
  border-radius: 6px;
  color: var(--muted);
  font-size: 12px;
  letter-spacing: .04em;
}
.crumbs {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  min-width: 0;
  margin: 0;
  font-size: 14px;
  color: var(--muted);
}
.crumb { text-decoration: none; color: var(--muted); }
.crumb:hover { color: var(--ink); }
.crumb.current { color: var(--ink); pointer-events: none; }
h1 {
  margin: 0;
  font-size: clamp(32px, 5vw, 56px);
  line-height: 1.05;
  font-weight: 600;
  letter-spacing: -.04em;
}
.list-meta {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 16px 24px;
  margin: 0 4px 12px;
}
.count {
  margin: 0;
  color: var(--muted);
  font-size: 14px;
  white-space: nowrap;
}
.stage {
  border: 1px solid var(--line);
  border-radius: 24px;
  background: var(--panel);
  overflow: hidden;
  box-shadow: 0 20px 50px rgba(18,24,32,.05);
}
.head, .row {
  display: grid;
  grid-template-columns: 64px minmax(0, 1.6fr) minmax(110px, .6fr) minmax(110px, .5fr) 108px;
  align-items: center;
  gap: 12px;
  padding: 0 22px;
}
.head {
  min-height: 48px;
  color: var(--muted);
  font-size: 12px;
  letter-spacing: .12em;
  text-transform: uppercase;
  border-bottom: 1px solid var(--line);
  background: var(--surface);
}
.row {
  min-height: 84px;
  border-top: 1px solid var(--line);
  transition: background .25s var(--ease);
}
.row:first-of-type { border-top: 0; }
.row:hover { background: var(--hover); }
.row.up .icon { background: var(--ink); color: var(--panel); }
.row.up .name { font-weight: 600; }
.hit {
  display: contents;
  color: inherit;
  text-decoration: none;
}
.icon {
  width: 48px;
  height: 48px;
  display: grid;
  place-items: center;
  border-radius: 14px;
  background: var(--surface);
  color: var(--ink);
}
.glyph { width: 22px; height: 22px; display: block; }
.copy { min-width: 0; }
.name {
  display: block;
  font-size: clamp(17px, 1.5vw, 20px);
  font-weight: 600;
  letter-spacing: -.02em;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.kind {
  display: block;
  margin-top: 4px;
  color: var(--muted);
  font-size: 13px;
}
.size, .date {
  color: var(--muted);
  font-size: 14px;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.action {
  justify-self: end;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  height: 40px;
  min-width: 84px;
  padding: 0 16px;
  border-radius: 999px;
  background: var(--action);
  color: var(--action-text);
  font-size: 14px;
  font-weight: 500;
  text-decoration: none;
  transition: transform .2s var(--ease), opacity .2s var(--ease);
}
.action:hover { opacity: .88; }
.action:active { transform: scale(.98); }
.empty {
  padding: 64px 24px;
  text-align: center;
  color: var(--muted);
}
.empty h2 {
  margin: 0 0 8px;
  color: var(--ink);
  font-size: 28px;
  letter-spacing: -.03em;
}
.empty p { margin: 0; font-size: 16px; }
.site-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-top: 22px;
  color: var(--muted);
  font-size: 13px;
}
.credit {
  margin-left: auto;
  letter-spacing: .02em;
  white-space: nowrap;
}
.hidden { display: none !important; }
@media (max-width: 900px) {
  .head, .row {
    grid-template-columns: 56px minmax(0, 1fr) 96px;
  }
  .size, .date, .head span:nth-child(3), .head span:nth-child(4) { display: none; }
  .action { min-width: 76px; }
}
@media (max-width: 720px) {
  .mast { flex-direction: column; align-items: stretch; }
  .search { width: 100%; height: 50px; border-radius: 14px; }
  .search-hint { display: none; }
  .list-meta { margin: 0 0 10px; }
  .head { display: none; }
  .row {
    grid-template-columns: 48px minmax(0, 1fr) auto;
    min-height: 76px;
    padding: 14px 16px;
    gap: 12px;
  }
  .icon { width: 44px; height: 44px; border-radius: 12px; }
  .action { height: 36px; min-width: 68px; padding: 0 12px; }
}
@media (prefers-reduced-motion: reduce) {
  .row, .action { transition: none; }
}

.md-toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  align-items: center;
  margin: 0 4px 12px;
}
.md-stage {
  border: 1px solid var(--line);
  border-radius: 24px;
  background: var(--panel);
  overflow: hidden;
  box-shadow: 0 20px 50px rgba(18,24,32,.05);
}
.md-body {
  padding: 28px clamp(18px, 4vw, 40px) 48px;
  font-size: 16px;
  line-height: 1.75;
  overflow-x: auto;
}
.md-body > :first-child { margin-top: 0; }
.md-body h1, .md-body h2, .md-body h3, .md-body h4 {
  line-height: 1.2;
  letter-spacing: -.03em;
  font-weight: 650;
  margin: 1.4em 0 .6em;
}
.md-body h1 { font-size: 1.8em; }
.md-body h2 { font-size: 1.4em; }
.md-body h3 { font-size: 1.18em; }
.md-body p, .md-body ul, .md-body ol, .md-body pre, .md-body blockquote, .md-body table {
  margin: 0 0 1em;
}
.md-body a { color: inherit; text-decoration: underline; text-underline-offset: 3px; }
.md-body code {
  font-family: "SF Mono", ui-monospace, Menlo, Consolas, monospace;
  font-size: .9em;
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: 6px;
  padding: .1em .35em;
}
.md-body pre {
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: 14px;
  padding: 14px 16px;
  overflow: auto;
}
.md-body pre code {
  background: none;
  border: 0;
  padding: 0;
  font-size: 13px;
  line-height: 1.55;
}
.md-body blockquote {
  margin: 0 0 1em;
  padding: 2px 0 2px 16px;
  border-left: 3px solid var(--ink);
  color: var(--muted);
}
.md-body ul, .md-body ol { padding-left: 1.4em; }
.md-body img { max-width: 100%; height: auto; border-radius: 12px; }
.md-body table { border-collapse: collapse; width: 100%; }
.md-body th, .md-body td {
  border: 1px solid var(--line);
  padding: 8px 10px;
  text-align: left;
  vertical-align: top;
}
.md-body th { background: var(--surface); }
.md-body hr { border: 0; border-top: 1px solid var(--line); margin: 1.6em 0; }
"""


def breadcrumbs(url_path: str, root_name: str) -> list[tuple[str, str, bool]]:
    decoded = urllib.parse.unquote(url_path)
    parts = [p for p in decoded.split("/") if p]
    crumbs = [("根目录", "/", not parts)]
    acc = ""
    for i, part in enumerate(parts):
        acc += "/" + part
        href = acc + "/"
        crumbs.append((part, href, i == len(parts) - 1))
    return crumbs


def parent_href(url_path: str) -> str | None:
    parts = [p for p in urllib.parse.unquote(url_path).split("/") if p]
    if not parts:
        return None
    if len(parts) == 1:
        return "/"
    return "/" + "/".join(parts[:-1]) + "/"



def decode_text_bytes(data: bytes) -> str:
    for enc in ("utf-8-sig", "utf-8", "gb18030"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", "replace")


def safe_href(url: str) -> str | None:
    url = (url or "").strip()
    if not url:
        return None
    if url.startswith("#"):
        return url
    lowered = url.lower()
    if lowered.startswith(("javascript:", "data:", "vbscript:")):
        return None
    return url


INLINE_RE = re.compile(
    r"\\(.)"
    r"|`([^`]+)`"
    r"|!\[([^\]]*)\]\(([^)\s]+)(?:\s+\"([^\"]*)\")?\)"
    r"|\[([^\]]+)\]\(([^)\s]+)(?:\s+\"([^\"]*)\")?\)"
    r"|\*\*(.+?)\*\*"
    r"|__(.+?)__"
    r"|~~(.+?)~~"
    r"|((?:https?://)[^\s<]+)"
    r"|\*([^*\n]+)\*"
    r"|_([^_\n]+)_"
)


def render_inline(text: str) -> str:
    out: list[str] = []
    pos = 0
    for match in INLINE_RE.finditer(text):
        out.append(html.escape(text[pos:match.start()]))
        if match.group(1) is not None:
            out.append(html.escape(match.group(1)))
        elif match.group(2) is not None:
            out.append("<code>" + html.escape(match.group(2)) + "</code>")
        elif match.group(4) is not None:
            href = safe_href(match.group(4))
            if href:
                out.append(
                    f'<img src="{html.escape(href)}" alt="{html.escape(match.group(3) or "")}">'
                )
            else:
                out.append(html.escape(match.group(0)))
        elif match.group(7) is not None:
            href = safe_href(match.group(7))
            inner = render_inline(match.group(6))
            if href:
                out.append(f'<a href="{html.escape(href)}">{inner}</a>')
            else:
                out.append(html.escape(match.group(0)))
        elif match.group(9) is not None:
            out.append("<strong>" + render_inline(match.group(9)) + "</strong>")
        elif match.group(10) is not None:
            out.append("<strong>" + render_inline(match.group(10)) + "</strong>")
        elif match.group(11) is not None:
            out.append("<del>" + render_inline(match.group(11)) + "</del>")
        elif match.group(12) is not None:
            url = match.group(12).rstrip(".,;:!?)")
            out.append(f'<a href="{html.escape(url)}">{html.escape(url)}</a>')
        elif match.group(13) is not None:
            out.append("<em>" + render_inline(match.group(13)) + "</em>")
        elif match.group(14) is not None:
            out.append("<em>" + render_inline(match.group(14)) + "</em>")
        pos = match.end()
    out.append(html.escape(text[pos:]))
    return "".join(out)


def _split_table_row(line: str) -> list[str]:
    raw = line.strip()
    if raw.startswith("|"):
        raw = raw[1:]
    if raw.endswith("|"):
        raw = raw[:-1]
    return [cell.strip() for cell in raw.split("|")]


def md_to_html(src: str) -> str:
    lines = src.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    parts: list[str] = []
    i = 0
    n = len(lines)

    def is_ul(value: str) -> bool:
        return re.match(r"^\s*[-*+]\s+", value) is not None

    def is_ol(value: str) -> bool:
        return re.match(r"^\s*\d+[.)]\s+", value) is not None

    while i < n:
        line = lines[i]
        stripped = line.strip()
        if re.match(r"^`{3,}([^`]*)$", stripped):
            buf: list[str] = []
            i += 1
            while i < n and not re.match(r"^`{3,}\s*$", lines[i].strip()):
                buf.append(lines[i])
                i += 1
            if i < n:
                i += 1
            parts.append("<pre><code>" + html.escape("\n".join(buf)) + "</code></pre>")
            continue
        compacted = re.sub(r"\s+", "", line)
        if compacted[:3] in {"---", "***", "___"} and re.fullmatch(r"[-*_]{3,}", compacted):
            parts.append("<hr>")
            i += 1
            continue
        heading = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if heading:
            level = len(heading.group(1))
            title = heading.group(2).rstrip("#").rstrip()
            parts.append(f"<h{level}>{render_inline(title)}</h{level}>")
            i += 1
            continue
        if stripped.startswith(">"):
            chunk: list[str] = []
            while i < n and lines[i].lstrip().startswith(">"):
                chunk.append(re.sub(r"^\s*>\s?", "", lines[i]))
                i += 1
            parts.append("<blockquote>" + md_to_html("\n".join(chunk)) + "</blockquote>")
            continue
        if "|" in line and i + 1 < n and re.match(r"^\s*\|?\s*:?-{2,}", lines[i + 1]):
            header = _split_table_row(line)
            i += 2
            body_rows: list[list[str]] = []
            while i < n and "|" in lines[i] and lines[i].strip():
                body_rows.append(_split_table_row(lines[i]))
                i += 1
            thead = "<thead><tr>" + "".join(f"<th>{render_inline(cell)}</th>" for cell in header) + "</tr></thead>"
            tbody = "<tbody>" + "".join(
                "<tr>" + "".join(f"<td>{render_inline(cell)}</td>" for cell in row) + "</tr>"
                for row in body_rows
            ) + "</tbody>"
            parts.append(f"<table>{thead}{tbody}</table>")
            continue
        if is_ul(line):
            items: list[str] = []
            while i < n and is_ul(lines[i]):
                items.append(re.sub(r"^\s*[-*+]\s+", "", lines[i]))
                i += 1
            parts.append("<ul>" + "".join(f"<li>{render_inline(item)}</li>" for item in items) + "</ul>")
            continue
        if is_ol(line):
            items = []
            while i < n and is_ol(lines[i]):
                items.append(re.sub(r"^\s*\d+[.)]\s+", "", lines[i]))
                i += 1
            parts.append("<ol>" + "".join(f"<li>{render_inline(item)}</li>" for item in items) + "</ol>")
            continue
        if not stripped:
            i += 1
            continue
        para: list[str] = []
        while i < n:
            cur = lines[i]
            if not cur.strip():
                break
            if cur.strip().startswith("```"):
                break
            if re.match(r"^#{1,6}\s+", cur):
                break
            if is_ul(cur) or is_ol(cur) or cur.lstrip().startswith(">"):
                break
            if "|" in cur and i + 1 < n and re.match(r"^\s*\|?\s*:?-{2,}", lines[i + 1]):
                break
            para.append(cur.strip())
            i += 1
        parts.append("<p>" + render_inline(" ".join(para)) + "</p>")
    return "\n".join(parts)


class ListingHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            parts = urllib.parse.urlsplit(self.path)
            if not parts.path.endswith("/"):
                self.send_response(301)
                new_url = urllib.parse.urlunsplit(
                    (parts.scheme, parts.netloc, parts.path + "/", parts.query, parts.fragment)
                )
                self.send_header("Location", new_url)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return None
            return self.list_directory(path)
        parsed = urllib.parse.urlsplit(self.path)
        raw = urllib.parse.parse_qs(parsed.query).get("raw", [""])[0].lower() in {"1", "true", "yes"}
        if Path(path).suffix.lower() in {".md", ".markdown", ".mdown"} and not raw:
            return self.preview_markdown(path)
        return super().send_head()

    def guess_type(self, path):  # type: ignore[override]
        ctype = super().guess_type(path)
        ext = Path(str(path)).suffix.lower()
        if ext in {".md", ".markdown", ".mdown"}:
            ctype = "text/markdown"
        if ctype.startswith("text/") or ctype in {
            "application/json",
            "application/javascript",
            "application/xml",
        }:
            if "charset=" not in ctype.lower():
                ctype += "; charset=utf-8"
        return ctype

    def preview_markdown(self, path: str):
        try:
            data = Path(path).read_bytes()
        except OSError:
            self.send_error(404, "File not found")
            return None

        rendered = md_to_html(decode_text_bytes(data))
        root_name = "内网下载"
        path_only = urllib.parse.urlsplit(self.path).path
        display_path = urllib.parse.unquote(path_only)
        file_name = Path(display_path).name or "Markdown"
        back_href = parent_href(path_only) or "/"
        raw_href = path_only + "?raw=1"

        crumb_html = []
        parts = [p for p in display_path.split("/") if p]
        acc = ""
        crumb_html.append(f'<a class="crumb" href="/">{html.escape(root_name)}</a>')
        for i, part in enumerate(parts):
            crumb_html.append('<span class="sep">/</span>')
            acc += "/" + part
            is_last = i == len(parts) - 1
            href = acc if is_last else acc + "/"
            cls = "crumb current" if is_last else "crumb"
            crumb_html.append(
                f'<a class="{cls}" href="{html.escape(href)}">{html.escape(part)}</a>'
            )

        page = f"""<!DOCTYPE HTML>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(file_name)}</title>
<style>{STYLE}</style>
</head>
<body>
<main class="page">
  <header class="mast">
    <div class="hero">
      <nav class="crumbs">{''.join(crumb_html)}</nav>
      <h1>{html.escape(file_name)}</h1>
    </div>
  </header>
  <div class="md-toolbar">
    <a class="action" href="{html.escape(back_href)}">返回</a>
    <a class="action" href="{html.escape(raw_href)}">下载原文</a>
  </div>
  <section class="md-stage">
    <article class="md-body">
{rendered}
    </article>
  </section>
</main>
</body>
</html>
"""
        encoded = page.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)
        return None

    def list_directory(self, path: str):  # type: ignore[override]
        try:
            entries = list(os.scandir(path))
        except OSError:
            self.send_error(404, "No permission to list directory")
            return None

        entries.sort(key=lambda e: (not e.is_dir(follow_symlinks=False), e.name.lower()))
        root_name = "内网下载"
        display_path = urllib.parse.unquote(self.path)
        current_name = Path(display_path.rstrip("/") or root_name).name or root_name

        rows: list[str] = []
        visible = 0
        up_href = parent_href(self.path)
        if up_href:
            rows.append(
                '<article class="row up">'
                f'<a class="hit" href="{html.escape(up_href)}">'
                f'<span class="icon">{icon_svg("up")}</span>'
                '<span class="copy">'
                '<span class="name">返回上层</span>'
                '<span class="kind">上一级目录</span>'
                "</span>"
                '<span class="size">—</span>'
                '<span class="date">—</span>'
                "</a>"
                f'<a class="action" href="{html.escape(up_href)}">返回</a>'
                "</article>"
            )
        for entry in entries:
            name = entry.name
            if name.startswith("."):
                continue
            if name in {
                "file_server.py",
                "__pycache__",
                "server.sh",
                "server.bat",
                "server.ps1",
                "start.sh",
                "stop.sh",
                "start.bat",
                "stop.bat",
                "start.ps1",
                "stop.ps1",
            }:
                continue

            try:
                stat = entry.stat(follow_symlinks=False)
                mtime_dt = dt.datetime.fromtimestamp(stat.st_mtime)
                mtime = f"{mtime_dt.year}.{mtime_dt.month:02d}.{mtime_dt.day:02d}"
                is_dir = entry.is_dir(follow_symlinks=False)
                size = "—" if is_dir else human_size(stat.st_size)
            except OSError:
                mtime = "—"
                size = "—"
                is_dir = entry.is_dir(follow_symlinks=False)

            kind_label, kind_key = file_kind(name, is_dir)
            display_name = name + ("/" if is_dir else "")
            href = urllib.parse.quote(display_name)
            is_markdown = (not is_dir) and Path(name).suffix.lower() in {".md", ".markdown", ".mdown"}
            action = "打开" if is_dir or is_markdown else "下载"
            visible += 1
            rows.append(
                '<article class="row" data-name="' + html.escape(name.lower()) + '">'
                f'<a class="hit" href="{html.escape(href)}">'
                f'<span class="icon">{icon_svg(kind_key)}</span>'
                '<span class="copy">'
                f'<span class="name">{html.escape(name)}</span>'
                f'<span class="kind">{html.escape(kind_label)}</span>'
                "</span>"
                f'<span class="size">{html.escape(size)}</span>'
                f'<span class="date">{html.escape(mtime)}</span>'
                "</a>"
                f'<a class="action" href="{html.escape(href)}">{action}</a>'
                "</article>"
            )

        crumb_html = []
        crumb_items = breadcrumbs(self.path, root_name)
        for i, (label, href, is_current) in enumerate(crumb_items):
            if i:
                crumb_html.append('<span class="sep">/</span>')
            cls = "crumb current" if is_current else "crumb"
            crumb_html.append(
                f'<a class="{cls}" href="{html.escape(href)}">{html.escape(label)}</a>'
            )

        empty_html = """
<div class="empty" id="empty-folder">
  <h2>没有文件</h2>
  <p>把要分享的内容放到这个文件夹，然后刷新页面。</p>
</div>"""
        search_empty = """
<div class="empty hidden" id="empty-search">
  <h2>未找到结果</h2>
  <p>试试其他关键词，或清空搜索。</p>
</div>"""

        file_rows = [row for row in rows if 'class="row up"' not in row]
        list_inner = "".join(rows) if rows else empty_html
        if up_href and not file_rows:
            list_inner = "".join(rows) + empty_html
        item_label = f"{visible} 个项目" if visible else "0 个项目"
        head = ""
        if rows:
            head = (
                '<div class="head"><span></span><span>名称</span>'
                "<span>大小</span><span>日期</span><span></span></div>"
            )

        body = f"""<!DOCTYPE HTML>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(current_name)}</title>
<style>{STYLE}</style>
</head>
<body>
<main class="page">
  <header class="mast">
    <div class="hero">
      <h1>{html.escape(root_name)}</h1>
    </div>
    <label class="search">
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="11" cy="11" r="6.2" fill="none" stroke="currentColor" stroke-width="1.7"/>
        <path d="M16 16.4 20 20.2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
      </svg>
      <input id="q" type="search" placeholder="搜索文件名称" autocomplete="off" spellcheck="false">
      <kbd class="search-hint">/</kbd>
    </label>
  </header>
  <div class="list-meta">
    <nav class="crumbs" aria-label="路径">{''.join(crumb_html)}</nav>
    <p class="count" id="status">{html.escape(item_label)}</p>
  </div>
  <section class="stage" id="grid" aria-label="文件">
    {head}
    {list_inner}
    {search_empty}
  </section>
  <footer class="site-footer"><span>仅限内网访问</span><span class="credit">© 2026 Vincent.J</span></footer>
</main>
<script>
(() => {{
  const q = document.getElementById("q");
  const tiles = [...document.querySelectorAll(".row[data-name]")];
  const emptySearch = document.getElementById("empty-search");
  const emptyFolder = document.getElementById("empty-folder");
  const status = document.getElementById("status");
  const total = tiles.length;
  const noun = (n) => n + " 个项目";
  const filter = () => {{
    const v = (q.value || "").trim().toLowerCase();
    let n = 0;
    tiles.forEach((t) => {{
      const show = !v || (t.dataset.name || "").includes(v);
      t.classList.toggle("hidden", !show);
      if (show) n += 1;
    }});
    emptySearch.classList.toggle("hidden", !(v && n === 0));
    if (emptyFolder) emptyFolder.classList.toggle("hidden", Boolean(v));
    status.textContent = v ? "找到 " + noun(n) : noun(total);
  }};
  q.addEventListener("input", filter);
  document.addEventListener("keydown", (e) => {{
    if (e.key === "/" && document.activeElement !== q) {{
      e.preventDefault();
      q.focus();
    }}
    if (e.key === "Escape" && document.activeElement === q) {{
      q.value = "";
      filter();
      q.blur();
    }}
  }});
}})();
</script>
</body>
</html>
"""
        encoded = body.encode("utf-8", "surrogateescape")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Intranet file download server")
    parser.add_argument("--bind", default="0.0.0.0", help="Bind address")
    parser.add_argument("--port", type=int, default=8765, help="Listen port")
    parser.add_argument(
        "--directory",
        default=str(Path(__file__).resolve().parent / "down"),
        help="Directory to serve",
    )
    args = parser.parse_args()

    directory_path = Path(args.directory).resolve()
    directory_path.mkdir(parents=True, exist_ok=True)
    directory = str(directory_path)
    os.chdir(directory)

    class ReusableServer(ThreadingHTTPServer):
        allow_reuse_address = True

    with ReusableServer((args.bind, args.port), ListingHandler) as httpd:
        print(f"Serving {directory}")
        print(f"Listening on http://{args.bind}:{args.port}/")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\\nStopped.")


if __name__ == "__main__":
    main()
