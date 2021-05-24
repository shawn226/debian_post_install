#!/bin/bash

set -e

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
	    iotop gnupg dnsutils grc ncdu p7zip-full -y

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
sed -i 's/iface $interface inet dhcp/auto $interface\
iface $interface inet static/' /etc/network/interfaces

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
sed -i 's/quiet/vga=791/' /etc/default/grub
sed -i 's/=5/=20/' /etc/default/grub
sed -i '$a set superusers="grubroot"' /etc/grub.d/40_custom

grub_mdp_hash='echo -e "root\root"| grub-mkpassword-pbkdf2| tail -1| cut -d " " -f9'

sed -i '$a password_pbkdf2 grub HASH' /etc/grub.d/40_custom
sed -i '/HASH/s/HASH/$grub_mdp_hash/' /etc/grub.d/40_custom

sed -i 's/--class os/--class os --unrestricted/g' /etc/grub.d/10_linux
update-grub



###########################
## Modification hostname ##
###########################
hostnamectl set-hostname wiki
echo wiki > /etc/hostname
sed -i 's/debian/wiki.esgi.local wiki' /etc/hosts



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
useradd -u 10000 -g 10000 -m -s /bin/bash esgi
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

mkdir -p /var/jail/{dev,etc,lib,lib64,usr,bin}

mkdir -p /var/jail/usr/bin

chown root:root /var/jail

mknod -m 666 /var/jail/dev/null c 1 3

cp /etc/ld.so.cache /var/jail/etc/
cp /etc/ld.so.conf /var/jail/etc/
cp /etc/nsswitch.conf /var/jail/etc/
cp /etc/hosts /var/jail/etc/

cp /usr/bin/ls /var/jail/usr/bin/
cp /usr/bin/cat /var/jail/usr/bin/
cp /bin/bash /var/jail/bin/
cp /usr/bin/rm /var/jail/usr/bin/
cp /usr/bin/touch /var/jail/usr/bin/
cp /usr/bin/vim /var/jail/usr/bin/

# ldd ls
mkdir -p /var/jail/lib/x86_64-linux-gnu/ && cp /lib/x86_64-linux-gnu/libselinux.so.1 $_
cp /lib/x86_64-linux-gnu/libc.so.6 /var/jail/lib/x86_64-linux-gnu/libc.so.6
cp /lib/x86_64-linux-gnu/libpcre.so.3 /var/jail/lib/x86_64-linux-gnu/libpcre.so.3
cp /lib/x86_64-linux-gnu/libdl.so.2 /var/jail/lib/x86_64-linux-gnu/libdl.so.2
cp /lib64/ld-linux-x86-64.so.2 /var/jail/lib64/ld-linux-x86-64.so.2
cp /lib/x86_64-linux-gnu/libpthread.so.0 /var/jail/lib/x86_64-linux-gnu/libpthread.so.0

# ldd bash
cp /lib/x86_64-linux-gnu/libtinfo.so.6 /var/jail/lib/x86_64-linux-gnu/libtinfo.so.6

# ldd vim
cp /lib/x86_64-linux-gnu/libm.so.6 /var/jail/lib/x86_64-linux-gnu/libm.so.6
cp /lib/x86_64-linux-gnu/libselinux.so.1 /var/jail/lib/x86_64-linux-gnu/libselinux.so.1
cp /lib/x86_64-linux-gnu/libacl.so.1 /var/jail/lib/x86_64-linux-gnu/libacl.so.1
cp /lib/x86_64-linux-gnu/libgpm.so.2 /var/jail/lib/x86_64-linux-gnu/libgpm.so.2
cp /lib/x86_64-linux-gnu/libpcre.so.3 /var/jail/lib/x86_64-linux-gnu/libpcre.so.3
cp /lib/x86_64-linux-gnu/libattr.so.1 /var/jail/lib/x86_64-linux-gnu/libattr.so.1

echo "Match user shawn
	ChrootDirectory /var/jail/
	X11Forwarding no
	AllowTcpForwarding no" >> /etc/ssh/sshd_config



#############################
## cryptsetup du lv coffre ##
#############################
cryptsetup -q -v -s 512 -c aes-xts-plain64 -h sha512 luksFormat /dev/VGCRYPT/lv_coffre

cryptsetup luksOpen /dev/VGCRYPT/lv_coffre lv_coffrecrypt

mkfs.xfs /dev/mapper/lv_coffrecrypt

mount /dev/mapper/lv_coffrecrypt /home/COFFRE

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

# On installe zsh et on le met en shell par défaut
apt install zsh -y
chsh -s $(which zsh)

# On télécharge et installe oh-my-zsh
echo "" |sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# On modifie le sshd config
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
systemctl restart sshd
chmod -v 640 /etc/ssh/sshd_config







