#!/bin/bash

GITHUB_WORKSPACE=$(cd $(dirname $0);pwd)
RELEASE_DIR=${RELEASE_DIR:-$GITHUB_WORKSPACE/release}
DEVICE_NAME=$(grep '^CONFIG_TARGET.*DEVICE.*=y' config.seed | sed -r 's/CONFIG_TARGET_(.*)_DEVICE.*=y/\1/')
RELEASE_NAME=${RELEASE_NAME:-$DEVICE_NAME}
REPO_URL="https://github.com/coolsnowwolf/lede"
REPO_BRANCH="master"
REPO_COMMIT=""
FEEDS_CONF="feeds.conf.default"
CONFIG_FILE="config.seed"
DIY_P1_SH="diy-part1.sh"
DIY_P2_SH="diy-part2.sh"


if [ ! -e openwrt ]; then
  git clone --depth 1 $REPO_URL -b $REPO_BRANCH openwrt
elif [ -z $REPO_COMMIT ]; then
  pushd openwrt
  rm -rf files package
  git pull origin $REPO_BRANCH
  git reset --hard origin/$REPO_BRANCH
  popd
fi

if [ ! -z $REPO_COMMIT ]; then
  pushd openwrt
  rm -rf files package
  git pull origin $REPO_COMMIT
  git reset --hard $REPO_COMMIT
  popd
fi

[ -e $FEEDS_CONF ] && cp $FEEDS_CONF openwrt/feeds.conf.default
chmod +x $DIY_P1_SH

pushd openwrt
GITHUB_WORKSPACE=$GITHUB_WORKSPACE $GITHUB_WORKSPACE/$DIY_P1_SH
./scripts/feeds update -f -a
./scripts/feeds install -a

# 复制配置并同步
[ -e ../$CONFIG_FILE ] && cp ../$CONFIG_FILE .config
make defconfig

# LuCI 25.12 已移除 luci-base/host/compile，po2lmo 不再需要
# echo "编译 luci-base 生成 po2lmo..."
# make package/luci-base/host/compile -j$(nproc) || make package/luci-base/host/compile -j1 V=s

popd

[ -e files ] && cp -r files openwrt/files
[ -e $CONFIG_FILE ] && cp $CONFIG_FILE openwrt/.config
chmod +x $DIY_P2_SH

pushd openwrt
GITHUB_WORKSPACE=$GITHUB_WORKSPACE $GITHUB_WORKSPACE/$DIY_P2_SH
make defconfig
make download -j8

# Fix vlmcsd GCC 13 compatibility
# $(notdir $(CC)) breaks when CC="ccache gcc" (contains spaces)
# Pre-extract vlmcsd source and patch GNUmakefile before build
make package/feeds/packages/vlmcsd/prepare 2>/dev/null || true
VLMCSD_GNUMAKE=$(ls build_dir/target-*/vlmcsd-*/src/GNUmakefile 2>/dev/null | head -1)
if [ -n "$VLMCSD_GNUMAKE" ]; then
  sed -i 's/notdir $(CC)/lastword $(subst ccache, ,$(CC))/g' "$VLMCSD_GNUMAKE"
fi

make -j$(nproc) || make -j1 || make -j1 V=s
popd

mkdir -p $RELEASE_DIR
pushd openwrt/bin/targets/*/*
cp config.buildinfo $RELEASE_DIR
cp $(ls -1 ./*img.gz | head -1) $RELEASE_DIR/$RELEASE_NAME.img.gz
popd

pushd $RELEASE_DIR
md5sum $RELEASE_NAME.img.gz > $RELEASE_NAME.img.gz.md5
gzip -dc $RELEASE_NAME.img.gz | md5sum | sed "s/-/$RELEASE_NAME.img/" > $RELEASE_NAME.img.md5
popd
