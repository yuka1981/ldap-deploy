#!/bin/bash
# 安裝 Ansible Collections 腳本
# 用於安裝 playbook 所需的所有 collections

set -e

echo "正在安裝 Ansible Collections..."
echo ""

# 嘗試使用 certifi 證書（推薦方法）
CERTIFI_PATH=$(python3 -c "import certifi; print(certifi.where())" 2>/dev/null)

if [ -n "$CERTIFI_PATH" ] && [ -f "$CERTIFI_PATH" ]; then
    echo "使用 certifi 證書: $CERTIFI_PATH"
    export SSL_CERT_FILE="$CERTIFI_PATH"
    export REQUESTS_CA_BUNDLE="$CERTIFI_PATH"
    export CURL_CA_BUNDLE="$CERTIFI_PATH"
fi

# 安裝 collections
SSL_ERROR=0
ansible-galaxy collection install -r collections.yml 2>&1 | tee /tmp/galaxy_install.log || SSL_ERROR=$?

if [ $SSL_ERROR -ne 0 ] && grep -q "CERTIFICATE_VERIFY_FAILED\|certificate verify failed" /tmp/galaxy_install.log; then
    echo ""
    echo "偵測到 SSL 證書驗證失敗問題。"
    echo "嘗試使用替代方法安裝 collections..."
    echo ""
    
    # 方法 1: 確保 certifi 已安裝
    if command -v pip3 &> /dev/null; then
        echo "更新 certifi..."
        pip3 install --upgrade certifi urllib3 || true
        
        # 重新取得 certifi 路徑
        CERTIFI_PATH=$(python3 -c "import certifi; print(certifi.where())" 2>/dev/null)
        if [ -n "$CERTIFI_PATH" ] && [ -f "$CERTIFI_PATH" ]; then
            export SSL_CERT_FILE="$CERTIFI_PATH"
            export REQUESTS_CA_BUNDLE="$CERTIFI_PATH"
            export CURL_CA_BUNDLE="$CERTIFI_PATH"
            echo "重新嘗試安裝..."
            ansible-galaxy collection install -r collections.yml && SSL_ERROR=0
        fi
    fi
    
    # 如果仍然失敗，提供其他解決方案
    if [ $SSL_ERROR -ne 0 ]; then
        echo ""
        echo "如果上述方法仍然失敗，請參考 INSTALL_COLLECTIONS.md 文件"
        echo "或使用手動安裝腳本: ./install-collections-manual.sh"
        echo ""
        exit 1
    fi
fi

echo ""
echo "Collections 安裝完成！"
echo ""
echo "已安裝的 collections:"
ansible-galaxy collection list | grep -E "(freeipa|community|ansible.posix)" || echo "未找到相關 collections"

