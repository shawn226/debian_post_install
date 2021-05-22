#!/bin/bash

set -e

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

# Modification de Grub
sed -i 's/quiet/vga=791/' /etc/default/grub
sed -i 's/=5/=20/' /etc/default/grub
sed -i '$a set superusers="grubroot"' /etc/grub.d/40_custom

grub_mdp_hash='echo -e "root\root"| grub-mkpassword-pbkdf2| tail -1| cut -d " " -f9'

sed -i '$a password_pbkdf2 grub HASH' /etc/grub.d/40_custom
sed -i '/HASH/s/HASH/$grub_mdp_hash/' /etc/grub.d/40_custom

sed -i 's/--class os/--class os --unrestricted/g' /etc/grub.d/10_linux
update-grub

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

# On modifie le sshd config
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
systemctl restart sshd
chmod -v 640 /etc/ssh/sshd_config

# On desactive le dhcp pour du static
sed -i 's/iface ens33 inet dhcp/auto ens33\
iface ens33 inet static/' /etc/network/interfaces

# On ajoute notre ip statique avec la gateway
echo "    address 192.168.1.18/24 
    gateway 192.168.1.1" >> /etc/network/interfaces

# On redémarre le service
systemctl restart networking


###########################################
## Configuration des droits des fichiers ##
###########################################

# Fichiers configuration hosts
chmod -v 600 /etc/host*

# Fichiers passwd
chmod -v 600 /etc/passwd*

# Fichier qui contient les terminaux sur lesquels root peut se log
chmod -v 600 /etc/securetty

# Fichiers politique sécurité
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

# Tous les fichiers du /etc en lecture sont maintenant visible que par root

#for FILE in /etc/*;
#do
#	if [[ $(stat -c "%a" $FILE) = "644" ]];
#	then
		# chmod -v 600 $FILE
#	fi
#done

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

# On fait un scan sur la racine
#clamscan -r /
sleep 2






