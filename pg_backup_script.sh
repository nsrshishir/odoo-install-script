#!/bin/bash

#Backup Config information
today=$(date +"%m_%d_%Y")

#put no of days you want to save the backups for, 0 if want to save all
daylimit=2

#Database information
db_name="db_name"
filename=$db_name"_backup_$today"

#Source Host information
src_bkup_loc="/odoo/db_backup/"
src_filestore="/Odoo/filestore/"

#Destination Host information
dest_bkup_loc="/dest/db_backup/"
dest_filestore=$dest_bkup_loc$db_name"_filestore"
dest_host="Host_address"
dest_user="Username"
dest_pass="Password"

#Checking Source backup Directory, Creating one if doesnt exits
if [ ! -d $src_bkup_loc ]; then
    echo "Directory "$src_bkup_loc" does not exist!"
    mkdir $src_bkup_loc
fi

if [ $daylimit -ne 0 ]; then
    find $src_bkup_loc -type f -mtime +$daylimit -delete
fi

#Checking Source backup file exist, Removing one if exits
if test -f "$src_bkup_loc$filename"; then
    rm "$src_bkup_loc$filename"
fi

#dumping database
sudo -u postgres pg_dump -Fc -f $src_bkup_loc$filename".dump" $db_name
tar -czf $src_bkup_loc$filename".tar.gz" -C $src_bkup_loc $filename".dump" -C $src_filestore_loc $db_name

sudo rm $src_bkup_loc$filename".dump"


if [ $dest_user != "Host_address" ] && [ $dest_user != "Username" ] && [ $WEBSITE_NAME != "Password" ]; then
    # sudo apt install sshpass
    #syncing databases
    rsync -a -e "sshpass -p $dest_pass ssh -o StrictHostKeyChecking=no" $src_bkup_loc $dest_user@$dest_host:$dest_bkup_loc


    #syncing filestore
    # rsync -a -e "sshpass -p $dest_pass ssh -o StrictHostKeyChecking=no" $src_filestore $dest_user@$dest_host:$dest_filestore
fi
