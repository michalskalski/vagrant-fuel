#!/bin/bash
function astute_config {
  f=${FUEL_VERSION%.*}
	case "$f" in
		9)    ubuntu=trusty;;
		10)   ubuntu=xenial;;
	esac
cat >/etc/fuel/astute.yaml <<EOF
"ADMIN_NETWORK":
  "cidr": "${ADMIN_NET}"
  "dhcp_gateway": "${DHCP_GW}"
  "dhcp_pool_end": "${DHCP_END}"
  "dhcp_pool_start": "${DHCP_START}"
  "interface": "eth1"
  "mac": "${ADMIN_MAC}"
  "ipaddress": "${FUEL_ADMIN_IP}"
  "netmask": "${FUEL_ADMIN_MASK}"
  "ssh_network": "0.0.0.0/0"
"BOOTSTRAP":
  "flavor": "ubuntu"
  "http_proxy": ""
  "https_proxy": ""
  "repos":
  - "name": "ubuntu"
    "priority": !!null "null"
    "section": "main universe multiverse"
    "suite": "${ubuntu}"
    "type": "deb"
    "uri": "http://archive.ubuntu.com/ubuntu"
  - "name": "ubuntu-updates"
    "priority": !!null "null"
    "section": "main universe multiverse"
    "suite": "${ubuntu}-updates"
    "type": "deb"
    "uri": "http://archive.ubuntu.com/ubuntu"
  - "name": "ubuntu-security"
    "priority": !!null "null"
    "section": "main universe multiverse"
    "suite": "${ubuntu}-security"
    "type": "deb"
    "uri": "http://archive.ubuntu.com/ubuntu"
  - "name": "mos"
    "priority": !!int "1050"
    "section": "main restricted"
    "suite": "mos${f}.0"
    "type": "deb"
    "uri": "http://mirror.fuel-infra.org/mos-repos/ubuntu/${f}.0"
  - "name": "mos-updates"
    "priority": !!int "1050"
    "section": "main restricted"
    "suite": "mos${f}.0-updates"
    "type": "deb"
    "uri": "http://mirror.fuel-infra.org/mos-repos/ubuntu/${f}.0"
  - "name": "mos-security"
    "priority": !!int "1050"
    "section": "main restricted"
    "suite": "mos${f}.0-security"
    "type": "deb"
    "uri": "http://mirror.fuel-infra.org/mos-repos/ubuntu/${f}.0"
  - "name": "mos-holdback"
    "priority": !!int "1100"
    "section": "main restricted"
    "suite": "mos${f}.0-holdback"
    "type": "deb"
    "uri": "http://mirror.fuel-infra.org/mos-repos/ubuntu/${f}.0"
  "skip_default_img_build": !!bool "false"
"DNS_DOMAIN": "domain.tld"
"DNS_SEARCH": "domain.tld"
"DNS_UPSTREAM": "${DNS_SERVER}"
"FEATURE_GROUPS":
- "experimental"
- "advanced"
"FUEL_ACCESS":
  "password": "admin"
  "user": "admin"
"HOSTNAME": "fuel"
"NTP1": "${NTP_1}"
"NTP2": "1.fuel.pool.ntp.org"
"NTP3": "2.fuel.pool.ntp.org"
"PRODUCTION": "docker"
"TEST_DNS": "www.google.com"
"astute":
  "password": "$(gen_password)"
  "user": "naily"
"cobbler":
  "password": "$(gen_password)"
  "user": "cobbler"
"keystone":
  "admin_token": "$(gen_password)"
  "monitord_password": "$(gen_password)"
  "monitord_user": "monitord"
  "nailgun_password": "$(gen_password)"
  "nailgun_user": "nailgun"
  "ostf_password": "$(gen_password)"
  "ostf_user": "ostf"
  "service_token_off": "true"
"mcollective":
  "password": "$(gen_password)"
  "user": "mcollective"
"postgres":
  "keystone_dbname": "keystone"
  "keystone_password": "$(gen_password)"
  "keystone_user": "keystone"
  "nailgun_dbname": "nailgun"
  "nailgun_password": "$(gen_password)"
  "nailgun_user": "nailgun"
  "ostf_dbname": "ostf"
  "ostf_password": "$(gen_password)"
  "ostf_user": "ostf"
EOF
}

function grow_disk {
  pvcreate /dev/vdb
  vgextend VolGroup00 /dev/vdb
  lvextend -l +100%FREE /dev/VolGroup00/LogVol00
  xfs_growfs /
}

function wait_for_config {
  pkill -0 -f wait_for_external_config
}
function kill_wait_for_config {
  pkill -f "^wait_for_external_config"
}

function gen_password {
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 15 | head -n 1
}

function get_current_snapshot {
  snapshot=$(curl http://mirror.fuel-infra.org/mos-repos/ubuntu/${FUEL_VERSION}.target.txt | head -n 1)
  echo "http://mirror.fuel-infra.org/mos-repos/ubuntu/${snapshot}"
}

function local_mirrors {
  if [ -z "$MOS_REPO" ]; then
    MOS_REPO=$(get_current_snapshot)
  fi

  sed -i "s|http://mirror.fuel-infra.org/mos-repos/ubuntu/\$mos_version|${MOS_REPO}|" /usr/share/fuel-mirror/ubuntu.yaml
  echo "Download mos packages"
  fuel-mirror create --group mos --pattern=ubuntu
  MIRROR_DIRECTORY=$(echo "${MOS_REPO}" | cut -d'/' -f4-)
  rm -rf /var/www/nailgun/mitaka-9.0/ubuntu/x86_64/
  mv /var/www/nailgun/mirrors/${MIRROR_DIRECTORY} /var/www/nailgun/mitaka-9.0/ubuntu/x86_64
  mkdir -p /var/www/nailgun/mitaka-9.0/ubuntu/x86_64/images
  touch /var/www/nailgun/mitaka-9.0/ubuntu/x86_64/images/initrd.gz
  touch /var/www/nailgun/mitaka-9.0/ubuntu/x86_64/images/linux
}

if [[ ! -z "${FUEL_ADMIN_NET_GW// }" ]]; then
  echo "GATEWAY=${FUEL_ADMIN_NET_GW}" > /etc/sysconfig/network
  systemctl restart network && sleep 5
  echo "nameserver ${DNS_SERVER}" > /etc/resolv.conf
fi

grow_disk
echo "root:r00tme" | chpasswd
yum install -y wget PyYAML net-tools
wget -O fuel-release.rpm ${RELEASE_RPM}
rpm -Uvh fuel-release.rpm
yum install -y fuel-setup
mkdir -p /etc/fuel
cat > /etc/fuel/bootstrap_admin_node.conf <<EOF
ADMIN_INTERFACE=eth0
showmenu=no
wait_for_external_config=yes
EOF

if [ "$FUEL_VERSION" = "9.1" ]; then
  yum install -y patch fuel-library9.0
  cp /home/vagrant/fuel_cobbler_9.1.patch /etc/puppet/modules/fuel_cobbler_9.1.patch
  pushd /etc/puppet/modules
  echo "Applying patch for cobbler: https://bugs.launchpad.net/fuel/+bug/1606181"
  patch -p3 < fuel_cobbler_9.1.patch
  popd
fi

echo "Start bootstraping admin node"
/usr/sbin/bootstrap_admin_node.sh > bootstrap.log 2>&1 & disown
BOOTSTRAP_PID=$!

echo "Wait until can inject own configuration"
WAIT_TIME=600
until wait_for_config || [ $WAIT_TIME -eq 0 ]; do
   sleep 1
   WAIT_TIME=$(( WAIT_TIME - 1 ))
done
echo "Inject configuration"
ADMIN_MAC=$(cat /sys/class/net/eth1/address)
astute_config
kill_wait_for_config
sleep 5
if [[ ! -z "${FUEL_ADMIN_NET_GW// }" ]]; then
  echo "nameserver ${DNS_SERVER}" > /etc/resolv.conf
fi
tail --pid ${BOOTSTRAP_PID} -n +1 -f bootstrap.log

if [[ "$FUEL_VERSION" =~ ^9.* ]]; then
  local_mirrors
else
  # Use external repos, there is no local copy
  fuel2 release repos update -f /home/vagrant/fuel10repos.json 2
fi
