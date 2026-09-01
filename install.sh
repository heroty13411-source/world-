#!/bin/bash
# Civizsicloud Addon Installer
# Powered By SKA

echo "==============================================="
echo "  CurseForge Maps Downloader Auto-Installer    "
echo "==============================================="

# ১. API Key ইনপুট নেওয়া
read -p "Please enter your CFCore API Key: " API_KEY

# Pterodactyl ডিরেক্টরিতে প্রবেশ
cd /var/www/pterodactyl || { echo "Pterodactyl directory not found!"; exit 1; }

# ২. cat কমান্ড দিয়ে .env ফাইলে API Key যুক্ত করা
echo "* Adding API Key to .env file..."
cat <<EOF >> .env

CURSEFORGE_API=$API_KEY
EOF
echo "* API Key added successfully!"

# ৩. গিটহাব থেকে ফাইল ডাউনলোড ও এক্সট্র্যাক্ট
echo "* Downloading upload.zip from GitHub..."
curl -sL https://raw.githubusercontent.com/heroty13411-source/world-/main/upload.zip -o upload.zip

echo "* Extracting files..."
unzip -o upload.zip
rm upload.zip

# ৪. ইয়ার্ন (Yarn) এবং ডিপেন্ডেন্সি ইন্সটল
echo "* Installing Node Dependencies..."
npm install --global yarn
yarn install

# ৫. প্যানেল বিল্ড করা
echo "* Building Production Assets (This may take a few minutes)..."
yarn run build:production

echo "==============================================="
echo " Build Complete! "
echo "==============================================="

