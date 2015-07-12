#!/bin/bash
set -e

SSL_CERTIFICATES_DIR="${DATA_DIR}/certs"
SYSCONF_TEMPLATES_DIR="${SETUP_DIR}/config"
USERCONF_TEMPLATES_DIR="${DATA_DIR}/config"

DB_HOST=${DB_HOST:-}
DB_PORT=${DB_PORT:-}
DB_NAME=${DB_NAME:-}
DB_USER=${DB_USER:-}
DB_PASS=${DB_PASS:-}
DB_POOL=${DB_POOL:-5}
DB_TYPE=${DB_TYPE:-}

MEMCACHED_HOST=${MEMCACHED_HOST:-}
MEMCACHED_PORT=${MEMCACHED_PORT:-}

SMTP_METHOD=${SMTP_METHOD:-smtp}
SMTP_DOMAIN=${SMTP_DOMAIN:-www.gmail.com}
SMTP_HOST=${SMTP_HOST:-smtp.gmail.com}
SMTP_PORT=${SMTP_PORT:-587}
SMTP_USER=${SMTP_USER:-}
SMTP_PASS=${SMTP_PASS:-}
SMTP_OPENSSL_VERIFY_MODE=${SMTP_OPENSSL_VERIFY_MODE:-}
SMTP_STARTTLS=${SMTP_STARTTLS:-true}
SMTP_TLS=${SMTP_TLS:-false}
if [ -n "${SMTP_USER}" ]; then
  SMTP_ENABLED=${SMTP_ENABLED:-true}
  SMTP_AUTHENTICATION=${SMTP_AUTHENTICATION:-:login}
fi
SMTP_ENABLED=${SMTP_ENABLED:-false}

REDMINE_PORT=${REDMINE_PORT:-}
REDMINE_HTTPS=${REDMINE_HTTPS:-false}
REDMINE_RELATIVE_URL_ROOT=${REDMINE_RELATIVE_URL_ROOT:-}
REDMINE_FETCH_COMMITS=${REDMINE_FETCH_COMMITS:-disable}

REDMINE_HTTPS_HSTS_ENABLED=${REDMINE_HTTPS_HSTS_ENABLED:-true}
REDMINE_HTTPS_HSTS_MAXAGE=${REDMINE_HTTPS_HSTS_MAXAGE:-31536000}

NGINX_WORKERS=${NGINX_WORKERS:-1}
NGINX_MAX_UPLOAD_SIZE=${NGINX_MAX_UPLOAD_SIZE:-20m}

SSL_CERTIFICATE_PATH=${SSL_CERTIFICATE_PATH:-${SSL_CERTIFICATES_DIR}/redmine.crt}
SSL_KEY_PATH=${SSL_KEY_PATH:-${SSL_CERTIFICATES_DIR}/redmine.key}
SSL_DHPARAM_PATH=${SSL_DHPARAM_PATH:-${SSL_CERTIFICATES_DIR}/dhparam.pem}
SSL_VERIFY_CLIENT=${SSL_VERIFY_CLIENT:-off}

UNICORN_WORKERS=${UNICORN_WORKERS:-2}
UNICORN_TIMEOUT=${UNICORN_TIMEOUT:-60}

# is a mysql or postgresql database linked?
# requires that the mysql or postgresql containers have exposed
# port 3306 and 5432 respectively.
if [ -n "${MYSQL_PORT_3306_TCP_ADDR}" ]; then
  DB_TYPE=mysql
  DB_HOST=${DB_HOST:-${MYSQL_PORT_3306_TCP_ADDR}}
  DB_PORT=${DB_PORT:-${MYSQL_PORT_3306_TCP_PORT}}

  # support for linked sameersbn/mysql image
  DB_USER=${DB_USER:-${MYSQL_ENV_DB_USER}}
  DB_PASS=${DB_PASS:-${MYSQL_ENV_DB_PASS}}
  DB_NAME=${DB_NAME:-${MYSQL_ENV_DB_NAME}}

  # support for linked orchardup/mysql and centurylink/mysql image
  # also supports official mysql image
  DB_USER=${DB_USER:-${MYSQL_ENV_MYSQL_USER}}
  DB_PASS=${DB_PASS:-${MYSQL_ENV_MYSQL_PASSWORD}}
  DB_NAME=${DB_NAME:-${MYSQL_ENV_MYSQL_DATABASE}}
elif [ -n "${POSTGRESQL_PORT_5432_TCP_ADDR}" ]; then
  DB_TYPE=postgres
  DB_HOST=${DB_HOST:-${POSTGRESQL_PORT_5432_TCP_ADDR}}
  DB_PORT=${DB_PORT:-${POSTGRESQL_PORT_5432_TCP_PORT}}

  # support for linked official postgres image
  DB_USER=${DB_USER:-${POSTGRESQL_ENV_POSTGRES_USER}}
  DB_PASS=${DB_PASS:-${POSTGRESQL_ENV_POSTGRES_PASSWORD}}
  DB_NAME=${DB_NAME:-${DB_USER}}

  # support for linked sameersbn/postgresql image
  DB_USER=${DB_USER:-${POSTGRESQL_ENV_DB_USER}}
  DB_PASS=${DB_PASS:-${POSTGRESQL_ENV_DB_PASS}}
  DB_NAME=${DB_NAME:-${POSTGRESQL_ENV_DB_NAME}}

  # support for linked orchardup/postgresql image
  DB_USER=${DB_USER:-${POSTGRESQL_ENV_POSTGRESQL_USER}}
  DB_PASS=${DB_PASS:-${POSTGRESQL_ENV_POSTGRESQL_PASS}}
  DB_NAME=${DB_NAME:-${POSTGRESQL_ENV_POSTGRESQL_DB}}

  # support for linked paintedfox/postgresql image
  DB_USER=${DB_USER:-${POSTGRESQL_ENV_USER}}
  DB_PASS=${DB_PASS:-${POSTGRESQL_ENV_PASS}}
  DB_NAME=${DB_NAME:-${POSTGRESQL_ENV_DB}}
fi

if [ -z "${DB_HOST}" ]; then
  echo "ERROR: "
  echo "  Please configure the database connection."
  echo "  Refer http://git.io/JkE-cw for more information."
  echo "  Cannot continue without a database. Aborting..."
  exit 1
fi

# use default port number if it is still not set
case "${DB_TYPE}" in
  mysql) DB_PORT=${DB_PORT:-3306} ;;
  postgres) DB_PORT=${DB_PORT:-5432} ;;
  *)
    echo "ERROR: "
    echo "  Please specify the database type in use via the DB_TYPE configuration option."
    echo "  Accepted values are \"postgres\" or \"mysql\". Aborting..."
    exit 1
    ;;
esac

# set the default user and database
DB_NAME=${DB_NAME:-redmine_production}
DB_USER=${DB_USER:-root}

# is a memcached container linked?
if [ -n "${MEMCACHED_PORT_11211_TCP_ADDR}" ]; then
  MEMCACHE_HOST=${MEMCACHE_HOST:-${MEMCACHED_PORT_11211_TCP_ADDR}}
  MEMCACHE_PORT=${MEMCACHE_PORT:-${MEMCACHED_PORT_11211_TCP_PORT}}
fi

# fallback to using the default memcached port 11211
MEMCACHE_PORT=${MEMCACHE_PORT:-11211}

# enable / disable memcached
if [ -n "${MEMCACHE_HOST}" ]; then
  MEMCACHE_ENABLED=true
fi
MEMCACHE_ENABLED=${MEMCACHE_ENABLED:-false}

case "${REDMINE_HTTPS}" in
  true)
    REDMINE_PORT=${REDMINE_PORT:-443}
    NGINX_X_FORWARDED_PROTO=${NGINX_X_FORWARDED_PROTO:-https}
    ;;
  *)
    REDMINE_PORT=${REDMINE_PORT:-80}
    NGINX_X_FORWARDED_PROTO=${NGINX_X_FORWARDED_PROTO:-\$scheme}
    ;;
esac

# create the .ssh directory
mkdir -p ${DATA_DIR}/dotfiles/.ssh/
chown -R redmine:redmine ${DATA_DIR}/dotfiles/.ssh/

# generate ssh keys
if [ ! -e ${DATA_DIR}/dotfiles/.ssh/id_rsa -o ! -e ${DATA_DIR}/dotfiles/.ssh/id_rsa.pub ]; then
  echo "Generating SSH keys..."
  rm -rf ${DATA_DIR}/dotfiles/.ssh/id_rsa ${DATA_DIR}/dotfiles/.ssh/id_rsa.pub
  sudo -u redmine -H ssh-keygen -t rsa -N "" -f ${DATA_DIR}/dotfiles/.ssh/id_rsa
fi

# make sure the ssh keys have the right ownership and permissions
chmod 600 ${DATA_DIR}/dotfiles/.ssh/id_rsa ${DATA_DIR}/dotfiles/.ssh/id_rsa.pub
chmod 700 ${DATA_DIR}/dotfiles/.ssh

# create the .subversion directory
mkdir -p ${DATA_DIR}/dotfiles/.subversion/

# fix ownership of the ${DATA_DIR}dotfiles/ directory
chown -R redmine:redmine ${DATA_DIR}/dotfiles

# fix ownership of ${DATA_DIR}/tmp/
mkdir -p ${DATA_DIR}/tmp/
chown -R redmine:redmine ${DATA_DIR}/tmp/

# populate ${LOG_DIR}
mkdir -m 0755 -p ${LOG_DIR}/supervisor  && chown -R root:root ${LOG_DIR}/supervisor
mkdir -m 0755 -p ${LOG_DIR}/nginx       && chown -R redmine:redmine ${LOG_DIR}/nginx
mkdir -m 0755 -p ${LOG_DIR}/redmine     && chown -R redmine:redmine ${LOG_DIR}/redmine

# fix permission and ownership of ${DATA_DIR}
chmod 755 ${DATA_DIR}
chown redmine:redmine ${DATA_DIR}

# set executable flags on ${DATA_DIR} (needed if mounted from a data-only
# container using --volumes-from)
chmod +x ${DATA_DIR}

cd ${INSTALL_DIR}

# copy configuration templates
case "${REDMINE_HTTPS}" in
  true)
    if [ -f "${SSL_CERTIFICATE_PATH}" -a -f "${SSL_KEY_PATH}" ]; then
      cp ${SYSCONF_TEMPLATES_DIR}/nginx/redmine-ssl /etc/nginx/sites-enabled/redmine
    else
      echo "SSL keys and certificates were not found."
      echo "Assuming that the container is running behind a HTTPS enabled load balancer."
      cp ${SYSCONF_TEMPLATES_DIR}/nginx/redmine /etc/nginx/sites-enabled/redmine
    fi
    ;;
  *) cp ${SYSCONF_TEMPLATES_DIR}/nginx/redmine /etc/nginx/sites-enabled/redmine ;;
esac
sudo -u redmine -H cp ${SYSCONF_TEMPLATES_DIR}/redmine/database.yml config/database.yml
sudo -u redmine -H cp ${SYSCONF_TEMPLATES_DIR}/redmine/unicorn.rb config/unicorn.rb
[ "${SMTP_ENABLED}" == "true" ] && \
sudo -u redmine -H cp ${SYSCONF_TEMPLATES_DIR}/redmine/smtp_settings.rb config/initializers/smtp_settings.rb
[ "${MEMCACHE_ENABLED}" == "true" ] && \
sudo -u redmine -H cp ${SYSCONF_TEMPLATES_DIR}/redmine/additional_environment.rb config/additional_environment.rb

# override default configuration templates with user templates
case "${REDMINE_HTTPS}" in
  true)
    if [ -f "${SSL_CERTIFICATE_PATH}" -a -f "${SSL_KEY_PATH}" ]; then
      [ -f ${USERCONF_TEMPLATES_DIR}/nginx/redmine-ssl ]           && cp ${USERCONF_TEMPLATES_DIR}/nginx/redmine-ssl /etc/nginx/sites-enabled/redmine
    else
      [ -f ${USERCONF_TEMPLATES_DIR}/nginx/redmine ]               && cp ${USERCONF_TEMPLATES_DIR}/nginx/redmine /etc/nginx/sites-enabled/redmine
    fi
    ;;
  *) [ -f ${USERCONF_TEMPLATES_DIR}/nginx/redmine ]                && cp ${USERCONF_TEMPLATES_DIR}/nginx/redmine /etc/nginx/sites-enabled/redmine ;;
esac
[ -f ${USERCONF_TEMPLATES_DIR}/redmine/database.yml ]              && sudo -u redmine -H cp ${USERCONF_TEMPLATES_DIR}/redmine/database.yml config/database.yml
[ -f ${USERCONF_TEMPLATES_DIR}/redmine/unicorn.rb ]                && sudo -u redmine -H cp ${USERCONF_TEMPLATES_DIR}/redmine/unicorn.rb  config/unicorn.rb
[ "${SMTP_ENABLED}" == "true" ] && \
[ -f ${USERCONF_TEMPLATES_DIR}/redmine/smtp_settings.rb ]          && sudo -u redmine -H cp ${USERCONF_TEMPLATES_DIR}/redmine/smtp_settings.rb config/initializers/smtp_settings.rb
[ "${MEMCACHE_ENABLED}" == "true" ] && \
[ -f ${USERCONF_TEMPLATES_DIR}/redmine/additional_environment.rb ] && sudo -u redmine -H cp ${USERCONF_TEMPLATES_DIR}/redmine/additional_environment.rb config/additional_environment.rb

# configure database
if [ "${DB_TYPE}" == "postgres" ]; then
  sudo -u redmine -H sed 's/{{DB_ADAPTER}}/postgresql/' -i config/database.yml
  sudo -u redmine -H sed 's/{{DB_ENCODING}}/unicode/' -i config/database.yml
  sudo -u redmine -H sed 's/reconnect: false/#reconnect: false/' -i config/database.yml
elif [ "${DB_TYPE}" == "mysql" ]; then
  sudo -u redmine -H sed 's/{{DB_ADAPTER}}/mysql2/' -i config/database.yml
  sudo -u redmine -H sed 's/{{DB_ENCODING}}/utf8/' -i config/database.yml
  sudo -u redmine -H sed 's/#reconnect: false/reconnect: false/' -i config/database.yml
else
  echo "Invalid database type: '$DB_TYPE'. Supported choices: [mysql, postgres]."
fi

sudo -u redmine -H sed 's/{{DB_HOST}}/'"${DB_HOST}"'/' -i config/database.yml
sudo -u redmine -H sed 's/{{DB_PORT}}/'"${DB_PORT}"'/' -i config/database.yml
sudo -u redmine -H sed 's/{{DB_NAME}}/'"${DB_NAME}"'/' -i config/database.yml
sudo -u redmine -H sed 's/{{DB_USER}}/'"${DB_USER}"'/' -i config/database.yml
sudo -u redmine -H sed 's/{{DB_PASS}}/'"${DB_PASS}"'/' -i config/database.yml
sudo -u redmine -H sed 's/{{DB_POOL}}/'"${DB_POOL}"'/' -i config/database.yml

# configure secure-cookie if using SSL/TLS
if [ "${REDMINE_HTTPS}" == "true" ]; then
  sed '/^\s*config\.session_store\s/s/$/, :secure => true/' -i config/application.rb
fi

# configure memcached
if [ "${MEMCACHE_ENABLED}" == "true" ]; then
  echo "Enabling memcache..."
  sed 's/{{MEMCACHE_HOST}}/'"${MEMCACHE_HOST}"'/' -i config/additional_environment.rb
  sed 's/{{MEMCACHE_PORT}}/'"${MEMCACHE_PORT}"'/' -i config/additional_environment.rb
fi

# configure nginx
sed 's/worker_processes .*/worker_processes '"${NGINX_WORKERS}"';/' -i /etc/nginx/nginx.conf
sed 's,{{INSTALL_DIR}},'"${INSTALL_DIR}"',g' -i /etc/nginx/sites-enabled/redmine
sed 's/{{REDMINE_PORT}}/'"${REDMINE_PORT}"'/' -i /etc/nginx/sites-enabled/redmine
sed 's/{{NGINX_MAX_UPLOAD_SIZE}}/'"${NGINX_MAX_UPLOAD_SIZE}"'/' -i /etc/nginx/sites-enabled/redmine
sed 's/{{NGINX_X_FORWARDED_PROTO}}/'"${NGINX_X_FORWARDED_PROTO}"'/' -i /etc/nginx/sites-enabled/redmine
sed 's,{{SSL_CERTIFICATE_PATH}},'"${SSL_CERTIFICATE_PATH}"',' -i /etc/nginx/sites-enabled/redmine
sed 's,{{SSL_KEY_PATH}},'"${SSL_KEY_PATH}"',' -i /etc/nginx/sites-enabled/redmine

# if dhparam path is valid, add to the config, otherwise remove the option
if [ -r "${SSL_DHPARAM_PATH}" ]; then
  sed 's,{{SSL_DHPARAM_PATH}},'"${SSL_DHPARAM_PATH}"',' -i /etc/nginx/sites-enabled/redmine
else
  sed '/ssl_dhparam {{SSL_DHPARAM_PATH}};/d' -i /etc/nginx/sites-enabled/redmine
fi

sed 's,{{SSL_VERIFY_CLIENT}},'"${SSL_VERIFY_CLIENT}"',' -i /etc/nginx/sites-enabled/redmine
if [ -f /usr/local/share/ca-certificates/ca.crt ]; then
  sed 's,{{CA_CERTIFICATES_PATH}},'"${CA_CERTIFICATES_PATH}"',' -i /etc/nginx/sites-enabled/redmine
else
  sed '/{{CA_CERTIFICATES_PATH}}/d' -i /etc/nginx/sites-enabled/redmine
fi

if [ "${REDMINE_HTTPS_HSTS_ENABLED}" == "true" ]; then
  sed 's/{{REDMINE_HTTPS_HSTS_MAXAGE}}/'"${REDMINE_HTTPS_HSTS_MAXAGE}"'/' -i /etc/nginx/sites-enabled/redmine
else
  sed '/{{REDMINE_HTTPS_HSTS_MAXAGE}}/d' -i /etc/nginx/sites-enabled/redmine
fi

# configure unicorn
sudo -u redmine -H sed 's,{{INSTALL_DIR}},'"${INSTALL_DIR}"',g' -i config/unicorn.rb
sudo -u redmine -H sed 's/{{UNICORN_WORKERS}}/'"${UNICORN_WORKERS}"'/' -i config/unicorn.rb
sudo -u redmine -H sed 's/{{UNICORN_TIMEOUT}}/'"${UNICORN_TIMEOUT}"'/' -i config/unicorn.rb

# configure relative_url_root
if [ -n "${REDMINE_RELATIVE_URL_ROOT}" ]; then
  sudo -u redmine -H cp -f ${SYSCONF_TEMPLATES_DIR}/redmine/config.ru config.ru
  sudo -u redmine -H sed 's,{{REDMINE_RELATIVE_URL_ROOT}},'"${REDMINE_RELATIVE_URL_ROOT}"',' -i config/unicorn.rb
  sed 's,# alias '"${INSTALL_DIR}"'/public,alias '"${INSTALL_DIR}"'/public,' -i /etc/nginx/sites-enabled/redmine
  sed 's,{{REDMINE_RELATIVE_URL_ROOT}},'"${REDMINE_RELATIVE_URL_ROOT}"',' -i /etc/nginx/sites-enabled/redmine
else
  sudo -u redmine -H sed '/{{REDMINE_RELATIVE_URL_ROOT}}/d' -i config/unicorn.rb
  sed 's,{{REDMINE_RELATIVE_URL_ROOT}},/,' -i /etc/nginx/sites-enabled/redmine
fi

# disable ipv6 support
if [ ! -f /proc/net/if_inet6 ]; then
  sed -e '/listen \[::\]:80/ s/^#*/#/' -i /etc/nginx/sites-enabled/redmine
  sed -e '/listen \[::\]:443/ s/^#*/#/' -i /etc/nginx/sites-enabled/redmine
fi

if [ "${SMTP_ENABLED}" == "true" ]; then
  # configure mail delivery
  sudo -u redmine -H sed 's/{{SMTP_METHOD}}/'"${SMTP_METHOD}"'/g' -i config/initializers/smtp_settings.rb
  sudo -u redmine -H sed 's/{{SMTP_HOST}}/'"${SMTP_HOST}"'/' -i config/initializers/smtp_settings.rb
  sudo -u redmine -H sed 's/{{SMTP_PORT}}/'"${SMTP_PORT}"'/' -i config/initializers/smtp_settings.rb

  case "${SMTP_USER}" in
    "") sudo -u redmine -H sed '/{{SMTP_USER}}/d' -i config/initializers/smtp_settings.rb ;;
    *) sudo -u redmine -H sed 's/{{SMTP_USER}}/'"${SMTP_USER}"'/' -i config/initializers/smtp_settings.rb ;;
  esac

  case "${SMTP_PASS}" in
    "") sudo -u redmine -H sed '/{{SMTP_PASS}}/d' -i config/initializers/smtp_settings.rb ;;
    *) sudo -u redmine -H sed 's/{{SMTP_PASS}}/'"${SMTP_PASS}"'/' -i config/initializers/smtp_settings.rb ;;
  esac

  sudo -u redmine -H sed 's/{{SMTP_DOMAIN}}/'"${SMTP_DOMAIN}"'/' -i config/initializers/smtp_settings.rb
  sudo -u redmine -H sed 's/{{SMTP_STARTTLS}}/'"${SMTP_STARTTLS}"'/' -i config/initializers/smtp_settings.rb
  sudo -u redmine -H sed 's/{{SMTP_TLS}}/'"${SMTP_TLS}"'/' -i config/initializers/smtp_settings.rb

  if [ -n "${SMTP_OPENSSL_VERIFY_MODE}" ]; then
    sudo -u redmine -H sed 's/{{SMTP_OPENSSL_VERIFY_MODE}}/'"${SMTP_OPENSSL_VERIFY_MODE}"'/' -i config/initializers/smtp_settings.rb
  else
    sudo -u redmine -H sed '/{{SMTP_OPENSSL_VERIFY_MODE}}/d' -i config/initializers/smtp_settings.rb
  fi

  case "${SMTP_AUTHENTICATION}" in
    "") sudo -u redmine -H sed '/{{SMTP_AUTHENTICATION}}/d' -i config/initializers/smtp_settings.rb ;;
    *) sudo -u redmine -H sed 's/{{SMTP_AUTHENTICATION}}/'"${SMTP_AUTHENTICATION}"'/' -i config/initializers/smtp_settings.rb ;;
  esac

fi

# create file uploads directory
mkdir -p ${DATA_DIR}/files
chmod 755 ${DATA_DIR}/files
chown redmine:redmine ${DATA_DIR}/files

# symlink file store
rm -rf files
if [ -d /redmine/files ]; then
  # for backward compatibility, user should mount the volume at ${DATA_DIR}
  echo "WARNING: "
  echo "  The data volume path has now been changed to ${DATA_DIR}/files."
  echo "  Refer http://git.io/H59-lg for migration information."
  echo "  Setting up backward compatibility..."
  chmod 755 /redmine/files
  chown redmine:redmine /redmine/files
  ln -sf /redmine/files
else
  ln -sf ${DATA_DIR}/files
fi

# due to the nature of docker and its use cases, we allow some time
# for the database server to come online.
case "${DB_TYPE}" in
  mysql)
    prog="mysqladmin -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} ${DB_PASS:+-p$DB_PASS} status"
    ;;
  postgres)
    prog=$(find /usr/lib/postgresql/ -name pg_isready)
    prog="${prog} -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -t 1"
    ;;
esac

timeout=60
echo -n "Waiting for database server to accept connections"
while ! ${prog} >/dev/null 2>&1
do
  timeout=$(expr $timeout - 1)
  if [ $timeout -eq 0 ]; then
    echo -e "\nCould not connect to database server. Aborting..."
    exit 1
  fi
  echo -n "."
  sleep 1
done
echo

# migrate database if the redmine version has changed.
CURRENT_VERSION=
REDMINE_VERSION=$(cat ${INSTALL_DIR}/VERSION)
[ -f ${DATA_DIR}/tmp/VERSION ] && CURRENT_VERSION=$(cat ${DATA_DIR}/tmp/VERSION)
if [ "${REDMINE_VERSION}" != "${CURRENT_VERSION}" ]; then
  # recreate the tmp directory
  rm -rf ${DATA_DIR}/tmp
  sudo -u redmine -H mkdir -p ${DATA_DIR}/tmp/
  chmod -R u+rwX ${DATA_DIR}/tmp/

  # create the tmp/thumbnails directory
  sudo -u redmine -H mkdir -p ${DATA_DIR}/tmp/thumbnails

  # create the plugin_assets directory
  sudo -u redmine -H mkdir -p ${DATA_DIR}/tmp/plugin_assets

  # copy the installed gems to tmp/bundle and move the Gemfile.lock
  sudo -u redmine -H cp -a vendor/bundle ${DATA_DIR}/tmp/
  sudo -u redmine -H cp -a Gemfile.lock ${DATA_DIR}/tmp/

  echo "Migrating database. Please be patient, this could take a while..."
  sudo -u redmine -H bundle exec rake db:create RAILS_ENV=production
  sudo -u redmine -H bundle exec rake db:migrate RAILS_ENV=production

  # clear sessions and application cache
  sudo -u redmine -H bundle exec rake tmp:cache:clear RAILS_ENV=production >/dev/null
  sudo -u redmine -H bundle exec rake tmp:sessions:clear RAILS_ENV=production >/dev/null

  echo "Generating secure token..."
  sudo -u redmine -H bundle exec rake generate_secret_token RAILS_ENV=production >/dev/null

  # update version file
  echo "${REDMINE_VERSION}" | sudo -u redmine -H tee --append ${DATA_DIR}/tmp/VERSION >/dev/null
fi

# create a cronjob to periodically fetch commits
case "${REDMINE_FETCH_COMMITS}" in
  hourly|daily|monthly)
    crontab -u redmine -l >/tmp/cron.redmine
    if ! grep -q 'Repository.fetch_changesets' /tmp/cron.redmine; then
      echo "@${REDMINE_FETCH_COMMITS} cd ${HOME_DIR}/redmine && ./bin/rails runner \"Repository.fetch_changesets\" -e production >> log/cron_rake.log 2>&1" >>/tmp/cron.redmine
      crontab -u redmine /tmp/cron.redmine
    fi
    rm -rf /tmp/cron.redmine
    ;;
esac

# remove vendor/bundle and symlink to ${DATA_DIR}/tmp/bundle
rm -rf vendor/bundle Gemfile.lock
ln -sf ${DATA_DIR}/tmp/bundle vendor/bundle
ln -sf ${DATA_DIR}/tmp/Gemfile.lock Gemfile.lock

# install user plugins
if [ -d ${DATA_DIR}/plugins ]; then
  echo "Installing plugins..."
  rsync -avq --chown=redmine:redmine ${DATA_DIR}/plugins/ ${INSTALL_DIR}/plugins/

  # install gems and migrate the plugins when plugins are added/removed
  CURRENT_SHA1=
  [ -f ${DATA_DIR}/tmp/plugins.sha1 ] && CURRENT_SHA1=$(cat ${DATA_DIR}/tmp/plugins.sha1)
  PLUGINS_SHA1=$(find ${DATA_DIR}/plugins -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | awk '{print $1}')
  if [ "${CURRENT_SHA1}" != "${PLUGINS_SHA1}" ]; then
    # remove the existing plugin assets
    # this ensures there is no cruft when a plugin is removed.
    rm -rf ${DATA_DIR}/tmp/plugin_assets/*

    echo "Installing gems required by plugins..."
    sudo -u redmine -H bundle install --without development test --path vendor/bundle

    echo "Migrating plugins. Please be patient, this could take a while..."
    sudo -u redmine -H bundle exec rake redmine:plugins:migrate RAILS_ENV=production

    # save SHA1
    echo -n "${PLUGINS_SHA1}" > ${DATA_DIR}/tmp/plugins.sha1
  fi

  # source plugins init script
  if [ -f ${DATA_DIR}/plugins/init ]; then
    echo "Executing plugins startup script..."
    . ${DATA_DIR}/plugins/init
  fi
fi

# install user themes
if [ -d ${DATA_DIR}/themes ]; then
  echo "Installing themes..."
  rsync -avq --chown=redmine:redmine ${DATA_DIR}/themes/ ${INSTALL_DIR}/public/themes/
fi

appStart () {
  # remove stale unicorn pid if it exists.
  rm -rf tmp/pids/unicorn.pid

  # remove state unicorn socket if it exists
  rm -rf tmp/sockets/redmine.socket

  # start supervisord
  exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
}

appRake () {
  if [ -z ${1} ]; then
    echo "Please specify the rake task to execute. See http://www.redmine.org/projects/redmine/wiki/RedmineRake"
    return 1
  fi
  echo "Running redmine rake task..."
  sudo -u redmine -H bundle exec rake $@ RAILS_ENV=production
}

appHelp () {
  echo "Available options:"
  echo " app:start          - Starts the redmine server (default)"
  echo " app:rake <task>    - Execute a rake task."
  echo " app:help           - Displays the help"
  echo " [command]          - Execute the specified linux command eg. bash."
}

case "$1" in
  app:start)
    appStart
    ;;
  app:rake)
    shift 1
    appRake $@
    ;;
  app:help)
    appHelp
    ;;
  *)
    if [ -x $1 ]; then
      $1
    else
      prog=$(which $1)
      if [ -n "${prog}" ] ; then
        shift 1
        $prog $@
      else
        appHelp
      fi
    fi
    ;;
esac

exit 0
