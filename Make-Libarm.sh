#!/bin/bash -e

LIBARM_SO_PATH=../res/raw/libarm.so

mkdir -p tmp
cd tmp

7z x -y ../$LIBARM_SO_PATH

cp ../build/armv6/libffmpeg.so 60/
cp ../build/vfp/libffmpeg.so   61/
cp ../build/armv7/libffmpeg.so 70/
cp ../build/neon/libffmpeg.so  71/

mv ../$LIBARM_SO_PATH libarm.so.`date +%s -r ../$LIBARM_SO_PATH`
7z a ../$LIBARM_SO_PATH 60 61 70 71

ls -l ../$LIBARM_SO_PATH
