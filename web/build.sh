#!/bin/sh
# Extremely simple in respect to path building!
# Public Domain.

# Relative paths..
SRCDIR=.
TARGETDIR="$TMPDIR/public-web"

if [ x"$TARGETDIR" = x ]; then
    if [ -d "$HOME/public_html" ]; then
        TARGETDIR="$HOME/public_html"
    elif [ -d "$HOME/Sites" ]; then
        TARGETDIR="$HOME/Sites"
    else
        echo 'No target directory found'
        exit 1
    fi
    echo "TARGETDIR was not set - auto-detected $TARGETDIR"
fi

set -e
set -u

if [ ! -d "$TARGETDIR" ]; then
    echo "TARGETDIR ($TARGETDIR) does not exist - sleep 3; mkdir -p"
    sleep 3; mkdir -p "$TARGETDIR"
fi

cd $SRCDIR

KEPT=0
REFRESHED=0
echo
echo "Checking base files: <$SRCDIR/base>"
cd base
for i in *.*; do
    echo "  - Action on <$i> ... \c"
    if [ ! -r "$i" ]; then
        echo "READ-ERROR: SKIP"
        continue
    fi
    target="$TARGETDIR/$i"

    if [ ! -f "$target" ] || [ "$target" -ot "$i" ]; then
        echo 'refresh'
        cp -X -f "$i" "$target"
        chmod o+r "$target"
        REFRESHED=$(( $REFRESHED + 1 ))
    else
        echo 'keep'
        KEPT=$(( $KEPT + 1 ))
    fi
done
cd ..
echo "$KEPT files were up to date."
echo "$REFRESHED files have been updated."

KEPT=0
REFRESHED=0
echo
echo "Processing HTML"
cd html
for i in *.html; do
    echo "  - Action on <$i> ... \c"
    if [ ! -r "$i" ]; then
        echo "READ-ERROR: SKIP"
        continue
    fi
    target="$TARGETDIR/$i"

    if [ ! -f "$target" ] || [ "$target" -ot "$i" ]; then
        echo 'refresh'
        perl -- "../expand-html.pl" < "$i" > "$target"
        chmod o+r "$target"
        REFRESHED=$(( $REFRESHED + 1 ))
    else
        echo 'keep'
        KEPT=$(( $KEPT + 1 ))
    fi
done
cd ..
echo "$KEPT files were up to date."
echo "$REFRESHED files have been updated."

exit 0
# vim:set fenc=utf-8 syntax=sh ts=4 sts=4 sw=4 et tw=79:
