# /// script
# requires-python = ">=3.13"
# ///
"""Build the public GitHub Pages copies of the pages in site/ into docs/.

The pages in site/ are written for Claude artifacts, which wrap them in a document skeleton at
publish time; a plain web host needs that skeleton in the file. index.html is the mission board.
Run from anywhere: uv run site/build_pages.py
"""

from pathlib import Path

SITE = Path(__file__).resolve().parent
DOCS = SITE.parent / "docs"
PAGES = {"legion-board.html": "index.html", "gem-setting-3d.html": "gem-setting-3d.html"}

HEAD = (
    '<!doctype html><html lang="ko"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
    "<style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);"
    "padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px/1.5 system-ui,sans-serif}"
    "img{max-width:100%}[hidden]{display:none!important}</style></head><body>\n"
)


def main() -> None:
    DOCS.mkdir(exist_ok=True)
    (DOCS / ".nojekyll").write_text("", encoding="utf-8")
    for source, target in PAGES.items():
        body = (SITE / source).read_text(encoding="utf-8")
        (DOCS / target).write_text(HEAD + body.rstrip() + "\n</body></html>\n", encoding="utf-8")
        print(f"docs/{target} <- site/{source}")


if __name__ == "__main__":
    main()
