#!/bin/sh
# pending-plants.sh DIR...: the plant copies among DIR whose .summary is
# missing or shorter than their .plant asks: one line a suite and a target.
for d in "$@"; do
  want=$(sed -n '1,2p' "$d/.plant" | wc -w)
  have=$( [ -f "$d/.summary" ] && wc -l < "$d/.summary" || echo 0)
  [ "$have" -eq "$want" ] || echo "$d"
done
