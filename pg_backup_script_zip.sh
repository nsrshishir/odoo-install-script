#!/bin/bash

#Backup Config information
today=$(date +"%m_%d_%Y")

#put no of days you want to save the backups for, 0 if want to save all
daylimit=2

#Database information
db_user="odoo"
db_name="db_name"
bkup_filename=$db_name"_backup_"$today
db_dump_filename="dump.sql"

#Source Host information
src_bkup_loc="/odoo/db_backup/"
src_filestore_loc="/odoo/.local/share/Odoo/filestore/"
abs_bkup_filename=$src_bkup_loc$bkup_filename".zip"
src_filestore_bak_loc=$src_bkup_loc"filestore"

#Destination Host information
dest_bkup_loc="/dest/db_backup/"
dest_filestore=$dest_bkup_loc$db_name"_filestore"
dest_host="Host_address"
dest_user="Username"
dest_pass="Password"

#Checking Source backup Directory, Creating one if doesnt exits
if [ ! -d $src_bkup_loc ]; then
    echo "Directory "$src_bkup_loc" does not exist! Creating..."
    mkdir $src_bkup_loc
    echo "Setting Premission 777 to "$src_bkup_loc
    chmod 777 $src_bkup_loc
fi

if [ $daylimit -ne 0 ]; then
    find $src_bkup_loc -type f -mtime +$daylimit -delete
fi

#Checking Source backup file exist, Removing one if exits
if test -f $abs_bkup_filename; then
    rm $abs_bkup_filename
fi


#delete filestore folder if exists in source backup location if exists
if test -f $src_filestore_bak_loc; then
    rm -r $src_filestore_bak_loc
fi

#dumping database
sudo -u $db_user pg_dump --no-owner --no-privileges -f $src_bkup_loc$db_dump_filename $db_name

#Copping filestore
cp -r $src_filestore_loc$db_name $src_filestore_bak_loc


#Creating a tar.gz file with db dump and db filestores
# tar -czf $abs_bkup_filename -C $src_bkup_loc $db_dump_filename -C $src_filestore_loc $db_name
cd $src_bkup_loc
zip -r $abs_bkup_filename $db_dump_filename filestore

#removing dump.sql and filestores
sudo rm $src_bkup_loc$db_dump_filename
sudo rm -r $src_filestore_bak_loc



if [ $dest_user != "Host_address" ] && [ $dest_user != "Username" ] && [ $dest_pass != "Password" ]; then
    # sudo apt install sshpass
    #syncing databases
    rsync -a --delete -e "sshpass -p $dest_pass ssh -o StrictHostKeyChecking=no" $src_bkup_loc $dest_user@$dest_host:$dest_bkup_loc

    #syncing filestore
    # rsync -a -e "sshpass -p $dest_pass ssh -o StrictHostKeyChecking=no" $src_filestore $dest_user@$dest_host:$dest_filestore
fi
