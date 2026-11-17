// Browser domain and path vocabulary from Edge-Drop (Apache-2.0), commit 31ac86cf.
enum ClipboardLinkDirectory {
    static let suffixes = Set("""
        co.uk org.uk gov.uk ac.uk me.uk net.uk sch.uk police.uk nhs.uk co.nz net.nz org.nz govt.nz ac.nz
        school.nz geek.nz gen.nz com.au net.au org.au edu.au gov.au id.au asn.au co.za org.za web.za gov.za ac.za
        net.za co.jp ne.jp or.jp go.jp ac.jp ed.jp lg.jp ad.jp gr.jp co.in net.in org.in gen.in firm.in ind.in
        gov.in res.in ac.in edu.in mil.in nic.in co.kr ne.kr or.kr re.kr pe.kr go.kr ac.kr hs.kr ms.kr es.kr
        com.sg net.sg org.sg gov.sg edu.sg per.sg com.tw org.tw net.tw gov.tw edu.tw idv.tw club.tw com.hk org.hk
        net.hk gov.hk edu.hk idv.hk com.cn net.cn org.cn gov.cn edu.cn ac.cn ah.cn bj.cn sh.cn co.id net.id
        org.id web.id sch.id go.id ac.id my.id biz.id com.my net.my org.my gov.my edu.my mil.my com.ph net.ph
        org.ph gov.ph edu.ph com.vn net.vn org.vn gov.vn edu.vn ac.vn co.th ac.th go.th in.th or.th net.th co.il
        org.il net.il ac.il gov.il muni.il k12.il co.ae net.ae org.ae gov.ae ac.ae sch.ae com.sa net.sa org.sa
        gov.sa edu.sa med.sa com.pk org.pk gov.pk edu.pk net.pk com.bd org.bd gov.bd edu.bd com.np org.np gov.np
        com.lk org.lk gov.lk com.tr org.tr gov.tr edu.tr net.tr k12.tr av.tr bel.tr co.at or.at gv.at ac.at co.hu
        org.hu gov.hu edu.hu co.ee org.ee fie.ee med.ee com.pl org.pl net.pl gov.pl com.ua org.ua gov.ua com.ru
        org.ru com.gr gov.gr com.es gob.es co.it com.br net.br org.br gov.br edu.br art.br app.br dev.br srv.br
        com.mx org.mx gob.mx edu.mx net.mx com.ar org.ar gov.ar edu.ar net.ar com.co org.co gov.co edu.co net.co
        com.pe org.pe gob.pe edu.pe net.pe com.cl gob.cl gov.cl co.cl gc.ca gov.bc.ca gov.ab.ca gov.sk.ca
        gov.mb.ca gov.on.ca gov.qc.ca com.ng org.ng gov.ng edu.ng net.ng com.eg org.eg gov.eg edu.eg net.eg co.ke
        or.ke go.ke ac.ke sc.ke
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static let hostedPlatforms = Set("""
        github.io vercel.app netlify.app pages.dev workers.dev web.app firebaseapp.com herokuapp.com blogspot.com
        wordpress.com substack.com medium.com notion.site webflow.io framer.website framer.app gitbook.io
        readthedocs.io tumblr.com myshopify.com hashnode.dev ghost.io wixsite.com carrd.co neocities.org
        glitch.me surge.sh onrender.com fly.dev replit.app streamlit.app bearblog.dev
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static let shorteners = Set("""
        bit.ly bitly.com t.co tinyurl.com ow.ly buff.ly rebrand.ly is.gd v.gd cutt.ly rb.gy shorturl.at s.id t.ly
        bl.ink dub.sh tiny.cc shorte.st lnkd.in amzn.to amzn.in amzn.eu a.co goo.gl maps.app.goo.gl forms.gle
        g.co fb.me pin.it spoti.fi spotify.link apple.co aka.ms 1drv.ms redd.it dl.flipkart.com vm.tiktok.com
        vt.tiktok.com instagr.am trib.al ift.tt lnk.to msft.it surl.li
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static let trackerKeys = Set("""
        utm_source utm_medium utm_campaign utm_term utm_content utm_id fbclid gclid dclid msclkid twclid gbraid
        wbraid ttclid li_fat_id epik srsltid ref ref_src ref_url source si igshid igsh feature trk trkid pp
        _hsenc _hsmi mc_cid mc_eid yclid zanpid sc_cid cmpid icid ncid mkt_tok spreportid __twitter_impression
        vero_id vero_conv oly_anon_id oly_enc_id rb_clickid s_cid share_id
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static let acronyms = Set("""
        AI API UI UX SDK CLI URL URI CSS HTML JS TS SQL DB AWS GCP OS ID IP VR AR MR ML LLM PR FAQ PDF CSV JSON
        YAML XML SVG PNG JPG GIF BBC CNN WSJ IMDB NPM PYPI USA UK EU GB TB MB KB HD UHD TV PC USB SSD GPU CPU RAM
        IOS NFT CEO GPT
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static let smallWords = Set("""
        a an the and or but of in on at to for by with vs via as from into
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static let fillerSegments = Set("""
        view edit index default home main p dp gp d s w r u c g e t a b l x product products item items itm
        article articles post posts page pages search amp m share shared embed watch file files folder folders
        open details detail show read story stories content contents entry category categories tag tags id
        preview download status comments thread topic articleshow photostory videoshow liveblog web www public
        static assets en us html php aspx redirect link out go click
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static let trackerPrefixes = ["utm_", "ga_", "mc_", "hs_", "pk_", "mtm_"]

    static let brands = [
        "github.com": "GitHub", "gist.github.com": "GitHub Gist", "docs.github.com": "GitHub Docs",
        "githubusercontent.com": "GitHub", "github.io": "GitHub Pages", "github.dev": "GitHub",
        "gitlab.com": "GitLab", "bitbucket.org": "Bitbucket", "codeberg.org": "Codeberg",
        "stackoverflow.com": "Stack Overflow", "stackexchange.com": "Stack Exchange",
        "superuser.com": "Super User", "serverfault.com": "Server Fault", "askubuntu.com": "Ask Ubuntu",
        "mathoverflow.net": "MathOverflow", "npmjs.com": "npm", "pypi.org": "PyPI", "crates.io": "crates.io",
        "packagist.org": "Packagist", "rubygems.org": "RubyGems", "pkg.go.dev": "Go Packages",
        "hub.docker.com": "Docker Hub", "docker.com": "Docker", "nuget.org": "NuGet", "codepen.io": "CodePen",
        "jsfiddle.net": "JSFiddle", "replit.com": "Replit", "codesandbox.io": "CodeSandbox",
        "stackblitz.com": "StackBlitz", "jsdelivr.com": "jsDelivr", "cdnjs.com": "cdnjs", "unpkg.com": "unpkg",
        "vercel.com": "Vercel", "vercel.app": "Vercel", "netlify.com": "Netlify", "netlify.app": "Netlify",
        "render.com": "Render", "railway.app": "Railway", "fly.io": "Fly.io", "supabase.com": "Supabase",
        "firebase.google.com": "Firebase", "cloudflare.com": "Cloudflare", "pages.dev": "Cloudflare Pages",
        "workers.dev": "Cloudflare Workers", "aws.amazon.com": "AWS", "console.aws.amazon.com": "AWS Console",
        "digitalocean.com": "DigitalOcean", "heroku.com": "Heroku", "herokuapp.com": "Heroku",
        "neon.tech": "Neon", "planetscale.com": "PlanetScale", "upstash.com": "Upstash", "sentry.io": "Sentry",
        "datadoghq.com": "Datadog", "postman.com": "Postman", "swagger.io": "Swagger",
        "readthedocs.io": "Read the Docs", "gitbook.io": "GitBook", "developer.mozilla.org": "MDN Web Docs",
        "w3schools.com": "W3Schools", "freecodecamp.org": "freeCodeCamp", "geeksforgeeks.org": "GeeksforGeeks",
        "leetcode.com": "LeetCode", "hackerrank.com": "HackerRank", "codeforces.com": "Codeforces",
        "codechef.com": "CodeChef", "tailwindcss.com": "Tailwind CSS", "react.dev": "React",
        "reactjs.org": "React", "vuejs.org": "Vue.js", "svelte.dev": "Svelte", "angular.dev": "Angular",
        "angular.io": "Angular", "nextjs.org": "Next.js", "nodejs.org": "Node.js", "deno.com": "Deno",
        "bun.sh": "Bun", "typescriptlang.org": "TypeScript", "python.org": "Python",
        "docs.python.org": "Python Docs", "rust-lang.org": "Rust", "go.dev": "Go", "kotlinlang.org": "Kotlin",
        "learn.microsoft.com": "Microsoft Learn", "electronjs.org": "Electron", "vitejs.dev": "Vite",
        "vite.dev": "Vite", "openai.com": "OpenAI", "platform.openai.com": "OpenAI Platform",
        "chatgpt.com": "ChatGPT", "chat.openai.com": "ChatGPT", "anthropic.com": "Anthropic",
        "claude.ai": "Claude", "console.anthropic.com": "Anthropic Console", "perplexity.ai": "Perplexity",
        "gemini.google.com": "Google Gemini", "aistudio.google.com": "Google AI Studio",
        "notebooklm.google.com": "NotebookLM", "huggingface.co": "Hugging Face", "kaggle.com": "Kaggle",
        "midjourney.com": "Midjourney", "stability.ai": "Stability AI", "replicate.com": "Replicate",
        "mistral.ai": "Mistral AI", "chat.mistral.ai": "Le Chat", "cohere.com": "Cohere",
        "elevenlabs.io": "ElevenLabs", "runwayml.com": "Runway", "suno.com": "Suno", "civitai.com": "Civitai",
        "cursor.com": "Cursor", "cursor.sh": "Cursor", "phind.com": "Phind", "deepseek.com": "DeepSeek",
        "chat.deepseek.com": "DeepSeek", "x.ai": "xAI", "grok.com": "Grok",
        "copilot.microsoft.com": "Microsoft Copilot", "poe.com": "Poe", "character.ai": "Character.AI",
        "figma.com": "Figma", "dribbble.com": "Dribbble", "behance.net": "Behance", "canva.com": "Canva",
        "adobe.com": "Adobe", "artstation.com": "ArtStation", "unsplash.com": "Unsplash", "pexels.com": "Pexels",
        "freepik.com": "Freepik", "pixabay.com": "Pixabay", "spline.design": "Spline", "webflow.com": "Webflow",
        "webflow.io": "Webflow", "framer.com": "Framer", "framer.website": "Framer", "framer.app": "Framer",
        "fontawesome.com": "Font Awesome", "fonts.google.com": "Google Fonts", "iconify.design": "Iconify",
        "lucide.dev": "Lucide", "coolors.co": "Coolors", "notion.so": "Notion", "notion.site": "Notion",
        "obsidian.md": "Obsidian", "linear.app": "Linear", "atlassian.net": "Atlassian",
        "atlassian.com": "Atlassian", "jira.atlassian.com": "Jira", "confluence.atlassian.com": "Confluence",
        "trello.com": "Trello", "asana.com": "Asana", "monday.com": "monday.com", "clickup.com": "ClickUp",
        "basecamp.com": "Basecamp", "airtable.com": "Airtable", "coda.io": "Coda", "miro.com": "Miro",
        "lucidchart.com": "Lucidchart", "excalidraw.com": "Excalidraw", "dropbox.com": "Dropbox",
        "box.com": "Box", "evernote.com": "Evernote", "raycast.com": "Raycast", "loom.com": "Loom",
        "calendly.com": "Calendly", "zoom.us": "Zoom", "zoom.com": "Zoom", "webex.com": "Webex",
        "whereby.com": "Whereby", "typeform.com": "Typeform", "tally.so": "Tally", "google.com": "Google",
        "docs.google.com": "Google Docs", "drive.google.com": "Google Drive", "maps.google.com": "Google Maps",
        "meet.google.com": "Google Meet", "calendar.google.com": "Google Calendar", "mail.google.com": "Gmail",
        "photos.google.com": "Google Photos", "keep.google.com": "Google Keep",
        "cloud.google.com": "Google Cloud", "console.cloud.google.com": "Google Cloud Console",
        "play.google.com": "Google Play", "news.google.com": "Google News",
        "translate.google.com": "Google Translate", "sites.google.com": "Google Sites",
        "chat.google.com": "Google Chat", "scholar.google.com": "Google Scholar",
        "books.google.com": "Google Books", "forms.gle": "Google Forms", "g.co": "Google", "goo.gl": "Google",
        "maps.app.goo.gl": "Google Maps", "blogspot.com": "Blogger", "blogger.com": "Blogger",
        "web.app": "Firebase", "firebaseapp.com": "Firebase", "microsoft.com": "Microsoft",
        "office.com": "Microsoft 365", "microsoft365.com": "Microsoft 365", "live.com": "Microsoft",
        "outlook.com": "Outlook", "outlook.live.com": "Outlook", "outlook.office.com": "Outlook",
        "teams.microsoft.com": "Microsoft Teams", "teams.live.com": "Microsoft Teams",
        "onedrive.live.com": "OneDrive", "1drv.ms": "OneDrive", "sharepoint.com": "SharePoint",
        "azure.microsoft.com": "Azure", "portal.azure.com": "Azure Portal", "bing.com": "Bing", "msn.com": "MSN",
        "aka.ms": "Microsoft", "apps.microsoft.com": "Microsoft Store", "xbox.com": "Xbox",
        "linkedin.com": "LinkedIn", "lnkd.in": "LinkedIn", "apple.com": "Apple", "icloud.com": "iCloud",
        "developer.apple.com": "Apple Developer", "music.apple.com": "Apple Music",
        "podcasts.apple.com": "Apple Podcasts", "tv.apple.com": "Apple TV", "apps.apple.com": "App Store",
        "support.apple.com": "Apple Support", "apple.co": "Apple", "twitter.com": "X", "x.com": "X", "t.co": "X",
        "reddit.com": "Reddit", "redd.it": "Reddit", "discord.com": "Discord", "discord.gg": "Discord",
        "slack.com": "Slack", "telegram.org": "Telegram", "t.me": "Telegram", "telegram.me": "Telegram",
        "web.telegram.org": "Telegram Web", "whatsapp.com": "WhatsApp", "web.whatsapp.com": "WhatsApp Web",
        "chat.whatsapp.com": "WhatsApp", "wa.me": "WhatsApp", "signal.org": "Signal", "signal.me": "Signal",
        "threads.net": "Threads", "threads.com": "Threads", "bsky.app": "Bluesky", "mastodon.social": "Mastodon",
        "instagram.com": "Instagram", "instagr.am": "Instagram", "facebook.com": "Facebook",
        "fb.com": "Facebook", "fb.me": "Facebook", "fb.watch": "Facebook", "messenger.com": "Messenger",
        "pinterest.com": "Pinterest", "pin.it": "Pinterest", "tiktok.com": "TikTok", "snapchat.com": "Snapchat",
        "tumblr.com": "Tumblr", "quora.com": "Quora", "medium.com": "Medium", "substack.com": "Substack",
        "dev.to": "DEV Community", "hashnode.com": "Hashnode", "hashnode.dev": "Hashnode",
        "producthunt.com": "Product Hunt", "news.ycombinator.com": "Hacker News", "linktr.ee": "Linktree",
        "wordpress.com": "WordPress", "ghost.io": "Ghost", "youtube.com": "YouTube", "youtu.be": "YouTube",
        "music.youtube.com": "YouTube Music", "studio.youtube.com": "YouTube Studio", "vimeo.com": "Vimeo",
        "twitch.tv": "Twitch", "netflix.com": "Netflix", "primevideo.com": "Prime Video",
        "disneyplus.com": "Disney+", "hotstar.com": "JioHotstar", "jiohotstar.com": "JioHotstar",
        "jiocinema.com": "JioCinema", "sonyliv.com": "SonyLIV", "zee5.com": "ZEE5", "hulu.com": "Hulu",
        "max.com": "Max", "spotify.com": "Spotify", "spotify.link": "Spotify", "spoti.fi": "Spotify",
        "soundcloud.com": "SoundCloud", "tidal.com": "Tidal", "bandcamp.com": "Bandcamp", "deezer.com": "Deezer",
        "gaana.com": "Gaana", "jiosaavn.com": "JioSaavn", "wynk.in": "Wynk Music", "imdb.com": "IMDb",
        "rottentomatoes.com": "Rotten Tomatoes", "letterboxd.com": "Letterboxd", "goodreads.com": "Goodreads",
        "audible.com": "Audible", "audible.in": "Audible", "steampowered.com": "Steam",
        "steamcommunity.com": "Steam", "epicgames.com": "Epic Games", "playstation.com": "PlayStation",
        "nintendo.com": "Nintendo", "roblox.com": "Roblox", "gog.com": "GOG", "itch.io": "itch.io",
        "chess.com": "Chess.com", "lichess.org": "Lichess", "amazon.com": "Amazon", "amzn.to": "Amazon",
        "amzn.in": "Amazon", "amzn.eu": "Amazon", "a.co": "Amazon", "ebay.com": "eBay",
        "aliexpress.com": "AliExpress", "shopify.com": "Shopify", "myshopify.com": "Shopify", "etsy.com": "Etsy",
        "walmart.com": "Walmart", "target.com": "Target", "bestbuy.com": "Best Buy", "ikea.com": "IKEA",
        "flipkart.com": "Flipkart", "dl.flipkart.com": "Flipkart", "myntra.com": "Myntra",
        "meesho.com": "Meesho", "nykaa.com": "Nykaa", "ajio.com": "AJIO", "snapdeal.com": "Snapdeal",
        "bigbasket.com": "BigBasket", "blinkit.com": "Blinkit", "zeptonow.com": "Zepto", "swiggy.com": "Swiggy",
        "zomato.com": "Zomato", "uber.com": "Uber", "olacabs.com": "Ola", "rapido.bike": "Rapido",
        "makemytrip.com": "MakeMyTrip", "goibibo.com": "Goibibo", "cleartrip.com": "Cleartrip",
        "bookmyshow.com": "BookMyShow", "irctc.co.in": "IRCTC", "booking.com": "Booking.com",
        "airbnb.com": "Airbnb", "tripadvisor.com": "Tripadvisor", "expedia.com": "Expedia",
        "skyscanner.net": "Skyscanner", "stripe.com": "Stripe", "paypal.com": "PayPal", "paypal.me": "PayPal",
        "wise.com": "Wise", "coinbase.com": "Coinbase", "binance.com": "Binance", "robinhood.com": "Robinhood",
        "paytm.com": "Paytm", "phonepe.com": "PhonePe", "razorpay.com": "Razorpay", "groww.in": "Groww",
        "zerodha.com": "Zerodha", "kite.zerodha.com": "Kite", "moneycontrol.com": "Moneycontrol",
        "onlinesbi.sbi": "SBI", "sbi.co.in": "SBI", "hdfcbank.com": "HDFC Bank", "icicibank.com": "ICICI Bank",
        "axisbank.com": "Axis Bank", "uidai.gov.in": "UIDAI", "incometax.gov.in": "Income Tax India",
        "digilocker.gov.in": "DigiLocker", "naukri.com": "Naukri", "indeed.com": "Indeed",
        "glassdoor.com": "Glassdoor", "internshala.com": "Internshala", "coursera.org": "Coursera",
        "udemy.com": "Udemy", "edx.org": "edX", "khanacademy.org": "Khan Academy", "unacademy.com": "Unacademy",
        "byjus.com": "BYJU'S", "duolingo.com": "Duolingo", "brilliant.org": "Brilliant", "nptel.ac.in": "NPTEL",
        "swayam.gov.in": "SWAYAM", "wikipedia.org": "Wikipedia", "wikimedia.org": "Wikimedia",
        "wiktionary.org": "Wiktionary", "wikihow.com": "wikiHow", "britannica.com": "Britannica",
        "theverge.com": "The Verge", "techcrunch.com": "TechCrunch", "wired.com": "WIRED",
        "arstechnica.com": "Ars Technica", "engadget.com": "Engadget", "9to5mac.com": "9to5Mac",
        "9to5google.com": "9to5Google", "macrumors.com": "MacRumors",
        "androidauthority.com": "Android Authority", "gsmarena.com": "GSMArena",
        "nytimes.com": "The New York Times", "wsj.com": "The Wall Street Journal",
        "washingtonpost.com": "The Washington Post", "bloomberg.com": "Bloomberg", "reuters.com": "Reuters",
        "apnews.com": "AP News", "ft.com": "Financial Times", "economist.com": "The Economist",
        "forbes.com": "Forbes", "bbc.com": "BBC", "bbc.co.uk": "BBC", "cnn.com": "CNN",
        "theguardian.com": "The Guardian", "aljazeera.com": "Al Jazeera", "ign.com": "IGN",
        "polygon.com": "Polygon", "timesofindia.indiatimes.com": "Times of India",
        "economictimes.indiatimes.com": "The Economic Times", "indiatimes.com": "Indiatimes", "ndtv.com": "NDTV",
        "thehindu.com": "The Hindu", "hindustantimes.com": "Hindustan Times",
        "indianexpress.com": "The Indian Express", "livemint.com": "Mint", "news18.com": "News18",
        "indiatoday.in": "India Today", "aajtak.in": "Aaj Tak", "thewire.in": "The Wire", "scroll.in": "Scroll",
        "arxiv.org": "arXiv", "nature.com": "Nature", "sciencedirect.com": "ScienceDirect",
        "pubmed.ncbi.nlm.nih.gov": "PubMed", "researchgate.net": "ResearchGate", "doi.org": "DOI",
        "archive.org": "Internet Archive", "web.archive.org": "Wayback Machine", "bit.ly": "Bitly",
        "bitly.com": "Bitly", "tinyurl.com": "TinyURL", "ow.ly": "Hootsuite", "buff.ly": "Buffer",
        "rebrand.ly": "Rebrandly", "is.gd": "is.gd", "v.gd": "v.gd", "cutt.ly": "Cuttly", "rb.gy": "rb.gy",
        "shorturl.at": "ShortURL", "s.id": "s.id", "t.ly": "T.LY", "bl.ink": "BL.INK", "dub.sh": "Dub",
        "tiny.cc": "tiny.cc", "ift.tt": "IFTTT", "lnk.to": "Linkfire", "trib.al": "Trib.al",
        "surl.li": "surl.li", "msft.it": "Microsoft", "shorte.st": "Shorte.st", "duckduckgo.com": "DuckDuckGo",
        "search.yahoo.com": "Yahoo Search", "yahoo.com": "Yahoo", "baidu.com": "Baidu", "yandex.com": "Yandex",
        "yandex.ru": "Yandex", "ecosia.org": "Ecosia", "search.brave.com": "Brave Search", "brave.com": "Brave",
        "startpage.com": "Startpage", "mozilla.org": "Mozilla",
    ]

    static let casedWords = [
        "iphone": "iPhone", "ipad": "iPad", "ipod": "iPod", "imac": "iMac", "macbook": "MacBook",
        "airpods": "AirPods", "ios": "iOS", "macos": "macOS", "ipados": "iPadOS", "watchos": "watchOS",
        "icloud": "iCloud", "itunes": "iTunes", "youtube": "YouTube", "github": "GitHub", "gitlab": "GitLab",
        "javascript": "JavaScript", "typescript": "TypeScript", "nodejs": "Node.js", "linkedin": "LinkedIn",
        "paypal": "PayPal", "whatsapp": "WhatsApp", "tiktok": "TikTok", "chatgpt": "ChatGPT", "openai": "OpenAI",
        "wifi": "Wi-Fi", "ebay": "eBay", "playstation": "PlayStation", "xbox": "Xbox", "oneplus": "OnePlus",
        "powerpoint": "PowerPoint", "onedrive": "OneDrive", "sharepoint": "SharePoint", "wordpress": "WordPress",
        "mongodb": "MongoDB", "postgresql": "PostgreSQL", "mysql": "MySQL", "graphql": "GraphQL",
        "webassembly": "WebAssembly", "devops": "DevOps", "faq": "FAQ", "faqs": "FAQs",
    ]

}
