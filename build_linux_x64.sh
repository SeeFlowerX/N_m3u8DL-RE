#!/bin/bash

# N_m3u8DL-RE Linux-x64 构建脚本
# 基于 .github/workflows/build_latest.yml 的构建流程

set -e  # 遇到错误时立即退出

echo "======================================"
echo "N_m3u8DL-RE Linux-x64 构建脚本"
echo "======================================"

# 获取当前日期
BUILD_DATE=$(date -u +'%Y%m%d')
echo "构建日期: $BUILD_DATE"

# 设置构建标签
BUILD_TAG="local-build-$(date +%s)"
echo "构建标签: $BUILD_TAG"

# 检查是否在项目根目录
if [ ! -f "src/N_m3u8DL-RE/N_m3u8DL-RE.csproj" ]; then
    echo "错误: 请在项目根目录运行此脚本!"
    echo "当前目录: $(pwd)"
    echo "期望找到: src/N_m3u8DL-RE/N_m3u8DL-RE.csproj"
    exit 1
fi

echo "======================================"
echo "检查系统要求"
echo "======================================"

# 检查系统架构
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "警告: 当前系统架构是 $ARCH，但脚本针对 x86_64 优化"
    echo "继续构建可能会遇到问题..."
fi

echo "系统信息:"
echo "  操作系统: $(uname -s)"
echo "  架构: $ARCH"
echo "  内核版本: $(uname -r)"

# 检查必要的依赖
echo "======================================"
echo "检查构建依赖"
echo "======================================"

# 检查curl
if ! command -v curl &> /dev/null; then
    echo "错误: curl 未安装"
    echo "Ubuntu/Debian: sudo apt-get install curl"
    echo "CentOS/RHEL: sudo yum install curl"
    exit 1
fi

# 检查wget
if ! command -v wget &> /dev/null; then
    echo "错误: wget 未安装"
    echo "Ubuntu/Debian: sudo apt-get install wget"
    echo "CentOS/RHEL: sudo yum install wget"
    exit 1
fi

# 检查tar
if ! command -v tar &> /dev/null; then
    echo "错误: tar 未安装"
    exit 1
fi

# 检查构建工具
echo "检查构建工具..."
BUILD_TOOLS_MISSING=()

if ! command -v gcc &> /dev/null; then
    BUILD_TOOLS_MISSING+=("build-essential/gcc")
fi

if ! command -v clang &> /dev/null; then
    BUILD_TOOLS_MISSING+=("clang")
fi

if ! command -v make &> /dev/null; then
    BUILD_TOOLS_MISSING+=("make")
fi

if [ ${#BUILD_TOOLS_MISSING[@]} -ne 0 ]; then
    echo "警告: 缺少以下构建工具:"
    for tool in "${BUILD_TOOLS_MISSING[@]}"; do
        echo "  - $tool"
    done
    echo ""
    echo "Ubuntu/Debian 安装命令:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y curl wget build-essential clang llvm zlib1g-dev libicu-dev libcurl4-openssl-dev libkrb5-dev ca-certificates"
    echo ""
    echo "CentOS/RHEL 安装命令:"
    echo "  sudo yum groupinstall -y 'Development Tools'"
    echo "  sudo yum install -y curl wget clang llvm zlib-devel libicu-devel libcurl-devel krb5-devel ca-certificates"
    echo ""
    echo "Arch Linux 安装命令:"
    echo "  sudo pacman -S --needed base-devel curl wget clang llvm zlib icu curl krb5 ca-certificates"
    echo ""
    read -p "是否继续构建? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "构建已取消"
        exit 1
    fi
fi

echo "======================================"
echo "安装 .NET SDK 9.0"
echo "======================================"

# 检查是否已安装 .NET
if command -v dotnet &> /dev/null; then
    DOTNET_VERSION=$(dotnet --version 2>/dev/null || echo "unknown")
    echo "已安装的 .NET 版本: $DOTNET_VERSION"
    
    # 检查是否是9.0版本
    if [[ $DOTNET_VERSION == 9.* ]]; then
        echo ".NET 9.0 已安装，跳过安装步骤"
        SKIP_DOTNET_INSTALL=true
    else
        echo "需要安装 .NET 9.0"
        SKIP_DOTNET_INSTALL=false
    fi
else
    echo ".NET 未安装，需要安装"
    SKIP_DOTNET_INSTALL=false
fi

if [ "$SKIP_DOTNET_INSTALL" = false ]; then
    echo "下载并安装 .NET SDK 9.0..."
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # 下载 .NET SDK 9.0.101
    echo "下载 .NET SDK 9.0.101..."
    wget -q --show-progress https://builds.dotnet.microsoft.com/dotnet/Sdk/9.0.101/dotnet-sdk-9.0.101-linux-x64.tar.gz
    
    # 创建安装目录
    DOTNET_INSTALL_DIR="$HOME/.dotnet"
    mkdir -p "$DOTNET_INSTALL_DIR"
    
    # 解压 .NET SDK
    echo "解压 .NET SDK..."
    tar -xzf dotnet-sdk-9.0.101-linux-x64.tar.gz -C "$DOTNET_INSTALL_DIR"
    
    # 设置环境变量
    export PATH="$DOTNET_INSTALL_DIR:$PATH"
    export DOTNET_ROOT="$DOTNET_INSTALL_DIR"
    
    # 返回原目录
    cd - > /dev/null
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"
    
    echo "验证 .NET 安装..."
    if "$DOTNET_INSTALL_DIR/dotnet" --version &> /dev/null; then
        echo ".NET SDK 安装成功!"
        echo "版本: $("$DOTNET_INSTALL_DIR/dotnet" --version)"
        
        # 创建符号链接 (可选)
        if [ -w "/usr/local/bin" ]; then
            sudo ln -sf "$DOTNET_INSTALL_DIR/dotnet" /usr/local/bin/dotnet 2>/dev/null || true
        fi
    else
        echo "错误: .NET SDK 安装失败"
        exit 1
    fi
else
    # 确保使用系统已安装的 dotnet
    export DOTNET_ROOT=$(dirname $(dirname $(readlink -f $(which dotnet))))
fi

echo "======================================"
echo "开始构建"
echo "======================================"

# 显示项目信息
echo "项目信息:"
echo "  项目路径: $(pwd)"
echo "  主项目: src/N_m3u8DL-RE/N_m3u8DL-RE.csproj"

# 清理之前的构建输出
if [ -d "artifact" ]; then
    echo "清理之前的构建输出..."
    rm -rf artifact
fi

# 开始构建
echo "开始构建 N_m3u8DL-RE for linux-x64..."
echo "构建命令: dotnet publish src/N_m3u8DL-RE -r linux-x64 -c Release -o artifact"

# 执行构建
if dotnet publish src/N_m3u8DL-RE -r linux-x64 -c Release -o artifact; then
    echo "✅ 构建成功!"
else
    echo "❌ 构建失败!"
    exit 1
fi

echo "======================================"
echo "打包构建结果"
echo "======================================"

# 检查构建输出
if [ ! -f "artifact/N_m3u8DL-RE" ]; then
    echo "错误: 构建输出中找不到 N_m3u8DL-RE 可执行文件"
    echo "artifact 目录内容:"
    ls -la artifact/ || echo "artifact 目录不存在"
    exit 1
fi

# 设置可执行权限
chmod +x artifact/N_m3u8DL-RE

# 显示文件信息
echo "构建的可执行文件信息:"
ls -lh artifact/N_m3u8DL-RE
file artifact/N_m3u8DL-RE

# 创建打包文件名
PACKAGE_NAME="N_m3u8DL-RE_${BUILD_TAG}_linux-x64_${BUILD_DATE}.tar.gz"

# 打包
echo "创建压缩包: $PACKAGE_NAME"
cd artifact
tar -czvf "../$PACKAGE_NAME" N_m3u8DL-RE
cd ..

echo "======================================"
echo "构建完成"
echo "======================================"

echo "✅ 构建成功完成!"
echo ""
echo "输出文件:"
echo "  可执行文件: artifact/N_m3u8DL-RE"
echo "  压缩包: $PACKAGE_NAME"
echo ""
echo "文件大小:"
ls -lh artifact/N_m3u8DL-RE
ls -lh "$PACKAGE_NAME"
echo ""

# 测试运行
echo "======================================"
echo "测试可执行文件"
echo "======================================"

echo "测试可执行文件是否可以运行..."
if ./artifact/N_m3u8DL-RE --version 2>/dev/null || ./artifact/N_m3u8DL-RE --help | head -5; then
    echo "✅ 可执行文件测试通过!"
else
    echo "⚠️  可执行文件可能有问题，但构建已完成"
fi

echo ""
echo "======================================"
echo "使用说明"
echo "======================================"
echo ""
echo "1. 可执行文件位置: ./artifact/N_m3u8DL-RE"
echo "2. 使用方法: ./artifact/N_m3u8DL-RE [选项] <URL>"
echo "3. 查看帮助: ./artifact/N_m3u8DL-RE --help"
echo "4. 压缩包: $PACKAGE_NAME"
echo ""
echo "示例命令:"
echo "  ./artifact/N_m3u8DL-RE \"https://example.com/playlist.m3u8\""
echo "  ./artifact/N_m3u8DL-RE -M format=mp4 \"https://example.com/playlist.m3u8\""
echo ""

# 如果安装了 .NET 到用户目录，提供环境变量设置建议
if [ "$SKIP_DOTNET_INSTALL" = false ] && [ -d "$HOME/.dotnet" ]; then
    echo "======================================"
    echo "环境变量设置建议"
    echo "======================================"
    echo ""
    echo "为了在其他终端会话中使用 .NET，请将以下内容添加到您的 shell 配置文件:"
    echo ""
    echo "对于 bash (~/.bashrc):"
    echo "  export PATH=\"\$HOME/.dotnet:\$PATH\""
    echo "  export DOTNET_ROOT=\"\$HOME/.dotnet\""
    echo ""
    echo "对于 zsh (~/.zshrc):"
    echo "  export PATH=\"\$HOME/.dotnet:\$PATH\""
    echo "  export DOTNET_ROOT=\"\$HOME/.dotnet\""
    echo ""
fi

echo "构建脚本执行完毕!"