#!/bin/bash

#Backup Config information
TODAY=$(date +"%m_%d_%Y")

#Put the number of days you want to save the backups for, 0 if you want to save all
BACKUP_DAYS_LIMIT=2

#Database information
DB_USER="odoo"
OE_USER=$DB_USER
DB_NAME="db_name"
BACKUP_FILENAME=$DB_NAME"_backup_"$TODAY
DB_DUMP_FILENAME="dump.sql"

#Source Host information
SRC_BACKUP_LOC="/odoo/db_backup/"
SRC_FILESTORE_LOC="/odoo/.local/share/Odoo/filestore/"
ABS_BACKUP_FILENAME=$SRC_BACKUP_LOC$BACKUP_FILENAME".zip"
SRC_FILESTORE_BAK_LOC=$SRC_BACKUP_LOC"filestore"

#Destination Host information
DEST_BACKUP_LOC="/dest/db_backup/"
DEST_FILESTORE=$DEST_BACKUP_LOC$DB_NAME"_filestore"
DEST_HOST="Host_address"
DEST_USER="Username"
DEST_PASS="Password"

#Checking Source backup Directory, Creating one if doesnt exists
if [ ! -d $SRC_BACKUP_LOC ]; then
    echo "Directory "$SRC_BACKUP_LOC" does not exist! Creating..."
    mkdir $SRC_BACKUP_LOC
    echo "Setting correct permissions to "$SRC_BACKUP_LOC
    chmod 750 $SRC_BACKUP_LOC
    chown $OE_USER:$OE_USER $SRC_BACKUP_LOC
fi

if [ $BACKUP_DAYS_LIMIT -ne 0 ]; then
    find $SRC_BACKUP_LOC -type f -mtime +$BACKUP_DAYS_LIMIT -delete
fi

#Checking Source backup file exist, Removing one if exists
if test -f $ABS_BACKUP_FILENAME; then
    rm $ABS_BACKUP_FILENAME
fi

#Checking if zip package is installed
if ! dpkg -s zip; then
    echo "Zip package is not installed, installing..."
    sudo apt install zip -y
fi

#delete filestore folder if exists in source backup location if exists
if test -f $SRC_FILESTORE_BAK_LOC; then
    rm -r $SRC_FILESTORE_BAK_LOC
fi

#dumping database
sudo -u $DB_USER pg_dump --no-owner --no-privileges -f $SRC_BACKUP_LOC$db_dump_filename $DB_NAME

#Copping filestore
cp -r $SRC_FILESTORE_LOC$db_name $SRC_FILESTORE_BAK_LOC

#Creating a tar.gz file with db dump and db filestores
cd $SRC_BACKUP_LOC
zip -r $ABS_BACKUP_FILENAME $DB_DUMP_FILENAME filestore

#removing dump.sql and filestores
sudo rm $SRC_BACKUP_LOC$db_dump_filename

if [ $DEST_USER != "Host_address" ] && [ $DEST_USER != "Username" ] && [ $DEST_PASS != "Password" ]; then
    # sudo apt install sshpass
    #syncing databases
    rsync -a --delete -e "sshpass -p $DEST_PASS ssh -o StrictHostKeyChecking=no" $SRC_BACKUP_LOC $DEST_USER@$DEST_HOST:$DEST_BACKUP_LOC

    #syncing filestore
    # rsync -a -e "sshpass -p $DEST_PASS ssh -o StrictHostKeyChecking=no" $SRC_FILESTORE $DEST_USER@$DEST_HOST:$DEST_FILESTORE
fi

