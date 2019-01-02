#!/usr/bin/env zsh
#
# Backup - Snapshot script, Alex 'thalunil' Bihlmaier
# 24. July 2018
#
# borgbackup support (https://www.borgbackup.org/)
#
# TBD
# * rsnapshot support (Inkrementelle Snapshot mit Hardlinks)

date=`date +%F`
umask 027

# defaults
# delete_date is for snapshots which get purged after specified age
delete_date=$(date -d "7 days ago" +%F)

# if backing up to the local system disk please use an exclude statement of the specific directory
# otherwise the backups backups up the backup....recursion ahead!
backup_dir="/backup"
snapshot_dir="/snapshot"
snapshot_num="3"
use_snapshots=true
USE_DUPLICITY=false
DUPLICITY_BACKUP_DIR=""
USE_BORG=false
BORG_REPO=""
BORG_BACKUP_DIR=""

usage() {
cat << EOF
Benutzung:
	-h: this information / help
	-b: only run borgbackup (if activated)

Konfigurationsdatei /etc/archlinux-backup.conf:
                    --------------------------
 USE_BORG=true (to enable borgbackup)
 BORG_REPO="<where to search for the borgbackup archive>"
 BORG_BACKUP_DIR="<what directories to backup - space separated>"

 USE_DUPLICITY=true (to enable duplicity)
 DUPLICITY_BACKUP_DIR="file:///backup/duplicity"
 
 DEBUG=true (to enable debugging)
EOF
}

setup () {
 if [[ -f /etc/archlinux-backup.conf ]]; then
 	source /etc/archlinux-backup.conf
 fi
}

# oldest (~ highest number) snapshot will get purged
purge_oldest_snapshot () {
	if [ -d "$snapshot_dir/$snapshot_num" ]; then
		if [ -n "$DEBUG" ]; then echo "### DEBUG: SNAPshot: oldest (~ highest number) snapshot will get purged"; fi
		btrfs subvolume delete -v "$snapshot_dir/$snapshot_num"
	fi
	}

# rename the old/previous snapshot to subsequent numbers
rename_snapshots () {
	for i in $(seq $((--snapshot_num)) -1 0)
	do      
        	if [ -d "$snapshot_dir/$i" ]; then
			if [ -n "$DEBUG" ]; then echo "### DEBUG: SNAPshot: rotating $snapshot_dir/$i"; fi
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

run_duplicity () {
	echo "### duplicity backup -> $DUPLICITY_BACKUP_DIR"
	duplicity -v0 --no-encryption --exclude-other-filesystems --exclude /backup --full-if-older-than 1M / "$DUPLICITY_BACKUP_DIR"
	echo "### Deleting old duplicity sets (preserve 2 full backup chains)"
	duplicity --no-encryption remove-all-but-n-full 2 --force "$DUPLICITY_BACKUP_DIR"
}	

run_borg () {
	echo "#########################"
	echo "## BORGbackup - 24. July 2018"
	if [ "X$USE_BORG" = "Xtrue" ]; then
	echo "## \$USE_BORG is true - running borgbackup"
	if type borg > /dev/null 2>&1; then
		echo -n "## Starting at: "; date +%H:%M
		echo "### borg repo \$BORG_REPO: $BORG_REPO"
		echo "### borg backup directories \$BORG_BACKUP_DIR: $BORG_BACKUP_DIR" 
		if borg check --repository-only $BORG_REPO; then
			if [ -n "$DEBUG" ]; then echo "### DEBUG: borg create -s -e */nobackup/ $BORG_REPO::{now} $BORG_BACKUP_DIR" ; fi
			borg create -s -e "*/nobackup/" $BORG_REPO::{hostname}-{now} ${=BORG_BACKUP_DIR}
		else
			echo "### borgbackup failed..."
		fi
		echo "### borg repo: cleanup - 5 monthly - 14 daily"
		borg prune --dry-run --stats --list --keep-monthly 5 --keep-daily 14 "$BORG_REPO"
		echo "### borg repo: cleanup finished"
		echo -n "## Finished at: "; date +%H:%M
	else
		echo "## borgbackup not found - please install"
	fi
else
	echo "## \$USE_BORG is not set - skipping borgbackup"
fi
}

run_btrfs_snapshot () {
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
# create snapshot directory
 if ! [[ -d "$snapshot_dir" ]]; then
	mkdir "$snapshot_dir" && chmod 0750 "$snapshot_dir" && chown root:thalunil "$snapshot_dir"
 else
	chmod 0750 "$snapshot_dir" && chown root:thalunil "$snapshot_dir"
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
}

run_full () {
 echo "#########################"
 # archlinux specific
 # type pacman checks the return code to see if pacman is a valid invokable executable
 if [ -e "/etc/arch-release" ] && type pacman > /dev/null 2>&1; then
	echo "## archlinux: Dumping Pacman Package List - $backup_dir/pkglist.txt"
	pacman -Qqe > "$backup_dir/pkglist.txt"
 else
	echo "## archlinux: not a valid archlinux platform - skipping archlinux specifics"
 fi

 echo "#########################"
 if [ "X$USE_DUPLICITY" = "Xtrue" ]; then
	echo "## \$USE_DUPLICITY is true - running duplicity"
	if type duplicity > /dev/null 2>&1; then
		echo -n "### Starting at: "; date +%H:%M
		run_duplicity
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
	echo "## \$USE_DUPLICITY is not set - skipping duplicity"
fi

run_btrfs_snapshot

run_borg

echo "#########################"
echo "## local disk space"
df -h -x tmpfs
echo "#########################"
}

if [ $# = 0 ]; then; setup; run_full; exit; fi

case $1 in
	-h)
		usage
		;;
	-b)
		setup
		run_borg
		;;
	*)
		usage
		;;
esac
