# 搭建网页，核心用到 linux系统 nginx代理服务器 mariadb数据库 php语言 （简称 lemp音译 或者 lnmp中译）
# 更新商店并升级系统
sudo apt update && sudo apt upgrade -y
# 安装数据库
sudo apt install mariadb-server -y
# 安装代理服务器
sudo apt install nginx -y
# 安装 php-fpm服务，php语言，及相关php插件，一定要把php-fpm放在php前面安装，不然就会默认安装 apache 代理服务器，和上面的 nginx 代理服务冲突，两个抢 80 端口
sudo apt install php-fpm php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip php-bz2 php-cli php-cgi php-imagick -y
# 安装网站模板 wordpress，首先切换至常用网站路径下
cd /var/www/
# 下载 wordpress 压缩包至当前目录
sudo wget https://wordpress.org/latest.tar.gz
# 解压压缩包
sudo tar -xvzf latest.tar.gz
# 删除压缩包
sudo rm -f latest.tar.gz



# 对数据库进行初始化
sudo mysql_secure_installation
# 默认选项
: <<'END'
Enter current password for root (enter for none):
Switch to unix_socket authentication [Y/n] n
Change the root password? [Y/n] y
New password: mariadb-password
Remove anonymous users? [Y/n] y
Disallow root login remotely? [Y/n] y
Remove test database and access to it? [Y/n] y
Reload privilege tables now? [Y/n] y
END
# 登陆数据库
mysql -u root -p
# 创建 wordpress 用户 及 数据库
: <<'END'
CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;     // 创建了 名为 wordpress 的数据库，以 utf8 加强版 格式编码
CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'wp-password';                          // 创建了 wpuser 的用户 并以 wp-password 作为授权密码，密码一定要复杂一点！！！
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';                           // 将 wordpress 数据库的所有操作权限 赋予 wpuser 用户
FLUSH PRIVILEGES;                                                                      // 刷新数据库权限
SELECT User, Host, Db, Select_priv, Insert_priv FROM mysql.db;                          // 校验
EXIT;                                                                                   // 退出数据库
END






# 查看 php 大版本号，只看前两位
php -v
# 修改带宽限制（假设大版本号为8.2，根据实际情况来写）
sudo nano /etc/php/8.2/fpm/php.ini
: <<'END'
upload_max_filesize = 2000M
post_max_size = 2000M
max_execution_time = 3000
cgi.fix_pathinfo=0
END



# 配置 wordpress 网站模板
# 到网站目录路径下
cd /var/www/wordpress/
# 复制一份配置单模板
sudo cp wp-config-sample.php wp-config.php
# 打开编辑器进行编辑（ctrl+w 查询，ctrl + o 保存，ctrl+x退出）
sudo nano /var/www/wordpress/wp-config.php
: <<'END'
define( 'DB_NAME', 'wordpress' );                       // 数据库名称，填前面的
define( 'DB_USER', 'wpuser' );                          // 数据库管理员用户名，填前面的
define( 'DB_PASSWORD', 'wp-password' );                // 数据库管理员密码，填前面的，一定要复杂
define( 'DB_HOST', 'localhost' );                     //访问ip地址，默认为localhost
define( 'DB_CHARSET', 'utf8mb4' );                   // 数据库编码格式 utf8 加强版
define( 'DB_COLLATE', 'utf8mb4_unicode_ci' );        // 数据库排序格式 utf8 加强版
END



# 自签证书部署,创建目录，自签名证书仅用于内网及开发测试。
sudo mkdir -p /root/cert/
# 编辑配置单描述文本，这里的前两个域名填自己的，第三个localhost不动，ip地址前两个不动（分别是本地 ipv4 和本地 ipv6），前三个服务器ip 通过命令 ip a 获取
sudo nano /root/cert/http.ext
: <<'END'
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = domain.com
DNS.2 = www.domain.com
DNS.3 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = 192.168.1.3

END

# 生成一个2048位的私钥 /root/cert/selfsigned.key，下面的CN=domain.com 这里需要该为自己的域名地址
sudo openssl req -new -newkey rsa:2048 -sha256 -nodes \
  -keyout /root/cert/selfsigned.key \
  -out /root/cert/selfsigned.csr \
  -subj "/C=CN/ST=Local/L=Local/O=Dev/OU=Test/CN=domain.com"  

# 利用私钥和配置单描述文本/root/cert/http.ext 签发一个有效期为10年的公钥 /root/cert/selfsigned.crt
sudo openssl x509 -req -days 3650 -in /root/cert/selfsigned.csr \
  -signkey /root/cert/selfsigned.key \
  -out /root/cert/selfsigned.crt \
  -extfile /root/cert/http.ext


# 配置 nginx 代理服务器，创建并打开配置文件，最后一行一定要是空白行，不然有时会出 bug
sudo nano /etc/nginx/conf.d/default.conf
: <<'END'
server {
    listen 443 ssl;           # 监听的是 443 端口，对应 https 服务，这个是约定俗成的
    server_name domain.com;  # 填入自己的网站域名，比如二级域名 www.domain.com 或者二级域名 video.domain.com 或者一级根域名 domain.com

    root /var/www/wordpress;   # 网站根路径
    index index.php index.html index.htm;  # 网站首页

    # SSL certificate paths
    ssl_certificate     /root/cert/selfsigned.crt;   #公钥路径
    ssl_certificate_key /root/cert/selfsigned.key;  #私钥路径
	
	# Upload file size limit
    client_max_body_size 2000M;              #上传带宽限制，和php构成木桶短板效应

    ssl_session_timeout 1d;                #过期时间
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets off;

    ssl_protocols TLSv1.2 TLSv1.3;          #加密方式及加密版本，tls1.1已经不安全
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5';
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/access.log;    #访问日志的路径
    error_log  /var/log/nginx/error.log;     #存储日志的路径
	
	# 处理请求的格式，依次是 文件，文件夹，首页当作传递参数
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

	# 后端执行的逻辑
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;  # 这里要填自己实际的 php 大版本号
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

	防止 apache 残留的干扰，因此拒绝 访问 .ht开头的任何文件
    location ~ /\.ht {
        deny all;
    }

	# 404、50x 等报错页面
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
	
	#报错页面的路径
    location = /50x.html {
        root /var/www/wordpress;
    }
}

# 80端口绑定的是 http，因此需要把http 重定向至 https
server {
    listen 80;
    server_name domain.com;  # 填入自己的网站域名，比如二级域名 www.domain.com 或者二级域名 video.domain.com 或者一级根域名 domain.com，和上面的一致
    return 301 https://$host$request_uri;   #把http 请求301重定向至 https
}

END

# 检查 nginx 配置信息
sudo nginx -t
# 检查无误后平稳载入 nginx
sudo systemctl reload nginx
# 重启 php（根据自己的实际版本来） 以更新上传下载带宽限制
sudo systemctl restart php8.2-fpm
# 将 网站所在目录的管理权限赋予 www-data 用户（即为nginx 运行时的低权限用户）
sudo chown -R www-data:www-data /var/www/wordpress/

# 在windows电脑的 C:\Windows\System32\drivers\etc\hosts 加入自己的dns地址，根据实际情况来，最后一行是空白行
192.168.242.1 domain.com
# 在windows 电脑的 cmd 里刷新dns 缓存
ipconfig /flushdns
# 然后测试 dns 是否生效，在windows 电脑的 cmd 里输入
ping domain.com
# 如果开启了 代理，需要让 domain.com 走 直连，否则 dns 走了公共 dns

# 此时在浏览器输入 domain.com 对网站进行初始化配置。邮箱务必填真实的，以便后续找回密码
# 后续进入后台时，在网站中输入 domain.com/wp-login.php，可通过 插件 wp-hide 隐藏登陆的网址
# 可在 网页中 直接嵌入 youtube 视频赚取广告费并节省服务器空间，对于b 站视频，点击 视频页面的 嵌入代码即可，高级设置比如窗口大小，弹幕设置，可根据需要自行查阅博客教程.
# 对 m3u8 文件可询问 ai 怎么在网页中插入视频，至于请求头的伪装。
