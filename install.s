#!/bin/bash
# Pterodactyl CurseForge Maps Downloader Auto-Installer
# Powered By SKA

echo "==============================================="
echo "  CurseForge Maps Downloader Auto-Installer    "
echo "==============================================="

# ১. API Key ইনপুট নেওয়া
read -p "Please enter your CFCore API Key: " API_KEY

# ২. গ্লোবাল ইন্সটলেশন
echo "* Installing global dependencies..."
npm install --global yarn

# ৩. ডিরেক্টরিতে প্রবেশ
cd /var/www/pterodactyl || { echo "Pterodactyl directory not found!"; exit 1; }

# ৪. cat কমান্ড দিয়ে .env ফাইলে API Key যুক্ত করা
echo "* Adding API Key to .env file..."
cat <<EOF >> .env

CURSEFORGE_API=$API_KEY
EOF

# ৫. গিটহাব থেকে ফাইল ডাউনলোড ও এক্সট্র্যাক্ট
echo "* Downloading files from GitHub..."
curl -sL https://raw.githubusercontent.com/heroty13411-source/world-/main/upload.zip -o upload.zip
echo "* Extracting files..."
unzip -o upload.zip
rm upload.zip

# ৬. cat কমান্ড দিয়ে ফাইলগুলোর ১০০% সঠিক মডিফিকেশন 
echo "* Modifying code files automatically..."

# ClientController.php - Imports
cat << 'CODE_EOF' > cc_uses.txt
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Cache;
CODE_EOF
sed -i -e "/use Pterodactyl\\\\Http\\\\Requests\\\\Api\\\\Client\\\\GetServersRequest;/r cc_uses.txt" app/Http/Controllers/Api/Client/ClientController.php

# ClientController.php - Main Function
cat << 'CODE_EOF' > cc_func.txt

    public function curse(Request $request)
    {
        $headers = ['x-api-key' => env('CURSEFORGE_API')];

        $response = Http::withHeaders($headers)->get('https://api.curseforge.com/v1/mods/search', [
            'index' => $request['index'],
            'pageSize' => $request['pageSize'],
            'gameId' => $request['gameId'],
            'classId' => $request['sectionId'],
            'searchFilter' => $request['searchFilter'],
            'sortField' => 2,
            'sortOrder' => 'desc'
        ])->json();

        $mods = collect($response['data'])->map(function ($mod) use ($request, $headers) {
            foreach ($mod['latestFiles'] as &$modFile) {
                $modFile['downloadUrl'] = str_replace("edge", "mediafiles", $modFile['downloadUrl']);
            }
            return $mod;
        });

        return [
            'mods' => $mods,
            'pagination' => $response['pagination'],
        ];
    }
CODE_EOF
awk 'NR==FNR{a=a$0"\n";next} /public function permissions\(\)/{printf "%s\n", a; print; next}1' cc_func.txt app/Http/Controllers/Api/Client/ClientController.php > tmp.php && mv tmp.php app/Http/Controllers/Api/Client/ClientController.php

# routes/api-client.php
cat << 'CODE_EOF' > route_mod.txt
Route::get('/curse', [Client\ClientController::class, 'curse']);
CODE_EOF
sed -i -e "/Route::get('\/permissions'/r route_mod.txt" routes/api-client.php

# ServerTransformer.php
cat << 'CODE_EOF' > transformer_mod.txt
            'nest_id' => $server->nest_id,
CODE_EOF
sed -i -e "/'internal_id' => \$server->id,/r transformer_mod.txt" app/Transformers/Api/Client/ServerTransformer.php

# getServer.ts
cat << 'CODE_EOF' > ts1.txt
    nestId: number | string;
CODE_EOF
sed -i -e "/internalId: number | string;/r ts1.txt" resources/scripts/api/server/getServer.ts

cat << 'CODE_EOF' > ts2.txt
        nestId: data.nest_id,
CODE_EOF
sed -i -e "/internalId: data.internal_id,/r ts2.txt" resources/scripts/api/server/getServer.ts

# ServerRouter.tsx - Imports & Variables
cat << 'CODE_EOF' > router_import.txt
import MinecraftMapsContainer from '@/components/server/maps/MinecraftMapsContainer';
CODE_EOF
sed -i -e "/import FileManagerContainer /r router_import.txt" resources/scripts/routers/ServerRouter.tsx

cat << 'CODE_EOF' > router_const.txt
    const nestId = ServerContext.useStoreState(state => state.server.data?.nestId);
CODE_EOF
sed -i -e "/const serverId = /r router_const.txt" resources/scripts/routers/ServerRouter.tsx

# ServerRouter.tsx - NavLink Block
cat << 'CODE_EOF' > router_nav.txt
            {nestId === 1 &&
            <Can action={'file.*'}>
                <NavLink to={`${match.url}/maps`}>Maps</NavLink>
            </Can>
            }
CODE_EOF
awk 'NR==FNR{a=a$0"\n";next} /File Manager<\/NavLink>/{print; getline; print; printf "%s", a; next}1' router_nav.txt resources/scripts/routers/ServerRouter.tsx > tmp.tsx && mv tmp.tsx resources/scripts/routers/ServerRouter.tsx

# ServerRouter.tsx - Route Block
cat << 'CODE_EOF' > router_route.txt
            {nestId === 1 &&
            <Route path={`${match.path}/maps`} exact>
                <RequireServerPermission permissions={'file.*'}>
                    <MinecraftMapsContainer/>
                </RequireServerPermission>
            </Route>
            }
CODE_EOF
awk 'NR==FNR{a=a$0"\n";next} /<FileEditContainer\/>/{print; getline; print; getline; print; printf "%s", a; next}1' router_route.txt resources/scripts/routers/ServerRouter.tsx > tmp.tsx && mv tmp.tsx resources/scripts/routers/ServerRouter.tsx

# অপ্রয়োজনীয় টেম্প ফাইল ডিলিট
rm cc_uses.txt cc_func.txt route_mod.txt transformer_mod.txt ts1.txt ts2.txt router_import.txt router_const.txt router_nav.txt router_route.txt

# ৭. ইয়ার্ন ডিপেন্ডেন্সি এবং প্রোডাকশন বিল্ড (OpenSSL Fix সহ)
echo "* Installing Yarn dependencies..."
yarn install

echo "* Applying OpenSSL Legacy Fix before production build..."
export NODE_OPTIONS=--openssl-legacy-provider

echo "* Building Production Assets (This may take a few minutes)..."
yarn run build:production

echo "==============================================="
echo " Build Complete! Check your Panel."
echo "==============================================="
