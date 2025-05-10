#!/bin/bash

set -e

print_status() {
  echo -ne "\033[0;37m[working] $1...\033[0m"
}

print_done() {
  echo -ne "\033[0;2K\r\033[0;37m[working] $1... \033[0;32m[done]\033[0m\n"
}

spinner() {
  local msg="$1"
  shift
  local cmd="$@"
  local log_file=$(mktemp)

  echo -ne "\033[0;37m[🛠️] $msg...\033[0m"

  bash -c "$cmd" >"$log_file" 2>&1 &
  local pid=$!
  local spinstr='|/-\\'
  local delay=0.1

  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?}
    printf "\r\033[0;37m[🛠️] $msg... [%c]\033[0m" "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
  done

  wait $pid
  local status=$?

  if [ $status -eq 0 ]; then
    printf "\r\033[0;32m[✅] $msg... Done\033[0m\n"
  else
    printf "\r\033[0;31m[❌] $msg failed\033[0m\n"
    echo -e "\033[0;33m🔍 Error output:\033[0m"
    cat "$log_file"
  fi

  rm "$log_file"
  return $status
}

setup_nginx() {
  local domain="$1"
  local app_path="$2"
  local port="$3"
  local php_version="$4"
  local app_type="$5"
  local msport="$6"
  local skip_ssl="$7"

  local nginx_conf="/etc/nginx/sites-available/$domain"

  {
    echo "server {"
    echo "    listen ${port:-80};"
    echo "    server_name $domain;"

    if [[ "$app_type" == "laravel" ]]; then
      echo "    root $app_path/public;"
    elif [[ "$app_type" == "react" ]]; then
      echo "    root $app_path/dist;"
    else
      echo "    root $app_path;"
    fi

    if [[ "$app_type" == "react" ]]; then
      echo "    index index.html index.htm index.nginx-debian.html;"
    else
      echo "    index index.php index.html index.htm index.nginx-debian.html;"
    fi

    if [[ "$app_type" == "meilisearch" ]]; then
      echo "    location / {"
      echo "        proxy_pass http://127.0.0.1:$msport;"
      echo "        proxy_set_header Host \$host;"
      echo "        proxy_set_header X-Real-IP \$remote_addr;"
      echo "    }"
    else
      echo "    location / {"
      if [[ "$app_type" == "react" ]]; then
        echo "        try_files \$uri \$uri/ /index.html;"
      else
        echo "        try_files \$uri \$uri/ /index.php?\$query_string;"
      fi
      echo "    }"
      if [[ "$app_type" != "react" ]]; then
      echo "    location ~ \.php\$ {"
      echo "        include snippets/fastcgi-php.conf;"
      echo "        fastcgi_pass unix:/run/php/php$php_version-fpm.sock;"
      echo "    }"
      fi
      echo "    location ~ /\.ht {"
      echo "        deny all;"
      echo "    }"
    fi

    echo "}"
  } > "$nginx_conf"

  ln -s "$nginx_conf" /etc/nginx/sites-enabled/
  [[ -n "$port" ]] && ufw allow "$port"/tcp && ufw reload

  if [[ "$skip_ssl" == "n" ]]; then
    systemctl stop nginx
    print_status "SSL for $domain"
    certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m admin@"$domain"
    print_done "SSL for $domain"

    {
      echo "server {"
      echo "    listen ${port:-443} ssl;"
      echo "    server_name $domain;"

      if [[ "$app_type" == "laravel" ]]; then
        echo "    root $app_path/public;"
      elif [[ "$app_type" == "react" ]]; then
        echo "    root $app_path/dist;"
      else
        echo "    root $app_path;"
      fi

      if [[ "$app_type" == "react" ]]; then
        echo "    index index.html;"
      else
        echo "    index index.php index.html;"
      fi

      if [[ "$app_type" == "meilisearch" ]]; then
        echo "    location / {"
        echo "        proxy_pass http://127.0.0.1:$msport;"
        echo "        proxy_set_header Host \$host;"
        echo "        proxy_set_header X-Real-IP \$remote_addr;"
        echo "    }"
      else
        echo "    location / {"
        if [[ "$app_type" == "react" ]]; then
        echo "        try_files \$uri \$uri/ /index.html?\$query_string;"
        else
        echo "        try_files \$uri \$uri/ /index.php?\$query_string;"
        fi
        echo "    }"
        echo "    location ~ \.php\$ {"
        echo "        include snippets/fastcgi-php.conf;"
        echo "        fastcgi_pass unix:/run/php/php$php_version-fpm.sock;"
        echo "    }"
        echo "    location ~ /\.ht {"
        echo "        deny all;"
        echo "    }"
      fi

      echo "    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;"
      echo "    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;"
      echo "}"
    } > "$nginx_conf"

    systemctl start nginx
  else
    echo -e "\033[0;37mSSL skipped. Remember to set up SSL manually.\033[0m"
  fi
}

setup_phpmyadmin_app() {
  local app_user="$1"
  local app_path="$2"
  local summary_file="$3"

  rm -rf "$app_path"
  spinner "Installing phpMyAdmin" "bash -c '
    echo \"phpmyadmin phpmyadmin/reconfigure-webserver multiselect none\" | debconf-set-selections
    echo \"phpmyadmin phpmyadmin/dbconfig-install boolean false\" | debconf-set-selections
    apt install -y phpmyadmin
  '"
  ln -s /usr/share/phpmyadmin "$app_path"
  chmod o+x "$app_path"
  echo -e "phpMyAdmin: https://$domain" >> "$summary_file"
}

clone_git_repo() {
  local repo_url="$1"
  local app_user="$2"
  local app_path="$3"

  if [[ -d "$app_path" ]]; then
    echo -e "\033[0;33m⚠️  $app_path exists. Recreating it...\033[0m"
    rm -rf "$app_path"
  fi

  mkdir -p "$app_path"
  chown -R $app_user:$app_user "$app_path"

  export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
  
  while true; do
    if spinner "Clone repository" "sudo -u $app_user git clone $repo_url $app_path"; then
      break
    else
      echo -e "\n❌ Clone failed. Make sure the repo exists and access is granted.\n"
      read -p $'\033[0;32mEnter Git repo URL: \033[0m ' repo_url
    fi
  done
}

setup_react_app() {
    local app_user="$1"
    local app_path="$2"
    
    spinner "Installing Node.js and npm" "apt install -y nodejs npm && npm install -g serve"
    
    cd "$app_path"
    spinner "Installing React dependencies" "sudo -u $app_user npm install"
    spinner "Building React app" "sudo -u $app_user npm run build"
}

setup_meilisearch_app() {
  local app_user="$1"
  local domain="$2"
  local app_path="$3"
  local summary_file="$4"
  local msport="$5"

  spinner "Installing Meilisearch..." "curl -L https://install.meilisearch.com -o install-meili.sh && chmod +x install-meili.sh && ./install-meili.sh"

  mv ./meilisearch /usr/local/bin/
  mkdir -p "$app_path/data.ms"
  chown -R $app_user:$app_user "$app_path/data.ms"

  meili_key=$(openssl rand -hex 16)
  echo -e "\033[0;32m🔐 Meilisearch master key:\033[0m $meili_key"
  echo -e "🔐 Meilisearch master key: $meili_key" >> "$summary_file"

  spinner "Setting up Supervisor for Meilisearch" "bash -c '
  cat > /etc/supervisor/conf.d/meilisearch_${domain}.conf <<EOL
[program:meilisearch_${domain}]
command=/usr/local/bin/meilisearch --http-addr 127.0.0.1:${msport} --env production --db-path ${app_path}/data.ms --master-key ${meili_key} --experimental-enable=contains
autostart=true
autorestart=true
stderr_logfile=/var/log/meilisearch_${domain}.err.log
stdout_logfile=/var/log/meilisearch_${domain}.log
EOL
  '"

  supervisorctl reread
  supervisorctl update

  echo -e "\033[0;36m🚀 Meilisearch service started on internal port $msport\033[0m"
}

setup_laravel_app() {
  local app_path="$1"
  local php_version="$2"
  local app_user="$3"
  local domain="$4"
  local summary_file="$5"
  local add_db="$9"
  local db_names="${10}"
  local use_sup="${11}"
  local worker_count="${12}"
  local worker_queues="${13}"

  cd "$app_path"

  # Install Redis server if not already installed
  if ! command -v redis-server &> /dev/null; then
    spinner "Installing Redis server..." apt install -y redis-server && systemctl enable redis-server && systemctl start redis-server
  else
    echo -e "\033[0;33m⚠️  Redis server is already installed.\033[0m"
  fi

  # Install Laravel PHP dependencies
  spinner "Installing Laravel PHP dependencies" apt install -y \
    php-xml \
    php$php_version \
    php$php_version-{fpm,mysql,cli,mbstring,xml,curl,bcmath,zip,gd,common,intl,readline,soap,xdebug,igbinary,redis} \
    mysql-server \
    supervisor \
    composer \
    zlib1g-dev

  # Enable extensions just in case
  phpenmod igbinary redis

  # Restart PHP FPM service
  systemctl restart php$php_version-fpm

  spinner "Installing Composer dependencies" sudo -u "$app_user" php$php_version /usr/bin/composer install
  spinner "Set ENV and generate key" cp .env.production .env && php artisan key:generate

  spinner "Set correct file permissions" sudo chown -R "$app_user":www-data . && find . -type f -exec chmod 644 {} \; && find . -type d -exec chmod 755 {} \; && sudo chown -R www-data:www-data storage bootstrap/cache && sudo chmod -R 775 storage bootstrap/cache

  db_pass=$(openssl rand -base64 18)
  echo -e "[$domain] Laravel App" >> "$summary_file"
  echo -e "MySQL User: $app_user" >> "$summary_file"
  echo -e "MySQL Password: $db_pass" >> "$summary_file"
  mysql -e "CREATE USER IF NOT EXISTS '$app_user'@'localhost' IDENTIFIED BY '$db_pass';"
  mysql -e "CREATE USER IF NOT EXISTS '$app_user'@'127.0.0.1' IDENTIFIED BY '$db_pass';"
  mysql -e "FLUSH PRIVILEGES;"

  if [[ "$add_db" == "y" && -n "$db_names" ]]; then
    for db_name in $db_names; do
      mysql -e "CREATE DATABASE IF NOT EXISTS \\\`$db_name\\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
      mysql -e "GRANT ALL PRIVILEGES ON \\\`$db_name\\\`.* TO '$app_user'@'localhost';"
      mysql -e "GRANT ALL PRIVILEGES ON \\\`$db_name\\\`.* TO '$app_user'@'127.0.0.1';"
      echo -e "Created DB: $db_name" >> "$summary_file"
    done
  fi

  if [[ "$use_sup" == "y" && "$worker_count" -gt 0 ]]; then
      cat > /etc/supervisor/conf.d/${domain}.conf <<EOL
[program:${domain}]
command=php artisan queue:work --queue=${worker_queues}
directory=$app_path
autostart=true
autorestart=true
numprocs=$worker_count
stdout_logfile=/var/log/${domain}.log
stderr_logfile=/var/log/${domain}.err.log
EOL

    supervisorctl reread
    supervisorctl update
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "\033[1;31m❌ You need root access. Please run this script as root (e.g., with sudo)\033[0m"
  exit 1
fi

spinner "Adding PHP repository" add-apt-repository ppa:ondrej/php -y
spinner "Updating package lists" apt update
spinner "Installing core utils (bc)" apt install -y bc

# ==== Step 1: DNS Reminder ====
server_ip=$(curl -s https://api.ipify.org)
echo "⚠️  BEFORE YOU CONTINUE:"
echo -e "\033[0;37mMake sure your domain/subdomain DNS is pointing to this server's IP:\033[0m\n"
echo -e "\033[0;37m ➤ Public IP: $server_ip\033[0m"
echo -e "\033[0;37m (check propagation: https://dnschecker.org)\033[0m"


read -p $'\033[0;32mDo you want to skip SSL (Certbot)? (y/n): \033[0m ' skip_ssl
while true; do
  read -p $'\033[0;32mEnter desired PHP version (e.g., 8.2): \033[0m ' php_version

  if [[ ! "$php_version" =~ ^8\.[0-9]+$ ]]; then
    echo "❌ Invalid format. Use format like 8.2"
    continue
  fi

  if (( $(echo "$php_version < 8.0" | bc -l) )); then
    echo "❌ PHP version must be 8.0 or higher."
    continue
  fi

  if ! apt-cache show php$php_version &>/dev/null; then
    echo "❌ PHP $php_version not available in apt. Try another version."
    continue
  fi

  break
done

read -p $'\033[0;32mEnter new deployment username: \033[0m ' app_user

if id -u "$app_user" >/dev/null 2>&1; then
  echo "User $app_user already exists. Skipping creation and SSH key generation."
else
  useradd -m -s /bin/bash $app_user
  passwd -l $app_user
  usermod -L $app_user

  mkdir -p /home/$app_user/.ssh
  sudo -u $app_user ssh-keygen -t rsa -b 4096 -f /tmp/id_rsa -N ""
  mv /tmp/id_rsa /home/$app_user/.ssh/id_rsa
  mv /tmp/id_rsa.pub /home/$app_user/.ssh/id_rsa.pub
  cat /home/$app_user/.ssh/id_rsa.pub > /home/$app_user/.ssh/authorized_keys
  chmod 700 /home/$app_user/.ssh
  chmod 600 /home/$app_user/.ssh/authorized_keys
  chown -R $app_user:$app_user /home/$app_user/.ssh
  chmod o+x /home/$app_user
fi

SUMMARY_FILE="/home/$app_user/server-setup-summary.txt"
touch $SUMMARY_FILE
chown $app_user:$app_user $SUMMARY_FILE
chmod 600 $SUMMARY_FILE

echo -e "\033[0;37m🔑 Add this SSH public key to your Git repositories:\033[0m"
cat /home/$app_user/.ssh/id_rsa.pub

echo -e "\033[0;37m⏳ Press ENTER when you're done copying to continue...\033[0m"

# ==== Step 4: Install System Packages ====
spinner "Install system packages" apt install -y nginx git curl unzip ufw nodejs npm build-essential autoconf pkg-config zlib1g-dev certbot python3-certbot-nginx fzf

# Detect if running inside Docker
if grep -q docker /proc/1/cgroup; then
  echo -e "\033[0;33m⚠️ Skipping UFW setup inside Docker container\033[0m"
else
  spinner "Setting up UFW" ufw allow OpenSSH && ufw allow 80/tcp && ufw --force enable
fi

# ==== Step 5: App Setup Loop ====
app_index=1

while true; do
  echo -e "\n\033[0;37m📦 Setting up app #$app_index\033[0m"
  read -p $'\033[0;32mEnter domain (e.g., app.example.com): \033[0m ' domain
  
  read -p $'\033[0;32mEnter app port (or leave blank for HTTPS-only): \033[0m ' port

  app_type=$(printf "laravel\nreact\nmeilisearch\nphpmyadmin" | fzf --prompt="Choose app type: " --height=10 --reverse)

  if [[ -z "$app_type" ]]; then
    echo "❌ No app type selected. Exiting."
    exit 1
  fi

  if [[ -n "$port" ]]; then
    if lsof -i :$port &>/dev/null; then
      echo -e "\033[0;33m⚠️  Port $port is already in use.\033[0m"
      existing_sites=$(grep -lr "listen $port" /etc/nginx/sites-available 2>/dev/null | xargs -r grep -E "server_name" | awk '{print $2}' | tr -d ';')
      if [[ -n "$existing_sites" ]]; then
        echo -e "\033[0;33m🔍 Detected this port is already used by domain(s):\033[0m $existing_sites"
        read -p $'\033[0;32mAre you sure you want to continue using this port? (y/n): \033[0m ' continue_port
        if [[ "$continue_port" != "y" ]]; then
          echo "Aborting due to port conflict."
          exit 1
        fi
      else
        echo -e "\033[0;33mNo matching domain found for this port in NGINX, but it is in use.\033[0m"
        read -p $'\033[0;32mContinue anyway? (y/n): \033[0m ' continue_anyway
        if [[ "$continue_anyway" != "y" ]]; then
          echo "Aborting due to port conflict."
          exit 1
        fi
      fi
    fi
  fi

  if [[ -z "$port" ]]; then
    port=443
  fi
  
  app_path="/home/$app_user/$domain"


  if [[ "$app_type" == "laravel" || "$app_type" == "react" ]]; then
    read -p $'\033[0;32mEnter Git repo URL: \033[0m ' repo_url
    clone_git_repo "$repo_url" "$app_user" "$app_path"
  fi

  if [[ "$app_type" == "laravel" ]]; then
    read -p $'\033[0;32mInstall gRPC extension? (y/n): \033[0m ' install_grpc
    read -p $'\033[0;32mDo you want to import a MySQL dump file? (y/n): \033[0m ' import_dump

    db_names=""
    if [[ "$import_dump" == "y" ]]; then
        read -p $'\033[0;32mEnter path to .zip or .7z dump file: \033[0m ' dump_path
        add_db="n"
    else
        dump_path=""
        read -p $'\033[0;32mAdd a database for this app? (y/n): \033[0m ' add_db

        if [[ "$add_db" == "y" ]]; then
            while true; do
                read -p $'\033[0;32mEnter DB name: \033[0m ' db_name
                db_names+="$db_name "
                read -p $'\033[0;32mAdd another DB? (y/n): \033[0m ' another_db
                [[ "$another_db" != "y" ]] && break
            done
        fi
    fi

    read -p $'\033[0;32mUse Supervisor for Laravel queue workers? (y/n): \033[0m ' use_sup
    if [[ "$use_sup" == "y" ]]; then
        read -p $'\033[0;32mNumber of workers: \033[0m ' worker_count
        read -p $'\033[0;32mQueue names (comma/default): \033[0m ' worker_queues
    else
        worker_count=0
        worker_queues=""
    fi

    setup_laravel_app "$app_path" "$php_version" "$app_user" "$domain" "$SUMMARY_FILE" "$add_db" "$db_names" "$use_sup" "$worker_count" "$worker_queues"
  fi

  if [[ "$app_type" == "react" ]]; then
    setup_react_app "$app_user" "$app_path"
  fi

  if [[ "$app_type" == "meilisearch" ]]; then
    read -p $'\033[0;32mEnter meilisearch internal port (Default 7700): \033[0m ' msport
    [[ -z "$msport" ]] && msport=7700
    setup_meilisearch_app "$app_user" "$domain" "$app_path" "$SUMMARY_FILE" "$msport"
  fi

  if [[ "$app_type" == "phpmyadmin" ]]; then
    setup_phpmyadmin_app "$app_user" "$app_path" "$SUMMARY_FILE"
  fi

  setup_nginx "$domain" "$app_path" "$port" "$php_version" "$app_type" "$msport" "$skip_ssl"

  echo -e "App URL: https://$domain:$port" >> $SUMMARY_FILE

  read -p $'\033[0;32mAdd another app? (y/n): \033[0m ' add_more
  [[ "$add_more" != "y" ]] && break
  ((app_index++))
done

nginx -t && systemctl reload nginx

echo -e "\n\033[0;37m✅ All apps deployed. Please launch your deployment pilines to have the appropriate configs.\033[0m"
echo -e "\033[0;37m📄 Credentials saved to: $SUMMARY_FILE\033[0m"
cat $SUMMARY_FILE
