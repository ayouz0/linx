#!/bin/bash
# xlink - 42 disk quota fix: move big regenerable dirs to /goinfre, symlink them back.
#
# /home is quota'd (~5G), /goinfre/$USER is machine-local scratch with hundreds of GB.
# Caches, node_modules and editor extensions all regenerate, so they have no business
# eating quota. /goinfre is wiped when you change machine, so this is idempotent:
# run it once to migrate, and let your shell rc run `xlink.sh -q` at login to
# re-create the targets so the symlinks never dangle.
#
#   ./xlink.sh            scan, then ask what to move
#   ./xlink.sh -y         move everything, no questions
#   ./xlink.sh -n         dry run, change nothing
#   ./xlink.sh -u         undo: turn every xlink symlink back into a real dir
#   ./xlink.sh -q         restore-only, silent (put this in ~/.zshrc or ~/.bashrc)
#   MIN_MB=10 ./xlink.sh  also move dirs smaller than the 25 MB default
#
# by: Abderrahim Zabir (xcleaner) / symlink rework

STORE=${STORE:-/goinfre/$USER/cache}
MIN_MB=${MIN_MB:-25}
mode=$1

# npm's palette: red brand, cyan indices, dim paths, yellow warnings, green results.
# Off when piped or NO_COLOR is set, so logs stay readable.
if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
    R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' C=$'\e[36m' B=$'\e[1m' D=$'\e[2m' X=$'\e[0m'
else
    R= G= Y= C= B= D= X=
fi
# dim the directory, keep the last component bright - npm does this with package names
pretty() { case $1 in */*) printf '%s' "${D}${1%/*}/${X}${B}${1##*/}${X}";; *) printf '%s' "${B}$1${X}";; esac; }

[ -d /goinfre ] || { echo "${R}${B}xlink${X} ${R}ERR!${X} no /goinfre on this machine"; exit 1; }
mkdir -p "$STORE" || exit 1

# --- restore: any symlink of ours whose target vanished (new machine) gets it back
find "$HOME" -maxdepth 12 -xtype l -lname "$STORE/*" -print0 2>/dev/null |
    while IFS= read -r -d '' l; do mkdir -p "$(readlink "$l")"; done
[ "$mode" = -q ] && exit 0

# --- undo: swap every xlink symlink back for a real dir (leave goinfre behind)
if [ "$mode" = -u ]; then
    find "$HOME" -maxdepth 12 -lname "$STORE/*" -print0 2>/dev/null |
        while IFS= read -r -d '' l; do
            t=$(readlink "$l"); rm "$l" && mkdir "$l" && cp -a "$t"/. "$l"/ &&
                echo "${G}-${X} restored $(pretty "${l#$HOME/}")"
        done
    exit 0
fi

# --- discover: what is worth moving, found fresh every run
candidates() {
    # plain caches and package stores, if they exist
    for p in .cache .npm/_cacache .bun/install/cache .yarn/cache .local/share/Trash \
             .cargo/registry .gradle/caches .m2/repository go/pkg/mod .nuget/packages \
             .nvm/.cache; do
        [ -d "$HOME/$p" ] && echo "$p"
    done
    # flatpak apps: every cache-shaped dir, plus editor extension stores.
    # -prune so we never descend into a cache to find caches inside it.
    [ -d "$HOME/.var/app" ] && find "$HOME/.var/app" -maxdepth 8 \( -name site-packages -o -name extensions \) -prune -o -type d \
        \( -iname cache -o -iname 'Cache*' -o -iname 'Code Cache' -o -iname GPUCache \
           -o -iname CacheStorage -o -iname ScriptCache -o -iname '*_crx_cache' \
           -o -iname 'File System' -o -iname ShaderCache \
           -o -iname screen_ai -o -iname optimization_guide_model_store \) \
        -prune -printf '%P\n' 2>/dev/null | sed 's|^|.var/app/|'
    # every project's node_modules / venv, at any depth, without recursing inside them
    find "$HOME" -maxdepth 6 \( -name .var -o -name .git -o -name .cache -o -name .nvm \) -prune -o \
        -type d \( -name node_modules -o -name .venv \) \
        -prune -printf '%P\n' 2>/dev/null
}

# --- which app owns a path, so we can warn if it is running right now
owner() { case $1 in *com.google.Chrome*) echo chrome;; *visualstudio.code*|.vscode*) echo code;;
    *Discord*) echo Discord;; *firefox*) echo firefox;; *Brave*) echo brave;; *) echo "";; esac; }

link() {
    local rel=$1 mb=$2 src="$HOME/$1" dst="$STORE/${1//\//%}"
    mkdir -p "$dst" &&
    cp -a "$src"/. "$dst"/ 2>/dev/null            # keep the contents, don't just nuke them
    chmod -R u+w "$src" 2>/dev/null               # read-only dirs refuse unlink otherwise
    rm -rf "$src" || { echo "${Y}${B}warn${X} in use, skipped  $(pretty "$rel")"; return; }
    ln -s "$dst" "$src" && printf "${G}+${X} moved ${B}%5s${X} ${D}MB${X}  %s\n" "$mb" "$(pretty "$rel")"
    moved=$((moved + mb))
}

# --- scan: collect what is movable and how big, before touching anything
echo "${R}${B}xlink${X} scanning ${D}$HOME${X} ${D}->${X} ${C}$STORE${X}"
rel=() size=() busy=""
while IFS= read -r p; do
    [ -L "$HOME/$p" ] && continue                 # already a symlink, ours or not
    [ -d "$HOME/$p" ] || continue
    mb=$(du -sm "$HOME/$p" 2>/dev/null | cut -f1)
    [ "${mb:-0}" -ge "$MIN_MB" ] || continue      # not worth a symlink
    rel+=("$p"); size+=("$mb")
done < <(candidates | sort -u)

n=${#rel[@]}
[ "$n" -eq 0 ] && { echo "${G}${B}clean${X} nothing over ${B}${MIN_MB}${X} MB left in home"; df -h "$HOME" | tail -1; exit 0; }

# biggest first, so the interesting ones are not buried
order=$(for i in $(seq 0 $((n-1))); do echo "${size[$i]} $i"; done | sort -rn | awk '{print $2}')

total=0
echo
echo "${D}  #    size  what${X}"
for i in $order; do
    o=$(owner "${rel[$i]}")
    [ -n "$o" ] && pgrep -x "$o" >/dev/null 2>&1 && { warn[$i]="  ${Y}<- $o is RUNNING${X}"; busy=1; }
    printf "${C}%3d${X}  ${B}%5s${X} ${D}MB${X}  %s%s\n" "$((i+1))" "${size[$i]}" "$(pretty "${rel[$i]}")" "${warn[$i]}"
    total=$((total + size[$i]))
done
echo "${D}     ${X}${B}${total}${X} ${D}MB movable in total${X}"
[ -n "$busy" ] && echo
[ -n "$busy" ] && echo "${Y}${B}warn${X} quit a ${Y}RUNNING${X} app before moving its dirs, or it may misbehave until restart"
[ "$mode" = -n ] && exit 0

# --- pick. stdin may be a pipe (curl | bash, an editor terminal), so ask the
# terminal itself when there is one, and never move anything behind your back.
if [ "$mode" = -y ]; then
    pick=a
elif { exec 3</dev/tty; } 2>/dev/null; then
    echo
    printf "${B}move what?${X} ${C}[a]ll${X} / numbers like ${C}1 3 5${X} / ${C}[q]uit${X}: "
    read -r pick <&3
else
    echo
    echo "${Y}${B}warn${X} no terminal to ask - re-run from a shell, or ${C}$0 -y${X} to move all of it"
    exit 0
fi
case ${pick:-q} in
    a|A|all) chosen=$order;;
    q|Q|"") echo "${D}nothing moved${X}"; exit 0;;
    *) chosen=$(for w in ${pick//,/ }; do
           [ "$w" -ge 1 ] 2>/dev/null && [ "$w" -le "$n" ] && echo $((w-1)) ||
               echo "${Y}${B}warn${X} ignoring ${B}$w${X}" >&2
       done);;
esac
[ -z "$(echo $chosen)" ] && { echo "${D}nothing valid selected${X}"; exit 0; }

echo
moved=0
for i in $chosen; do link "${rel[$i]}" "${size[$i]}"; done
echo
echo "${G}${B}freed ${moved} MB${X}${G} from your quota${X}"
echo "${D}$(df -h "$HOME" | tail -1)${X}"

# --- offer to make it survive a machine change, since that is the usual breakage
rc=$HOME/.zshrc; [ -n "$BASH_VERSION" ] && [ ! -f "$rc" ] && rc=$HOME/.bashrc
if [ "$moved" -gt 0 ] && ! grep -q 'xlink.sh -q' "$rc" 2>/dev/null; then
    echo
    echo "${Y}${B}warn${X} /goinfre is wiped when you change machine - the links need re-creating at login."
    printf "${B}add${X} ${C}%s -q${X} ${B}to${X} ${C}%s${X}? [Y/n]: " "$0" "${rc/#$HOME/~}"
    if [ "$mode" = -y ]; then echo "y"; a=y; else read -r a <&3; fi
    case ${a:-y} in y|Y)
        printf '\n# re-create /goinfre cache symlinks (wiped between machines)\n%s -q\n' \
            "$(readlink -f "$0")" >> "$rc" && echo "${G}+${X} added to ${C}${rc/#$HOME/~}${X}";;
    esac
fi
