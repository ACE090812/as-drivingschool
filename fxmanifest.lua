fx_version 'cerulean'
game 'gta5'

author 'AS'
description 'DVLA driving school: theory and practical tests, penalty points, and lsgov.co.uk booking'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/locale.lua',
    'locales/*.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js'
}
