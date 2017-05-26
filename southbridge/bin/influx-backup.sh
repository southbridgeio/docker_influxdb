#!/bin/bash
set -e
#
# InfluxDB Backup Script
# VER. 0.1
# More Info: http://github.com/micahwedemeyer/automongobackup
#=====================================================================
#=====================================================================
# Set the following variables to your system needs
# (Detailed instructions below variables)
#=====================================================================

# External config - override default values set below
EXTERNAL_CONFIG="/srv/southbridge/etc/influx-backup.conf" # centos style

# Host name (or IP address) of influx server e.g localhost
DBHOST="localhost"

# Port that influx is listening on
DBPORT="8088"

# Backup directory location e.g /backups
BACKUPDIR="/var/backups/influxdb"

# Whether should I explicitly dump metastore
# for more info see: https://docs.influxdata.com/influxdb/v1.2/administration/backup_and_restore/
BACKUP_METASTORE=true

# List of dbs to backup
# if 'all' specified will backup all found databases
BACKUP_DBS='all'

# Mail setup
# What would you like to be mailed to you?
# - log : send only log file
# - files : send log file and sql files as attachments (see docs)
# - stdout : will simply output the log to the screen if run manually.
# - quiet : Only send logs if an error occurs to the MAILADDR.
MAILCONTENT="quiet"

# Set the maximum allowed email size in k. (4000 = approx 5MB email [see docs])
MAXATTSIZE="4000"

# Email Address to send mail to? (user@domain.com)
MAILADDR="root"

# ============================================================
# === ADVANCED OPTIONS ( Read the doc's below for details )===
#=============================================================

# Which day do you want weekly backups? (1 to 7 where 1 is Monday)
DOWEEKLY=6

# Choose Compression type. (gzip or bzip2)
COMP="gzip"

# Choose if the uncompressed folder should be deleted after compression has completed
CLEANUP="yes"

# Additionally keep a copy of the most recent backup in a seperate directory.
LATEST="yes"

# Make Hardlink not a copy
LATESTLINK="yes"

# Command to run before backups (uncomment to use)
# PREBACKUP=""

# Command run after backups (uncomment to use)
# POSTBACKUP=""

# === Advanced options ===
#
# To set the day of the week that you would like the weekly backup to happen
# set the DOWEEKLY setting, this can be a value from 1 to 7 where 1 is Monday,
# The default is 6 which means that weekly backups are done on a Saturday.
#
# Use PREBACKUP and POSTBACKUP to specify Pre and Post backup commands
# or scripts to perform tasks either before or after the backup process.
#=====================================================================
# Backup Rotation..
#=====================================================================
#
# Daily Backups are rotated weekly.
#
# Weekly Backups are run by default on Saturday Morning when
# cron.daily scripts are run. This can be changed with DOWEEKLY setting.
#
# Weekly Backups are rotated on a 5 week cycle.
# Monthly Backups are run on the 1st of the month.
# Monthly Backups are NOT rotated automatically.
#
# It may be a good idea to copy Monthly backups offline or to another
# server.
#
#=====================================================================
# Please Note!!
#=====================================================================
#
# I take no resposibility for any data loss or corruption when using
# this script.
#
# This script will not help in the event of a hard drive crash. You
# should copy your backups offline or to another PC for best protection.
#
# Happy backing up!
#
#=====================================================================

# Should not need to be modified from here down!!
#

if [ ! -f "/root/.influxdb" ]; then
	exit;
fi

# Include external config
#[ ! -z "$EXTERNAL_CONFIG" ] && [ -f "$EXTERNAL_CONFIG" ] && source "${EXTERNAL_CONFIG}"
# Include extra config file if specified on commandline, e.g. for backuping several remote dbs from central server
#[ ! -z "$1" ] && [ -f "$1" ] && source ${1}

#=====================================================================

PATH=/usr/local/bin:/usr/bin:/bin
DATE=`date +%Y-%m-%d_%Hh%Mm` # Datestamp e.g 2002-09-21
DOW=`date +%A` # Day of the week e.g. Monday
DNOW=`date +%u` # Day number of the week 1 to 7 where 1 represents Monday
DOM=`date +%d` # Date of the Month e.g. 27
M=`date +%B` # Month e.g January
W=`date +%V` # Week Number e.g 37
VER=0.9 # Version Number
BACKUPFILES=""
OPT="" # OPT string for use with influxdump
LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."

if [ -f "$LOCATION/etc/influx-backup.conf.dist" ]; then
    . "$LOCATION/etc/influx-backup.conf.dist"
    if [ -f "$LOCATION/etc/influx-backup.conf" ]; then
	. "$LOCATION/etc/influx-backup.conf"
    fi
else
    echo "influx-backup.conf.dist not found"
    exit 0
fi

if [ ! "$NICE" ]; then
  NICE=20
fi
if [ -x /usr/bin/nice ]; then
  NICE_CMD="/usr/bin/nice -n $NICE"
else
  NICE_CMD=""
fi

# Create required directories
if [ ! -e "$BACKUPDIR" ] # Check Backup Directory exists.
    then
    mkdir -p "$BACKUPDIR"
fi

if [ ! -e "$BACKUPDIR/daily" ] # Check Daily Directory exists.
    then
    mkdir -p "$BACKUPDIR/daily"
fi

if [ ! -e "$BACKUPDIR/weekly" ] # Check Weekly Directory exists.
    then
    mkdir -p "$BACKUPDIR/weekly"
fi

if [ ! -e "$BACKUPDIR/monthly" ] # Check Monthly Directory exists.
    then
    mkdir -p "$BACKUPDIR/monthly"
fi

if [ "$LATEST" = "yes" ]
    then
    if [ ! -e "$BACKUPDIR/latest" ] # Check Latest Directory exists.
	      then
       	mkdir -p "$BACKUPDIR/latest"
    fi
    eval rm -f "$BACKUPDIR/latest/*"
fi


# Functions

# Database dump function
dbdump () {
  if ${BACKUP_METASTORE} ; then
    influxd backup "${1}/metastore"
  fi

  if [ "x${BACKUP_DBS}" == "xall" ]; then
    BACKUP_DBS=$(influx -execute 'SHOW DATABASES' | tail -n+4 | tr '\n' ' ')
  fi

  for db in ${BACKUP_DBS}; do
    influxd backup -database "${db}" "${1}/${db}"
  done

#  if [ "$DO_HOT_BACKUP" = "yes" ]; then
#	  $NICE_CMD influx admin $LOCATION/etc/influxdb_backup.js
#	  [ -e "$1" ] && return 0
#	  echo "ERROR: influx failed to create hot backup: $1" >&2
#	  return 1
#  else
#	  $NICE_CMD influxdump --host=$DBHOST:$DBPORT --out=$1 #$OPT
#  	[ -e "$1" ] && return 0
#  	echo "ERROR: influxdump failed to create dumpfile: $1" >&2
#  	return 1
#  fi
}

# Compression function plus latest copy
SUFFIX=""
compression () {
  if [ "$COMP" = "gzip" ]; then
    SUFFIX=".tgz"
    echo Tar and gzip to "$2$SUFFIX"
    cd $1 && tar -cvzf "$2$SUFFIX" "$2"
  elif [ "$COMP" = "bzip2" ]; then
    SUFFIX=".tar.bz2"
    echo Tar and bzip2 to "$2$SUFFIX"
    cd $1 && tar -cvjf "$2$SUFFIX" "$2"
  else
    echo "No compression option set, check advanced settings"
  fi
  if [ "$LATEST" = "yes" ]; then
    if [ "$LATESTLINK" = "yes" ];then
    	COPY="cp -l"
    else
    	COPY="cp"
    fi
    $COPY $1$2$SUFFIX "$BACKUPDIR/latest/"
  fi
  if [ "$CLEANUP" = "yes" ]; then
    echo Cleaning up folder at "$1$2"
    rm -rf "$1$2"
  fi
  return 0
}

# Run command before we begin
if [ "$PREBACKUP" ]
then
echo ======================================================================
echo "Prebackup command output."
echo
eval $PREBACKUP
echo
echo ======================================================================
echo
fi

# Hostname for LOG information
if [ "$DBHOST" = "localhost" ]; then
    HOST=`hostname`
else
    HOST=$DBHOST
fi

echo
echo Backup of Database Server - $HOST on $DBHOST
echo ======================================================================

echo Backup Start `date`
echo ======================================================================
# Monthly Full Backup of all Databases
if [ $DOM = "01" ]; then
    echo Monthly Full Backup
    dbdump "$BACKUPDIR/monthly/$DATE.$M" &&
    compression "$BACKUPDIR/monthly/" "$DATE.$M"
echo ----------------------------------------------------------------------

# Weekly Backup
elif [ $DNOW = $DOWEEKLY ]; then
    echo Weekly Backup
    echo
    echo Rotating 5 weeks Backups...
if [ "$W" -le 05 ];then
    REMW=`expr 48 + $W`
elif [ "$W" -lt 15 ];then
    REMW=0`expr $W - 5`
else
    REMW=`expr $W - 5`
fi

eval rm -f "$BACKUPDIR/weekly/week.$REMW.*"
echo
    dbdump "$BACKUPDIR/weekly/week.$W.$DATE" &&
    compression "$BACKUPDIR/weekly/" "week.$W.$DATE"
echo ----------------------------------------------------------------------

# Daily Backup
else
echo Daily Backup of Databases
echo Rotating last weeks Backup...
echo
    eval rm -f "$BACKUPDIR/daily/*.$DOW.*"
echo
    dbdump "$BACKUPDIR/daily/$DATE.$DOW" &&
    compression "$BACKUPDIR/daily/" "$DATE.$DOW"
echo ----------------------------------------------------------------------
fi
echo Backup End Time `date`
echo ======================================================================

echo Total disk space used for backup storage..
echo Size - Location
echo `du -hs "$BACKUPDIR"`
echo
echo ======================================================================

# Run command when we're done
if [ "$POSTBACKUP" ]
then
echo ======================================================================
echo "Postbackup command output."
echo
eval $POSTBACKUP
echo
echo ======================================================================
fi