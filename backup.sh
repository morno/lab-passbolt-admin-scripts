#! /bin/bash

# Be sure to set this variable to what your webserver user is. Typically it will be www-data or nginx
# webserver_user=

# Function to check and install lftp
check_install_lftp() {
    if ! command -v lftp &> /dev/null; then
        echo "Installing lftp..."
        # Add installation command based on the package manager of the operating system
        if command -v apt-get &> /dev/null; then
            sudo apt-get install -y lftp
        elif command -v yum &> /dev/null; then
            sudo yum install -y lftp
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm lftp
        else
            echo "Unsupported package manager. Please install lftp manually and rerun the script."
            exit 1
        fi
    fi
}

# Check and install lftp if not present
check_command "lftp"

if ! command -v mysqldump &> /dev/null; then
    echo "+------------------------------------------------------------------------------------------+"
    echo "|                         mysqldump is required to run this script                         |"
    echo "|           Try installing either mysql-server or mariadb-server to correct this           |"
    echo "+------------------------------------------------------------------------------------------+"
    exit
fi

# Set this to the location you'd like backups placed, be sure to leave off the trailing /
backup_dir="/tmp"
# If you want to change how the date is displayed edit this line
backup_dir_date="$backup_dir/backup-$(date +"%Y-%m-%d--%H-%M-%S")"
backup_file="$backup_dir/backup-$(date +"%Y-%m-%d--%H-%M-%S").tar.gz"

# FTP configuration
ftp_host="your_ftp_host"
ftp_user="your_ftp_user"
ftp_password="your_ftp_password"
ftp_remote_dir="/remote/directory"

# Function to upload file to FTP
upload_to_ftp() {
    local file_to_upload=$1
    lftp -u "$ftp_user","$ftp_password" "$ftp_host" <<EOF
    set ftp:ssl-allow no
    set ssl:verify-certificate no
    cd $ftp_remote_dir
    put $file_to_upload
    bye
EOF
}

if [ -f /.dockerenv ]; then
    echo "+------------------------------------------------------------------------------------------+"
    echo "Docker detected"
    echo "+------------------------------------------------------------------------------------------+"
    su -s /bin/bash -c "mkdir $backup_dir_date" www-data
    echo "Taking database backup and storing in $backup_dir_date"

    su -s /bin/bash -c "./bin/cake passbolt mysql_export --dir $backup_dir_date" www-data
    echo "+------------------------------------------------------------------------------------------+"
    echo "Copying /etc/environment to $backup_dir_date"
    echo "+------------------------------------------------------------------------------------------+"
    cp /etc/environment $backup_dir_date/.
else
    if [ -z ${webserver_user} ]; then
        echo "+------------------------------------------------------------------------------------------+"
        echo "|            You don't have the webserver_user set in the backup.sh file                   |"
        echo "|                  Please correct this and then re-run this script                         |"
        echo "+------------------------------------------------------------------------------------------+"
        exit
    fi
    echo "+------------------------------------------------------------------------------------------+"
    echo "Docker not detected"
    echo "+------------------------------------------------------------------------------------------+"
    su -s /bin/bash -c "mkdir $backup_dir_date" $webserver_user
    echo "Taking database backup and storing in $backup_dir_date"
    echo "+------------------------------------------------------------------------------------------+"
    su -s /bin/bash -c "/usr/share/php/passbolt/bin/cake passbolt mysql_export --dir $backup_dir_date" $webserver_user
    echo "+------------------------------------------------------------------------------------------+"
    echo "Copying /etc/passbolt/passbolt.php to $backup_dir_date"
    echo "+------------------------------------------------------------------------------------------+"
    cp /etc/passbolt/passbolt.php $backup_dir_date/.
fi

echo "Copying /etc/passbolt/gpg/serverkey_private.asc to $backup_dir_date"
echo "+------------------------------------------------------------------------------------------+"
cp /etc/passbolt/gpg/serverkey_private.asc $backup_dir_date/.
echo "Copying /etc/passbolt/gpg/serverkey.asc to $backup_dir_date"
echo "+------------------------------------------------------------------------------------------+"
cp /etc/passbolt/gpg/serverkey.asc $backup_dir_date/.
echo "Creating archive of $backup_dir_date"
echo "+------------------------------------------------------------------------------------------+"
tar -czvf "$backup_dir_date.tar.gz" -C "$backup_dir_date" .
echo "+------------------------------------------------------------------------------------------+"
echo "Cleaning up $backup_dir"
echo "+------------------------------------------------------------------------------------------+"
rm "$backup_dir_date"/*
rmdir "$backup_dir_date"

# Upload to FTP
echo "Uploading backup to FTP server..."
upload_to_ftp "$backup_file"

echo "Backup completed, you can find the file as $backup_file"
echo "+------------------------------------------------------------------------------------------+"
