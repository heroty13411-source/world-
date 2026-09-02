#!/bin/bash

# একটু অ্যানিমেশন ও কালার
echo -e "\033[0;36m====================================================\033[0m"
echo -e "\033[0;32m   CurseForge Maps Downloader Auto-Installer\033[0m"
echo -e "\033[0;36m====================================================\033[0m\n"
sleep 1

# API Key নেওয়া এবং .env ফাইলে যুক্ত করা
echo -e "\033[1;33mPlease enter your CURSEFORGE_API Key:\033[0m"
read -p "> " api_key

echo -e "\n\033[0;36m[+] Adding API Key to .env file...\033[0m"
cd /var/www/pterodactyl
echo "CURSEFORGE_API=$api_key" >> .env
sleep 1
echo -e "\033[0;32m[✔] API Key successfully added!\033[0m\n"
sleep 1

# এখান থেকে আপনার দেওয়া হুবহু কোড শুরু (কোনো পরিবর্তন ছাড়া)

echo -e "\nStarting Automatic Installation of CurseForge Maps Downloader...\n" 

cd /var/www/pterodactyl 

# ১. ফোল্ডার তৈরি করা হচ্ছে
mkdir -p resources/scripts/api/swr
mkdir -p resources/scripts/components/server/maps 

# ২. getMinecraftMaps.ts ফাইল তৈরি
cat << 'EOF' > resources/scripts/api/swr/getMinecraftMaps.ts
import useSWR from 'swr';
import http, { PaginatedResult } from '@/api/http';
import { createContext, useContext } from 'react'; 

interface ctx {
    page: number;
    setPage: (value: number | ((s: number) => number)) => void;
    searchFilter: string;
    setSearchFilter: (value: string | ((s: string) => string)) => void;
} 

export const Context = createContext<ctx>({ page: 1, setPage: () => 1, searchFilter: '', setSearchFilter: () => '' }); 

export default () => {
    const { page, searchFilter } = useContext(Context); 

    return useSWR<PaginatedResult<any>>([ 'server:minecraftMaps', page, searchFilter ], async () => {
        const { data } = await http.get('/api/client/curse', { params: { index: page - 1 + (page - 1) * 10, pageSize: 10, gameId: 432, searchFilter, sectionId: 17 }, timeout: 120000 }); 

        return ({
            items: (data.mods || []),
            pagination: { total: data.pagination.totalCount, count: data.pagination.resultCount, perPage: data.pagination.pageSize, currentPage: page, totalPages: data.pagination.totalCount / data.pagination.pageSize },
        });
    });
};
EOF 

# ৩. MinecraftMapsContainer.tsx ফাইল তৈরি
cat << 'EOF' > resources/scripts/components/server/maps/MinecraftMapsContainer.tsx
import React, { useContext, useEffect, useState } from 'react';
import Spinner from '@/components/elements/Spinner';
import useFlash from '@/plugins/useFlash';
import { Form, Formik } from 'formik';
import FlashMessageRender from '@/components/FlashMessageRender';
import MinecraftMapsRow from '@/components/server/maps/MinecraftMapsRow';
import tw from 'twin.macro';
import Field from '@/components/elements/Field';
import { object, string } from 'yup';
import getMinecraftMaps, { Context as ServerMinecraftMapsContext } from '@/api/swr/getMinecraftMaps';
import ServerContentBlock from '@/components/elements/ServerContentBlock';
import Pagination from '@/components/elements/Pagination'; 

interface Values {
    search: string;
} 

const MinecraftMapsContainer = () => {
    const { page, setPage, searchFilter, setSearchFilter } = useContext(ServerMinecraftMapsContext);
    const { clearFlashes, clearAndAddHttpError } = useFlash();
    const { data: minecraftMaps, error, isValidating } = getMinecraftMaps(); 

    const submit = ({ search }: Values) => {
        clearFlashes('minecraftMaps');
        setSearchFilter(search);
    }; 

    useEffect(() => {
        if (!error) {
            clearFlashes('minecraftMaps');
            return;
        }
        clearAndAddHttpError({ error, key: 'minecraftMaps' });
    }, [ error ]); 

    if (!minecraftMaps || (error && isValidating)) {
        return <Spinner size={'large'} centered/>;
    } 

    return (
        <ServerContentBlock title={'Minecraft Maps'}>
            <FlashMessageRender byKey={'minecraftMaps'} css={tw`mb-4`}/>
            <Formik
                onSubmit={submit}
                initialValues={{ search: searchFilter }}
                validationSchema={object().shape({ search: string().optional().min(1) })}
            >
                <Form css={tw`mb-4`}>
                    <Field id={'search'} name={'search'} label={'Search'} type={'text'} />
                </Form>
            </Formik>
            <Pagination data={minecraftMaps} onPageSelect={setPage}>
                {({ items }) => (
                    !items.length ?
                        <p css={tw`text-center text-sm text-neutral-300`}>
                            {page > 1 ?
                                'Looks like we\'ve run out of Minecraft maps to show you, try going back a page.'
                                :
                                'It looks like there are no Minecraft maps matching search criteria.'
                            }
                        </p>
                        :
                        items.map((minecraftMap, index) => <MinecraftMapsRow
                            key={minecraftMap.id}
                            minecraftMap={minecraftMap}
                            css={index > 0 ? tw`mt-2` : undefined}
                        />)
                )}
            </Pagination>
        </ServerContentBlock>
    );
}; 

export default () => {
    const [ page, setPage ] = useState<number>(1);
    const [ searchFilter, setSearchFilter ] = useState<string>(''); 

    return (
        <ServerMinecraftMapsContext.Provider value={{ page, setPage, searchFilter, setSearchFilter }}>
            <MinecraftMapsContainer/>
        </ServerMinecraftMapsContext.Provider>
    );
};
EOF 

# ৪. MinecraftMapsRow.tsx ফাইল তৈরি
cat << 'EOF' > resources/scripts/components/server/maps/MinecraftMapsRow.tsx
import React, { useCallback, useState } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faDownload } from '@fortawesome/free-solid-svg-icons';
import { format, formatDistanceToNow } from 'date-fns';
import tw from 'twin.macro';
import useFlash from '@/plugins/useFlash';
import GreyRowBox from '@/components/elements/GreyRowBox';
import SpinnerOverlay from '@/components/elements/SpinnerOverlay';
import { ServerContext } from '@/state/server';
import Select from '@/components/elements/Select';
import http from '@/api/http'; 

interface Props {
    minecraftMap: any;
    className?: string;
} 

export default ({ minecraftMap, className }: Props) => {
    const uuid = ServerContext.useStoreState(state => state.server.data!.uuid);
    const { clearAndAddHttpError, addFlash } = useFlash();
    let url = minecraftMap.files[0]?.downloadUrl; 

    const updateSelectedFile = useCallback((v: React.ChangeEvent<HTMLSelectElement>) => {
        url = v.currentTarget.value;
    }, [ uuid, url ]); 

    const installMap = () => {
        if (url === null || url === undefined) return; 

    http.post(`/api/client/servers/${uuid}/files/pull`, { directory: '/', url: encodeURI(url) })
.then(function () {
addFlash({ type: 'success', key: 'minecraftMaps', message: 'File has been scheduled for downloading.' });
})
.catch(function (error) {
    clearAndAddHttpError({ key: 'minecraftMaps', error });
});
    }; 

    return (
        <GreyRowBox css={tw`flex-wrap md:flex-nowrap items-center`} className={className}>
            <div css={tw`flex items-center truncate w-full md:flex-1`}>
                <div css={tw`flex flex-col truncate`}>
                    <div css={tw`flex items-center text-sm mb-1`}>
                        <div css={tw`w-10 h-10 rounded-lg bg-white border-2 border-neutral-800 overflow-hidden hidden md:block`}>
                            <img css={tw`w-full h-full`} alt={minecraftMap.name} src={minecraftMap.logo.thumbnailUrl}/>
                        </div>
                        <a href={minecraftMap.websiteUrl} css={tw`ml-4 break-words truncate`}>
                            {minecraftMap.name}
                        </a>
                    </div>
                    <p css={tw`mt-1 md:mt-0 text-xs truncate`}>
                        {minecraftMap.categories.map((category: any, index: any) => (
                            <img css={index > 0 ? tw`ml-1 w-4 h-auto inline` : tw`w-4 h-auto inline`} key={category.categoryId} src={category.iconUrl} alt={category.name} title={category.name} />
                        ))}
                    </p>
                </div>
            </div>
            <div css={tw`flex-1 md:flex-none md:w-96 mt-4 md:mt-0 md:ml-8 md:text-center`}>
                <p css={tw`text-sm`}>
                    {minecraftMap.summary}
                </p>
            </div>
            <div css={tw`flex-1 md:flex-none md:w-48 mt-4 md:mt-0 md:ml-8 md:text-center`}>
                <p
                    title={format(new Date(minecraftMap.dateReleased), 'ddd, MMMM do, yyyy HH:mm:ss')}
                    css={tw`text-sm`}
                >
                    {formatDistanceToNow(new Date(minecraftMap.dateReleased), { includeSeconds: true, addSuffix: true })}
                </p>
                <p css={tw`text-2xs text-neutral-500 uppercase mt-1`}>Released</p>
            </div>
            <div css={tw`flex-1 md:flex-none md:w-48 mt-4 md:mt-0 md:ml-8 md:text-center`}>
                <Select
                    disabled={minecraftMap.files.length < 2}
                    onChange={updateSelectedFile}
                    defaultValue={minecraftMap.files[0]?.id}
                >
                    {minecraftMap.files.map((file: any) => (
                        <option key={file.id} value={file.downloadUrl}>{file.displayName}</option>
                    ))}
                </Select>
            </div>
            <div css={tw`mt-4 md:mt-0 ml-6`} style={{ marginRight: '-0.5rem' }}>
                <button
                    type={'button'}
                    aria-label={'Install'}
                    css={tw`block text-sm p-1 md:p-2 text-neutral-500 hover:text-neutral-100 transition-colors duration-150 mx-4`}
                    onClick={installMap}
                >
                    <FontAwesomeIcon icon={faDownload} />
                </button>
            </div>
        </GreyRowBox>
    );
};
EOF 

# ৫. কোর ফাইলগুলোতে কোড প্যাচ করা (Backend & Routes)
echo -e "\n\033[0;36mPatching Core Files...\033[0m"
sleep 1
grep -q "ClientController::class, 'curse'" routes/api-client.php || echo "Route::get('/curse', [Client\ClientController::class, 'curse']);" >> routes/api-client.php 

sed -i "s/'uuid' => \$server->uuid,/'internal_id' => \$server->id,\n            'nest_id' => \$server->nest_id,\n            'uuid' => \$server->uuid,/g" app/Transformers/Api/Client/ServerTransformer.php 

php -r '
$f="app/Http/Controllers/Api/Client/ClientController.php";
$c=file_get_contents($f);
if(!strpos($c,"function curse(")){
    $c=str_replace("namespace Pterodactyl\Http\Controllers\Api\Client;","namespace Pterodactyl\Http\Controllers\Api\Client;\n\nuse Illuminate\Http\Request;\nuse Illuminate\Support\Facades\Http;\nuse Illuminate\Support\Facades\Cache;",$c);
    $m="\n    public function curse(Request \$request)\n    {\n        \$headers = [\"x-api-key\" => env(\"CURSEFORGE_API\")];\n\n        \$response = Http::withHeaders(\$headers)->get(\"https://api.curseforge.com/v1/mods/search\", [\n            \"index\" => \$request[\"index\"],\n            \"pageSize\" => \$request[\"pageSize\"],\n            \"gameId\" => \$request[\"gameId\"],\n            \"classId\" => \$request[\"sectionId\"],\n            \"searchFilter\" => \$request[\"searchFilter\"],\n            \"sortField\" => 2,\n            \"sortOrder\" => \"desc\"\n        ])->json();\n\n        \$mods = collect(\$response[\"data\"])->map(function (\$mod) use (\$request, \$headers) {\n            foreach (\$mod[\"latestFiles\"] as &\$modFile) {\n                \$modFile[\"downloadUrl\"] = str_replace(\"edge\", \"mediafiles\", \$modFile[\"downloadUrl\"]);\n            }\n            return \$mod;\n        });\n\n        return [\n            \"mods\" => \$mods,\n            \"pagination\" => \$response[\"pagination\"],\n        ];\n    }";
    $c=preg_replace("/}\s*$/", $m."\n}", $c);
    file_put_contents($f,$c);
}' 

# ৬. কোর ফাইলগুলোতে কোড প্যাচ করা (Frontend TypeScript)
sed -i "s/uuid: string;/internalId: number | string;\n    nestId: number | string;\n    uuid: string;/g" resources/scripts/api/server/getServer.ts
sed -i "s/uuid: data.uuid,/internalId: data.internal_id,\n        nestId: data.nest_id,\n        uuid: data.uuid,/g" resources/scripts/api/server/getServer.ts 

# Node.js ব্যবহার করে Arix এর ServerRouter এডিট করা
node -e "
const fs = require('fs');
let file = fs.readFileSync('resources/scripts/routers/ServerRouter.tsx', 'utf8'); 

if(!file.includes('MinecraftMapsContainer')) {
    file = file.replace(/import \{ ServerContext \} from '@\/state\/server';/, \"import { ServerContext } from '@/state/server';\\nimport MinecraftMapsContainer from '@/components/server/maps/MinecraftMapsContainer';\");
    
    file = file.replace(/const serverId = ServerContext\.useStoreState\(state => state\.server\.data(!|\?)\.internalId\);/, \"const serverId = ServerContext.useStoreState(state => state.server.data\$1.internalId);\\n    const nestId = ServerContext.useStoreState(state => state.server.data\$1.nestId);\");
    
    file = file.replace(/<Can action=\{'database\.\*'\}>/g, \"{nestId === 1 && (\\n                                <Can action={'file.*'}>\\n                                    <NavLink to={\`\${match.url}/maps\`}>Maps</NavLink>\\n                                </Can>\\n                            )}\\n                            <Can action={'database.*'}>\");
    
    file = file.replace(/<Route path=\{\`\\\$\\{match\.path\\}\/databases\`\} exact>/g, \"{nestId === 1 && (\\n                                <Route path={\`\${match.path}/maps\`} exact>\\n                                    <RequireServerPermission permissions={'file.*'}>\\n                                        <MinecraftMapsContainer/>\\n                                    </RequireServerPermission>\\n                                </Route>\\n                            )}\\n                            <Route path={\`\${match.path}/databases\`} exact>\");
    
    fs.writeFileSync('resources/scripts/routers/ServerRouter.tsx', file);
}
" 

# ৭. বিল্ড ও অপ্টিমাইজেশন
echo -e "\n\033[0;33mBuilding Pterodactyl Assets (This may take a minute)...\033[0m\n"
sleep 1
chown -R www-data:www-data /var/www/pterodactyl/*
chown -R www-data:www-data /var/www/pterodactyl/.*
export NODE_OPTIONS="--openssl-legacy-provider --no-deprecation"
yarn build:production
php artisan view:clear
php artisan optimize:clear 

echo -e "\n\033[0;32mInstallation Complete! 🚀\033[0m\n" 
sleep 1

cd /var/www/pterodactyl 

# কোর ফাইলগুলোতে কোড প্যাচ করা (Frontend TypeScript)
grep -q "internalId: number" resources/scripts/api/server/getServer.ts || sed -i "s/uuid: string;/internalId: number | string;\n    nestId: number | string;\n    uuid: string;/g" resources/scripts/api/server/getServer.ts 

grep -q "internalId: data.internal_id" resources/scripts/api/server/getServer.ts || sed -i "s/uuid: data.uuid,/internalId: data.internal_id,\n        nestId: data.nest_id,\n        uuid: data.uuid,/g" resources/scripts/api/server/getServer.ts 

# Node.js স্ক্রিপ্ট দিয়ে ServerRouter.tsx এডিট করা (নিরাপদ পদ্ধতি)
cat << 'EOF' > patch_router.js
const fs = require('fs');
let file = fs.readFileSync('resources/scripts/routers/ServerRouter.tsx', 'utf8'); 

if(!file.includes('MinecraftMapsContainer')) {
    file = file.replace(/import \{ ServerContext \} from '@\/state\/server';/, "import { ServerContext } from '@/state/server';\nimport MinecraftMapsContainer from '@/components/server/maps/MinecraftMapsContainer';");
    
    file = file.replace(/const serverId = ServerContext\.useStoreState\(state => state\.server\.data(!|\?)\.internalId\);/, "const serverId = ServerContext.useStoreState(state => state.server.data$1.internalId);\n    const nestId = ServerContext.useStoreState(state => state.server.data$1.nestId);");
    
    file = file.replace(/<Can action=\{'database\.\*'\}>/g, "{nestId === 1 && (\n                                <Can action={'file.*'}>\n                                    <NavLink to={`${match.url}/maps`}>Maps</NavLink>\n                                </Can>\n                            )}\n                            <Can action={'database.*'}>");
    
    file = file.replace(/<Route path=\{\`\$\{match\.path\}\/databases\`\} exact>/g, "{nestId === 1 && (\n                                <Route path={`${match.path}/maps`} exact>\n                                    <RequireServerPermission permissions={'file.*'}>\n                                        <MinecraftMapsContainer/>\n                                    </RequireServerPermission>\n                                </Route>\n                            )}\n                            <Route path={`${match.path}/databases`} exact>");
    
    fs.writeFileSync('resources/scripts/routers/ServerRouter.tsx', file);
    console.log("ServerRouter patched successfully!");
} else {
    console.log("ServerRouter already patched.");
}
EOF
node patch_router.js
rm patch_router.js 

# বিল্ড ও অপ্টিমাইজেশন (Asset Building)
echo -e "\n\033[0;33mBuilding Pterodactyl Assets (This may take a minute)...\033[0m\n"
sleep 1
chown -R www-data:www-data /var/www/pterodactyl/*
chown -R www-data:www-data /var/www/pterodactyl/.*
export NODE_OPTIONS="--openssl-legacy-provider --no-deprecation"
yarn build:production
php artisan view:clear
php artisan optimize:clear 

echo -e "\n\033[0;32mInstallation Complete! 🚀\033[0m\n" 
sleep 1

cd /var/www/pterodactyl 

# আপনার আগের যুক্ত করা ম্যানুয়াল রাউটগুলো ক্লিন করা
git checkout resources/scripts/routers/ServerRouter.tsx 

# ফাইলের পারমিশন ঠিক করা
chown -R www-data:www-data /var/www/pterodactyl/*
chown -R www-data:www-data /var/www/pterodactyl/.*
chmod -R 755 storage/* bootstrap/cache/ 

# Arix থিমের সাথে অ্যাসেট রিবিল্ড করা
export NODE_OPTIONS="--openssl-legacy-provider --no-deprecation"
yarn build:production 

# লারাভেল ক্যাশ ক্লিয়ার করা
php artisan view:clear
php artisan optimize:clear 

cd /var/www/pterodactyl 

# Node.js দিয়ে নিরাপদভাবে routes.ts ফাইলে কোড বসানো হচ্ছে
cat << 'EOF' > patch_routes.js
const fs = require('fs');
const path = 'resources/scripts/routers/routes.ts';
let file = fs.readFileSync(path, 'utf8'); 

if(!file.includes('MinecraftMapsContainer')) {
    // ইম্পোর্ট লাইন যুক্ত করা হচ্ছে
    file = file.replace(
        "import AccountSecurityContainer from '@/components/dashboard/account/AccountSecurityContainer';",
        "import AccountSecurityContainer from '@/components/dashboard/account/AccountSecurityContainer';\nimport MinecraftMapsContainer from '@/components/server/maps/MinecraftMapsContainer';"
    );
    
    // সার্ভার রাউটের ভেতরে Maps পেজের রুট যুক্ত করা হচ্ছে (nestIds: 1 মানে শুধু মাইনক্রাফটে দেখাবে)
    const mapRoute = `
        {
            path: '/maps',
            permission: 'file.*',
            name: 'maps',
            nestIds: [1],
            component: MinecraftMapsContainer,
        },`;
    
    file = file.replace(/server:\s*\[/, "server: [" + mapRoute);
    
    fs.writeFileSync(path, file);
    console.log("routes.ts patched successfully!");
} else {
    console.log("routes.ts already patched.");
}
EOF 

node patch_routes.js
rm patch_routes.js 

# প্যানেল রিবিল্ড করা হচ্ছে
chown -R www-data:www-data /var/www/pterodactyl/*
chown -R www-data:www-data /var/www/pterodactyl/.*
export NODE_OPTIONS="--openssl-legacy-provider --no-deprecation"
yarn build:production
php artisan view:clear
php artisan optimize:clear
cd /var/www/pterodactyl 

# ত্রুটিযুক্ত ফাইলটিকে ক্র্যাশ-প্রুফ কোড দিয়ে রিপ্লেস করা হচ্ছে
cat << 'EOF' > resources/scripts/components/server/maps/MinecraftMapsRow.tsx
import React, { useCallback } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faDownload } from '@fortawesome/free-solid-svg-icons';
import { format, formatDistanceToNow } from 'date-fns';
import tw from 'twin.macro';
import useFlash from '@/plugins/useFlash';
import GreyRowBox from '@/components/elements/GreyRowBox';
import { ServerContext } from '@/state/server';
import Select from '@/components/elements/Select';
import http from '@/api/http'; 

interface Props {
    minecraftMap: any;
    className?: string;
} 

export default ({ minecraftMap, className }: Props) => {
    const uuid = ServerContext.useStoreState(state => state.server.data!.uuid);
    const { clearAndAddHttpError, addFlash } = useFlash();
    
    // বাগ ফিক্স: files এবং latestFiles দুটোই চেক করবে
    const files = minecraftMap.files || minecraftMap.latestFiles || [];
    let url = files[0]?.downloadUrl; 

    const updateSelectedFile = useCallback((v: React.ChangeEvent<HTMLSelectElement>) => {
        url = v.currentTarget.value;
    }, [ uuid, url ]); 

    const installMap = () => {
        if (!url) return; 

        http.post(`/api/client/servers/${uuid}/files/pull`, { directory: '/', url: encodeURI(url) })
        .then(function () {
            addFlash({ type: 'success', key: 'minecraftMaps', message: 'File has been scheduled for downloading.' });
        })
        .catch(function (error) {
            clearAndAddHttpError({ key: 'minecraftMaps', error });
        });
    }; 

    return (
        <GreyRowBox css={tw`flex-wrap md:flex-nowrap items-center`} className={className}>
            <div css={tw`flex items-center truncate w-full md:flex-1`}>
                <div css={tw`flex flex-col truncate`}>
                    <div css={tw`flex items-center text-sm mb-1`}>
                        <div css={tw`w-10 h-10 rounded-lg bg-white border-2 border-neutral-800 overflow-hidden hidden md:block`}>
                            {/* বাগ ফিক্স: লোগো না থাকলে ক্র্যাশ করবে না */}
                            {minecraftMap.logo?.thumbnailUrl && (
                                <img css={tw`w-full h-full`} alt={minecraftMap.name} src={minecraftMap.logo.thumbnailUrl}/>
                            )}
                        </div>
                        <a href={minecraftMap.websiteUrl} css={tw`ml-4 break-words truncate`}>
                            {minecraftMap.name}
                        </a>
                    </div>
                    <p css={tw`mt-1 md:mt-0 text-xs truncate`}>
                        {/* বাগ ফিক্স: ক্যাটাগরি না থাকলে ক্র্যাশ করবে না */}
                        {(minecraftMap.categories || []).map((category: any, index: any) => (
                            <img css={index > 0 ? tw`ml-1 w-4 h-auto inline` : tw`w-4 h-auto inline`} key={category.categoryId} src={category.iconUrl} alt={category.name} title={category.name} />
                        ))}
                    </p>
                </div>
            </div>
            <div css={tw`flex-1 md:flex-none md:w-96 mt-4 md:mt-0 md:ml-8 md:text-center`}>
                <p css={tw`text-sm truncate`}>
                    {minecraftMap.summary || 'No description provided.'}
                </p>
            </div>
            <div css={tw`flex-1 md:flex-none md:w-48 mt-4 md:mt-0 md:ml-8 md:text-center`}>
                <p
                    title={minecraftMap.dateReleased ? format(new Date(minecraftMap.dateReleased), 'MMM do, yyyy') : 'Unknown'}
                    css={tw`text-sm`}
                >
                    {minecraftMap.dateReleased ? formatDistanceToNow(new Date(minecraftMap.dateReleased), { addSuffix: true }) : 'Unknown Date'}
                </p>
                <p css={tw`text-2xs text-neutral-500 uppercase mt-1`}>Released</p>
            </div>
            <div css={tw`flex-1 md:flex-none md:w-48 mt-4 md:mt-0 md:ml-8 md:text-center`}>
                <Select
                    disabled={files.length < 2}
                    onChange={updateSelectedFile}
                    defaultValue={files[0]?.id}
                >
                    {files.map((file: any) => (
                        <option key={file.id} value={file.downloadUrl}>{file.displayName}</option>
                    ))}
                </Select>
            </div>
            <div css={tw`mt-4 md:mt-0 ml-6`} style={{ marginRight: '-0.5rem' }}>
                <button
                    type={'button'}
                    aria-label={'Install'}
                    css={tw`block text-sm p-1 md:p-2 text-neutral-500 hover:text-neutral-100 transition-colors duration-150 mx-4`}
                    onClick={installMap}
                >
                    <FontAwesomeIcon icon={faDownload} />
                </button>
            </div>
        </GreyRowBox>
    );
};
EOF 

# কোড ফিক্স হয়ে গেছে, এখন প্যানেল পুনরায় রিবিল্ড করা হচ্ছে
chown -R www-data:www-data /var/www/pterodactyl/*
export NODE_OPTIONS="--openssl-legacy-provider --no-deprecation"
yarn build:production
php artisan view:clear
cd /var/www/pterodactyl 

cat << 'EOF' > resources/scripts/components/server/maps/MinecraftMapsRow.tsx
import React, { useCallback } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faDownload } from '@fortawesome/free-solid-svg-icons';
import { format, formatDistanceToNow } from 'date-fns';
import tw from 'twin.macro';
import useFlash from '@/plugins/useFlash';
import GreyRowBox from '@/components/elements/GreyRowBox';
import { ServerContext } from '@/state/server';
import Select from '@/components/elements/Select';
import http from '@/api/http'; 

interface Props {
    minecraftMap: any;
    className?: string;
} 

export default ({ minecraftMap, className }: Props) => {
    const uuid = ServerContext.useStoreState(state => state.server.data!.uuid);
    const { clearAndAddHttpError, addFlash } = useFlash();
    
    const files = minecraftMap.files || minecraftMap.latestFiles || [];
    let url = files[0]?.downloadUrl; 

    const updateSelectedFile = useCallback((v: React.ChangeEvent<HTMLSelectElement>) => {
        url = v.currentTarget.value;
    }, [ uuid, url ]); 

    const installMap = () => {
        if (!url) return; 

        http.post(`/api/client/servers/${uuid}/files/pull`, { directory: '/', url: encodeURI(url) })
        .then(function () {
            addFlash({ type: 'success', key: 'minecraftMaps', message: 'File has been scheduled for downloading.' });
        })
        .catch(function (error) {
            clearAndAddHttpError({ key: 'minecraftMaps', error });
        });
    }; 

    return (
        <GreyRowBox css={tw`flex-wrap xl:flex-nowrap items-center`} className={className}>
            <div css={tw`flex items-center truncate w-full xl:flex-1`}>
                <div css={tw`flex flex-col truncate`}>
                    <div css={tw`flex items-center text-sm mb-1`}>
                        <div css={tw`w-10 h-10 rounded-lg bg-white border-2 border-neutral-800 overflow-hidden hidden md:block`}>
                            {minecraftMap.logo?.thumbnailUrl && (
                                <img css={tw`w-full h-full`} alt={minecraftMap.name} src={minecraftMap.logo.thumbnailUrl}/>
                            )}
                        </div>
                        <a href={minecraftMap.websiteUrl} css={tw`ml-4 break-words truncate`}>
                            {minecraftMap.name}
                        </a>
                    </div>
                    <p css={tw`mt-1 md:mt-0 text-xs truncate`}>
                        {(minecraftMap.categories || []).map((category: any, index: any) => (
                            <img css={index > 0 ? tw`ml-1 w-4 h-auto inline` : tw`w-4 h-auto inline`} key={category.categoryId} src={category.iconUrl} alt={category.name} title={category.name} />
                        ))}
                    </p>
                </div>
            </div>
            
            {/* ডেসক্রিপশন শুধুমাত্র অনেক বড় স্ক্রিনে দেখাবে, যাতে ওভারফ্লো না হয় */}
            <div css={tw`hidden 2xl:block flex-1 mt-4 xl:mt-0 xl:ml-8 xl:text-center`}>
                <p css={tw`text-sm truncate`}>
                    {minecraftMap.summary || 'No description provided.'}
                </p>
            </div>
            
            <div css={tw`flex-1 xl:flex-none xl:w-40 mt-4 xl:mt-0 xl:ml-8 xl:text-center`}>
                <p title={minecraftMap.dateReleased ? format(new Date(minecraftMap.dateReleased), 'MMM do, yyyy') : 'Unknown'} css={tw`text-sm`}>
                    {minecraftMap.dateReleased ? formatDistanceToNow(new Date(minecraftMap.dateReleased), { addSuffix: true }) : 'Unknown Date'}
                </p>
                <p css={tw`text-2xs text-neutral-500 uppercase mt-1`}>Released</p>
            </div>
            
            <div css={tw`flex-1 xl:flex-none xl:w-48 mt-4 xl:mt-0 xl:ml-8 xl:text-center`}>
                <Select disabled={files.length < 2} onChange={updateSelectedFile} defaultValue={files[0]?.id}>
                    {files.map((file: any) => (
                        <option key={file.id} value={file.downloadUrl}>{file.displayName}</option>
                    ))}
                </Select>
            </div>
            
            <div css={tw`mt-4 xl:mt-0 ml-4`} style={{ marginRight: '-0.5rem' }}>
                <button type={'button'} aria-label={'Install'} css={tw`block text-sm p-1 md:p-2 text-neutral-500 hover:text-neutral-100 transition-colors duration-150 mx-4`} onClick={installMap}>
                    <FontAwesomeIcon icon={faDownload} />
                </button>
            </div>
        </GreyRowBox>
    );
};
EOF 

# ইউআই পারফেক্ট করার পর প্যানেল রিবিল্ড করা হচ্ছে
chown -R www-data:www-data /var/www/pterodactyl/*
export NODE_OPTIONS="--openssl-legacy-provider --no-deprecation"
yarn build:production
php artisan view:clear
chown -R www-data:www-data /var/www/pterodactyl/*
chown -R www-data:www-data /var/www/pterodactyl/.*
cd /var/www/pterodactyl 
yarn add xterm-addon-unicode11
yarn build
chown -R www-data:www-data /var/www/pterodactyl/*
cd
