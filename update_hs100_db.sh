#!/bin/bash
# Replace HS100_database_YYYYMMDD in every PT_*/Makefile with a new date
# Usage:
#   ./update_hs100_db.sh                     # run in current dir, target 20261127
#   ./update_hs100_db.sh -d 20261128         # specify new date
#   ./update_hs100_db.sh -p /path/to/tests   # specify root directory
#   ./update_hs100_db.sh -n                  # dry run, no changes
#   ./update_hs100_db.sh -b                  # back up to Makefile.bak before editing

NEW_DATE=20261127
ROOT=.
DRYRUN=0
BACKUP=0

while getopts "d:p:nbh" opt; do
    case $opt in
        d) NEW_DATE=$OPTARG ;;
        p) ROOT=$OPTARG ;;
        n) DRYRUN=1 ;;
        b) BACKUP=1 ;;
        *) sed -n '2,9p' "$0"; exit 0 ;;
    esac
done

NEW="HS100_database_${NEW_DATE}"
PATTERN='HS100_database_[0-9]\{8\}'

changed=0; skipped=0; missing=0

for dir in "$ROOT"/PT_*/; do
    mk="${dir}Makefile"
    if [ ! -f "$mk" ]; then
        echo "[NO MAKEFILE] $dir"
        missing=$((missing+1))
        continue
    fi

    # Lines that need replacing (date differs from target)
    hits=$(grep -n "$PATTERN" "$mk" | grep -v "$NEW")
    if [ -z "$hits" ]; then
        echo "[UP TO DATE]  $mk"
        skipped=$((skipped+1))
        continue
    fi

    echo "[UPDATE]      $mk"
    echo "$hits" | sed 's/^/    old: /'

    if [ $DRYRUN -eq 0 ]; then
        [ $BACKUP -eq 1 ] && cp -p "$mk" "$mk.bak"
        sed -i "s/$PATTERN/$NEW/g" "$mk"
        grep -n "$NEW" "$mk" | sed 's/^/    new: /'
    fi
    changed=$((changed+1))
done

echo "----------------------------------------"
[ $DRYRUN -eq 1 ] && echo "(dry run, no files modified)"
echo "Updated: $changed   Up to date: $skipped   Missing Makefile: $missing"
