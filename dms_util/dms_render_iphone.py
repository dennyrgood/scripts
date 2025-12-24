#!/usr/bin/env python3
"""
dms_render_iphone.py - Regenerate a mobile-friendly index.html from .dms_state.json

This script is a variant of dms_render.py, specifically designed to produce
an HTML file that is responsive and usable on mobile devices like the iPhone.

Usage:
  python3 dms_render_iphone.py --doc Doc --index Doc/index_iphone.html
"""
import argparse
import json
import html as html_module
from pathlib import Path
from datetime import datetime

def format_file_mtime(mtime_iso: str) -> str:
    """Format ISO 8601 timestamp for display"""
    if not mtime_iso:
        return ""
    try:
        dt = datetime.fromisoformat(mtime_iso)
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except:
        return ""

def render_index_html(state_path: Path, index_path: Path):
    """Generate index.html from .dms_state.json"""
    
    # Read state
    if not state_path.exists():
        print(f"ERROR: {state_path} not found")
        return 1
    
    state = json.loads(state_path.read_text(encoding='utf-8'))
    
    # Group documents by category
    docs_by_category = {}
    for category in state.get("categories", []):
        docs_by_category[category] = []
    
    for file_path, doc_data in state.get("documents", {}).items():
        category = doc_data.get("category", "Junk")
        if category not in docs_by_category:
            docs_by_category[category] = []
        docs_by_category[category].append((file_path, doc_data))
    
    # Sort documents within each category
    for category in docs_by_category:
        docs_by_category[category].sort(key=lambda x: x[1].get("title", x[0]))
    
    # Generate HTML
    html_content = _generate_html(docs_by_category, state)
    
    # Write index.html
    index_path.write_text(html_content, encoding='utf-8')
    
    print(f"✓ Generated {index_path}")
    print(f"  Categories: {len(docs_by_category)}")
    total_docs = sum(len(docs) for docs in docs_by_category.values())
    print(f"  Documents: {total_docs}")
    
    return 0

def _generate_html(docs_by_category, state):
    """Generate the complete HTML from state"""
    
    # Embed state in HTML for reference (read-only, for debugging)
    state_json = json.dumps(state, indent=2)
    
    categories_html = []
    for category in state.get("categories", []):
        docs = docs_by_category.get(category, [])
        cat_html = _generate_category_section(category, docs)
        categories_html.append(cat_html)
    
    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Project Docs Index - Mobile</title>
  <style>
    :root {{
      --bg: #0f1720;
      --panel: #0b1220;
      --muted: #9aa4b2;
      --accent: #79c0ff;
      --card: #0f1726;
    }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      margin: 0;
      background-color: var(--bg);
      color: #e6eef6;
    }}
    #app {{
      display: flex;
      flex-direction: column;
      height: 100vh;
    }}
    #main-content {{
      display: flex;
      flex: 1;
      overflow: hidden;
    }}
    #sidebar {{
      width: 100%;
      border-right: 1px solid rgba(255,255,255,0.03);
      overflow-y: auto;
      padding: 1rem;
      background: linear-gradient(180deg, rgba(255,255,255,0.012), rgba(255,255,255,0.008));
    }}
    #viewer {{
      display: none;
      flex: 1;
      flex-direction: column;
      padding: 1rem;
    }}
    header {{
      padding: 1rem;
      border-bottom: 1px solid rgba(255,255,255,0.03);
    }}
    header h1 {{
      font-size: 1.25rem;
      margin: 0;
    }}
    .category h2 {{
      font-size: 1rem;
      color: var(--accent);
      margin-top: 1.5rem;
    }}
    ul.files {{
      list-style: none;
      padding: 0;
    }}
    li.file {{
      padding: 0.75rem;
      border-radius: 8px;
      margin: 0.5rem 0;
      background: linear-gradient(180deg, rgba(255,255,255,0.008), rgba(255,255,255,0.006));
      cursor: pointer;
    }}
    .file .title {{
      color: #dff3ff;
      font-weight: 600;
      font-size: 1rem;
    }}
    .file .desc {{
      font-size: 0.875rem;
      color: var(--muted);
      line-height: 1.4;
    }}
    #back-button {{
        display: none;
        padding: 0.5rem 1rem;
        background-color: var(--accent);
        color: #000;
        border: none;
        border-radius: 5px;
        cursor: pointer;
        margin-bottom: 1rem;
    }}
    @media (min-width: 768px) {{
      #main-content {{
        flex-direction: row;
      }}
      #sidebar {{
        width: 350px;
      }}
      #viewer {{
        display: flex;
      }}
    }}
  </style>
  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
</head>
<body>
  <div id="app">
    <header>
      <h1>📚 Project Docs</h1>
    </header>
    <div id="main-content">
      <section id="sidebar">
        {"".join(categories_html)}
      </section>
      <section id="viewer">
        <button id="back-button">Back to list</button>
        <h3 id="viewerTitle"></h3>
        <div id="content" style="overflow-y: auto; height: 100%;">
          <div id="mdViewer"></div>
          <iframe id="pdfViewer" style="width:100%;height:100%;border:none;display:none;"></iframe>
        </div>
      </section>
    </div>
  </div>

  <script>
    const sidebar = document.getElementById('sidebar');
    const viewer = document.getElementById('viewer');
    const viewerTitle = document.getElementById('viewerTitle');
    const mdViewer = document.getElementById('mdViewer');
    const pdfViewer = document.getElementById('pdfViewer');
    const backButton = document.getElementById('back-button');

    function openFilePreview(liElement) {{
        const path = liElement.dataset.path;
        const title = liElement.querySelector('.title').innerText;
        const readableVersion = liElement.dataset.readableVersion;

        viewerTitle.innerText = title;
        mdViewer.style.display = 'none';
        pdfViewer.style.display = 'none';
        
        if (window.innerWidth < 768) {{
            sidebar.style.display = 'none';
            viewer.style.display = 'flex';
            backButton.style.display = 'block';
        }}

        if (readableVersion && readableVersion !== "None") {{ // Check for "None" string too
            fetch(readableVersion)
                .then(response => response.text())
                .then(text => {{
                    mdViewer.innerHTML = marked.parse(text);
                    mdViewer.style.display = 'block';
                }})
                .catch(err => {{
                    console.error("Error fetching readable version:", err);
                    mdViewer.innerHTML = `<p>Error loading content for ${{title}}.</p>`;
                    mdViewer.style.display = 'block';
                }});
        }} else if (path.endsWith('.pdf')) {{
            pdfViewer.src = path;
            pdfViewer.style.display = 'block';
        }} else {{
            fetch(path)
                .then(response => response.text())
                .then(text => {{
                    mdViewer.innerHTML = `<pre>${{text}}</pre>`;
                    mdViewer.style.display = 'block';
                }})
                .catch(err => {{
                    console.error("Error fetching raw file:", err);
                    mdViewer.innerHTML = `<p>Error loading content for ${{title}}.</p>`;
                    mdViewer.style.display = 'block';
                }});
        }}
    }}

    function goBack() {{
        sidebar.style.display = 'block';
        viewer.style.display = 'none';
        backButton.style.display = 'none';
    }}

    document.querySelectorAll('.file').forEach(item => {{
      item.addEventListener('click', event => {{
        openFilePreview(item);
      }});
    }});

    backButton.addEventListener('click', goBack);
  </script>
</body>
</html>"""
    return html

def _generate_category_section(category, docs):
    """Generate a category section with document list"""
    
    if not docs:
        return ""
    
    li_items = []
    for file_path, doc_data in docs:
        title = html_module.escape(doc_data.get("title", Path(file_path).stem))
        summary = html_module.escape(doc_data.get("summary", ""))
        path_escaped = html_module.escape(file_path)
        readable_version = doc_data.get("readable_version", "")
        
        # Conditionally include and escape readable_version
        readable_version_attr = ""
        if readable_version:
            readable_version_attr = f'data-readable-version="{html_module.escape(readable_version)}"'
        
        li = f"""<li class="file" data-path="{path_escaped}" {readable_version_attr}>
          <div class="title">{title}</div>
          <div class="desc">{summary}</div>
        </li>"""
        li_items.append(li)
    
    category_escaped = html_module.escape(category)
    return f"""<section class="category" data-category="{category_escaped}">
        <h2>{category_escaped}</h2>
        <ul class="files">
{"".join(li_items)}
        </ul>
      </section>"""

def main():
    parser = argparse.ArgumentParser(description="Render a mobile-friendly index.html from .dms_state.json")
    parser.add_argument("--doc", default="Doc", help="Doc directory")
    parser.add_argument("--index", default="Doc/index_iphone.html", help="Path to output index.html")
    args = parser.parse_args()
    
    doc_dir = Path(args.doc)
    index_path = Path(args.index)
    state_path = doc_dir / ".dms_state.json"
    
    if not doc_dir.exists():
        print(f"ERROR: {doc_dir} not found")
        return 1
    
    return render_index_html(state_path, index_path)

if __name__ == "__main__":
    exit(main())
