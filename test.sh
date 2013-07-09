#!/usr/bin/env sh
rm luacov.* 2>/dev/null
busted -c spec && egrep "\s+src/" luacov.report.out
