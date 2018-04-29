#!/usr/bin/env zsh

date=`date +%F`
umask 027

# defaults
backup_dir="file:///backup/duplicity/"
snapshot_dir="/snapshot"
snapshot_num="3"
use_snapshots=true
use_duplicity=true

# sourcing archlinux-backup.conf in /etcm otherwise exit gracefully
if [[ -f /etc/archlinux-backup.conf ]]; then
	source /etc/archlinux-backup.conf
else
	echo "### WARNING: /etc/archlinux-backup.conf - configuration file not present"
fi

case "$snapshot_num" in
[[:digit:]]*)
	if [ ! $snapshot_num -ge 1 ]; then
		echo "not a valid number - snapshot count must be greater than 1"
		exit 1
	fi
      	;;
*)
       	echo "### INFO: /etc/archlinux-backup.conf - \$snapshot_num not set - using defaults"
       	;;
esac

if ! [[ -d "$snapshot_dir" ]]; then
	mkdir "$snapshot_dir" && chmod 0750 "$snapshot_dir" && chown root:thalunil "$snapshot_dir"
else
	chmod 0750 "$snapshot_dir" && chown root:thalunil "$snapshot_dir"
fi

# delete_date is for snapshots which get purged after specified age
delete_date=$(date -d "7 days ago" +%F)


echo "#########################"
echo "## Dumping Pacman Package List - $backup_dir/pkglist.txt"
pacman -Qqe > "$backup_dir/pkglist.txt"
echo "#########################"

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

use_duplicity () {
	echo "### duplicity backup -> $backup_dir"
	duplicity -v0 --no-encryption --exclude-other-filesystems --full-if-older-than 1M / "$backup_dir"
	echo "### Deleting old duplicity sets (preserve 2 full backup chains)"
	duplicity --no-encryption remove-all-but-n-full 2 --force "$backup_dir"
}	


if [ "X$use_snapshots" = "Xtrue" ]; then
	echo "## Archlinux thal snapshot script v1.0"
	echo -n "### Starting at: "; date +%H:%M
	purge_oldest_snapshot
	rename_snapshots 
	mksnapshot
	echo -n "### Finished at: "; date +%H:%M
	echo "#########################"
fi

if [ "X$use_duplicity" = "Xtrue" ]; then
	echo "## \$use_duplicity is true - running duplicity"
	if [ -x $(which duplicity) ]; then
		echo -n "### Starting at: "; date +%H:%M
		use_duplicity
		echo -n "### Finished at: "; date +%H:%M
	else
		echo "duplicity not found - please install"
	fi
	echo "#########################"
fi

echo "Disk Space"
df -h "$snapshot_dir" "$backup_dir"
echo "#########################"

## Not implemented TBD after this comment
exit 0

echo "### Daily system backup - "$date" - "$target"/rsync"
echo -n "### Starting at: "; date +%H:%M
rsync -ax --delete / "$target/rsync"
