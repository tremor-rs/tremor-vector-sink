#!/bin/bash

while true;
do
  ts=`gdate '+%s%N'`
  echo '{"application": "test", "date": ' $ts ', "message": "demo"}' | nc localhost 8880
  sleep 1
done
