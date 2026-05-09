#!/bin/bash
set -e 
WGET_UA="clash.meta"

config_file="config.yaml"
if [ ! -f "$config_file" ]; then
    echo "错误: 找不到配置文件 $config_file"
    exit 1
fi

# 检查必要命令是否存在
for cmd in yq jq curl wget gunzip sha256sum; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误: 系统未安装 $cmd，请先安装。"
        exit 1
    fi
done

work_dir=$(yq -r '.work_dir' "$config_file")
rm -rf "$work_dir" || true
mkdir -p "$work_dir"

api_url=$(yq -r '.mihomo.api_url' "$config_file")
start_with=$(yq -r '.mihomo.start_with' "$config_file")
end_with=$(yq -r '.mihomo.end_with' "$config_file")

if [ -z "$api_url" ] || [ "$api_url" == "null" ]; then
    echo "错误: 无法从 YAML 中解析配置，请检查配置文件格式。"
    exit 1
fi

echo "正在获取 API 信息..."
if [ -n "$GITHUB_TOKEN" ]; then
  AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
else
  AUTH_HEADER="User-Agent: curl"
fi
api_response=$(curl -sL -f -H "$AUTH_HEADER" "$api_url")
if [ $? -ne 0 ]; then
    echo "错误: 无法连接到 API 地址 (可能是速率限制或网络问题)。"
    exit 1
fi

asset_info=$(echo "$api_response" | jq -c ".[] | .assets[] | select(.name | startswith(\"$start_with\") and endswith(\"$end_with\"))" | head -n 1)
if [ -z "$asset_info" ] || [ "$asset_info" == "null" ]; then
    echo "错误: 未找到符合条件的资源。"
    exit 1
fi

download_url=$(echo "$asset_info" | jq -r '.browser_download_url')
expected_digest=$(echo "$asset_info" | jq -r '.digest' | cut -d ':' -f 2)

if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
    echo "错误: JSON 中未找到下载链接。"
    exit 1
fi

echo "开始下载 Mihomo..."
wget -q -O "$work_dir/mihomo.gz" "$download_url"

actual_digest=$(sha256sum "$work_dir/mihomo.gz" | awk '{print $1}')
if [ "$actual_digest" != "$expected_digest" ]; then
    echo "错误: 文件校验失败！"
    exit 1
fi

echo "正在解压..."
gunzip -f "$work_dir/mihomo.gz"
chmod +x "$work_dir/mihomo"

# ========== 重点修改区：建立三个独立的输出目录 ==========
out_mrs="./out_mrs"
out_yaml="./out_yaml"
out_lsr="./out_lsr"
rm -rf "$out_mrs" "$out_yaml" "$out_lsr" || true
mkdir -p "$out_mrs" "$out_yaml" "$out_lsr"


echo "开始处理任务..."
task_names=$(yq -r '.tasks | keys | .[]' "$config_file")

for task in $task_names; do
    echo "---------------------------------------"
    echo "正在处理任务: $task"

    urls=$(yq -r ".tasks.$task.src[]" "$config_file")
    custom_script_content=$(yq -r ".tasks.$task.custom_script" "$config_file")
    
    if [ "$custom_script_content" == "null" ]; then
        custom_script_content=""
    fi
    export CUSTOM_SCRIPT="$custom_script_content"

    for url in $urls; do
        echo "正在下载: $url"
        filename=$(basename "$url")
        download_path="$work_dir/$filename"
        
        if ! wget --user-agent="$WGET_UA" -q -O "$download_path" "$url"; then
            echo "错误: 下载失败 $url，退出..."
            exit 1
        fi

        sed -i -e '$a\' "$download_path"

        if [[ "$filename" == "pihole.txt" ]]; then
            sed -i '/^[a-zA-Z0-9]/ s/^/+./' "$download_path"
        fi

        if [[ "$filename" == *.yaml ]]; then
            sed -n '/^payload:/,$ { /^[[:space:]]*-[[:space:]]*/ { s/^[[:space:]]*-[[:space:]]*//; s/['\'']//g; p } }' "$download_path" >> "$work_dir/tmp.txt"
        else
            cat "$download_path" >> "$work_dir/tmp.txt"
        fi
    done

# === 整合与合并逻辑 ===
    # 提取基础任务名，如果以 -IP 结尾则去掉 -IP (例如 AdBlock-IP 变成 AdBlock)
    base_task="${task%-IP}"

    # 为三种格式分别创建包含基础名字的子文件夹 (从而共用同一个文件夹)
    dir_mrs="$out_mrs/$base_task"
    dir_yaml="$out_yaml/$base_task"
    dir_lsr="$out_lsr/$base_task"
    mkdir -p "$dir_mrs" "$dir_yaml" "$dir_lsr"

    echo "字典序排序、去重 (基础清理)"
    sed -i -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' -e 's/^[[:space:]]*//;s/[[:space:]]*$//' "$work_dir/tmp.txt"
    sort -u "$work_dir/tmp.txt" -o "$work_dir/tmp.txt"

    echo "-> 执行纯整合：合并到 ${base_task} 的 .yaml 和 .lsr 中"
    
    # 1. 生成或追加 yaml
    file_yaml="$dir_yaml/${base_task}.yaml"
    # 如果文件不存在，说明是第一次写入，先加上表头
    if [ ! -f "$file_yaml" ]; then
        echo "payload:" > "$file_yaml"
    fi
    # 使用追加 (>>) 而不是覆盖 (>)，把规则接在后面
    sed "s/^/  - '/; s/$/'/" "$work_dir/tmp.txt" >> "$file_yaml"
    
    # 2. 生成或追加 lsr
    file_lsr="$dir_lsr/${base_task}.lsr"
    # 同样使用追加
    cat "$work_dir/tmp.txt" >> "$file_lsr"

    # 3. 将后续 MRS 流程的输出路径指向共享的 mrs 专属文件夹
    # MRS 因为要区分编译类型，文件名依旧保留 $task (如 AdBlock.mrs 和 AdBlock-IP.mrs 不会覆盖)
    output_file="$dir_mrs/${task}.txt"
    classical_file="$dir_mrs/${task}_Classical.yaml"

    echo "分离非 Domain/IP 的其他规则 (为 MRS 流程准备)..."
    rm -f "$work_dir/other_rules.tmp" "$work_dir/clean_tmp.txt"
    
    awk '
    /^[A-Z0-9-]+,/ && !/^(DOMAIN,|DOMAIN-SUFFIX,|IP-CIDR,|IP-CIDR6,)/ {
        print "  - " $0 >> "'"$work_dir/other_rules.tmp"'"
        next
    }
    { print $0 >> "'"$work_dir/clean_tmp.txt"'" }
    ' "$work_dir/tmp.txt"

    if [ -f "$work_dir/clean_tmp.txt" ]; then
        mv "$work_dir/clean_tmp.txt" "$work_dir/tmp.txt"
    else
        > "$work_dir/tmp.txt"
    fi

    if [ -s "$work_dir/other_rules.tmp" ]; then
        echo "  -> 发现非标准规则，整合生成: ${task}_Classical.yaml"
        echo "payload:" > "$classical_file"
        sort -u "$work_dir/other_rules.tmp" >> "$classical_file"
    fi

    task_type=$(yq -r ".tasks.$task.type" "$config_file")

    if [ "$task_type" == "ipcidr" ]; then
        behavior="ipcidr"
        echo "类型：IP/CIDR"
    elif [ "$task_type" == "domain" ]; then
        behavior="domain"
        echo "类型：域名列表"
    else
        first_line=$(head -n 1 "$work_dir/tmp.txt")
        if [[ "$first_line" =~ [:/] ]]; then
            behavior="ipcidr"
        else
            behavior="domain"
        fi
    fi

    if [ "$behavior" == "ipcidr" ]; then
        python3 - "$work_dir/tmp.txt" "$output_file" <<-'EOF'
import sys
import ipaddress

input_path = sys.argv[1]
output_path = sys.argv[2]
ipv4_nets = []
ipv6_nets = []

try:
    with open(input_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                if "IP-CIDR" in line.upper():
                    parts = line.split(',')
                    if len(parts) >= 2:
                        line = parts[1].strip()
                net = ipaddress.ip_network(line, strict=False)
                if net.version == 4:
                    ipv4_nets.append(net)
                else:
                    ipv6_nets.append(net)
            except ValueError:
                pass

    merged_v4 = list(ipaddress.collapse_addresses(ipv4_nets))
    merged_v6 = list(ipaddress.collapse_addresses(ipv6_nets))
    merged_v4.sort()
    merged_v6.sort()

    with open(output_path, 'w', encoding='utf-8', newline='\n') as f:
        for net in merged_v4:
            f.write(str(net) + '\n')
        for net in merged_v6:
            f.write(str(net) + '\n')

except Exception as e:
    print(f"发生错误: {e}")
    sys.exit(1)
EOF
    else
        python3 - "$work_dir/tmp.txt" "$output_file" <<-'EOF'
import sys
import re
import os

input_path = sys.argv[1]
output_path = sys.argv[2]

def get_clean_domain(domain_str):
    return re.sub(r'^[\+\*\.]+', '', domain_str)

try:
    raw_lines = []
    with open(input_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                raw_lines.append(line)
    
    raw_lines.sort()
    raw_lines.sort(key=lambda x: len(get_clean_domain(x)))

    roots = set()
    domains = []
    
    for line in raw_lines:
        clean_domain = get_clean_domain(line)
        parts = clean_domain.split('.')
        is_redundant = False
        
        if clean_domain in roots:
            is_redundant = True
        else:
            for i in range(1, len(parts)):
                parent = ".".join(parts[i:])
                if parent in roots:
                    is_redundant = True
                    break
        
        if not is_redundant:
            domains.append(line)
            roots.add(clean_domain)

    custom_code = os.environ.get('CUSTOM_SCRIPT', '')
    if custom_code and custom_code.strip() != "":
        try:
            exec_globals = {}
            exec_locals = {'domains': domains, 're': re, 'ipaddress': __import__('ipaddress')}
            exec(custom_code, exec_globals, exec_locals)
            domains = exec_locals['domains']
        except Exception as e:
            pass

    with open(output_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write("\n".join(domains))
        f.write("\n")

except Exception as e:
    print(f"发生错误: {e}")
    sys.exit(1)
EOF
    fi

    need_mrs=$(yq -r ".tasks.$task.format" "$config_file" | grep -q "mrs" && echo "true" || echo "false")
    if [ "$need_mrs" == "true" ]; then
        if [ ! -s "$output_file" ]; then
            echo "  -> [跳过] 提取到的规则数量为 0，放弃生成 ${task}.mrs"
            rm -f "$output_file"
        else
            echo "转换为 mrs 格式"
            # 路径已修复为 $dir_mrs
            $work_dir/mihomo convert-ruleset $behavior text "$output_file" "$dir_mrs/${task}.mrs"
        fi
    fi
    rm -f "$work_dir/tmp.txt"
done

echo "---------------------------------------"
echo "所有任务处理完成，准备部署！"
echo "---------------------------------------"

max_history=$(yq -r '.git.max_history' "$config_file")

if [ -n "$GITHUB_TOKEN" ]; then
    git config --global user.name "$(yq -r '.git.user_name' "$config_file")"
    git config --global user.email "$(yq -r '.git.user_email' "$config_file")"
fi

remote_url=$(git config --get remote.origin.url)

# 通用部署函数
deploy_to_branch() {
    local source_folder="$1"
    local target_branch="$2"
    
    echo "======================================="
    echo "开始部署到分支: $target_branch"
    
    local temp_repo="$work_dir/temp_repo_$target_branch"
    rm -rf "$temp_repo" || true
    
    echo "正在拉取分支..."
    if git clone -q --filter=blob:none --branch "$target_branch" "$remote_url" "$temp_repo" 2>/dev/null; then
        echo "成功拉取远程分支 $target_branch"
    else
        echo "远程分支不存在，初始化新仓库"
        mkdir -p "$temp_repo"
        cd "$temp_repo"
        git init
        git checkout -b "$target_branch"
        git remote add origin "$remote_url"
        cd - > /dev/null
    fi
    
    find "$temp_repo" -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +
    cp -r "$source_folder"/* "$temp_repo/"
    
    cd "$temp_repo"
    git add .
    if git diff --staged --quiet; then
        echo "分支 $target_branch 无变化，跳过。"
        cd - > /dev/null
        return 0
    fi
    
    git commit -m "Auto Update: $(date '+%Y-%m-%d %H:%M:%S')"
    
    local commit_count=$(git rev-list --count HEAD)
    local push_args=""
    if [ "$commit_count" -gt "$max_history" ]; then
        echo "触发历史清理机制..."
        git checkout --orphan temp_reset_branch
        git add .
        git commit -m "Reset History: $(date '+%Y-%m-%d')"
        git branch -D "$target_branch"
        git branch -m "$target_branch"
        push_args="--force"
    fi
    
    if [ -n "$GITHUB_TOKEN" ]; then
        local clean_url=$(echo "$remote_url" | sed -E 's/https:\/\/[^@]+@/https:\/\//')
        local auth_url=$(echo "$clean_url" | sed "s/https:\/\//https:\/\/x-access-token:$GITHUB_TOKEN@/")
        git remote set-url origin "$auth_url"
    fi
    
    echo "推送到 GitHub ($target_branch)..."
    git push $push_args origin "$target_branch"
    cd - > /dev/null
}

# 调用部署函数
deploy_to_branch "$out_mrs" "mrs"
deploy_to_branch "$out_yaml" "yaml"
deploy_to_branch "$out_lsr" "lsr"

echo "部署完毕！"
