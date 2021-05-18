#!/bin/bash

set -e
set -u
set -o pipefail

# TODO: update from github
# TODO: reexec with caffeinate
# TODO: take arguments: config, verbose, progress
# TODO: purge old backups
# TODO: purge previous progress
# TODO: lock, and unlock on trap exit
# TODO: non-darwin compatibility

if [[ -z "${HOME}" ]]; then
    echo "error: \$HOME unset" 1>&2
    exit 1
fi

excluded=()
excluded+=('.DS_Store')

included=()

config="${HOME}/.config/rsync-backup/rsync-backup.conf"

if [[ -f "${config}" ]]; then
    # shellcheck disable=SC1090
    source "${config}"
fi

name="${name:-$(hostname -s)}"

if [[ -z "${name}" ]]; then
    echo "error: \$name unset" 1>&2
    exit 1
fi

if [[ -z "${tgt}" ]]; then
    echo "error: \$tgt unset" 1>&2
    exit 1
fi

src="${src:-${HOME}}"
port="${port:-22}"
ts="${ts:-$(date -u '+%Y-%m-%d-%H%M%S')}"

ssh=()
if [[ ${tgt} = *:* ]]; then
    ssh-add -l > /dev/null || ssh-add -A
    ssh+=(ssh -p "${port}" "${tgt%%:*}")
fi

# TODO: create only when no latest
# TODO: remove after first backup
"${ssh[@]}" mkdir -p "${tgt#*:}/1970-01-01-000000"

"${ssh[@]}" mkdir -p "${tgt#*:}/${ts}.progress"

function latest() {
    "${ssh[@]}" ls -1 "${tgt#*:}/" | grep -v '\.progress$' | grep -v latest | tail -1
}
latest="${tgt#*:}/$(latest)"
echo "latest: '${latest}'"

args=()
args+=(--verbose)
args+=(--progress)
args+=(--compress)
args+=(--rsh "ssh -p ${port}")
args+=(--archive)
args+=(--delete)
args+=(--delete-excluded)

for inc in "${included[@]}"; do
    args+=(--include "${inc}")
done

for exc in "${excluded[@]}"; do
    args+=(--exclude "${exc}")
done

# TODO: add multiple --link-dest
args+=(--link-dest "${latest}/")
args+=("${src}/")
args+=("${tgt}/${ts}.progress/")

# TODO: create local snapshot, and delete on trap exit
# tmutil localsnapshot # => Created local snapshot with date: 2021-05-18-184103
# tmutil listlocalsnapshots / # => com.apple.TimeMachine.2021-05-18-184302.local
# diskutil apfs listvolumesnapshots disk1s2 # => Name:        com.apple.TimeMachine.2021-05-18-184302.local
# mkdir -p /tmp/rsync-backup.snapshot.2021-05-18-184302
# mount_apfs -s com.apple.TimeMachine.2021-05-18-184302.local /Users /tmp/rsync-backup.snapshot.2021-05-18-184302
# ls /tmp/rsync-backup.snapshot.2021-05-18-184302/Users/
# diskutil unmount /tmp/rsync-backup.snapshot.2021-05-18-184302
# tmutil deletelocalsnapshots 2021-05-18-184302
# tmutil deletelocalsnapshots /

rc="0"
set -x
rsync "${args[@]}" || rc="$?"
set +x

case $rc in
    24|0) : ;;
    *) exit "$rc" ;;
esac

"${ssh[@]}" mv -v "${tgt#*:}/${ts}.progress" "${tgt#*:}/${ts}"
"${ssh[@]}" ln -svhf "${tgt#*:}/${ts}" "${tgt#*:}/latest"
