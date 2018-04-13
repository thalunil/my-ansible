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

# input validation
[[ -z "$backup_dir" ]] && echo "### ERROR: /etc/archlinux-backup.conf - please set \$backup_dir" && return 1
[[ -z "$snapshot_dir" ]] && echo "### ERROR: /etc/archlinux-backup.conf - please set \$snapshot_dir" && return 1

case "$snapshot_num" in
[[:digit:]]*)
	if [ ! $snapshot_num -ge 1 ]; then
		echo "not a valid number - snapshot count must be greater than 1"
		exit 1
	fi
      	;;
*)
       	echo "### INFO: /etc/archlinux-backup.conf - \$snapshot_num is not correctly set - assuming 3"
	snapshot_num="3"
       	;;
esac

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
delete_date=$(date -d "7 days ago" +%F)

echo "### Dumping Pacman Package List - $backup_dir/pkglist.txt"
pacman -Qqe > "$backup_dir/pkglist.txt"

# oldest (~ highest number) snapshot will get purged
purge_oldest_snapshot () {
	if [ -d "$snapshot_dir/$snapshot_num" ]; then
		echo "### INFO: SNAPshot: oldest (~ highest number) snapshot will get purged"
		btrfs subvolume delete -v "$snapshot_dir/$snapshot_num"
	fi
	}

# rename the old/previous snapshot to subsequent numbers
rename_snapshots () {
	for i in $(seq $((--snapshot_num)) -1 0)
	do      
        	if [ -d "$snapshot_dir/$i" ]; then
			echo "### INFO: SNAPshot: rotating $snapshot_dir/$i"
			mv $snapshot_dir/$i $snapshot_dir/$((i+1))
		fi
	done
	}

## Snapshot routine for btrfs root filesystem
mksnapshot () {
	echo "### INFO: SNAPshot: creating btrfs snapshot of / - $date"
	echo "snapshot creation: $date" > /snapshot.info
	btrfs subvolume snapshot / "$snapshot_dir"/0
}

## run script functions
purge_oldest_snapshot
rename_snapshots 
mksnapshot

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
