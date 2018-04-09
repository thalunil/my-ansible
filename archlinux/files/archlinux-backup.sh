#!/usr/bin/env zsh

date=`date +%F`
umask 027

# sourcing archlinux-backup.conf in /etcm otherwise exit gracefully
if [[ -f /etc/archlinux-backup.conf ]]; then
	source /etc/archlinux-backup.conf
else
	echo "### ERROR: configuration file not present - /etc/archlinux-backup.conf"
	exit 1
fi

# check if $target and $snapshot_dir is set
[[ -z "$backup_dir" ]] && echo "### ERROR: /etc/archlinux-backup.conf - please set \$backup_dir" && return 1
[[ -z "$snapshot_dir" ]] && echo "### ERROR: /etc/archlinux-backup.conf - please set \$snapshot_dir" && return 1

if ! [[ -d "$backup_dir" ]]; then
	mkdir "$backup_dir" && chmod 0750 "$backup_dir" && chown root:thalunil "$backup_dir"
else
	chmod 0750 "$backup_dir" && chown root:thalunil "$backup_dir"
fi

if ! [[ -d "$snapshot_dir" ]]; then
	mkdir "$snapshot_dir" && chmod 0750 "$snapshot_dir" && chown root:thalunil "$snapshot_dir"
else
	chmod 0750 "$snapshot_dir" && chown root:thalunil "$snapshot_dir"
fi

# delete_date is for snapshots which get purged after specified age
delete_date=`date -d "7 days ago" +%F`

echo "### Dumping Pacman Package List - $backup_dir/pkglist.txt"
pacman -Qqe > "$backup_dir/pkglist.txt"

## Snapshot routine for btrfs
## set $snapshot_dir do a snapshot directory under which the snapshots 
## are created
snapshot="$snapshot_dir"

mksnapshot(){
	echo "### Daily btrfs snapshot of / - $date"
	echo "btrfs subvolume snapshot / $snapshot_dir/$date-snapshot"
	btrfs subvolume snapshot / "$snapshot_dir/$date-snapshot"
	echo "### Delete snapshot of 7 days ago - $delete_date"
	echo btrfs subvolume delete -v "$snapshot_dir/$delete_date-snapshot"
	btrfs subvolume delete -v "$snapshot_dir/$delete_date-snapshot"
}

## Invoke mksnapshot when directory is existent
if [[ -d "$snapshot_dir" ]]; then
       	mksnapshot 
else
	echo "### NOTICE: $snapshot_dir not a directory"
fi

## Not implemented TBD after this comment
exit 0

echo "### Daily system backup - "$date" - "$target"/rsync"
echo -n "### Starting at: "; date +%H:%M
rsync -ax --delete / "$target/rsync"

echo "### Daily duplicity backup"
echo -n "### Starting at: "; date +%H:%M
duplicity -v4 --no-encryption --exclude-other-filesystems --full-if-older-than 1M / "file://$target/duplicity"
echo "### Deleting old duplicity sets (> 1 month)"
duplicity --no-encryption remove-older-than 1M "file://$target/duplicity"
