import os
import json
import urllib.request

# === 基础配置 / Basic Configuration ===
REPO = "Arlia-Etoile/Diversion-Rule-List"
BASE_URL = "https://r.arlia.cn.mt"
# 按照你要求的顺序排列分支
BRANCHES = ["mrs", "lsr", "yaml"] 
OUTPUT_FILE = "README.md"
# =====================================

def get_files_in_branch(branch):
    """
    通过 GitHub API 递归获取分支下的所有文件路径
    Fetch all file paths in the branch recursively via GitHub API
    """
    url = f"https://api.github.com/repos/{REPO}/git/trees/{branch}?recursive=1"
    req = urllib.request.Request(url)
    
    # 获取 GitHub Actions 自动提供的 Token 以避免 API 速率限制
    token = os.getenv("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            # 过滤出我们需要的文件后缀
            valid_extensions = ('.yaml', '.mrs', '.lsr')
            # 只提取文件（blob 类型）
            return sorted([
                item['path'] for item in data.get('tree', []) 
                if item['type'] == 'blob' and item['path'].lower().endswith(valid_extensions)
            ])
    except Exception as e:
        print(f"⚠️ Error fetching branch {branch}: {e}")
        return []

def main():
    markdown_content = ""

    for branch in BRANCHES:
        files = get_files_in_branch(branch)
        if not files:
            continue
        
        # 为每个分支生成独立的英文表头
        markdown_content += f"### 📁 {branch.upper()} Branch\n\n"
        markdown_content += "| Rule Set | Type | Link |\n"
        markdown_content += "| :--- | :---: | :--- |\n"
        
        for file_path in files:
            # 提取文件名（不含路径）
            file_name_full = file_path.split('/')[-1]
            # 提取规则集名称（不含后缀）
            rule_set_name = os.path.splitext(file_name_full)[0]
            # 提取文件后缀作为类型并大写
            file_type = os.path.splitext(file_name_full)[1][1:].upper()
            
            # 拼接 Cloudflare Worker 代理的短链
            short_link = f"{BASE_URL}/{branch}/{file_path}"
            
            # 生成表格行
            markdown_content += f"| `{rule_set_name}` | `{file_type}` | {short_link} |\n"
            
        markdown_content += "\n"

    # 定位 README.md 中的注入点
    marker_start = ""
    marker_end = ""
    
    # 构造要插入的完整文本块
    replacement_text = f"{marker_start}\n{markdown_content}{marker_end}"

    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            content = f.read()
        
        # 检查标记是否存在，如果存在则替换，不存在则追加
        if marker_start in content and marker_end in content:
            parts = content.split(marker_start)
            before = parts[0]
            after = parts[1].split(marker_end)[1]
            new_content = before + replacement_text + after
        else:
            # 如果没找到标记，则在文件末尾追加（建议预先在 README 中放好标记）
            new_content = content + "\n\n" + replacement_text
            
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            f.write(new_content)
        
        print(f"✅ Successfully updated {OUTPUT_FILE} with categorized tables.")
    else:
        print(f"❌ Error: {OUTPUT_FILE} not found!")

if __name__ == "__main__":
    main()
