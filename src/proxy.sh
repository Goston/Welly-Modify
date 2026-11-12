#!/usr/bin/env bash
echo "Connecting to BBS via Websockets..."
BASEDIR=$(dirname "$0")
"$BASEDIR/usock2wsock" -u $1 -r $2 &
sleep 2
# 第三個參數是 Welly 轉送層的 unix socket；沒給的話就像原本一樣直接連到 websocket 轉接程式
"$BASEDIR/telnet" -8 -u "${3:-/tmp/telnetBYwebsocket.$2.sock}"
