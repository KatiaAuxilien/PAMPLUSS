#!/bin/bash

# .·:'''''''''''''''''''''''''''''''''''''''''''''''''''''''':·.
# : :  ____                       _                          : :
# : : |  _ \ __ _ _ __ ___  _ __ | |_   _ ___ ___            : :
# : : | |_) / _` | '_ ` _ \| '_ \| | | | / __/ __|           : :
# : : |  __/ (_| | | | | | | |_) | | |_| \__ \__ \           : :
# : : |_|   \__,_|_| |_| |_| .__/|_|\__,_|___/___/        _  : :
# : : | |__   __ _ _ __ ___|_|    _ __ ___   ___| |_ __ _| | : :
# : : | '_ \ / _` | '__/ _ \_____| '_ ` _ \ / _ \ __/ _` | | : :
# : : | |_) | (_| | | |  __/_____| | | | | |  __/ || (_| | | : :
# : : |_.__/ \__,_|_|  \___|     |_| |_| |_|\___|\__\__,_|_| : :
# '·:........................................................:·'

#===================================================================#
#                            Sommaire                               #
#===================================================================#
# 1. Vérifications de l'environnement et des variables              #
# 2. Préparation de l'arborescence                                  #
# 3. Installation de Apache                                         #
# 4. Configuration de Apache                                        #
# 5. Sécurisation de Apache                                         #
# 6. Création des sites                                             #
# 7. Installation et configuration de PHP                           #
# 8. Installation et configuration de mysql                         #
# 9. Installation de PhpMyAdmin                                     #
#===================================================================#

#===================================================================#
source ../.common.sh
#===================================================================#

required_vars_start=(
"DOMAIN_NAME"
"WEB_ADMIN_ADDRESS"
"WEB_PORT"
"WEB_ADMIN_USER"
"WEB_ADMIN_PASSWORD"
"SSL_KEY_PASSWORD"

"PHPMYADMIN_HTACCESS_PASSWORD"
"PHPMYADMIN_ADMIN_ADDRESS"
"PHPMYADMIN_ADMIN_USERNAME"
"PHPMYADMIN_ADMIN_PASSWORD"

"DB_PORT"
"DB_ROOT_PASSWORD"
"DB_ADMIN_USERNAME"
"DB_ADMIN_PASSWORD"
"DB_ADMIN_ADDRESS"
"DB_NAME"
)

#===================================================================#
# 1. Vérifications de l'environnement et des variables              #
#===================================================================#

source ./.common.sh

logs_info "Vérification des services déjà installés ..."

check_apache_installed
apache_installed=$?

check_php_installed
php_installed=$?

check_mysql_installed
mysql_installed=$?

check_phpmyadmin_installed
phpmyadmin_installed=$?

error_count=0

  if [ $apache_installed -eq 1 ]; then
      logs_error "Une installation d'apache existe déjà."
      let error_count++
  fi

  if [ $php_installed -eq 1 ]; then
      logs_error "Une installation de php existe déjà."
      let error_count++
  fi

  if [ $mysql_installed -eq 1 ]; then
      logs_error "Une installation de mysql existe déjà."
      let error_count++
  fi

  if [ $phpmyadmin_installed -eq 1 ]; then
      logs_error "Une installation de phpmyadmin existe déjà."
      let error_count++
  fi

if [ $error_count -ne 0 ];then
    logs_end "Installation annulée."
  exit 1
fi

logs_success "Vérification réussie, les services ne sont pas déjà installés."

#===================================================================#
# 2. Préparation de l'arborescence                                  #
#===================================================================#

logs_info "Mise à jour des paquets en cours ..."

    run_command sudo apt update -y
    error_handler $? "La mise à jour des paquets a échouée."

logs_success "Mise à jour des paquets terminée."

#===================================================================#
# 3. Installation de Apache                                         #
#===================================================================#
logs_info "Apache > Installation et configuration avancée en cours ..."

logs_info "Apache > Installation du service en cours ..."

    run_command sudo apt install -y apache2 apache2-utils
    error_handler $? "Apache > L'installation du service a échouée."

    run_command sudo ufw allow 'Apache'
    error_handler $? "Apache > L'autorisation du service apache auprès du pare-feu a échouée."

logs_success "Apache > Installation du service terminée."

logs_info "Apache > Lancement du service en cours..."

    run_command sudo systemctl start apache2
    error_handler $? "Apache > Le lancement du service apache a échouée."
        
logs_success "Apache > Service lancé."

#===================================================================#
# 4. Configuration de Apache                                        #
#===================================================================#
logs_info "Apache > Configuration basique du service en cours ..."

    echo "ServerRoot \"/etc/apache2\"

ServerName $DOMAIN_NAME

ServerAdmin $WEB_ADMIN_ADDRESS

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
    Options -Indexes
    AllowOverride All
    Require all granted
</Directory>

<Directory /var/www/>
    Options -Indexes
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

IncludeOptional sites-enabled/*.conf" > /etc/apache2/apache2.conf
    error_handler $? "Apache > L'écriture du fichier de configuration /etc/apache2/apache2.conf a échouée."


CERT_NAME="servicescomplexe"

    echo "<VirtualHost *:80>
  ServerAdmin $WEB_ADMIN_ADDRESS
  ServerName $DOMAIN_NAME

  RewriteEngine On
  RewriteCond %{HTTPS} off
  RewriteRule ^ https://%{HTTP_HOST}:$WEB_PORT%{REQUEST_URL} [R,L]
</VirtualHost>

<VirtualHost *:443>
  ServerAdmin $WEB_ADMIN_ADDRESS
  ServerName $DOMAIN_NAME

  RewriteEngine On
  RewriteCond %{SERVER_PORT} 443
  RewriteRule ^ https://%{HTTP_HOST}:$WEB_PORT%{REQUEST_URL} [R,L]

  SSLEngine on
  SSLCertificateFile /etc/apache2/certificate/"$CERT_NAME"_server.crt
  SSLCertificateKeyFile /etc/apache2/certificate/"$CERT_NAME"_server.key

  <Directory /var/www/html>
    Options -Indexes
    AllowOverride All
    Require all granted
  </Directory>
 
  ErrorLog \${APACHE_LOG_DIR}/error.log
  CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>

<VirtualHost *:$WEB_PORT>
  ServerAdmin $WEB_ADMIN_ADDRESS
  ServerName $DOMAIN_NAME

  DocumentRoot /var/www/html

  SSLEngine on
  SSLCertificateFile /etc/apache2/certificate/"$CERT_NAME"_server.crt
  SSLCertificateKeyFile /etc/apache2/certificate/"$CERT_NAME"_server.key

  <Directory /var/www/html>
    Options -Indexes
    AllowOverride All
    Require all granted
  </Directory>
 
  ErrorLog \${APACHE_LOG_DIR}/error.log
  CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>" > /etc/apache2/sites-enabled/000-default.conf
    error_handler $? "Apache > L'écriture du fichier de configuration du site par défaut a échouée."

    echo "127.0.0.1 $DOMAIN_NAME" >> /etc/hosts
    error_handler $? "Apache > L'écriture du fichier /etc/hosts a échouée."

    echo "# If you just change the port or add more ports here, you will likely also
# have to change the VirtualHost statement in
# /etc/apache2/sites-enabled/000-default.conf

Listen $WEB_PORT

<IfModule ssl_module>
  Listen 443
</IfModule>

<IfModule mod_gnutls.c>
  Listen 443
</IfModule>" > /etc/apache2/ports.conf 
    error_handler $? "Apache > L'écriture du fichier de configuration des ports a échouée."

logs_success "Apache > Configuration basique du service terminée."

logs_info "Apache > PHP > Installation du module php pour apache en cours ..."
    run_command sudo apt-get install -y libapache2-mod-php
    error_handler $? "Apache > PHP > L'installation du module php pour apache a échouée."
logs_success "Apache > PHP > Installation du module php pour apache terminée."

# Activer les modules PHP nécessaires pour Apache
logs_info "Apache > PHP > Activation du module php en cours ..."
    run_command sudo a2enmod php8.3
    error_handler $? "Apache > PHP > L'activation du module php a échouée."
logs_success "Apache > PHP > Activation du module php terminée."

#===================================================================#
# 5. Sécurisation de Apache                                         #
#===================================================================#
logs_info "Apache > Sécurisation du service en cours..."

    logs_info "Apache > Sécurisation > Activation des modules headers et rewrite en cours."

        run_command sudo a2enmod headers
        error_handler $? "Apache > Sécurisation > L'activation du module Mod_headers a échouée."

        run_command sudo a2enmod rewrite
        error_handler $? "Apache > Sécurisation > L'activation du module Mod_rewrite a échouée."

    logs_success "Apache > Sécurisation > Modules headers et rewrite activé."

    logs_info "Apache > Sécurisation > HTTPS > Installation d'openssl et ssl-cert en cours."

        run_command sudo apt-get install -y openssl ssl-cert
        error_handler $? "L'installation d'openssl a échouée."

    logs_success "Apache > Sécurisation > HTTPS > Installation d'openssl et ssl-cert terminée."

    logs_info "Apache > Sécurisation > HTTPS > Activation du module ssl en cours."

        run_command sudo a2enmod ssl
        error_handler $? "Apache > Sécurisation > HTTPS > L'activation du module Mod_ssl a échouée."

        run_command a2ensite default-ssl
        error_handler $? "Apache > Sécurisation > HTTPS > L'activation du module default_ssl a échouée."

    logs_success "Apache > Sécurisation > HTTPS > Activation du module ssl terminée."

    logs_info "Apache > Sécurisation > HTTPS > Génération du certificat et de la clé en cours ..."

        run_command mkdir -p /etc/apache2/certificate/
        error_handler $? "Apache > Sécurisation > HTTPS > La création du dossier /etc/apache2/certificate/ a échouée."

        run_command sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -sha256 -out /etc/apache2/certificate/"$CERT_NAME"_server.crt -keyout /etc/apache2/certificate/"$CERT_NAME"_server.key -subj "/C=FR/ST=Occitanie/L=Montpellier/O=IUT/OU=Herault/CN=$DOMAIN_NAME/emailAddress=$WEB_ADMIN_ADDRESS" -passin pass:"$SSL_KEY_PASSWORD"
        error_handler $? "Apache > Sécurisation > HTTPS > La génération de demande de signature de certificat a échouée."

        run_command openssl x509 -in /etc/apache2/certificate/"$CERT_NAME"_server.crt -text -noout
        error_handler $? "Apache > Sécurisation > HTTPS > La vérification du certificat a échouée."

        run_command sudo chmod 600 /etc/apache2/certificate/"$CERT_NAME"_server.key
        error_handler $? "Apache > Sécurisation > HTTPS > ..."

        run_command sudo chown root:root /etc/apache2/certificate/"$CERT_NAME"_server.crt
        error_handler $? "Apache > Sécurisation > HTTPS > ..."

        run_command sudo chmod 440 /etc/apache2/certificate/"$CERT_NAME"_server.crt
        error_handler $? "Apache > Sécurisation > HTTPS > ..."

    logs_success "Apache > Sécurisation > HTTPS > Génération du certificat et de la clé terminée."

    # Sécurisation - Installation et configuration de ModSecurity

    logs_info "Apache > Sécurisation > ModSecurity > Préparation de la configuration en cours."

        run_command sudo apt-get install -y libapache2-mod-security2
        error_handler $? "Apache > Sécurisation > ModSecurity > L'installation du module a échouée."

        # Récupérer l'adresse IP publique de l'utilisateur
        IP=$(curl -s https://api.ipify.org)

        # Vérifier si l'adresse IP a été récupérée correctement
        if [ -z "$IP" ]; then
          logs_error "Apache > Sécurisation > ModSecurity > Impossible de récupérer l'adresse IP."
          exit 1
        fi

        echo "# -- Rule engine initialization ----------------------------------------------

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
SecRule REQUEST_HEADERS:Content-Type \"^(?:application(?:/soap\+|/)|text/)xml\" \\
     \"id:'200000',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=XML\"

# Enable JSON request body parser.
# Initiate JSON Processor in case of JSON content-type; change accordingly
# if your application does not use 'application/json'
#
SecRule REQUEST_HEADERS:Content-Type \"^application/json\" \\
     \"id:'200001',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=JSON\"

# Sample rule to enable JSON request body parser for more subtypes.
# Uncomment or adapt this rule if you want to engage the JSON
# Processor for \"+json\" subtypes
#
#SecRule REQUEST_HEADERS:Content-Type \"^application/[a-z0-9.-]+[+]json\" \\
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
SecRule REQBODY_ERROR \"!@eq 0\" \\
\"id:'200002', phase:2,t:none,log,deny,status:400,msg:'Failed to parse request body.',logdata:'%{reqbody_error_msg}',severity:2\"

# By default be strict with what we accept in the multipart/form-data
# request body. If the rule below proves to be too strict for your
# environment consider changing it to detection-only. You are encouraged
# _not_ to remove it altogether.
#
SecRule MULTIPART_STRICT_ERROR \"!@eq 0\" \\
\"id:'200003',phase:2,t:none,log,deny,status:400, \\
msg:'Multipart request body failed strict validation: \\
PE %{REQBODY_PROCESSOR_ERROR}, \\
BQ %{MULTIPART_BOUNDARY_QUOTED}, \\
BW %{MULTIPART_BOUNDARY_WHITESPACE}, \\
DB %{MULTIPART_DATA_BEFORE}, \\
DA %{MULTIPART_DATA_AFTER}, \\
HF %{MULTIPART_HEADER_FOLDING}, \\
LF %{MULTIPART_LF_LINE}, \\
SM %{MULTIPART_MISSING_SEMICOLON}, \\
IQ %{MULTIPART_INVALID_QUOTING}, \\
IP %{MULTIPART_INVALID_PART}, \\
IH %{MULTIPART_INVALID_HEADER_FOLDING}, \\
FL %{MULTIPART_FILE_LIMIT_EXCEEDED}'\"

# Did we see anything that might be a boundary?
#
SecRule MULTIPART_UNMATCHED_BOUNDARY \"!@eq 0\" \\
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
SecRule TX:/^MSC_/ \"!@streq 0\" \\
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
SecAuditLogRelevantStatus \"^(?:5|4(?!04))\"

# Log everything we know about a transaction.
SecAuditLogParts ABCEFHJKZ

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
SecStatusEngine Off

SecRule REMOTE_ADDR \"^$IP\$\" \"phase:1,pass,nolog,id:1000001\"
" > /etc/modsecurity/modsecurity.conf
        error_handler $? "Apache > Sécurisation > ModSecurity > La configuration de /etc/modsecurity/modsecurity.conf a échouée."
logs_success "Apache > Sécurisation > ModSecurity > L'adresse IP $IP a été ajoutée à la configuration de ModSecurity."

        echo "<IfModule security2_module>
  # Default Debian dir for modsecurity's persistent data
  SecDataDir /var/cache/modsecurity

  # Include all the *.conf files in /etc/modsecurity.
  # Keeping your local configuration in that directory
  # will allow for an easy upgrade of THIS file and
  # make your life easier
        IncludeOptional /etc/modsecurity/*.conf

  # Include OWASP ModSecurity CRS rules if installed
  IncludeOptional /etc/apache2/modsecurity-crs/coreruleset-3.3.0/crs-setup.conf
  IncludeOptional /etc/apache2/modsecurity-crs/coreruleset-3.3.0/rules/*.conf
</IfModule>" > /etc/apache2/mods-enabled/security2.conf
        error_handler $? "Apache > Sécurisation > ModSecurity > La configuration de /etc/apache2/mods-enabled/security2.conf a échouée."

        # ModSecurity : Règles de base OWASP (CRS)

        logs_info "Apache > Sécurisation > ModSecurity > Règles OWASP (CRS) > Préparation de la configuration en cours."

            run_command wget https://github.com/coreruleset/coreruleset/archive/v3.3.0.tar.gz
            error_handler $? "Apache > Sécurisation > ModSecurity > wget https://github.com/coreruleset/coreruleset/archive/v3.3.0.tar.gz a échoué."

            run_command tar xvf v3.3.0.tar.gz
            error_handler $? "Apache > Sécurisation > ModSecurity > tar xvf v3.3.0.tar.gz a échoué."

            run_command rm -rf v3.3.0.tar.gz
            error_handler $? "Apache > Sécurisation > ModSecurity > rm -rf v3.3.0.tar.gz a échoué."

            run_command sudo mkdir /etc/apache2/modsecurity-crs/
            error_handler $? "Apache > Sécurisation > ModSecurity > ..."

            run_command sudo mv coreruleset-3.3.0/ /etc/apache2/modsecurity-crs/
            error_handler $? "Apache > Sécurisation > ModSecurity > mv coreruleset-3.3.0/ /etc/apache2/modsecurity-crs/ a échoué."

            run_command sudo mv /etc/apache2/modsecurity-crs/coreruleset-3.3.0/crs-setup.conf.example /etc/apache2/modsecurity-crs/coreruleset-3.3.0/crs-setup.conf
            error_handler $? "Apache > Sécurisation > ModSecurity > mv /etc/apache2/modsecurity-crs/coreruleset-3.3.0/crs-setup.conf.example /etc/apache2/modsecurity-crs/coreruleset-3.3.0/crs-setup.conf a échoué."

        logs_success "Apache > Sécurisation > ModSecurity > Règles OWASP (CRS) > Préparation de la configuration terminée."

    logs_success "Apache > Sécurisation > ModSecurity > Préparation de la configuration terminée."
      
    logs_info "Apache > Sécurisation > ModSecurity > Activation en cours ..."
      
      run_command sudo a2enmod security2
      error_handler $? "Apache > Sécurisation > ModSecurity > L'activation du module a échouée."

    logs_success "Apache > Sécurisation > ModSecurity > Module activé."

    # Sécurisation - Installation et configuration de ModEvasive
    logs_info "Apache > Sécurisation > ModEvasive > Préparation de la configuration en cours ..."

        run_command sudo apt-get install -y libapache2-mod-evasive
        error_handler $? "Apache > Sécurisation > ModEvasive > L'installation du module a échouée."

        run_command sudo mkdir /var/log/mod_evasive

        echo "<IfModule mod_evasive20.c>
    DOSHashTableSize    3097
    DOSPageCount        2
    DOSSiteCount        50
    DOSPageInterval     1
    DOSSiteInterval     1
    DOSBlockingPeriod   10
    DOSEmailNotify      $WEB_ADMIN_ADDRESS
    DOSLogDir           \"/var/log/mod_evasive\"
    DOSWhitelist        $IP
</IfModule>" > /etc/apache2/mods-enabled/evasive.conf
        error_handler $? "Apache > Sécurisation > ModEvasive > L'écriture du fichier /etc/apache2/mods-enabled/evasive.conf a échouée."

    logs_success "Apache > Sécurisation > ModEvasive > Préparation de la configuration terminée."

    logs_info "Apache > Sécurisation > ModEvasive > Activation en cours ..."

        run_command sudo a2enmod evasive
        error_handler $? "Apache > Sécurisation > ModEvasive > L'activation a échouée."

    logs_success "Apache > Sécurisation > ModEvasive > Module activé."

    #TODO BONUS : Sécurisation - Installation et configuration de ModRatelimit

logs_success "Apache > Sécurisation > Installations et configurations terminées."

logs_info "Apache > Redémarrage du service en cours..."

    run_command sudo systemctl reload apache2
    error_handler $? "Apache > Le redémarrage du service a échoué."
        
logs_success "Apache > Service redémarré."

#===================================================================#
# 6. Création des sites                                             #
#===================================================================#

# Création de la page principale
logs_info "Apache > Site page d'accueil > Création et configuration de la page principale en cours ..."

    run_command touch /var/www/html/index.html
    error_handler $? "Apache > Site page d'accueil > La création du fichier /var/www/html/index.html a échouée."

    run_command chmod -R 755 /var/www/html/index.html
    error_handler $? "Apache > Site page d'accueil > L'attribution des droits sur le fichier /var/www/html/index.html a échoué."

    echo "<!DOCTYPE html>
<html>
  <head>
    <title>Accueil de $DOMAIN_NAME</title>
    <meta charset=\"utf-8\"/>
    <style>
body{
  background-color: #C6E7FF;
  font-family: Avantgarde, TeX Gyre Adventor, URW Gothic L, sans-serif;
}
      </style>
  </head>
  <body>
    <h1>Bienvenue sur $DOMAIN_NAME ! 👋</h1>
    <p> ✨ <a href=\"https://siteA.$DOMAIN_NAME:$WEB_PORT\">Visiter siteA.$DOMAIN_NAME</a> </p>
    <p> ✨ <a href=\"https://siteB.$DOMAIN_NAME:$WEB_PORT\">Visiter siteB.$DOMAIN_NAME</a> </p>
  </body>
</html> " > /var/www/html/index.html
    error_handler $? "Apache > Site page d'accueil > L'écriture de la page /var/www/index.html a échouée."

logs_success "Apache > Site page d'accueil > Création et configuration de la page principale terminée."

# Configuration du .htaccess et .htpasswd
logs_info "Apache > .htaccess > Configuration en cours ..."

    run_command sudo apt install apache2-utils -y
    error_handler $? "Apache > .htaccess > L'installation de apache2-utils pour la génération de .htpasswd a échouée."

    run_command touch /var/www/.htpasswd
    error_handler $? "Apache > .htaccess > La création du fichier /var/www/.htpasswd a échouéee."

    run_command sudo htpasswd -b /var/www/.htpasswd admin $WEB_HTACCESS_PASSWORD
    error_handler $? "Apache > .htaccess > L'écriture dans le fichier /var/www/.htpasswd avec la commande htpasswd a échouée."

logs_success "Apache > .htaccess > Configuration terminée."

# Création de deux sites (siteA, siteB)
    for site_name in siteA siteB
    do
    logs_info "Apache > $site_name > Configuration du site en cours ..."
        
        run_command sudo mkdir /var/www/$site_name
        error_handler $? "Apache > $site_name > La création du dossier /var/www/$site_name a échouée."
        
        run_command sudo chmod -R 755 /var/www/$site_name
        error_handler $? "Apache > $site_name > L'attribution des droits sur le dossier /var/www/$site_name a échouée."
        
        run_command sudo touch /var/www/$site_name/index.html
        error_handler $? "Apache > $site_name > La création du fichier /var/www/$site_name/index.html a échouée."

        echo "<!DOCTYPE html>
<html>
    <head>
        <title>$site_name</title>
        <meta charset=\"utf-8\"/>
    <style>
body{
  background-color: #C6E7FF;
  font-family: Avantgarde, TeX Gyre Adventor, URW Gothic L, sans-serif;
}
      </style>
    </head>
    <body>
      <h1>Bienvenue sur le " $site_name " ! 👋</h1>
        <h2> N'allez pas sur l'autre site, ce site est malveillant !</h2>
        <a href=\"https://$site_name.$DOMAIN_NAME:79/confidential/confidential.php\"><h2> Page confidentiel ici</h2></a>
    </body>
</html>" > /var/www/$site_name/index.html
        error_handler $? "Apache > $site_name > L'écriture dans le fichier /var/www/$site_name/index.html a échouée."

        run_command sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -sha256 -out /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt -keyout /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.key -subj "/C=FR/ST=Occitanie/L=Montpellier/O=IUT/OU=Herault/CN=$site_name.$DOMAIN_NAME/emailAddress=$WEB_ADMIN_ADDRESS" -passin pass:"$SSL_KEY_PASSWORD"
        error_handler $? "Apache > $site_name > La génération de demande de signature de certifcat du site $site_name a échouée"

        run_command openssl x509 -in /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt -text -noout
        error_handler $? "Apache > $site_name > La vérification du certificat a échouée."
        
        run_command sudo chmod 600 /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.key
        run_command sudo chown root:root /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt
        run_command sudo chmod 440 /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt

        #Création des Virtual Host
        run_command touch /etc/apache2/sites-available/$site_name.conf
        error_handler $? "Apache > $site_name > La création du fichier /etc/apache2/sites-available/$site_name.conf a échouée."


        echo "<VirtualHost *:80>
  ServerAdmin $WEB_ADMIN_ADDRESS
  ServerName $site_name.$DOMAIN_NAME

  RewriteEngine On
  RewriteCond %{HTTPS} off
  RewriteRule ^ https://%{HTTP_HOST}:$WEB_PORT%{REQUEST_URL} [R,L]
</VirtualHost>

<VirtualHost *:443>
  ServerAdmin $WEB_ADMIN_ADDRESS
  ServerName $site_name.$DOMAIN_NAME

  RewriteEngine On
  RewriteCond %{SERVER_PORT} 443
  RewriteRule ^ https://%{HTTP_HOST}:$WEB_PORT%{REQUEST_URL} [R,L]

  SSLEngine on
  SSLCertificateFile /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt
  SSLCertificateKeyFile /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.key

  <Directory /var/www/html>
    Options -Indexes
    AllowOverride All
    Require all granted
  </Directory>
 
  ErrorLog \${APACHE_LOG_DIR}/$site_name-error.log
  CustomLog \${APACHE_LOG_DIR}/$site_name-access.log combined
</VirtualHost>

<VirtualHost *:$WEB_PORT>
  ServerAdmin $WEB_ADMIN_ADDRESS
  ServerName $site_name.$DOMAIN_NAME

  DocumentRoot /var/www/$site_name

  SSLEngine on
  SSLCertificateFile /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.crt
  SSLCertificateKeyFile /etc/apache2/certificate/"$site_name"".""$DOMAIN_NAME"_server.key

  <Directory /var/www/$site_name>
    Options -Indexes
    AllowOverride All
    Require all granted
  </Directory>
 
  ErrorLog \${APACHE_LOG_DIR}/$site_name-error.log
  CustomLog \${APACHE_LOG_DIR}/$site_name-access.log combined
</VirtualHost>" > /etc/apache2/sites-available/$site_name.conf
        error_handler $? "Apache > $site_name > L'écriture du fichier /etc/apache2/sites-available/$site_name.conf a échouée."

# Création de la page confidentielle
        run_command mkdir /var/www/$site_name/confidential
        error_handler $? "Apache > $site_name > La création du dossier /var/www/$site_name/confidential a échouée."
        
        run_command chmod -R 755 /var/www/$site_name/confidential
        error_handler $? "Apache > $site_name > L'attribution des droits au dossier /var/www/$site_name/confidential a échouée."

        run_command touch /var/www/$site_name/confidential/confidential.php
        error_handler $? "Apache > $site_name > La création du fichier /var/www/$site_name/confidential/confidential.php a échouée."
        
        run_command chmod -R 755 /var/www/$site_name/confidential/confidential.php
        error_handler $? "Apache > $site_name > L'attribution des droits au fichier /var/www/$site_name/confidential/confidential.php a échouée."

        echo "<!DOCTYPE html>
<html>
    <head>
        <title>Page protégée du site $site_name</title>
        <meta charset=\"utf-8\"/>
    </head>
    <style>
body{
  background-color: #C6E7FF;
  font-family: Avantgarde, TeX Gyre Adventor, URW Gothic L, sans-serif;
}
table {
  width: 100%;
  border: 1px solid;
}
.todo{
  background-color: #B06161;
  text-align: center;

}
.inprogess{
  background-color: #FFCF9D;
  text-align: center;
}
.done{
  background-color: #D0E8C5;
  text-align: center;
}
      </style>
      <script>

      </script>
    <body>
        <h1> TOP SECRET </h1>
<?php
    \$user = \""$DB_ADMIN_USERNAME"\";
    \$password = \""$DB_ADMIN_PASSWORD"\";
    \$database = \""$DB_NAME"\";
    \$table = \"todo_list\";


    \$session = new mysqli(\"localhost\",\$user,\$password, \$database, $DB_PORT);

    if (\$session->connect_error)
    {
      die(\"Connection failed: \" . \$session->connect_error);
    }
    
    \$sql = \"SELECT * FROM \$table\";
    \$result = \$session->query(\$sql);

    echo \"<h2>Liste de tâches à faire</h2>\";

    echo \"<table>
    <tr> 
      <th>Tâche</th>
      <th>Statut</th>
    </tr>\";

    if (\$result->num_rows > 0) 
    {
       while( \$row = \$result->fetch_assoc() )
       { \$statut = \"\";
         if( \$row[\"statut\"] == 0 )
         { \$statut = \"<td class="todo"> A faire </td>\";
         }
         if( \$row[\"statut\"] == 1 )
         { \$statut = \"<td class="inprogess"> En cours </td>\";
         }
         if( \$row[\"statut\"] == 2 )
         { \$statut = \"<td class="done"> Fait </td>\";
         }

         echo \"<tr><td>\" . \$row[\"content\"] . \"</td>\" . \$statut . \"</tr>\";
       }
    } 
    else 
    {
      echo \"0 results\";
    }

    echo \"</table>\";
    \$session->close();

?>
    </body>
</html>" > /var/www/$site_name/confidential/confidential.php
        error_handler $? "Apache > $site_name > L'écriture dans le fichier /var/www/$site_name/confidential/confidential.php a échouée."

# Configuration de la page confidentielle (.htaccess et .htpasswd)

        run_command touch /var/www/$site_name/confidential/.htaccess
        error_handler $? "Apache > $site_name > La création du fichier /var/www/$site_name/confidential/.htaccess a échouée."

        echo "AuthType Basic
AuthName \"Accès protégé\"
AuthUserFile /var/www/.htpasswd
require valid-user
Options -Indexes" > /var/www/$site_name/confidential/.htaccess
        error_handler $? "Apache > $site_name > L'écriture du fichier /var/www/$site_name/confidential/.htaccess a échouée."

        run_command sudo a2ensite $site_name.conf
        error_handler $? "Apache > $site_name > Activation du site a échouée."

        run_command sudo systemctl reload apache2
        error_handler $? "Apache > $site_name > Le redémarrage du service apache a échouée."

        echo "127.0.0.1 $site_name.$DOMAIN_NAME" >> /etc/hosts
        error_handler $? "Apache > $site_name > L'écriture du fichier /etc/hosts a échouée."

    logs_success "Apache > $site_name > $site_name.$DOMAIN_NAME créé et configuré."
    done

#===================================================================#

logs_info "Apache > Redémarrage du service en cours..."

    run_command sudo systemctl restart apache2
    error_handler $? "Apache > Le redémarrage du service apache a échoué."
        
logs_success "Apache > Service redémarré."

logs_success "Apache > Installation et configuration avancée terminée."

#===================================================================#
# 7. Installation et configuration de PHP                           #
#===================================================================#
# Installer PHP et les extensions couramment utilisées
logs_info "PHP > Installation et configuration en cours ..."

    logs_info "PHP > Installation de php en cours ..."
        run_command sudo apt-get install -y php php-mysql php-xml php-mbstring php-curl php-zip php-gd php-json
        error_handler $? "PHP > L'installation de php-mysql, php-xml, php-mbstring, php-curl, php-zip et php-gd a échouée."
    logs_success "PHP > Installation de php terminée."

    # Redémarrer Apache pour appliquer les changements
    logs_info "PHP > Apache > Redémarrage en cours ..."
        run_command sudo systemctl restart apache2
        error_handler $? "PHP > Apache > Le redémarrage a échouée."
    logs_success "PHP > Apache > Redémarrage en terminé."

    # Vérifier la version de PHP installée
    logs_info "PHP > Vérification en cours ..."
        run_command php -v
        error_handler $? "PHP > L'installation de php a échouée."
    logs_success "PHP > Vérification terminée."

logs_success "PHP > Installation et configuration avancée terminée."

#===================================================================#
# 8. Installation et configuration de mysql                         #
#===================================================================#
logs_info "MySQL > Installation et configuration avancée en cours ..."

    logs_info "MySQL > Installation en cours ..."
        run_command sudo apt-get install -y mysql-server
        error_handler $? "MySQL > L'installation a échouée."
    logs_success "MySQL > Installation terminée."

    # Configuration sécurisée de mysql
    logs_info "MySQL > Configuration sécurisée en cours ..."
        run_command sudo mysql_secure_installation <<EOF

Y
$DB_ADMIN_PASSWORD
$DB_ADMIN_PASSWORD
Y
Y
Y
Y
EOF
        error_handler $? "MySQL > Changement du port par défaut a échoué."
    logs_success "MySQL > Configuration sécurisée terminée."

    # Changer le port MySQL
    logs_info "MySQL > Configuration du port en cours ..."
        run_command sudo sed -i "s/^port\s*=\s*3306/port = $DB_PORT/" /etc/mysql/mysql.conf.d/mysqld.cnf
        error_handler $? "MySQL > Changement du port par défaut a échoué."
    logs_success "MySQL > Configuration du port terminée."

    # Redémarrer MySQL pour appliquer les changements
    logs_info "MySQL > Redémarrage du service en cours ..."
        run_command sudo systemctl restart mysql
        error_handler $? "MySQL > Le redémarrage du service a échoué."
    logs_success "MySQL > Redémarrage du service terminée."

    # Créer la base de données et l'utilisateur admin
    logs_info "MySQL > Initialisation de la base de données $DB_NAME et création des utilisateurs en cours ..."

        run_command sudo mysql -u root -p$DB_ADMIN_PASSWORD <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER '$DB_ADMIN_USERNAME'@'localhost' IDENTIFIED BY '$DB_ADMIN_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_ADMIN_USERNAME'@'localhost';
FLUSH PRIVILEGES;

USE $DB_NAME;
CREATE TABLE IF NOT EXISTS todo_list (
    id INT AUTO_INCREMENT PRIMARY KEY,
    content VARCHAR(255) NOT NULL,
    statut INT DEFAULT 0
);

INSERT INTO todo_list (content, statut) VALUES
('Sécuriser le site A.', 0),
('Sécuriser le site B.', 0),
('Créer une page secrète.', 1),
('Faire fonctionner les services php, phpmyadmin, mysql et apache.', 2);

CREATE USER 'phpmyadmin'@'localhost' IDENTIFIED BY '$PHPMYADMIN_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO 'phpmyadmin'@'localhost';
FLUSH PRIVILEGES;
EOF
        error_handler $? "MySQL > Le lancement de l'initialisation de $DB_NAME et création des utilisateurs a échoué."

    logs_success "MySQL > Initialisation de la base de données $DB_NAME et création des utilisateurs terminée."

logs_success "MySQL > Installation et configuration avancée terminée."

#===================================================================#
# 9. Installation de PhpMyAdmin                                     #
#===================================================================#

logs_info "PhpMyAdmin > Installation et configuration en cours ..."

    # Installer phpMyAdmin
    logs_info "PhpMyAdmin > Installation en cours ..."

        export DEBIAN_FRONTEND="noninteractive"

        run_command "sudo apt install -yq phpmyadmin"
        error_handler $? "PhpMyAdmin > L'installation a échouée."
        
        sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
        # sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-user string admin"
        sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $PHPMYADMIN_PASSWORD"
        sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $DB_ADMIN_PASSWORD"
        sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $DB_ADMIN_PASSWORD"
        sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"

        run_command sudo dpkg-reconfigure -f noninteractive phpmyadmin
        error_handler $? "PhpMyAdmin > Configuration de l'installation a échouée."

        echo "Include /etc/phpmyadmin/apache.conf" >> /etc/apache2/apache2.conf

    logs_success "PhpMyAdmin > Installation terminée."

    # Configurer phpMyAdmin avec Apache
    logs_info "PhpMyAdmin > Activation du module mbstring en cours ..."
        run_command sudo phpenmod mbstring
        error_handler $? "PhpMyAdmin > Activation du module mbstring a échouée."
    logs_success "PhpMyAdmin > Activation du module terminée."

    # Redémarrer Apache pour appliquer les changements
    logs_info "PhpMyAdmin > Apache > Redémarrage en cours ..."
        run_command sudo systemctl restart apache2
        error_handler $? "PhpMyAdmin > Apache > Le redémarrage a échouée."
    logs_success "PhpMyAdmin > Apache > Redémarrage terminé."

    # Configurer phpMyAdmin pour utiliser la base de données créée
    logs_info "PhpMyAdmin > Configuration basique en cours ..."

        run_command sudo sed -i "s/^.*\$cfg\['Servers'\]\[\$i\]\['auth_type'\] = 'cookie';/\$cfg['Servers'][\$i]['auth_type'] = 'cookie';/" /etc/phpmyadmin/config.inc.php
        error_handler $? "PhpMyAdmin > La configuration de l'authentification a échouée."

        run_command sudo sed -i "s/^.*\$cfg\['Servers'\]\[\$i\]\['user'\] = 'root';/\$cfg['Servers'][\$i]['user'] = 'phpmyadmin';/" /etc/phpmyadmin/config.inc.php
        error_handler $? "PhpMyAdmin > La configuration de l'utilisateur a échouée."

        run_command sudo sed -i "s/^.*\$cfg\['Servers'\]\[\$i\]\['password'\] = '';/\$cfg['Servers'][\$i]['password'] = '$PHPMYADMIN_PASSWORD';/" /etc/phpmyadmin/config.inc.php
        error_handler $? "PhpMyAdmin > La configuration du mot de passe a échouée."
        
        sudo sed -i "s/^.*\$cfg\['Servers'\]\[\$i\]\['password'\] = '';/\$cfg['Servers'][\$i]['password'] = '$PHPMYADMIN_PASSWORD';/" /etc/phpmyadmin/config.inc.php
        error_handler $? "PhpMyAdmin > La configuration du mot de passe a échouée."
 
        run_command sudo ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
        # error_handler $? "PhpMyAdmin > La création du symlink /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf a échouée."

    logs_success "PhpMyAdmin > Configuration basique terminée."
    logs_info "PhpMyAdmin > Sécurisation > Configuration avancée en cours ..."

    logs_info "PhpMyAdmin > Sécurisation > HTTPS > Génération du certificat et de la clé privée en cours ..."

        run_command sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -sha256 -out /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.crt -keyout /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.key -subj "/C=FR/ST=Occitanie/L=Montpellier/O=IUT/OU=Herault/CN=phpmyadmin.$DOMAIN_NAME/emailAddress=$PHPMYADMIN_ADMIN_ADDRESS" -passin pass:"$SSL_KEY_PASSWORD"
        error_handler $? "Apache > HTTPS > La génération de demande de signature de certifcat du site phpmyadmin.$DOMAIN_NAME a échouée"

        run_command openssl x509 -in /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.crt -text -noout
        error_handler $? "Apache > HTTPS > La vérification du certificat a échouée."
        
        run_command sudo chmod 600 /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.key
        run_command sudo chown root:root /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.crt
        run_command sudo chmod 440 /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.crt

        #Création des Virtual Host
        run_command touch /etc/apache2/sites-available/phpmyadmin.conf
        error_handler $? "Apache > HTTPS > La création du fichier /etc/apache2/sites-available/phpmyadmin.conf a échouée."

    logs_success "PhpMyAdmin > Sécurisation > HTTPS > Génération du certificat et de la clé privée terminée."
    
    logs_info "PhpMyAdmin > Sécurisation > Configuration de la page phpmyadmin.$DOMAIN_NAME en cours ..."

        echo "<VirtualHost *:80>
  ServerAdmin $PHPMYADMIN_ADMIN_ADDRESS
  ServerName phpmyadmin.$DOMAIN_NAME

  RewriteEngine On
  RewriteCond %{HTTPS} off
  RewriteRule ^ https://%{HTTP_HOST}:$$WEB_PORT%{REQUEST_URL} [R,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName phpmyadmin.$DOMAIN_NAME
    ServerAdmin $PHPMYADMIN_ADMIN_ADDRESS

    RewriteEngine On
    RewriteCond %{SERVER_PORT} 443
    RewriteRule ^ https://%{HTTP_HOST}:$WEB_PORT%{REQUEST_URL} [R,L]

    SSLEngine on
    SSLCertificateFile /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.crt
    SSLCertificateKeyFile /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.key

    <Directory /usr/share/phpmyadmin>
        Options -Indexes
        DirectoryIndex index.php
        AllowOverride All
        Require all granted
    </Directory>
 
    ErrorLog ${APACHE_LOG_DIR}/phpmyadmin_error.log
    CustomLog ${APACHE_LOG_DIR}/phpmyadmin_access.log combined
</VirtualHost>

<VirtualHost *:$WEB_PORT>
    ServerName phpmyadmin.$DOMAIN_NAME
    ServerAdmin $PHPMYADMIN_ADMIN_ADDRESS
    DocumentRoot /usr/share/phpmyadmin

    SSLEngine on
    SSLCertificateFile /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.crt
    SSLCertificateKeyFile /etc/apache2/certificate/phpmyadmin."$DOMAIN_NAME"_server.key

    <Directory /usr/share/phpmyadmin>
        DirectoryIndex index.php
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/phpmyadmin_error.log
    CustomLog ${APACHE_LOG_DIR}/phpmyadmin_access.log combined
</VirtualHost>" > /etc/apache2/sites-available/phpmyadmin.conf
        error_handler $? "PhpMyAdmin > Sécurisation > L'écriture du fichier /etc/apache2/sites-available/phpmyadmin.conf a échouée."

        # run_command sudo ufw allow $PHPMYADMIN_PORT/tcp
        # error_handler $? "PhpMyAdmin > Sécurisation > L'autorisation du port personnalisé pour phpMyAdmin a échouée."
        
        # run_command sudo ufw reload
        # error_handler $? "PhpMyAdmin > Sécurisation > Le redémarrage du pare-feu a échoué."

        run_command sudo a2ensite phpmyadmin.conf
        error_handler $? "PhpMyAdmin > Sécurisation > Activation du site a échouée."

        echo "127.0.0.1 phpmyadmin.$DOMAIN_NAME" >> /etc/hosts
        error_handler $? "PhpMyAdmin > Sécurisation > L'écriture dans /etc/hosts échouée."

    logs_success "PhpMyAdmin > Sécurisation > Configuration de la page phpmyadmin.$DOMAIN_NAME terminée."
    logs_info "PhpMyAdmin > Sécurisation > .htaccess > Configuration en cours ..."

        run_command sudo touch /usr/share/phpmyadmin/.htaccess
        error_handler $? "PhpMyAdmin > Sécurisation > .htaccess > La création du fichier /usr/share/phpmyadmin/.htaccess a échouée."

        echo "AuthType Basic
AuthName \"Accès protégé\"
AuthUserFile /var/www/.htpasswd
require valid-user
Options -Indexes" > /usr/share/phpmyadmin/.htaccess
        error_handler $? "PhpMyAdmin > Sécurisation > .htaccess > L'écriture dans /usr/share/phpmyadmin/.htaccess a échouée."

    logs_success "PhpMyAdmin > Sécurisation > .htaccess > Configuration terminée."

    logs_success "PhpMyAdmin > Sécurisation > Configuration avancée terminée."

    # Redémarrer Apache pour appliquer les changements
    logs_info "PhpMyAdmin > Apache > Redémarrage en cours ..."

        run_command sudo systemctl reload apache2
        error_handler $? "PhpMyAdmin > Apache > Le redémarrage a échouée."

    logs_success "PhpMyAdmin > Apache > Redémarrage terminé."

logs_success "PhpMyAdmin > Installation et configuration avancée terminée."

#===================================================================#
logs_info "Redémarrage en cours ..."

    run_command sudo systemctl restart apache2
    error_handler $? "Le redémarrage a échouée."

logs_success "Redémarrage terminé."
#===================================================================#

# sudo apt-get clean
# sudo rm -rf /var/lib/apt/lists/*

#===================================================================#

logs_end "Script terminée."