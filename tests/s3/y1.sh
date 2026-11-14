#!/bin/bash
# the Y1 file list of the s3 oracles, in the standard order: lib/prelude.srs, s2/*.srs, s2c/main.srs (31 files).
# usage (from the repo root): bash tests/s3/y1.sh
echo lib/prelude.srs
LC_ALL=C ls s2/*.srs
echo s2c/main.srs
