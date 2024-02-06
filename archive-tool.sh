#!/usr/bin/env bash

usage() {
	cat <<EOUSAGE
Usage: $(basename "$0") {a|b} [-h] -t target_dir -n backup_name [-d source_dir] [-m max_backups] [files_to_backup...]
  -h: Show usage
  -a: Archive mode. For files already backed up by -a mode.
  -b: Backup mode.
  -t: The target directory the backup/archive file
  -d: The source directory containing the backup.
  -m: The maximum number of backups in the target directory for this file.
  files_to_backup: A list of files to be backed up in -b backup mode.

When in backup mode, a filename will be generated that follows the convention of chosen_name-YYYYMMDD-HHSS.N.tar.gz
Here, chosen_name is either supplied as an argument to -m, or the name of the target file if only one file is provided. N is the backup number, ranging from 0 to max_backups. If max_backups was not provided with -m, 10 is assumed.

When in archival mode, the filename is used to parse the file names in the source directory and find the backups for the given name. Only the most recent backup will be archived.

The intent is to have two or more cron jobs for backups and archives.
  1. Backup the target files regularly in -b mode (hourly)
  2. Archive some subset of backups sparsely (daily/weekly)

Examples:
  To backup file1 and file2 in /path/to/backups as backup-YYYYMMDD-HHMMSS.N.tar.gz, with a maximum of 5 redundant backups:
  $(basename "$0") -b -t /path/to/backups -m 5 -n backup /target/file1 /target/file2

  To archive an existing backup of "backup" into /archive/dir with a maximum of 4 redundant archive files:
  $(basename "$0") -a -d /path/to/backups -m 4 -n backup -t /path/to/archives

EOUSAGE
}

while getopts ":abhd:m:n:t:" o; do
	case "${o}" in
		a)
			archive_mode=true
			;;
		b)
			backup_mode=true
			;;
		d)
			source_dir=${OPTARG}
			;;
		h)
			usage
			exit 0
			;;
		m)
			max_backups=${OPTARG}
			;;
		n)
			backup_name=${OPTARG}
			;;
		t)
			target_dir=${OPTARG}
			;;
		*)
			echo "Unknown option $o"
			echo "Unknown option $OPTARG"
			usage
			exit 1
			;;
	esac
done

# Shift $@ to leftover args
shift $((OPTIND-1))

# Require archival or backup mode
if [[ -z $archive_mode && -z $backup_mode ]]; then
	echo "Specify either backup mode with -b or archive mode with -a"
	usage
	exit 1
fi

# Require source directory in archive mode
if [[ $archive_mode == "true" && ! -d $source_dir ]]; then
       usage
       exit 1
fi

# Target directory is required
if [[ -z "$target_dir" ]]; then
	echo "Specify a target directory."
	usage
	exit 1
fi


# If we are in archive mode, require a name
if [[ -z $backup_name ]]; then
	echo "An archive name must be supplied. Use something short and simple, the date and time will be appended."
	usage
	exit 1
fi

# Post shift, we can check if there are multiple files for archival.
# If there are, require a name for the backup.
if [[ $# > 1 && -z $backup_name ]]; then
	echo "A name must be supplied when more than one file is to be archived."
	echo "Specify a name with -n."
	usage
	exit 1
fi

## Set up variables
suffix=".tar.gz"

# $1 the name of the backup to be rotated
# $2 the directory containing the backup to be rotated
function rotate () {

	# Format for backups and archives:
	# name-YYYYMMDD-HHMMSS.N.tar.gz
	# Where N is the backup number, starting at 0.
	# "^$1-[0-9]{8}-[0-9]{6}\.[0-9]+$suffix$"

	# If $2 isn't a valid directory, fail.
	if [[ ! -d $2 ]]; then
		return 1
	fi
	
	# Remove the oldest backup if max_backups has been reached
	max_regex="^$1-[0-9]{8}-[0-9]{6}\.${max_backups}${suffix}$"
	max_file=$(ls $2 | grep -E $max_regex)
	if [[ ! -z $max_file ]]; then
		rm "$2/$max_file"
	fi

	for i in $(seq $(($max_backups-1)) -1 0); do
		backup_regex="^$1-[0-9]{8}-[0-9]{6}\.${i}${suffix}$"
		backup_file=$(ls $2 | grep -E $backup_regex)
		if [[ -f "$2/$backup_file" ]]; then
			new_filename="$(basename -- "$backup_file" ".${i}${suffix}").$(($i + 1))${suffix}"
			mv "$2/$backup_file" "$2/$new_filename"
		fi
	done
}

if [[ $backup_mode == true ]]; then
	tar_args=""
	for f in $@; do
		if [[ ! -f $f && ! -d $f ]]; then
			echo "File/directory not found:"
			echo "$f"
			usage
			exit 1
		fi
		fullname=$(realpath $f)
		tar_args="$tar_args -C $(dirname $fullname) $(basename -- $fullname)"
	done
	echo "Backing up the following files:"
	echo "$@"
	echo "In the following directory:"
	echo "$(realpath $target_dir)"

	mkdir -p $target_dir

	rotate $backup_name $target_dir

	timestamp=$(date +%Y%m%d-%H%M%S)
	archive_name="$backup_name-$timestamp.0$suffix"
	tar -czvf "$target_dir/$archive_name" $tar_args

elif [[ $archive_mode == true ]]; then
	# TODO: Check the date stamp of the backup and the archive and make sure they do not match - abort if they do
	archive_regex="^$backup_name-[0-9]{8}-[0-9]{6}\.0${suffix}$"
	archive_file=$(ls $source_dir | grep -E $archive_regex)
	if [[ -z $archive_file ]]; then
		echo "A backup could not be found for $backup_name in $source_dir"
		usage
		exit 1
	fi

	mkdir -p $target_dir
	rotate $backup_name $target_dir
	cp "$source_dir/$archive_file" "$target_dir"
fi

