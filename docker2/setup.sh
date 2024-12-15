#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

error_handler()
{
    if [ $1 -ne 0 ]
    then
        echo -e "${RED}Erreur : $2 ${RESET}"
        exit $1
    fi
}

logs()
{
    local color="$1"
    shift
    date_formated=$(date +"%d-%m-%Y %H:%M:%S")
    echo -e "${color}[$date_formated] $1 ${RESET}" | tee -a /logs/install.log
}

logs_info()
{
    logs "$YELLOW" "$*"
}

logs_success()
{
    logs "$GREEN" "$*"
}

logs_end()
{
    logs "$BLUE" "$*"
}

# Fonction pour vérifier si une variable est définie
check_variable() {
  local var_name=$1
  if [ -z "${!var_name+x}" ]; then
    echo "La variable $var_name n'est pas définie."
    exit 2
  fi
}

#======================================================================#

required_vars_start=(
"DOMAIN_NAME"
"NETWORK_NAME"
"WEB_CONTAINER_NAME"
"WEB_ADMIN_ADDRESS"
"WEB_PORT"
"WEB_ADMIN_USER"
"WEB_ADMIN_PASSWORD"
"SSL_KEY_PASSWORD"

"PHPMYADMIN_CONTAINER_NAME"
"PHPMYADMIN_HTACCESS_PASSWORD"
"PHPMYADMIN_ADMIN_ADDRESS"
"PHPMYADMIN_ADMIN_USERNAME"
"PHPMYADMIN_ADMIN_PASSWORD"
"PHPMYADMIN_PORT"

"DB_CONTAINER_NAME"
"DB_PORT"
"DB_ROOT_PASSWORD"
"DB_ADMIN_USERNAME"
"DB_ADMIN_PASSWORD"
"DB_ADMIN_ADDRESS"
"DB_NAME"
)

mkdir /logs

#===================================================================#
# Vérifications de l'environnement et des variables                 #
#===================================================================#

if [ "$EUID" -ne 0 ]
then
    echo -e "${RED}Ce script doit être exécuté avec des privilèges root.${RESET}"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker n'est pas installé. Veuillez l'installer avant de continuer.${RESET}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Docker n'est pas installé. Veuillez l'installer avant de continuer.${RESET}"
    exit 1
fi

#TODO : Vérifier le format valide des variables

logs_info "Vérification des variables .env..."

    # Charger les variables depuis le fichier .env
    if [ ! -f .env ]; then
        echo "Erreur : fichier .env non trouvé."
        exit 1
    fi
    source .env

    for var in "${required_vars_start[@]}"; do
      check_variable "$var"
    done

logs_success "Les variables .env ont été vérifiées."


#===================================================================#
# Prépartion de l'arborescence                                      #
#===================================================================#

# Créer les répertoires nécessaires
mkdir -p apache2/certificate apache2/mods-available www/ phpmyadmin/
error_handler $? "Création des dossiers a échouée."

sudo apt install apache2-utils -y
error_handler $? "Installation d'apache2-utils a échouée."

#===================================================================#
# Création du docker_compose.yml avec les varaibles d'environnement #
#===================================================================#

sudo docker network create $NETWORK_NAME
error_handler $? "  a échouée."

#TODO : VOLUMES APACHE
# error_handler $? "  a échouée."

touch docker-compose.yml
echo "
version: '3.8'

services:
  mysql:
    image: mysql:latest
    container_name: $DB_CONTAINER_NAME
    ports:
      - \"$DB_PORT:3306\"
    volumes:
      - mysql_data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: $DB_ROOT_PASSWORD
      MYSQL_DATABASE: $DB_NAME
      MYSQL_USER: $DB_ADMIN_USERNAME
      MYSQL_PASSWORD: $DB_ADMIN_PASSWORD
    networks:
      - $NETWORK_NAME

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    container_name: $PHPMYADMIN_CONTAINER_NAME
    ports:
      - \"$PHPMYADMIN_PORT:80\"
    environment:
      PMA_HOST: mysql
      MYSQL_ROOT_PASSWORD: $DB_ROOT_PASSWORD
      PMA_USER: $PHPMYADMIN_ADMIN_USERNAME
      PMA_PASSWORD: $PHPMYADMIN_ADMIN_PASSWORD
    depends_on:
      - mysql
    networks:
      - $NETWORK_NAME
      
  web:
    image: php:7.4-apache
    container_name: $WEB_CONTAINER_NAME
    ports:
      - \"$WEB_PORT:9000\"
    volumes:
      - ./www:/var/www/html
      - ./apache2:/etc/apache2/
    depends_on:
      - mysql
    networks:
      - $NETWORK_NAME

volumes:
  mysql_data:

networks:
  $NETWORK_NAME:
    external: true" > docker-compose.yml
error_handler $? "  a échouée."

#================================================================================================================================#
# Configuration du service (HTTPS, ModSecurity, ModEvasive, mod_ratelimit, .htaccess & masquage dans l'url des noms de dossier.) #
#================================================================================================================================#

#HTTPS

logs_info "Configuration du service apache en cours..."

    logs_info "Génération du certificat et de la clé privée pour une configuration en HTTPS..."

        sudo apt-get install -y openssl
        error_handler $? "L'installation d'openssl a échouée."

        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -sha256 -out apache2/certificate/"$DOMAIN_NAME"_server.crt -keyout apache2/certificate/"$DOMAIN_NAME"_server.key -subj "/C=FR/ST=Occitanie/L=Montpellier/O=IUT/OU=Herault/CN=$DOMAIN_NAME/emailAddress=$WEB_ADMIN_ADDRESS" -passin pass:"$SSL_KEY_PASSWORD"
        error_handler $? "La génération de demande de signature de certifcat a échouée"

        openssl x509 -in apache2/certificate/"$DOMAIN_NAME"_server.crt -text -noout
        error_handler $? "La vérification du certificat a échouée."

        sudo chmod 600 apache2/certificate/"$DOMAIN_NAME"_server.key
        sudo chown root:root apache2/certificate/"$DOMAIN_NAME"_server.crt
        sudo chmod 440 apache2/certificate/"$DOMAIN_NAME"_server.crt

    logs_success "Génération du certificat et de la clé privée terminée."


# Configuration apache

    touch apache2/apache2.conf
    error_handler $? "  a échouée."

    echo "
ServerRoot \"/etc/apache2\"

ServerName $DOMAIN_NAME

#Mutex file:\${APACHE_LOCK_DIR} default

DefaultRuntimeDir \${APACHE_RUN_DIR}

PidFile \${APACHE_PID_FILE}

Timeout 300

KeepAlive On

MaxKeepAliveRequests 100

KeepAliveTimeout 5

User \${APACHE_RUN_USER}
Group \${APACHE_RUN_GROUP}

HostnameLookups Off

ErrorLog \${APACHE_LOG_DIR}/error.log

LogLevel warn

IncludeOptional mods-enabled/*.load
IncludeOptional mods-enabled/*.conf

Include ports.conf

<Directory />
    Options FollowSymLinks
    AllowOverride None
    Require all denied
</Directory>

<Directory /usr/share>
    AllowOverride None
    Require all granted
</Directory>

<Directory /var/www/>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

AccessFileName .htaccess

<FilesMatch "^\.ht">
    Require all denied
</FilesMatch>


LogFormat \"%v:%p %h %l %u %t \\\"%r\\\" %>s %O \\\"%{Referer}i\\\" \\\"%{User-Agent}i\\\"\" vhost_combined
LogFormat \"%h %l %u %t \\\"%r\\\" %>s %O \\\"%{Referer}i\\\" \\\"%{User-Agent}i\\\"\" combined
LogFormat \"%h %l %u %t \\\"%r\\\" %>s %O\" common
LogFormat \"%{Referer}i -> %U\" referer
LogFormat \"%{User-agent}i\" agent

IncludeOptional conf-enabled/*.conf

IncludeOptional sites-enabled/*.conf" > apache2/apache2.conf
error_handler $? "  a échouée."

#Configuration pour php

    mkdir apache2/mods-enabled/
    error_handler $? "  a échouée."

    touch apache2/mods-enabled/dir.conf
    error_handler $? "  a échouée."

    echo "
<IfModule mod_dir.c>
        DirectoryIndex index.html index.cgi index.pl index.php index.xhtml index.htm
</IfModule>" > apache2/mods-enabled/dir.conf

    error_handler $? "L'écriture du fichier de configuration apache apache2/mods-enabled/dir.conf a échouée."

#Configuration de la page web par défaut.

    mkdir apache2/sites-enabled/
    touch apache2/sites-enabled/000-default.conf

    echo "
<VirtualHost *:$WEB_PORT>
    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteRule ^/?(.*) https://%SERVER_NAME/$1 [R=301,L]
</VirtualHost>
<VirtualHost *:443>
    ServerAdmin $WEB_ADMIN_ADDRESS
    ServerName $DOMAIN_NAME
    ServerAlias localhost
    DocumentRoot /var/www/html
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
    SSLEngine on
    SSLCertificateFile /etc/apache2/certificate/"$DOMAIN_NAME"_server.crt
    SSLCertificateKeyFile /etc/apache2/certificate/"$DOMAIN_NAME"_server.key

    Header set Strict-Transport-Security \"max-age=31536000; includeSubDomains\"
</VirtualHost>" > apache2/sites-enabled/000-default.conf

    error_handler $? "L'écriture du fichier de configuration du site par défaut a échouée."

# Configuration du port du service apache

    touch apache2/ports.conf 
    error_handler $? "La création du fichier de configuration des ports a échouée."

    echo "
# If you just change the port or add more ports here, you will likely also
# have to change the VirtualHost statement in
# /etc/apache2/sites-enabled/000-default.conf

Listen $WEB_PORT

<IfModule ssl_module>
    Listen 443
</IfModule>

<IfModule mod_gnutls.c>
    Listen 443
</IfModule>" > /apache2/ports.conf
    error_handler $? "L'écriture du fichier de configuration des ports a échouée."

# Configuration ModSecurity

    touch /apache2/modsecurity.conf
    error_handler $? "La création du fichier /apache2/modsecurity.conf a échouée."

    echo "
# -- Rule engine initialization ----------------------------------------------

# Enable ModSecurity, attaching it to every transaction. Use detection
# only to start with, because that minimises the chances of post-installation
# disruption.
#
SecRuleEngine On

# -- Request body handling ---------------------------------------------------

# Allow ModSecurity to access request bodies. If you don't, ModSecurity
# won't be able to see any POST parameters, which opens a large security
# hole for attackers to exploit.
#
SecRequestBodyAccess On

# Enable XML request body parser.
# Initiate XML Processor in case of xml content-type
#
SecRule REQUEST_HEADERS:Content-Type \"^(?:application(?:/soap\+|/)|text/)xml\" \
     \"id:'200000',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=XML\"

# Enable JSON request body parser.
# Initiate JSON Processor in case of JSON content-type; change accordingly
# if your application does not use 'application/json'
#
SecRule REQUEST_HEADERS:Content-Type \"^application/json\" \
     \"id:'200001',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=JSON\"

# Sample rule to enable JSON request body parser for more subtypes.
# Uncomment or adapt this rule if you want to engage the JSON
# Processor for \"+json\" subtypes
#
#SecRule REQUEST_HEADERS:Content-Type \"^application/[a-z0-9.-]+[+]json\" \
#     \"id:'200006',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=JSON\"

# Maximum request body size we will accept for buffering. If you support
# file uploads then the value given on the first line has to be as large
# as the largest file you are willing to accept. The second value refers
# to the size of data, with files excluded. You want to keep that value as
# low as practical.
#
SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072

# Store up to 128 KB of request body data in memory. When the multipart
# parser reaches this limit, it will start using your hard disk for
# storage. That is slow, but unavoidable.
#
SecRequestBodyInMemoryLimit 131072

# What do do if the request body size is above our configured limit.
# Keep in mind that this setting will automatically be set to ProcessPartial
# when SecRuleEngine is set to DetectionOnly mode in order to minimize
# disruptions when initially deploying ModSecurity.
#
SecRequestBodyLimitAction Reject

# Maximum parsing depth allowed for JSON objects. You want to keep this
# value as low as practical.
#
SecRequestBodyJsonDepthLimit 512

# Verify that we've correctly processed the request body.
# As a rule of thumb, when failing to process a request body
# you should reject the request (when deployed in blocking mode)
# or log a high-severity alert (when deployed in detection-only mode).
#
SecRule REQBODY_ERROR \"!@eq 0\" \
\"id:'200002', phase:2,t:none,log,deny,status:400,msg:'Failed to parse request body.',logdata:'%{reqbody_error_msg}',severity:2\"

# By default be strict with what we accept in the multipart/form-data
# request body. If the rule below proves to be too strict for your
# environment consider changing it to detection-only. You are encouraged
# _not_ to remove it altogether.
#
SecRule MULTIPART_STRICT_ERROR \"!@eq 0\" \
\"id:'200003',phase:2,t:none,log,deny,status:400, \
msg:'Multipart request body failed strict validation: \
PE %{REQBODY_PROCESSOR_ERROR}, \
BQ %{MULTIPART_BOUNDARY_QUOTED}, \
BW %{MULTIPART_BOUNDARY_WHITESPACE}, \
DB %{MULTIPART_DATA_BEFORE}, \
DA %{MULTIPART_DATA_AFTER}, \
HF %{MULTIPART_HEADER_FOLDING}, \
LF %{MULTIPART_LF_LINE}, \
SM %{MULTIPART_MISSING_SEMICOLON}, \
IQ %{MULTIPART_INVALID_QUOTING}, \
IP %{MULTIPART_INVALID_PART}, \
IH %{MULTIPART_INVALID_HEADER_FOLDING}, \
FL %{MULTIPART_FILE_LIMIT_EXCEEDED}'\"

# Did we see anything that might be a boundary?
#
SecRule MULTIPART_UNMATCHED_BOUNDARY \"!@eq 0\" \
\"id:'200004',phase:2,t:none,log,deny,msg:'Multipart parser detected a possible unmatched boundary.'\"

# PCRE Tuning
# We want to avoid a potential RegEx DoS condition
#
SecPcreMatchLimit 100000
SecPcreMatchLimitRecursion 100000

# Some internal errors will set flags in TX and we will need to look for these.
# All of these are prefixed with \"MSC_\".  The following flags currently exist:
#
# MSC_PCRE_LIMITS_EXCEEDED: PCRE match limits were exceeded.
#
SecRule TX:/^MSC_/ \"!@streq 0\" \
        \"id:'200005',phase:2,t:none,deny,msg:'ModSecurity internal error flagged: %{MATCHED_VAR_NAME}'\"

# -- Response body handling --------------------------------------------------

# Allow ModSecurity to access response bodies.
# You should have this directive enabled in order to identify errors
# and data leakage issues.
#
# Do keep in mind that enabling this directive does increases both
# memory consumption and response latency.
#
SecResponseBodyAccess On

# Which response MIME types do you want to inspect? You should adjust the
# configuration below to catch documents but avoid static files
# (e.g., images and archives).
#
SecResponseBodyMimeType text/plain text/html text/xml

# Buffer response bodies of up to 512 KB in length.
SecResponseBodyLimit 524288

# What happens when we encounter a response body larger than the configured
# limit? By default, we process what we have and let the rest through.
# That's somewhat less secure, but does not break any legitimate pages.
#
SecResponseBodyLimitAction ProcessPartial

# -- Filesystem configuration ------------------------------------------------

# The location where ModSecurity stores temporary files (for example, when
# it needs to handle a file upload that is larger than the configured limit).
#
# This default setting is chosen due to all systems have /tmp available however,
# this is less than ideal. It is recommended that you specify a location that's private.
#
SecTmpDir /tmp/

# The location where ModSecurity will keep its persistent data.  This default setting
# is chosen due to all systems have /tmp available however, it
# too should be updated to a place that other users can't access.
#
SecDataDir /tmp/

# -- File uploads handling configuration -------------------------------------

# The location where ModSecurity stores intercepted uploaded files. This
# location must be private to ModSecurity. You don't want other users on
# the server to access the files, do you?
#
#SecUploadDir /opt/modsecurity/var/upload/

# By default, only keep the files that were determined to be unusual
# in some way (by an external inspection script). For this to work you
# will also need at least one file inspection rule.
#
#SecUploadKeepFiles RelevantOnly

# Uploaded files are by default created with permissions that do not allow
# any other user to access them. You may need to relax that if you want to
# interface ModSecurity to an external program (e.g., an anti-virus).
#
#SecUploadFileMode 0600

# -- Debug log configuration -------------------------------------------------

# The default debug log configuration is to duplicate the error, warning
# and notice messages from the error log.
#
#SecDebugLog /opt/modsecurity/var/log/debug.log
#SecDebugLogLevel 3

# -- Audit log configuration -------------------------------------------------

# Log the transactions that are marked by a rule, as well as those that
# trigger a server error (determined by a 5xx or 4xx, excluding 404,
# level response status codes).
#
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus \"^(?:5|4(?!04)) \"

# Log everything we know about a transaction.
SecAuditLogParts ABDEFHIJZ

# Use a single file for logging. This is much easier to look at, but
# assumes that you will use the audit log only ocassionally.
#
SecAuditLogType Serial
SecAuditLog /var/log/apache2/modsec_audit.log

# Specify the path for concurrent audit logging.
#SecAuditLogStorageDir /opt/modsecurity/var/audit/

# -- Miscellaneous -----------------------------------------------------------

# Use the most commonly used application/x-www-form-urlencoded parameter
# separator. There's probably only one application somewhere that uses
# something else so don't expect to change this value.
#
SecArgumentSeparator &

# Settle on version 0 (zero) cookies, as that is what most applications
# use. Using an incorrect cookie version may open your installation to
# evasion attacks (against the rules that examine named cookies).
#
SecCookieFormat 0

# Specify your Unicode Code Point.
# This mapping is used by the t:urlDecodeUni transformation function
# to properly map encoded data to your language. Properly setting
# these directives helps to reduce false positives and negatives.
#
SecUnicodeMapFile unicode.mapping 20127

# Improve the quality of ModSecurity by sharing information about your
# current ModSecurity version and dependencies versions.
# The following information will be shared: ModSecurity version,
# Web Server version, APR version, PCRE version, Lua version, Libxml2
# version, Anonymous unique id for host.
# NB: As of April 2022, there is no longer any advantage to turning this
# setting On, as there is no active receiver for the information.
SecStatusEngine Off" > /apache2/modsecurity.conf
    error_handler $? "L'écriture du fichier /apache2/modsecurity.conf a échouée."
    
# Configuration ModEvasive

    touch /apache2/mods-available/evasive.conf
    error_handler $? "La création /apache2/mods-available/evasive.conf a échouée."

    echo "
    <IfModule mod_evasive20.c>
        DOSHashTableSize    496
        DOSPageCount        20
        DOSSiteCount        50
        DOSPageInterval     1
        DOSSiteInterval     1
        DOSBlockingPeriod   10
        DOSEmailNotify      $WEB_ADMIN_ADDRESS
        DOSLogDir           \"/var/log/mod_evasive\"
    </IfModule>
    " > /apache2/mods-available/evasive.conf
    error_handler $? "L'écriture du fichier /apache2/mods-available/evasive.conf a échouée."
    

# Sécurisation : .htaccess & masquage dans l'url des noms de dossier.
    
    logs_info "Sécurisation du .htaccess ..."
        
        sudo touch www/.htpasswd
        error_handler $? "La création du fichier www/.htpasswd a échouée."

        htpasswd -cb www/.htpasswd admin \${HTACCESS_PASSWORD}
        error_handler $? "L'écriture dans le fichier www/.htpasswd a échouée."

#======================================================================#
# Création et configuration de n sites-enabled                         #
#======================================================================#

    mkdir /apache2/sites-available/

    for site_name in siteA siteB
    do
        logs_info "Création du site " $site_name "..."
        
        mkdir www/$site_name
        error_handler $? "La création du dossier www/$site_name a échouée."
        
        sudo chown -R $USER:$USER www/$site_name
        error_handler $? "L'attribution des droits sur le dossier www/$site_name a échouée."
        
        sudo touch www/$site_name/index.html
        error_handler $? "La création du fichier www/$site_name/index.html a échouée."
        
        echo "
<html>
    <head>
        <title>Bienvenue sur le " $site_name " !</title>
    </head>
    <body>
        <h1> N'allez pas sur l'autre site, ce site est malveillant !</h1>
    </body>
</html>" > www/$site_name/index.html
        error_handler $? "L'écriture dans le fichier www/$site_name/index.html a échouée."

#HTTPS sur le n site

        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -sha256 -out /apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt -keyout /apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.key -subj "/C=FR/ST=Occitanie/L=Montpellier/O=IUT/OU=Herault/CN=$site_name.$DOMAIN_NAME/emailAddress=$WEB_ADMIN_ADDRESS" -passin pass:"$SSL_KEY_PASSWORD"
        error_handler $? "La génération de demande de signature de certifcat du site $site_name a échouée"

        openssl x509 -in /apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt -text -noout
        error_handler $? "La vérification du certificat a échouée."

        sudo chmod 600 /apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.key
        sudo chown root:root /apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt
        sudo chmod 440 /apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt

# Configuration des Virtual Host

        touch /apache2/sites-available/$site_name.conf
        error_handler $? "La création du fichier /etc/apache2/sites-available/$site_name.conf a échouée."

        echo "
<VirtualHost *:$WEB_PORT>
    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteRule ^/?(.*) https://%SERVER_NAME/$1 [R=301,L]
</VirtualHost>
<VirtualHost *:443>
    ServerAdmin $WEB_ADMIN_ADDRESS
    ServerName $site_name.$DOMAIN_NAME
    DocumentRoot /var/www/$site_name

    SSLEngine on
    SSLCertificateFile /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt
    SSLCertificateKeyFile /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.key

    Header set Strict-Transport-Security \"max-age=31536000; includeSubDomains\"

    <Directory /var/www/$site_name>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
  </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>" > /apache2/sites-available/$site_name.conf
        error_handler $? "L'écriture du fichier /etc/apache2/sites-available/$site_name.conf a échouée."

# Création de la page confidentielle

        mkdir www/$site_name/confidential
        error_handler $? "La création du dossier www/$site_name/confidential a échouée."

        touch www/$site_name/confidential/confidential.php
        error_handler $? "La création du fichier /www/$site_name/confidential/confidential.php a échouée."
        
        echo "
<html>
    <head>
        <title>Page protégée du site $site_name</title>
    </head>
    <body>
        <h1> TOP SECRET </h1>
<?php
    \$user = \""$DB_ADMIN_USERNAME"\";
    \$password = \""DB_ADMIN_PASSWORD"\";
    \$database = \""$DB_NAME"\";
    \$table = \"todo_list\";
    try
    {   \$db = new PDO("",$,\$password);
        echo \"<h2>TODO</h2> <ol>\";
        foreach(\$db->query(\"SELECT content FROM \$table\") as \$row)
         { echo \"<li>\" .\$row['content'] . \"</li>\";
         }
        echo \"</ol>\";
    } 
    catch (PDOException \$e)
    {   print \"ERROR ! : \" . \$e->getMessage() . \"<br/>\";
        die();
    }
?>
    </body>
</html>" > www/$site_name/confidential/confidential.php
        error_handler $? "L'écriture dans le fichier /www/$site_name/confidential/confidential.php a échouée."
        
        touch www/$site_name/confidential/.htaccess
        error_handler $? "La création du fichier www/$site_name/confidential/.htaccess a échouée."
        echo "AuthType Basic
        AuthName \"Accès protégé\"
        AuthUserFile /var/www/.htpasswd
        require valid-user
        Options -Indexes" > www/$site_name/confidential/.htaccess
        error_handler $? "L'écriture du fichier /www/$site_name/confidential/.htaccess a échouée."

        logs_success "$site_name créé."
    done


#======================================================================#

logs_info "Lancement du conteneur $WEB_CONTAINER_NAME en cours..."
docker-compose up -d web
sleep 60

# Chargement des sites
    for site_name in siteA siteB
    do
        docker exec -i web a2ensite $site_name
        error_handler $? "L'activation du fichier de configuration du site $site_name a échouée."
    done



#======================================================================#
# Activation des modules ssl et apache                                 #
#======================================================================#
logs_info "Activation des modules pour apache en cours..."

    docker exec -i web a2enmod ssl
    error_handler $? "L'activation du module Mod_ssl a échouée."

    docker exec -i web a2ensite default-ssl
    error_handler $? "L'activation du module default_ssl a échouée."

    docker exec -i web a2enmod rewrite
    error_handler $? "L'activation du module Mod_rewrite a échouée."

    docker exec -i web a2enmod headers
    error_handler $? "L'activation du module Mod_headers a échouée."

logs_success "Activation des modules pour apache terminée."

#======================================================================#
# Installation du ModSecurity                                          #
#======================================================================#

logs_info "Installation de ModSecurity en cours..."
    
    docker exec -i web apt install -y libapache2-mod-security2 
    error_handler $? "L'installation de libapache2-mod-security2 a échouée."
    
    docker exec -i web a2enmod security2
    error_handler $? "L'activation de libapache2-mod-security2 a échouée."

    #TODO trouver un moyen de vérifier la bonne installation de modsecurity avec un retour de variable.
    # "security2_module (shared)"
    docker exec -i web apachectl -M | grep --color security
    
    docker exec -i web mv /etc/apache2/modsecurity/modsecurity.conf /etc/modsecurity/modsecurity.conf
    error_handler $? "Déplacement du fichier /etc/apache2/modsecurity/modsecurity.conf a échouée."

    # sudo cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
    # error_handler $? "Copie du fichier /etc/modsecurity/modsecurity.conf-recommended a échouée."
    
    #TODO Redémarrage apache

    # sudo systemctl restart apache2
    # error_handler $? "Le rédémarrage du service apache2 a échoué."
    
logs_success "Installation de ModSecurity terminée."

#======================================================================#
# Installation du ModEvasive                                           #
#======================================================================#

logs_info "Installation de ModEvasive en cours..."

    #TODO :
    # sudo apt install -y libapache2-mod-evasive
    # error_handler $? "L'installation du service libapache2-mod-evasive a échouée."
    
    # sudo mkdir -p /var/log/mod_evasive
    #TODO

    # sudo chown -R www-data:www-data /var/log/mod_evasive
    #TODO

    docker exec -i web a2enmod evasive
    error_handler $? "L'activation du ModEvasive a échouée."
    
    #TODO :
    # sudo systemctl restart apache2
    # error_handler $? "Le redémarrage du service apache a échouée."

logs_success "Installation de ModEvasive terminée."


#======================================================================#
# Configuration de phpmyadmin                                          #
#======================================================================#

# Sécuriser phpMyAdmin avec .htaccess
htpasswd -cb phpmyadmin/.htpasswd $PHP_ADMIN_USERNAME $PHP_ADMIN_PASSWORD
error_handler $? "La création du fichier .htpasswd a échouée."

touch phpmyadmin/.htaccess
error_handler $? "La création du fichier phpmyadmin/.htaccess a échouée."

echo "AuthType Basic
AuthName \"Accès protégé\"
AuthUserFile /usr/local/apache2/htdocs/.htpasswd
require valid-user" > phpmyadmin/.htaccess
error_handler $? "L'écriture du fichier phpmyadmin/.htaccess a échouée."

#======================================================================#
# Configuration de MySQL                                               #
#======================================================================#

logs_info "Configuration du service mysql en cours..."
docker-compose up -d $DB_CONTAINER_NAME
sleep 50

docker exec -i $DB_CONTAINER_NAME mysql -uroot -p$DB_ROOT_PASSWORD -e "CREATE USER '$DB_ADMIN_USERNAME'@'localhost' IDENTIFIED BY '$DB_ADMIN_PASSWORD';"
error_handler $? "La création de l'utilisateur administrateur $DB_ADMIN_USERNAME a échouée."
 
docker exec -i $DB_CONTAINER_NAME mysql -uroot -p$DB_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_ADMIN_USERNAME'@'localhost' WITH GRANT OPTION;"

docker exec -i $DB_CONTAINER_NAME mysql -uroot -p$DB_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

docker exec -i $DB_CONTAINER_NAME mysql -u$DB_ADMIN_USERNAME -p$DB_ADMIN_PASSWORD -e "CREATE DATABASE $DB_NAME;"
error_handler $? "La création de la base de données $DB_NAME a échouée."

docker exec -i $DB_CONTAINER_NAME mysql -u$DB_ADMIN_USERNAME -p$DB_ADMIN_PASSWORD -e "USE $DB_NAME; CREATE TABLE todolist (item_id INT AUTO_INCREMENT, content VARCHAR(255), PRIMARY KEY (item_id));"
error_handler $? "Création de la table todolist a échouée."

docker exec -i $DB_CONTAINER_NAME mysql -u$DB_ADMIN_USERNAME -p$DB_ADMIN_PASSWORD -e "USE $DB_NAME; INSERT INTO todolist (task) VALUES ('Task 1'), ('Task 2'), ('Task 3');"
error_handler $? "Insertion des données dans la table todolist a échouée."

logs_success "Configuration du service mysql terminée."

#======================================================================#

# Démarrer les services

docker-compose up -d
error_handler $? "L a échouée." #TODO



# Afficher les adresses IP des conteneurs
logs_info "Adresses IP des conteneurs :"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $WEB_CONTAINER_NAME
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PHP_CONTAINER_NAME
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PHPMYADMIN_CONTAINER_NAME

# Récupérer les adresses IP des conteneurs
WEB_CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $WEB_CONTAINER_NAME)
PHP_CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PHP_CONTAINER_NAME)
PHPMYADMIN_CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PHPMYADMIN_CONTAINER_NAME)

# Mettre à jour le fichier /etc/hosts
echo "$WEB_CONTAINER_IP siteA.$DOMAIN_NAME" | sudo tee -a /etc/hosts
echo "$WEB_CONTAINER_IP siteB.$DOMAIN_NAME" | sudo tee -a /etc/hosts
echo "$PHPMYADMIN_CONTAINER_IP phpmyadmin.$DOMAIN_NAME" | sudo tee -a /etc/hosts

# Afficher les adresses IP des conteneurs
logs_info "Adresses IP des conteneurs :"
logs_info "Apache (siteA et siteB) : $WEB_CONTAINER_IP siteA.$DOMAIN_NAME siteB.$DOMAIN_NAME"
logs_info "PHP : $PHP_CONTAINER_IP phpmyadmin.$DOMAIN_NAME"
logs_info "phpMyAdmin : $PHPMYADMIN_CONTAINER_IP"


#======================================================================#

logs_end "Installation et configuration des services apache, mysql, php et phpmyadmin sous docker terminée."
exit 0
