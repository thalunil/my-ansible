#!/usr/bin/env zsh
#
# Backup - Snapshot script, Alex 'thalunil' Bihlmaier
# 24. July 2018
#
# borgbackup support (https://www.borgbackup.org/)

date=`date +%F`
umask 027

# defaults
# delete_date is for snapshots which get purged after specified age
delete_date=$(date -d "7 days ago" +%F)

backup_dir="/backup"
BORG_REPO="/backup/borg/"
# if backing up to the local system disk please use an exclude statement of the specific directory
# otherwise the backups backups up the backup....recursion ahead!
duplicity_dir="file:///backup/duplicity/"
snapshot_dir="/snapshot"
snapshot_num="3"
use_snapshots=true
use_duplicity=true
#debug=true # uncomment to enable debugging

usage() {
cat << EOF
Benutzung:
	-r: run backup/snapshot (e.g. via cron)

Konfigurationsdatei /etc/archlinux-backup.conf:
                    --------------------------
 use_borg=true (to enable borgbackup)
 borg_repo="<where to search for the borgbackup archive>"
 BORG_BACKUP_DIR="<what directories to backup - space seperated>"
EOF
}

# oldest (~ highest number) snapshot will get purged
purge_oldest_snapshot () {
	if [ -d "$snapshot_dir/$snapshot_num" ]; then
		if [ -n "$debug" ]; then echo "### DEBUG: SNAPshot: oldest (~ highest number) snapshot will get purged"; fi
		btrfs subvolume delete -v "$snapshot_dir/$snapshot_num"
	fi
	}

# rename the old/previous snapshot to subsequent numbers
rename_snapshots () {
	for i in $(seq $((--snapshot_num)) -1 0)
	do      
        	if [ -d "$snapshot_dir/$i" ]; then
			if [ -n "$debug" ]; then echo "### DEBUG: SNAPshot: rotating $snapshot_dir/$i"; fi
			mv $snapshot_dir/$i $snapshot_dir/$((i+1))
		fi
	done
	}

## Snapshot routine for btrfs root filesystem
mksnapshot () {
	echo "### INFO: SNAPshot: creating btrfs snapshot of / - date of snapshot: see /snapshot.info"
	echo "snapshot creation: $date" > /snapshot.info
	btrfs subvolume snapshot / "$snapshot_dir"/0
}

use_duplicity () {
	echo "### duplicity backup -> $duplicity_dir"
	duplicity -v0 --no-encryption --exclude-other-filesystems --exclude /backup --full-if-older-than 1M / "$duplicity_dir"
	echo "### Deleting old duplicity sets (preserve 2 full backup chains)"
	duplicity --no-encryption remove-all-but-n-full 2 --force "$duplicity_dir"
}	

run_borg () {
	echo "### borg repo \$BORG_REPO: $BORG_REPO"
	echo "### borg backup directories \$BORG_BACKUP_DIR: $BORG_BACKUP_DIR" 
	if borg check $BORG_REPO ; then
		if [ -n "$debug" ]; then echo "### DEBUG: borg create -s -e */nobackup/ $BORG_REPO::{now} $BORG_BACKUP_DIR" ; fi
		borg create -s -e "*/nobackup/" $BORG_REPO::{now} ${=BORG_BACKUP_DIR}
	else
		echo "### borgbackup failed..."
	fi
}

run_full () {
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

 echo "#########################"
 # archlinux specific
 # type pacman checks the return code to see if pacman is a valid invokable executable
 if [ -e "/etc/arch-release" ] && type pacman > /dev/null 2>&1; then
	echo "## archlinux: Dumping Pacman Package List - $backup_dir/pkglist.txt"
	pacman -Qqe > "$backup_dir/pkglist.txt"
 else
	echo "## archlinux: not a valid archlinux platform - skipping archlinux specifics"
 fi

 ## BTRFS snapshots
 # Check to see if use_snapshots is true and if / is a valid btrfs filesystem
 echo "#########################"
 if [ "X$use_snapshots" = "Xtrue" ] && btrfs filesystem show / > /dev/null 2>&1; then
	echo "## btrfs snapshot creation"
	echo -n "## Starting at: "; date +%H:%M
	purge_oldest_snapshot
	rename_snapshots 
	mksnapshot
	echo -n "## Finished at: "; date +%H:%M
 else
	echo "## btrfs snapshot creation either disabled or / is not a valid btrfs filesystem"
 fi

 echo "#########################"
 if [ "X$use_duplicity" = "Xtrue" ]; then
	echo "## \$use_duplicity is true - running duplicity"
	if type duplicity > /dev/null 2>&1; then
		echo -n "### Starting at: "; date +%H:%M
		use_duplicity
		echo -n "### Finished at: "; date +%H:%M
		cat << HERE
### Duplicity info
### Looking for files
#### duplicity --no-encryption list-current-files <duplicity target specification> | grep "etc/"

### Restore files
#### duplicity -t 1D --no-encryption --file-to-restore home/thalunil/ --tempdir . <duplicity target specification> <target dir>
HERE
	else
		echo "## duplicity not found - please install"
	fi
else
	echo "## \$use_duplicity is not set - skipping duplicity"
fi

echo "#########################"
echo "## BORGbackup - 24. July 2018"
if [ "X$use_borg" = "Xtrue" ]; then
	echo "## \$use_borg is true - running borgbackup"
	if type borg > /dev/null 2>&1; then
		echo -n "## Starting at: "; date +%H:%M
		run_borg
		echo -n "## Finished at: "; date +%H:%M
	else
		echo "## borgbackup not found - please install"
	fi
else
	echo "## \$use_borg is not set - skipping borgbackup"
fi

echo "#########################"
echo "## local disk space"
df -h -x tmpfs
echo "#########################"
}

if [ $# = 0 ]; then; usage; exit; fi

case $1 in
	-r)
		run_full
		;;
	*)
		usage
		;;
esac
