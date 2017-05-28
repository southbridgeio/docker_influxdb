#!/bin/bash
set -e
#
# InfluxDB Backup Script
# VER. 0.2
#=====================================================================
#=====================================================================
# Set the following variables to your system needs
# (Detailed instructions below variables)
#=====================================================================

# External config - override default values set below
EXTERNAL_CONFIG="/srv/southbridge/etc/influxdb-backup.conf" # centos style

# Host name (or IP address) of influx server e.g localhost
DBHOST="localhost"

# Port that influx is listening on
DBPORT="8088"
DBPORTI="8086"

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
VER=0.9.0.11-sb # Version Number
LOGFILE=$BACKUPDIR/$DBHOST-`date +%N`.log # Logfile Name
LOGERR=$BACKUPDIR/ERRORS_$DBHOST-`date +%N`.log # Logfile Name
BACKUPFILES=""
OPT="" # OPT string for use with influxdump
OPTI="" # OPT string for use with influxdump
LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."
#"

if [ -f "$LOCATION/etc/influxdb-backup.conf.dist" ]; then
    . "$LOCATION/etc/influxdb-backup.conf.dist"
    if [ -f "$LOCATION/etc/influxdb-backup.conf" ]; then
	. "$LOCATION/etc/influxdb-backup.conf"
    fi
else
    echo "influxdb-backup.conf.dist not found"
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

# IO redirection for logging.
touch $LOGFILE
exec 6>&1 # Link file descriptor #6 with stdout.
                    # Saves stdout.
exec > $LOGFILE # stdout replaced with file $LOGFILE.

touch $LOGERR
exec 7>&2 # Link file descriptor #7 with stderr.
                    # Saves stderr.
exec 2> $LOGERR # stderr replaced with file $LOGERR.

# When a desire is to receive log via e-mail then we close stdout and stderr.
[ "x$MAILCONTENT" == "xlog" ] && exec 6>&- 7>&-

# Functions

# Database dump function
dbdump () {
  if ${BACKUP_METASTORE} ; then
    influxd backup $OPT "${1}/metastore"
  fi

  if [ "x${BACKUP_DBS}" == "xall" ]; then
    BACKUP_DBS=$(influx $OPTI -execute 'SHOW DATABASES' | tail -n+4 | tr '\n' ' ')
  fi

  for db in ${BACKUP_DBS}; do
    influxd backup $OPT -database "${db}" "${1}/${db}"
  done

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
    OPT=$OPT" -host $DBHOST:$DBPORT "
    OPTI=$OPTI" -host $DBHOST:$DBPORTI "
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
    if [[ $BACKUP_MONTH -ge 0 ]] ; then
      NUM_OLD_FILES=$(find $BACKUPDIR/monthly -depth -not -newermt "$BACKUP_MONTH month ago" -type f | wc -l)
      if [[ $NUM_OLD_FILES -gt 0 ]] ; then
        echo Deleting "$NUM_OLD_FILES" global setting backup file\(s\) older than "$BACKUP_MONTH" month\(s\) old.
        find $BACKUPDIR/monthly -not -newermt "$BACKUP_MONTH month ago" -type f -delete
      fi
    fi
    dbdump "$BACKUPDIR/monthly/$DATE.$M" &&  compression "$BACKUPDIR/monthly/" "$DATE.$M"
echo ----------------------------------------------------------------------

# Weekly Backup
elif [ $DNOW = $DOWEEKLY ]; then
    echo Weekly Backup
    echo
    if [[ $BACKUP_WEEKS -ge 0 ]] ; then
      NUM_OLD_FILES=$(find $BACKUPDIR/weekly -depth -not -newermt "$BACKUP_WEEKS week ago" -type f | wc -l)
      if [[ $NUM_OLD_FILES -gt 0 ]] ; then
        echo Deleting "$NUM_OLD_FILES" global setting backup file\(s\) older than "$BACKUP_WEEKS" week\(s\) old.
        find $BACKUPDIR/weekly -not -newermt "$BACKUP_WEEKS week ago" -type f -delete
      fi
    fi
    dbdump "$BACKUPDIR/weekly/week.$W.$DATE" &&  compression "$BACKUPDIR/weekly/" "week.$W.$DATE"
echo ----------------------------------------------------------------------

# Daily Backup
else
echo Daily Backup of Databases
echo
    if [[ $BACKUP_DAYS -ge 0 ]] ; then
      NUM_OLD_FILES=$(find $BACKUPDIR/daily -depth -not -newermt "$BACKUP_DAYS days ago" -type f | wc -l)
      if [[ $NUM_OLD_FILES -gt 0 ]] ; then
        echo Deleting "$NUM_OLD_FILES" global setting backup file\(s\) older than "$BACKUP_DAYS" day\(s\) old.
        find $BACKUPDIR/weekly -not -newermt "$BACKUP_DAYS days ago" -type f -delete
      fi
    fi
    dbdump "$BACKUPDIR/daily/$DATE.$DOW" &&  compression "$BACKUPDIR/daily/" "$DATE.$DOW"
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

# Clean up IO redirection if we plan not to deliver log via e-mail.
[ ! "x$MAILCONTENT" == "xlog" ] && exec 1>&6 2>&7 6>&- 7>&-
#if [ -s "$LOGERR" ]
#    then
#    sed -i "/^connected/d" "$LOGERR"
#    sed -i "/writing/d" "$LOGERR"
#    sed -i "/done/d" "$LOGERR"
#    sed -i "/dumped .* oplog entries/d" "$LOGERR"
#    sed -i "/error getting oplog start/d" "$LOGERR"
#fi

if [ "$MAILCONTENT" = "log" ]
    then
    cat "$LOGFILE" | mail -s "Mongo Backup Log for $HOST - $DATE" $MAILADDR
    if [ -s "$LOGERR" ]; then
            cat "$LOGERR"
            (cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: Mongo Backup error Log for $HOST - $DATE" $MAILADDR
    fi

elif [ "$MAILCONTENT" = "quiet" ]
    then
    if [ -s "$LOGERR" ]
    then
        (cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: MongoDB Backup error Log for $HOST - $DATE" $MAILADDR
        cat "$LOGFILE" | mail -s "MongoDB Backup Log for $HOST - $DATE" $MAILADDR
    fi
else
    if [ -s "$LOGERR" ]
        then
        cat "$LOGFILE"
        echo
        echo "###### WARNING ######"
        echo "STDERR written to during mongodump execution."
        echo "The backup probably succeeded, as mongodump sometimes writes to STDERR, but you may wish to scan the error log below:"
        cat "$LOGERR"
    else
        cat "$LOGFILE"
    fi
fi

# TODO: Would be nice to know if there were any *actual* errors in the $LOGERR
STATUS=0
if [ -s "$LOGERR" ]; then
  STATUS=1
fi
# Clean up Logfile
eval rm -f "$LOGFILE"
eval rm -f "$LOGERR"

exit $STATUS
