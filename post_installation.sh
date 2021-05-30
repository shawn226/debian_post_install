#!/bin/bash

#set -e

###################
## Les fonctions ##
###################
get_ip_valid(){
  local error=1

  while [[ $error = 1 ]]
  do
    read -p "Entrez une adresse IP (exemple 10.0.0.0): " ip_address

    if [[ $ip_address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
    then
      error=0
    else
      echo "Veuillez choisir une adresse ip valide!" >&2 #On redirige vers la sortie d'erreur
    fi
  done

  echo $ip_address
}

get_pub_key(){
  local error=1

  while [[ $error = 1 ]]
  do
    read -p "Veuillez coller votre clé publique RSA : " pub_key

    if [[ $pub_key =~ ^(ssh-rsa AAAA[0-9A-Za-z+/]+[=]{0,3}( [^@]+@[^@]+)?)$ ]]
    then
      error=0
    else
      echo "Veuillez entrer une clé publique valide!" >&2
    fi
  done

  echo $pub_key
}



##############################
## Installation des paquets ##
##############################
# On set la timezone pour être toujours à l'heure
apt install ntp ntpdate -y
timedatectl set-timezone Europe/Paris
echo "server 0.fr.pool.ntp.org" >> /etc/ntp.conf
echo "server 1.fr.pool.ntp.org" >> /etc/ntp.conf
service ntp stop
ntpdate pool.ntp.org 
service ntp start

apt update -y
apt upgrade -y

apt autoremove task-laptop -y
apt remove telnet -y

apt install vim sudo curl rsync net-tools zip git htop dstat \
	    pigz pixz psmisc clamav tree lynx sshfs tmux screen \
	    mlocate at jq hddtemp lshw inxi figlet \
	    gdisk mc cifs-utils ntfs-3g iptraf psmisc wajig \
	    iotop pv gnupg dnsutils grc ncdu p7zip-full -y

apt clean -y



#############################
## Configuration du réseau ##
#############################
echo "----------------------------------------"
echo "Configuration du réseau"
echo "----------------------------------------"
echo "Entrez l'IP de cette machine"
addr=$(get_ip_valid)

echo "Entrez la gateway"
gateway=$(get_ip_valid)

interface=$(ip address show | grep "^[^,\d]:" | grep -v "lo" | cut -d " " -f 2 | cut -d : -f 1)
# On désactive le dhcp pour du static
sed -i "s/iface $interface inet dhcp/auto $interface\niface $interface inet static/" /etc/network/interfaces

# On ajoute notre ip statique avec la gateway
echo "    address $addr/24
    gateway $gateway" >> /etc/network/interfaces

# On flush la carte réseau
ip a flush $interface
# On redémarre le service
systemctl restart networking



##########################
## Modification de Grub ##
##########################

sed -i '$a set superusers="grubroot"' /etc/grub.d/40_custom
grub_mdp_hash='echo -e "root\nroot"| grub-mkpassword-pbkdf2| tail -1| cut -d " " -f9'

sed -i '$a password_pbkdf2 grub HASH' /etc/grub.d/40_custom
sed -i '/HASH/s/HASH/$grub_mdp_hash/' /etc/grub.d/40_custom

sed -i 's/--class os/--class os --unrestricted/g' /etc/grub.d/10_linux

sed -i 's/quiet/vga=791/' /etc/default/grub
sed -i 's/=5/=20/' /etc/default/grub

update-grub



###########################
## Modification hostname ##
###########################
hostnamectl set-hostname wiki
echo wiki > /etc/hostname
sed -i 's/debian/wiki.esgi.local wiki/' /etc/hosts



#################
## Service SSH ##
#################
echo "----------------------------------------"
echo "Création des clés SSH pour le compte root"
echo "----------------------------------------"
mkdir -p ~/.ssh
chmod -v 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -q -N ""
echo "done!"

echo "----------------------------------------"
echo "Création des clés SSH pour le simple user"
echo "----------------------------------------"
user=$(grep 1000 /etc/passwd|cut -d: -f1)
mkdir -v -p /home/$user/.ssh
chmod -v 700 /home/$user/.ssh
ssh-keygen -t ed25519 -f /home/$user/.ssh/id_ed25519 -q -N ""
usermod -aG sudo $user
chmod -v 700 /home/$user
echo "done!"

echo "----------------------------------------"
echo "Création d'un user pour le prof"
echo "----------------------------------------"
# Création du user "esgi"
groupadd -g 10000 esgi
useradd -u 10000 -g 10000 -m -s /bin/zsh esgi
echo -e "P@ssword\nP@ssword" |passwd esgi
usermod -aG sudo esgi
mkdir -v /home/esgi/.ssh
chmod -v 700 /home/esgi/.ssh
ssh-keygen -t ed25519 -f /home/esgi/.ssh/id_ed25519 -q -N ""
chmod -v 700 /home/esgi
echo "done!"


# On définit vim comme editor principal
ln -sfvn /usr/bin/vim.basic /etc/alternatives/editor




######################
## Creation du MOTD ##
######################
# On supprime le fichier 10-uname

rm /etc/update-motd.d/10-uname

# Création du fichier de couleurs
echo "NONE=\"\\033[m\"
WHITE=\"\\033[1;37m\"
GREEN=\"\\033[1;32m\"
RED=\"\\033[0;32;31m\"
YELLOW=\"\\033[1;33m\"
BLUE=\"\\033[34m\"
CYAN=\"\\033[36m\"
LIGHT_GREEN=\"\\033[1;32m\"
LIGHT_RED=\"\\033[1;31m\"" > /etc/update-motd.d/colors

echo "#!/bin/bash
printf \"\n\"
figlet \" \" $(hostname -s)
printf \"\n\"" > /etc/update-motd.d/00-hostname

echo "#!/bin/bash
. /etc/update-motd.d/colors

[ -r /etc/update-motd.d/lsb-release ] && . /etc/update-motd.d/lsb-release

if [ -z \"\$DISTRIB_DESCRIPTION\" ] && [ -x /usr/bin/lsb_release ]; then
    # Fall back to using the very slow lsb_release utility
    DISTRIB_DESCRIPTION=\$(lsb_release -s -d)
fi

re='(.*\\()(.*)(\\).*)'
if [[ \$DISTRIB_DESCRIPTION =~ \$re ]]; then
    DISTRIB_DESCRIPTION=\$(printf \"%s%s%s%s%s\" \"\${BASH_REMATCH[1]}\" \"\${YELLOW}\" \"\${BASH_REMATCH[2]}\" \"\${NONE}\" \"\${BASH_REMATCH[3]}\")
fi

echo -e \"  \"\$DISTRIB_DESCRIPTION \"(kernel \"\$(uname -r)\")\n\"

# Update the information for next time
printf \"DISTRIB_DESCRIPTION=\\\"%s\\\"\" \"\$(lsb_release -s -d)\" > /etc/update-motd.d/lsb-release &"> /etc/update-motd.d/10-banner


echo "#!/bin/bash
proc=\`(echo \$(more /proc/cpuinfo | grep processor | wc -l ) \"x\" \$(more /proc/cpuinfo | grep 'model name' | uniq |awk -F\":\"  '{print \$2}') )\`
memfree=\`cat /proc/meminfo | grep MemFree | awk {'print \$2'}\`
memtotal=\`cat /proc/meminfo | grep MemTotal | awk {'print \$2'}\`
uptime=\`uptime -p\`
addrip=\`hostname -I | cut -d \" \" -f1\`
# Récupérer le loadavg
read one five fifteen rest < /proc/loadavg

# Affichage des variables
printf \"  Processeur : \$proc\"
printf \"\\n\"
printf \"  Charge CPU : \$one (1min) / \$five (5min) / \$fifteen (15min)\"
printf \"\\n\"
printf \"  Adresse IP : \$addrip\"
printf \"\\n\"
printf \"  RAM : \$((\$memfree/1024))MB libres / \$((\$memtotal/1024))MB\"
printf \"\\n\"
printf \"  Uptime : \$uptime\"
printf \"\n\"
printf \"\\n\"" > /etc/update-motd.d/20-sysinfo

# On rend les fichiers executables
chmod 755 /etc/update-motd.d/00-hostname
chmod 755 /etc/update-motd.d/10-banner
chmod 755 /etc/update-motd.d/20-sysinfo

# On supprime le motd actuel
rm /etc/motd
ln -s /var/run/motd /etc/motd



###########################################
## Configuration des droits des fichiers ##
###########################################

# Fichiers configuration hosts
chmod -v 600 /etc/host*

#Fichiers passwd
chmod -v 600 /etc/passwd*

# Fichier qui contient les terminaux sur lesquels root peut se log
chmod -v 600 /etc/securetty

#Fichiers politique sécurité
chmod -v 600 /etc/security/access.conf
chmod -v 600 /etc/security/group.conf
chmod -v 600 /etc/security/limits.conf
chmod -v 700 /etc/security/limits.d
chmod -v 600 /etc/security/namespace.conf
chmod -v 700 /etc/security/namespace.d
chmod -v 700 /etc/security/namespace.init
chmod -v 600 /etc/security/pam_env.conf
chmod -v 600 /etc/security/sepermit.conf
chmod -v 600 /etc/security/time.conf



##########################
## Unlock LUKS remotely ##
##########################
apt install -y dropbear-initramfs

sed -i "s/#DROPBEAR_OPTIONS=/DROPBEAR_OPTIONS=\"-I 180 -j -k -p 2222 -s\"/" /etc/dropbear-initramfs/config

echo "IP=$addr::$gateway:255.255.255.0:wiki" >> /etc/initramfs-tools/initramfs.conf

update-initramfs -u -v

user_pub_key=$(get_pub_key)

echo $user_pub_key > /etc/dropbear-initramfs/authorized_keys

update-initramfs -u



##########################
## chroot du user shawn ##
##########################
usermod -s /bin/sh shawn

CHROOT='/home/CHROOT'
mkdir $CHROOT
chown root:root $CHROOT

mkdir $CHROOT/dev

mknod -m 666 $CHROOT/dev/null c 1 3

mkdir -p $CHROOT/home/shawn

binaries=( /bin/{ls,cat,echo,rm,sh} /usr/bin/clear /usr/bin/vim)

for i in $( ldd ${binaries[@]} | grep -v dynamic | cut -d " " -f 3 | sed 's/://' | sort | uniq );
do
	echo $i
	cp --parents $i $CHROOT
done

# ARCH amd64
if [ -f /lib64/ld-linux-x86-64.so.2 ]; then
   cp --parents /lib64/ld-linux-x86-64.so.2 /$CHROOT
fi

# ARCH i386
if [ -f  /lib/ld-linux.so.2 ]; then
   cp --parents /lib/ld-linux.so.2 /$CHROOT
fi

echo "Match user shawn
	ChrootDirectory /home/CHROOT
	X11Forwarding no
	AllowTcpForwarding no" >> /etc/ssh/sshd_config

#############################
## cryptsetup du lv coffre ##
#############################
mkdir /home/COFFRE

umount /dev/VGCRYPT/lv_coffre
cryptsetup -q -v -s 512 -c aes-xts-plain64 -h sha512 --type luks2 luksFormat /dev/VGCRYPT/lv_coffre

cryptsetup luksOpen /dev/VGCRYPT/lv_coffre lv_coffrecrypt

pv -tpreb /dev/zero | dd of=/dev/VGCRYPT/lv_coffre bs=128M

mkfs.xfs /dev/mapper/lv_coffrecrypt

mount /dev/mapper/lv_coffrecrypt /home/COFFRE

sed -i '/\/dev\/mapper\/VGCRYPT-lv_coffre/d' /etc/fstab

########################
## création du coffre ##
########################

cd /home/COFFRE
mkdir CERTIFICAT ENVIRONNEMENT ENVIRONNEMENT/bash ENVIRONNEMENT/ksh ENVIRONNEMENT/zsh SECURITE SECURITE/fai2ban SECURITE/firewall SECURITE/supervision SERVEUR SERVEUR/apache SERVEUR/apache/CENTOS8 SERVEUR/apache/DEBIAN10 SERVEUR/bind SERVEUR/nginx SERVEUR/rsyslog SERVEUR/ssh


###########################
## installation de cheat ##
###########################
# On installe zsh et on le met en shell par défaut
apt install zsh -y
chsh -s $(which zsh)

wget https://github.com/cheat/cheat/releases/download/4.2.1/cheat-linux-amd64.gz

gunzip cheat-linux-amd64.gz
chmod +x cheat-linux-amd64

mv cheat-linux-amd64 /bin/cheat

yes | cheat

su shawn << EOF
yes | cheat
EOF

su esgi << EOF
yes | cheat
EOF


###############
## Bookstack ##
###############

apt install nginx php-fpm lynx net-tools php-tokenizer php-gd php-mysql php-xml mariadb-server php-curl composer -y | tee -a install.bookstack.log

mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"

mysql -e "FLUSH PRIVILEGES"

mysql --execute="
CREATE DATABASE IF NOT EXISTS bookstackdb DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
GRANT ALL PRIVILEGES ON bookstackdb.* TO 'bookstackuser'@'localhost' IDENTIFIED BY 'P@ssword' WITH GRANT OPTION;
FLUSH PRIVILEGES;
quit"

mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('P@ssword');FLUSH PRIVILEGES;"

systemctl enable mariadb

systemctl enable nginx

cat << '_EOF_' > /etc/nginx/sites-available/bookstack.conf
server {
  listen 80;
  listen [::]:80;

  server_name wiki.esgi.local;

  root /var/www/bookstack/public;

  index index.php index.html;

  location / {
    try_files $uri $uri/ /index.php?$query_string;
  }

  location ~ \.php$ {
    fastcgi_index index.php;
    try_files $uri =404;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass unix:/run/php/php7.3-fpm.sock;
  }
}
_EOF_



ln -s /etc/nginx/sites-available/bookstack.conf /etc/nginx/sites-enabled/

nginx -t

systemctl reload nginx.service
systemctl restart php7.3-fpm.service

cd /home/shawn
git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch

cd BookStack

echo "\n" |composer install --no-dev

mv /home/shawn/BookStack /var/www/bookstack
cd /var/www/bookstack
chmod -R 755 bootstrap/cache public/uploads storage

cp .env.example .env

sed -i.bak 's/APP_URL=.*$/APP_URL=wiki.esgi.local/' .env
sed -i.bak 's/DB_DATABASE=.*$/DB_DATABASE=bookstackdb/' .env
sed -i.bak 's/DB_USERNAME=.*$/DB_USERNAME=bookstackuser/' .env
sed -i.bak "s/DB_PASSWORD=.*\$/DB_PASSWORD=P@ssword/" .env

php artisan key:generate --force

php artisan migrate --force

chown -R www-data:www-data /var/www/bookstack

#################
## Secure apps ##
#################

#Fail2ban configuration
apt install fail2ban -y

systemctl enable fail2ban


# Configuration Clamav anti-virus
apt update && apt upgrade -y
apt-get install clamav clamav-daemon -y

systemctl stop clamav-freshclam
systemctl stop clamav-daemon.service

service clamav-daemon restart

# On met à jour la base antiviral 
freshclam



# On initialise le ClamAV daemon.
systemctl start clamav-daemon
systemctl start clamav-freshclam


###Configuration de apparmor

apt install apparmor-utils apparmor-profiles -y


#start profiles in complain mode
aa-complain /etc/apparmor.d/*


###########################################################################
## Changement du shell par zsh (à faire en dernier car arrête le script) ##
###########################################################################



# On télécharge et installe oh-my-zsh
echo "" |sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# On modifie le sshd config
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
systemctl restart sshd
chmod -v 640 /etc/ssh/sshd_config







