#!/bin/bash -e

cd $(git rev-parse --show-toplevel)


if grep --line-number --include \*.hs -riP '(TODO|FIXME|XXX)\b' src app 2>&1 | grep -vP '#\d+'; then
  echo "Please add a link to Issue, for example: TODO: #123"
  exit 1
else
  echo "No TODOs without links found, all good!"
fi
