# Examples

## First boot

```bash
apt-get update
apt-get install -y neofetch curl wget git nano htop
neofetch
```

## SSH remote access

```bash
# Inside the chroot on Kindle:
apt-get install -y dropbear
dropbear -R -p 0.0.0.0:2222 -B

# From your PC:
ssh root@192.168.1.42 -p 2222
# Password: kindle
```

## Python

```bash
apt-get install -y python3 python3-pip
python3 -c "print('Hello from Kindle!')"

pip3 install requests
python3 -c "import requests; print(requests.get('https://ifconfig.me').text)"
```

## Web server

```bash
apt-get install -y python3
mkdir -p /srv/www && echo "<h1>Served from Kindle!</h1>" > /srv/www/index.html
cd /srv/www && python3 -m http.server 8080 &
# Access: http://<kindle-ip>:8080
```

## Node.js

```bash
apt-get install -y nodejs npm
node -e "console.log('Node.js ' + process.version + ' on Kindle!')"

npm init -y && npm install express
node -e "
const app = require('express')();
app.get('/', (req, res) => res.send('Hello from Kindle!'));
app.listen(3000, () => console.log('http://0.0.0.0:3000'));
"
```

## Compile C natively

```bash
apt-get install -y gcc make

cat > hello.c << 'EOF'
#include <stdio.h>
#include <sys/utsname.h>

int main() {
    struct utsname buf;
    uname(&buf);
    printf("Hello from %s %s (%s)\n", buf.sysname, buf.release, buf.machine);
    return 0;
}
EOF

gcc -o hello hello.c && ./hello
# Output: Hello from Linux 4.1.15 (armv7l)
```

## Network / pentest tools

```bash
apt-get install -y nmap netcat-openbsd dnsutils whois tcpdump

nmap -sn 192.168.1.0/24
nmap -sV 192.168.1.1
dig google.com
nc -lvp 4444
```

## Git server

```bash
apt-get install -y git

mkdir -p /srv/git/myproject.git
cd /srv/git/myproject.git
git init --bare

# From your PC (with SSH running):
git remote add kindle root@<kindle-ip>:/srv/git/myproject.git
git push kindle main
```

## Telegram bot

```bash
apt-get install -y python3 python3-pip
pip3 install python-telegram-bot

cat > bot.py << 'EOF'
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, ContextTypes

async def hello(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(f'Hello from Kindle! Uptime: {open("/proc/uptime").read().split()[0]}s')

app = ApplicationBuilder().token("YOUR_BOT_TOKEN").build()
app.add_handler(CommandHandler("hello", hello))
app.run_polling()
EOF

python3 bot.py
```

## IRC bouncer

```bash
apt-get install -y znc
znc --makeconf
```

## Torrents

```bash
apt-get install -y transmission-cli
transmission-cli "magnet:?xt=urn:btih:..." -w /mnt/us/downloads/
```

## Custom distro (Void Linux, etc.)

```bash
sudo ./build_rootfs.sh --distro custom \
    --rootfs-url https://repo-default.voidlinux.org/live/current/void-armv7l-ROOTFS-20230628.tar.xz \
    --size 1024

# From local file:
sudo ./build_rootfs.sh --distro custom \
    --rootfs-file ~/Downloads/my-rootfs-armhf.tar.gz \
    --size 512

# Rename: mv custom.ext3 void.ext3
# The KUAL extension auto-detects any .ext3 in /mnt/us/
```
