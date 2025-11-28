#!/bin/bash
# 手動安裝 Ansible Collections 腳本
# 用於解決 SSL 證書問題時的手動安裝方式

set -e

echo "正在手動安裝 Ansible Collections..."
echo ""

# 逐一安裝 collections（如果某個失敗，會繼續安裝其他的）
install_collection() {
    local collection=$1
    echo "安裝 $collection..."
    ansible-galaxy collection install "$collection" --force || {
        echo "警告: $collection 安裝失敗，但會繼續安裝其他 collections"
        return 1
    }
}

# 安裝所有必要的 collections
install_collection "freeipa.ansible_freeipa"
install_collection "community.crypto"
install_collection "community.general"
install_collection "community.postgresql"
install_collection "ansible.posix"

echo ""
echo "Collections 安裝完成！"
echo ""
echo "已安裝的 collections:"
ansible-galaxy collection list | grep -E "(freeipa|community|ansible.posix)" || echo "未找到相關 collections"

