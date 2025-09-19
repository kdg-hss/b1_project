#!/bin/bash
# =================================================================================
# Installer Otomatis Jualan Bot v9 (Final Definitif)
# - Perbaikan alur systemd untuk instalasi baru.
# =================================================================================

# --- Variabel dan Fungsi Bantuan ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

set -e

info() { echo -e "\n${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# --- Cek Root ---
if [ "$(id -u)" -ne 0 ]; then
   error "Skrip ini harus dijalankan sebagai root."
fi

# --- Langkah 0: Pengecekan Izin IP dari GitHub ---
clear
info "Mengecek perizinan IP VPS Anda..."
IZIN_URL="https://raw.githubusercontent.com/kdg-hss/izin-tele/main/izin"
MYIP=$(curl -s ipv4.icanhazip.com)

IZIN_LIST=$(curl -sL "$IZIN_URL")
if [ -z "$IZIN_LIST" ]; then
    error "Gagal mengambil daftar izin dari GitHub."
fi

LICENSE_LINE=$(echo "$IZIN_LIST" | grep -w "$MYIP")
if [ -z "$LICENSE_LINE" ]; then
    error "IP Anda ($MYIP) TIDAK TERDAFTAR.\nInstalasi dibatalkan. Silakan hubungi pemilik skrip."
fi

USERNAME=$(echo "$LICENSE_LINE" | awk '{print $1}')
EXP_DATE=$(echo "$LICENSE_LINE" | awk '{print $3}')
TODAY_SECONDS=$(date -u +%s)
EXP_SECONDS=$(date -u -d "$EXP_DATE" +%s 2>/dev/null)

if [ -z "$EXP_SECONDS" ]; then
    error "Format tanggal di file izin salah untuk IP ($MYIP). Gunakan format YYYY-MM-DD."
fi

if [ "$TODAY_SECONDS" -gt "$EXP_SECONDS" ]; then
    error "Lisensi untuk IP ($MYIP) atas nama ($USERNAME) sudah KADALUARSA pada ($EXP_DATE)."
else
    success "IP ($MYIP) terdaftar atas nama ($USERNAME). Lisensi aktif hingga ($EXP_DATE)."
    sleep 2
fi

# --- Meminta Input dari Pengguna ---
clear
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN} Selamat Datang di Installer Otomatis Jualan Bot ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo "IP Terverifikasi. Silakan masukkan detail bot Anda."
echo ""

read -p "Masukkan BOT_TOKEN Anda: " BOT_TOKEN
read -p "Masukkan User ID Admin utama Anda: " ADMIN_ID
read -sp "Masukkan Password ROOT VPS Anda: " SSH_PASSWORD
echo ""; echo ""

if [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_ID" ] || [ -z "$SSH_PASSWORD" ]; then
    error "Semua input wajib diisi."
fi

# --- Variabel Global ---
REPO_URL="https://raw.githubusercontent.com/kdg-hss/b1_project/main"
VENV_PATH="/bot/julak/cbt/jualanbot_env"
BOT_DIR="/bot/julak"

# --- Proses Instalasi ---

info "1. Menginstal Dependensi..."
source /etc/os-release
if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]]; then VENV_PKG="python3.12-venv"
elif [[ "$ID" == "debian" && "$VERSION_ID" == "12" ]]; then VENV_PKG="python3.11-venv"
else VENV_PKG="python3-venv"; warning "OS tidak terdeteksi secara spesifik, menggunakan paket python3-venv generik."; fi

apt-get update
apt-get install -y python3 python3-pip "$VENV_PKG" nginx at curl jq
success "Dependensi sistem berhasil diinstal."

info "2. Membuat Lingkungan Virtual Python..."
rm -rf ${VENV_PATH}
mkdir -p ${VENV_PATH}
python3 -m venv ${VENV_PATH}
success "Lingkungan virtual berhasil dibuat."

info "3. Menginstal pustaka Python..."
${VENV_PATH}/bin/pip install python-telegram-bot==21.0.1 paramiko httpx
success "Pustaka Python berhasil diinstal."

info "4. Mengunduh semua skrip dari GitHub..."
SCRIPTS=(
    "julak.py" "addss-bot" "addssh-bot" "addvless-bot" "addws-bot" "bot-backup"
    "bot-cek-login-ssh" "bot-trial" "bot-trialtrojan" "bot-trialvless"
    "bot-trialws" "bot-trialss" "bot-vps-info" "resservice" "bot-cek-vless"
    "bot-cek-ws" "bot-delvless" "bot-del-ws" "bot-del-trojan" "bot-del-ss"
    "bot-delssh" "bot-list-vless" "bot-list-vmess" "bot-list-trojan" "bot-list-shadowsocks"
    "bot-list-ssh" "bot-cek-tr" "bot-cek-ss" "bot-clearcache" "bot-restore" "ext-ssh" "ext-ws" "ext-vless" "ext-tr"
)
for script_name in "${SCRIPTS[@]}"; do
    echo -n "  -> Mengunduh ${script_name}..."
    curl -sL -o "${BOT_DIR}/${script_name}" "${REPO_URL}/${script_name}"
    if [ -s "${BOT_DIR}/${script_name}" ]; then
        chmod +x "${BOT_DIR}/${script_name}"
        echo -e " ${GREEN}OK${NC}"
    else
        echo -e " ${YELLOW}Gagal${NC}"
    fi
done
success "Proses pengunduhan skrip selesai."

info "5. Mengkonfigurasi jualan.py..."
if [ ! -f "${BOT_DIR}/julak.py" ]; then error "File julak bot tidak berhasil diunduh."; fi
sed -i "s/12345:GANTI_DENGAN_TOKEN_ASLI/${BOT_TOKEN}/g" "${BOT_DIR}/julak.py"
sed -i "s/1234567890/${ADMIN_ID}/g" "${BOT_DIR}/julak.py"
success "Julak bot berhasil dikonfigurasi."

info "6. Membuat layanan systemd..."
cat > /etc/systemd/system/julak.service << EOF
[Unit]
Description=Jualan Telegram Bot by Julak-Bantur
After=network.target
[Service]
WorkingDirectory=${BOT_DIR}/
ExecStart=${VENV_PATH}/bin/python3 ${BOT_DIR}/julak.py
Restart=always
User=root
Group=root
Environment="SSH_USERNAME=root"
Environment="SSH_PASSWORD=${SSH_PASSWORD}"
[Install]
WantedBy=multi-user.target
EOF
chmod 600 /etc/systemd/system/julak.service
success "File layanan systemd berhasil dibuat."

info "7. Menyelesaikan instalasi dan menjalankan layanan..."
systemctl daemon-reload
# FIX: Menghapus baris 'reset-failed' yang tidak perlu untuk instalasi baru
systemctl enable julak.service
systemctl start julak.service

systemctl enable nginx > /dev/null 2>&1; systemctl restart nginx
systemctl enable atd > /dev/null 2>&1; systemctl start atd

sleep 5
echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}       INSTALASI SELESAI & BOT TELAH AKTIF!       ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo "Periksa status bot dengan:"
echo -e "${YELLOW}sudo systemctl status julak.service${NC}"
echo ""
echo "Jika ada masalah, lihat log dengan:"
echo -e "${YELLOW}sudo journalctl -u julak.service -n 100 --no-pager${NC}"
echo ""
success "Silakan buka aplikasi Telegram dan mulai gunakan bot Anda."

