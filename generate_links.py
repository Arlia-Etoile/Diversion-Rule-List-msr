import os
import json
import urllib.request
import re

# === Configuration ===
REPO = "Arlia-Etoile/Diversion-Rule-List"
BASE_URL = "https://r.arlia.cn.mt"
BRANCHES = ["mrs", "lsr", "yaml"] 
OUTPUT_FILE = "README.md"

# 占位符标记 - 务必确保这里不是空字符串
MARKER_START = ""
MARKER_END = ""
# =====================

def get_files_in_branch(branch):
    """Fetch file paths via GitHub API"""
    url = f"https://api.github.com/repos/{REPO}/git/trees/{branch}?recursive=1"
    req = urllib.request.Request(url)
    
    token = os.getenv("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            valid_exts = ('.yaml', '.mrs', '.lsr')
            return sorted([
                item['path'] for item in data.get('tree', []) 
                if item['type'] == 'blob' and item['path'].lower().endswith(valid_exts)
            ])
    except Exception as e:
        print(f"⚠️ Warning: Could not fetch branch {branch}: {e}")
        return []

def main():
    # 1. 校验标记是否有效
    if not MARKER_START or not MARKER_END:
        raise ValueError("Configuration Error: MARKER_START or MARKER_END is empty.")

    markdown_tables = ""

    # 2. 遍历分支生成表格
    for branch in BRANCHES:
        files = get_files_in_branch(branch)
        if not files:
            continue
        
        markdown_tables += f"### 📁 {branch.upper()} Branch\n\n"
        markdown_tables += "| Rule Set | Type | Link |\n"
        markdown_tables += "| :--- | :---: | :--- |\n"
        
        for file_path in files:
            file_name = file_path.split('/')[-1]
            rule_set = os.path.splitext(file_name)[0]
            ext = os.path.splitext(file_name)[1][1:].upper()
            link = f"{BASE_URL}/{branch}/{file_path}"
            
            markdown_tables += f"| `{rule_set}` | `{ext}` | {link} |\n"
        markdown_tables += "\n"

    # 3. 读取并写入文件
    if not os.path.exists(OUTPUT_FILE):
        print(f"❌ Error: {OUTPUT_FILE} not found.")
        return

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    # 检查标记是否存在
    if MARKER_START not in content or MARKER_END not in content:
        print(f"❌ Error: Markers not found in {OUTPUT_FILE}!")
        print(f"Please ensure {MARKER_START} and {MARKER_END} exist.")
        return

    # 使用正则表达式精准替换两个标记之间的内容
    # re.DOTALL 确保 . 可以匹配换行符
    pattern = re.escape(MARKER_START) + r".*?" + re.escape(MARKER_END)
    replacement = f"{MARKER_START}\n{markdown_tables}{MARKER_END}"
    
    new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(new_content)
    
    print(f"✅ Successfully updated {OUTPUT_FILE} with categorized tables.")

if __name__ == "__main__":
    main()
