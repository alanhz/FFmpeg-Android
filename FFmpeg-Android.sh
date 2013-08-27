#!/bin/bash -e

if [ ! -x $ANDROID_NDK/ndk-build ]; then
	echo "Please export ANDROID_NDK=/your/android/ndk/path"
	exit 1;
fi

DEST=`pwd`/build && rm -rf $DEST
SOURCE=`pwd`/ffmpeg
OPENSSL=`pwd`/openssl

if [ -d openssl ]; then
  cd openssl
else
  git clone https://github.com/dpolishuk/openssl-android.git openssl
  cd openssl
fi

$ANDROID_NDK/ndk-build
$ANDROID_NDK/ndk-build ssl_static crypto_static

cd ..

if [ -d ffmpeg ]; then
  cd ffmpeg
else
  git clone git://source.ffmpeg.org/ffmpeg.git ffmpeg
  cd ffmpeg
fi

git reset --hard
git clean -f -d
#git checkout `cat ../ffmpeg-version`
git checkout n2.0
patch -p1 <../FFmpeg-VPlayer.patch
[ $PIPESTATUS == 0 ] || exit 1

#git log --pretty=format:%H -1 > ../ffmpeg-version

TOOLCHAIN=/tmp/vplayer
SYSROOT=$TOOLCHAIN/sysroot/
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --toolchain=arm-linux-androideabi-4.7 --install-dir=$TOOLCHAIN

export PATH=$TOOLCHAIN/bin:$PATH
export CC="ccache arm-linux-androideabi-gcc"
export LD=arm-linux-androideabi-ld
export AR=arm-linux-androideabi-ar

CFLAGS="-std=c99 -O3 -Wall -mthumb -pipe -fpic -fasm \
  -finline-limit=300 -ffast-math \
  -fstrict-aliasing -Werror=strict-aliasing \
  -fmodulo-sched -fmodulo-sched-allow-regmoves \
  -fgraphite -fgraphite-identity \
  -floop-block -floop-flatten -floop-interchange -floop-strip-mine -floop-parallelize-all -ftree-loop-linear \
  -Wno-psabi -Wa,--noexecstack \
  -D__ARM_ARCH_5__ -D__ARM_ARCH_5E__ -D__ARM_ARCH_5T__ -D__ARM_ARCH_5TE__ \
  -DANDROID -DNDEBUG \
  -I$OPENSSL/include"

#  -fgraphite -fgraphite-identity \
#Optimization
FFMPEG_FLAGS="--enable-openssl --target-os=linux \
  --cross-prefix=arm-linux-androideabi- \
  --enable-cross-compile \
  --enable-shared \
  --disable-static \
  --disable-runtime-cpudetect \
  --disable-symver \
  --disable-doc \
  --disable-ffplay \
  --disable-ffmpeg \
  --disable-ffprobe \
  --disable-ffserver \
  --disable-avdevice \
  --disable-postproc \
  --disable-encoders \
  --disable-muxers \
  --disable-devices \
  --disable-demuxer=sbg \
  --disable-demuxer=dts \
  --disable-parser=dca \
  --disable-decoder=dca --disable-decoder=svq3 \
  --enable-network \
  --enable-asm \
  --enable-version3"


for version in vfp armv6 neon armv7; do

  cd $SOURCE

  case $version in
    neon)
      EXTRA_CFLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=softfp -mvectorize-with-neon-quad"
      EXTRA_LDFLAGS="-Wl,--fix-cortex-a8"
      FFMPEG_FLAGS="--arch=armv7-a --cpu=cortex-a8 $FFMPEG_FLAGS"
      ;;
    armv7|armeabi-v7a)
      EXTRA_CFLAGS="-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp"
      EXTRA_LDFLAGS="-Wl,--fix-cortex-a8"
      FFMPEG_FLAGS="--arch=armv7-a --cpu=cortex-a8 $FFMPEG_FLAGS"
      ;;
    vfp)
      EXTRA_CFLAGS="-march=armv6 -mfpu=vfp -mfloat-abi=softfp"
      EXTRA_LDFLAGS=""
      FFMPEG_FLAGS="--arch=arm $FFMPEG_FLAGS"
      ;;
    armv6)
      EXTRA_CFLAGS="-march=armv6"
      EXTRA_LDFLAGS=""
      FFMPEG_FLAGS="--arch=arm $FFMPEG_FLAGS"
      ;;
    *)
      EXTRA_CFLAGS=""
      EXTRA_LDFLAGS=""
      ;;
  esac

  PREFIX="$DEST/$version" && mkdir -p $PREFIX
  FFMPEG_FLAGS="$FFMPEG_FLAGS --prefix=$PREFIX"
  EXTRA_LDFLAGS="-lm -lz -Wl,--no-undefined -Wl,-z,noexecstack $EXTRA_LDFLAGS -L$OPENSSL/obj/local/armeabi/"

  ./configure $FFMPEG_FLAGS --extra-cflags="$CFLAGS $EXTRA_CFLAGS" --extra-ldflags="$EXTRA_LDFLAGS" | tee $PREFIX/configuration.txt
  cp config.* $PREFIX
  [ $PIPESTATUS == 0 ] || exit 1

  make clean
  make -j4 || exit 1
  make install || exit 1

  rm libavformat/log2_tab.o
  rm libswresample/log2_tab.o
  rm libavcodec/log2_tab.o
  $CC -shared --sysroot=$SYSROOT $EXTRA_LDFLAGS libavutil/*.o libavutil/arm/*.o libavcodec/*.o libavcodec/arm/*.o libavformat/*.o libswresample/*.o libswresample/arm/*.o libswscale/*.o libavfilter/*.o compat/*.o $OPENSSL/obj/local/armeabi/objs/ssl_static/ssl/*.o -lcrypto_static -o $PREFIX/libffmpeg.so

  cp $PREFIX/libffmpeg.so $PREFIX/libffmpeg-debug.so
  arm-linux-androideabi-strip --strip-unneeded $PREFIX/libffmpeg.so

done
