#!/bin/bash

# Script for installing Web2py with Nginx and Uwsgi on Centos 5
# Created By Hutchinson
# Modified by spametki
# License: BSD

# It was originally posted in this web2py-users group thread:
# https://groups.google.com/forum/?fromgroups#!topic/web2py/O4c4Jfr18tM

# There are lots of subtleties of ownership, and one has to take care
# when installing python 2.7 not to stop the systems python2.4 from working.

# NOTE: The only thing that should need changing for
# each installation is the $BASEARCH (base architecture) of the machine.
# This is determined by doing uname -i. This is needed for the nginx installation.

# Retrieve base architecture
BASEARCH=$(uname -i)

echo 'Install development tools (it should take a while)'
yum install gcc gdbm-devel readline-devel ncurses-devel zlib-devel \
bzip2-devel sqlite-devel db4-devel openssl-devel tk-devel bluez-libs-devel

echo 'Install python 2.7 without overwriting python 2.4 (no, really, this will take a while too)'

VERSION=2.7.3
cd ~
curl -O http://www.python.org/ftp/python/2.7.3/Python-2.7.3.tgz
tar -xvfz Python-2.7.3.tgz
cd Python-2.7.3
./configure --prefix=/opt/python2.7 --with-threads --enable-shared
make

echo 'The altinstall ensures that python2.4 is left okay'
make altinstall
echo "/opt/python2.7/lib">/etc/ld.so.conf.d/opt-python2.7.conf
ldconfig

echo 'Create alias so that python 2.7 can be run with python2.7'
alias -p python2.7="/opt/python2.7/bin/python2.7"
ln -s /opt/python2.7/bin/python2.7 /usr/bin/python2.7

echo 'Install uwsgi'

version=uwsgi-1.2.3
cd ~
curl -O http://projects.unbit.it/downloads/$version.tar.gz
tar -zxvf $version.tar.gz
mkdir /opt/uwsgi-python
cp -R ./$version/* /opt/uwsgi-python/*
cd /opt/uwsgi-python

echo 'build using python 2.7'
python2.7 setup.py build
python2.7 uwsgiconfig.py --build
useradd uwsgi

echo 'Create and own uwsgi log'
# Note this log will need emptying from time to time

touch /var/log/uwsgi.log
chown uwsgi /var/log/uwsgi.log

echo 'Install web2py'

cd /opt
mkdir ./web-apps
cd ./web-apps
curl -O http://www.web2py.com/examples/static/web2py_src.zip
unzip web2py_src.zip

echo 'Set the ownership for web2py application to uwsgi'
cd /opt/web-apps/web2py
chown -R uwsgi /opt/web-apps/web2py
chmod -R u+rwx ./applications

echo 'Now install nginx'
cd /etc/yum.repos.d
echo "[nginx]">nginx.repo

echo "baseurl=http://nginx.org/packages/centos/5/$BASEARCH/">>nginx.repo
echo "gpgcheck=0">>nginx.repo
echo "enabled=1">>nginx.repo
yum install nginx

echo "We don't want the defaults, so remove them"
cd /etc/nginx/conf.d
mv default.conf default.conf.o
mv example_ssl.conf example_ssl.conf.o

echo '
The following configuration files are also needed
The options for uwsgi are in the following file.
Other options could be included.
'

echo 'uwsgi_for_nginx.conf'

echo '
[uwsgi]
uuid=uwsgi
pythonpath = /opt/web-apps/web2py
module = wsgihandler
socket=127.0.0.1:9001
harakiri 60
harakiri-verbose
enable-threads
daemonize = /var/log/uwsgi.log
' > /opt/uwsgi-python/uwsgi_for_nginx.conf

chmod 755 /opt/uwsgi-python/uwsgi_for_nginx.conf

echo '
The next configuration file is for nginx, and goes in /etc/nginx/conf.d
It serves the static directory of applications directly. I have not set up
ssl because I access web2py admin by using ssh tunneling and the web2py rocket server.
It should be straightforward to set up the ssl server however.
'

echo 'web2py.conf'

echo '
server {
  listen 80;
  server_name $hostname;
  location ~* /(\w+)/static/ {
    root /opt/web-apps/web2py/applications/;
  }
  location / {
    uwsgi_pass 127.0.0.1:9001;
    include uwsgi_params;
  }
}

server {
  listen 443;
  server_name $hostname;
  ssl on;
  ssl_certificate /etc/nginx/ssl/web2py.cert;
  ssl_certificate_key /etc/nginx/ssl/web2py.key;
  location / {
    uwsgi_pass 127.0.0.1:9001;
    include uwsgi_params;
    uwsgi_param UWSGI_SCHEME $scheme;
  }
}
' > /etc/nginx/conf.d/web2py.conf


echo 'Auto-signed ssl certs'
mkdir /etc/nginx/ssl
echo "creating a self signed certificate"
echo "=================================="
openssl genrsa 1024 > /etc/nginx/ssl/web2py.key
chmod 400 /etc/nginx/ssl/web2py.key
openssl req -new -x509 -nodes -sha1 -days 365 -key /etc/nginx/ssl/web2py.key > /etc/nginx/ssl/web2py.cert
openssl x509 -noout -fingerprint -text < /etc/nginx/ssl/web2py.cert > /etc/nginx/ssl/web2py.info

echo 'uwsgi as service'

echo '
#!/bin/bash

# uwsgi - Use uwsgi to run python and wsgi web apps.
#
# chkconfig: - 85 15
# description: Use uwsgi to run python and wsgi web apps.
# processname: uwsgi

# author: Roman Vasilyev

# Source function library.
. /etc/rc.d/init.d/functions

###########################
PATH=/opt/uwsgi-python:/sbin:/bin:/usr/sbin:/usr/bin
PYTHONPATH=/home/www-data/web2py
MODULE=wsgihandler
PROG=/opt/uwsgi-python/uwsgi
OWNER=uwsgi
NAME=uwsgi
DESC=uwsgi
DAEMON_OPTS="-s 127.0.0.1:9001 -M 4 -t 30 -A 4 -p 16 -b 32768 -d \
/var/log/$NAME.log --pidfile /var/run/$NAME.pid --uid $OWNER \
--ini-paste /opt/uwsgi-python/uwsgi_for_nginx.conf"
##############################

[ -f /etc/sysconfig/uwsgi ] && . /etc/sysconfig/uwsgi

lockfile=/var/lock/subsys/uwsgi

start () {
  echo -n "Starting $DESC: "
  daemon $PROG $DAEMON_OPTS
  retval=$?
  echo
  [ $retval -eq 0 ] && touch $lockfile
  return $retval
}

stop () {
  echo -n "Stopping $DESC: "
  killproc $PROG
  retval=$?
  echo
  [ $retval -eq 0 ] && rm -f $lockfile
  return $retval
}

reload () {
  echo "Reloading $NAME"
  killproc $PROG -HUP
  RETVAL=$?
  echo
}

force-reload () {
  echo "Reloading $NAME"
  killproc $PROG -TERM
  RETVAL=$?
  echo
}

restart () {
    stop
    start
}

rh_status () {
  status $PROG
}

rh_status_q() {
  rh_status >/dev/null 2>&1
}

case "$1" in
  start)
    rh_status_q && exit 0
    $1
    ;;
  stop)
    rh_status_q || exit 0
    $1
    ;;
  restart|force-reload)
    $1
    ;;
  reload)
    rh_status_q || exit 7
    $1
    ;;
  status)
    rh_status
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|reload|force-reload|status}" >&2
    exit 2
    ;;
  esac
  exit 0
' > /etc/init.d/uwsgi

chmod 755 /etc/init.d/uwsgi
chkconfig --add uwsgi
chkconfig uwsgi on

echo '
You can test it with

service uwsgi start

and stop it similarly.

Nginx has automatically been set up as a service
if you want to start it run

service nginx start

You should find the web2py welcome app will be displayed at your web address.
As they are both services, they should automatically start on a system reboot.
If you already had a server running, such as apache, you would need to stop
that and turn its service off before running nginx.
'

echo 'Turning off apache service'
service httpd stop
chkconfig httpd off

echo '
Installation complete. You might want to restart your server running

reboot

as superuser
'
