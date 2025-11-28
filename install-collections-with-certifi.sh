#!/bin/bash
# 使用 certifi 證書安裝 Ansible Collections 腳本

set -e

echo "正在使用 certifi 證書安裝 Ansible Collections..."
echo ""

# 取得 certifi 證書路徑
CERTIFI_PATH=$(python3 -c "import certifi; print(certifi.where())" 2>/dev/null)

if [ -z "$CERTIFI_PATH" ] || [ ! -f "$CERTIFI_PATH" ]; then
    echo "錯誤: 無法找到 certifi 證書文件"
    echo "請先執行: pip3 install --upgrade certifi"
    exit 1
fi

echo "使用證書路徑: $CERTIFI_PATH"
echo ""

# 設定環境變數使用 certifi 證書
export SSL_CERT_FILE="$CERTIFI_PATH"
export REQUESTS_CA_BUNDLE="$CERTIFI_PATH"
export CURL_CA_BUNDLE="$CERTIFI_PATH"

# 嘗試安裝 collections
echo "嘗試安裝 collections..."
ansible-galaxy collection install -r collections.yml

echo ""
echo "Collections 安裝完成！"
echo ""
echo "已安裝的 collections:"
ansible-galaxy collection list | grep -E "(freeipa|community|ansible.posix)" || echo "未找到相關 collections"

