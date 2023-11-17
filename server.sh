#!/bin/sh

set -eu

echo "ADDRESS=${ADDRESS:=127.0.0.1}"
echo "PORT=${PORT:=42080}"

ncat -kle './handler.sh' "$ADDRESS" "$PORT"
