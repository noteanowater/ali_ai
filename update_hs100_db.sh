#!/bin/bash
# 把各 PT_* 目录下 Makefile 中的 HS100_database_YYYYMMDD 统一替换为新日期
# 用法:
#   ./update_hs100_db.sh                     # 在当前目录下处理, 目标 20261127
#   ./update_hs100_db.sh -d 20261128         # 指定新日期
#   ./update_hs100_db.sh -p /path/to/tests   # 指定根目录
#   ./update_hs100_db.sh -n                  # 只预览, 不修改
#   ./update_hs100_db.sh -b                  # 修改前备份为 Makefile.bak

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
        echo "[无Makefile] $dir"
        missing=$((missing+1))
        continue
    fi

    # 找出需要替换的行(日期不等于目标日期的)
    hits=$(grep -n "$PATTERN" "$mk" | grep -v "$NEW")
    if [ -z "$hits" ]; then
        echo "[无需修改] $mk"
        skipped=$((skipped+1))
        continue
    fi

    echo "[修改] $mk"
    echo "$hits" | sed 's/^/    旧: /'

    if [ $DRYRUN -eq 0 ]; then
        [ $BACKUP -eq 1 ] && cp -p "$mk" "$mk.bak"
        sed -i "s/$PATTERN/$NEW/g" "$mk"
        grep -n "$NEW" "$mk" | sed 's/^/    新: /'
    fi
    changed=$((changed+1))
done

echo "----------------------------------------"
[ $DRYRUN -eq 1 ] && echo "(预览模式, 未实际修改)"
echo "修改: $changed   无需修改: $skipped   缺少Makefile: $missing"
