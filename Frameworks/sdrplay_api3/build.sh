#!/bin/sh

API_DIR=/usr/local
INC_DIR=include
LIB_DIR=lib
DYLIB=libsdrplay_api.dylib
OUT_XCFW=sdrplay_api3.xcframework
SIGN_ID=hooper@queensu.ca

set -e
rm -rf $INC_DIR $LIB_DIR $OUT_XCFW
mkdir $INC_DIR $LIB_DIR
cp -p $API_DIR/include/sdrplay_api*.h $INC_DIR
cat <<_EOF_ >$INC_DIR/module.modulemap
module sdrplay_api [system] {
  header "sdrplay_api.h"
  header "sdrplay_api_callback.h"
  header "sdrplay_api_control.h"
  header "sdrplay_api_dev.h"
  header "sdrplay_api_rsp1a.h"
  header "sdrplay_api_rsp2.h"
  header "sdrplay_api_rspDuo.h"
  header "sdrplay_api_rspDx.h"
  header "sdrplay_api_rx_channel.h"
  header "sdrplay_api_tuner.h"
  export *
}
_EOF_
cp -p $API_DIR/lib/$DYLIB $LIB_DIR
codesign --remove-signature $LIB_DIR/$DYLIB
install_name_tool -id @rpath/$DYLIB $LIB_DIR/$DYLIB
xcodebuild -create-xcframework -library $LIB_DIR/$DYLIB -headers $INC_DIR -output $OUT_XCFW
codesign --timestamp -fs $SIGN_ID $OUT_XCFW
