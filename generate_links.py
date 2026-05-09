import os
import json
import urllib.request
import re

# ================= 配置信息 / Configuration =================
REPO = "Arlia-Etoile/Diversion-Rule-List"
BASE_URL = "https://r.arlia.cn.mt"
# 分支处理顺序
BRANCHES = ["mrs", "lsr", "yaml"] 
OUTPUT_FILE = "README.md"

# 占位符（必须与 README.md 中的内容完全一致）
START_SIGN = ""
END_SIGN = ""
# ============================================================

def get_files_in_branch(branch):
    """从 GitHub API 获取文件列表"""
    url = f"https://api.github.com/repos/{REPO}/git/trees/{branch}?recursive=1"
    req = urllib.request.Request(url)
    
    # 尝试获取 GitHub Token 以防止触发速率限制
    token = os.getenv("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            valid_exts = ('.yaml', '.mrs', '.lsr')
            # 过滤并排序
            files = [
                item['path'] for item in data.get('tree', []) 
                if item['type'] == 'blob' and item['path'].lower().endswith(valid_exts)
            ]
            return sorted(files)
    except Exception as e:
        print(f"⚠️ Branch {branch} skip: {e}")
        return []

def main():
    print(f"🔍 Target REPO: {REPO}")
    print(f"🔍 Using Markers: {START_SIGN} to {END_SIGN}")

    all_tables_md = ""

    # 1. 遍历每个分支生成表格内容
    for branch in BRANCHES:
        files = get_files_in_branch(branch)
        if not files:
            continue
        
        print(f"📦 Processing {len(files)} files in branch: {branch}")
        
        branch_md = f"### 📁 {branch.upper()} Branch\n\n"
        branch_md += "| Rule Set | Type | Link |\n"
        branch_md += "| :--- | :---: | :--- |\n"
        
        for file_path in files:
            file_name = file_path.split('/')[-1]
            rule_set = os.path.splitext(file_name)[0]
            ext = os.path.splitext(file_name)[1][1:].upper()
            # 构造短链
            link = f"{BASE_URL}/{branch}/{file_path}"
            branch_md += f"| `{rule_set}` | `{ext}` | {link} |\n"
        
        all_tables_md += branch_md + "\n"

    # 2. 检查 README 文件是否存在
    if not os.path.exists(OUTPUT_FILE):
        print(f"❌ Error: {OUTPUT_FILE} not found in root directory!")
        return

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        readme_content = f.read()

    # 3. 检查标记是否存在于内容中
    if START_SIGN not in readme_content or END_SIGN not in readme_content:
        print(f"❌ Error: Markers not found in {OUTPUT_FILE}!")
        print(f"Please make sure your README.md contains: {START_SIGN} and {END_SIGN}")
        return

    # 4. 正则替换占位符中间的内容
    # re.DOTALL 允许点号匹配换行符
    pattern = re.escape(START_SIGN) + r".*?" + re.escape(END_SIGN)
    new_block = f"{START_SIGN}\n\n{all_tables_md}{END_SIGN}"
    
    updated_content = re.sub(pattern, new_block, readme_content, flags=re.DOTALL)

    # 5. 写回文件
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(updated_content)
    
    print(f"🚀 Success! {OUTPUT_FILE} has been updated.")

if __name__ == "__main__":
    main()
