// GENERATED 1:1 from the Generator Hub workflow (generator.yml, ringtone
// job): the Zedge policy texts and word lists. Edit the workflow text
// and this file together.

final RegExp policyPromo = RegExp(
    r"\b(free|download|downloads|website|subscribe|follow|buy|sale|discount|promo|www|http|https|telegram|whatsapp|instagram|tiktok|youtube|facebook|twitter|zedge)\b",
    caseSensitive: false);

final RegExp policyAdult = RegExp(
    r"\b(sexy|sex|sexual|nude|nudity|naked|porn|porno|xxx|erotic|erotica|boobs|breasts?|booty|bikini|lingerie|topless|hot girls?|seductive|nsfw|hentai|fetish|stripper|thong|underwear|cleavage)\b",
    caseSensitive: false);

final RegExp policyHarm = RegExp(
    r"\b(nigg\w*|fagg?\w*|retard\w*|murder|gore|gun|guns|rifle|pistol|shooting|shooter|terror\w*|nazi|hitler|swastika|isis|jihad|marijuana|cocaine|heroin|meth|drugs|suicide|self-harm|rape|racist|slur)\b",
    caseSensitive: false);

final RegExp policyIp = RegExp(
    r"\b(disney|pixar|marvel|dc comics|batman|superman|spider-?man|iron ?man|avengers|wolverine|x-?men|deadpool|harley quinn|star ?wars|darth|vader|yoda|jedi|mandalorian|grogu|harry ?potter|hogwarts|lord of the rings|hobbit|game of thrones|stranger things|squid game|breaking bad|pokemon|pikachu|charizard|super mario|luigi|zelda|minecraft|fortnite|roblox|among us|gta|call of duty|pubg|free fire|valorant|league of legends|overwatch|god of war|kratos|elden ring|naruto|goku|dragon ?ball|one piece|luffy|attack on titan|demon slayer|jujutsu|gojo|itachi|sasuke|death note|my hero academia|hello kitty|sanrio|mickey|minnie|donald duck|elsa|moana|encanto|toy story|shrek|minions|despicable|kung fu panda|spongebob|simpsons|rick and morty|peppa|paw patrol|barbie|hot wheels|lego|nike|adidas|puma|gucci|louis vuitton|iphone|ipad|ipod|apple|ios|macintosh|macbook|imac|airdrop|facetime|imessage|siri|marimba|reflection|tritone|tri-?tone|samsung|galaxy|over the horizon|nokia|nokia tune|nokia tone|gran vals|motorola|hello moto|google pixel|pixel chime|sony xperia|xperia|blackberry|windows phone|android|skype|microsoft teams|teams ringtone|discord chime|discord call|slack knock|intel inside|netflix tudum|tudum|playstation|xbox|nintendo|game boy|xiaomi|oneplus|huawei|tesla|bmw|mercedes|audi|ferrari|lamborghini|porsche|toyota|coca-?cola|pepsi|starbucks|mcdonald'?s|kfc|netflix|spotify|nfl|nba|fifa|uefa|real madrid|barcelona|manchester united|liverpool fc|juventus|psg|messi|ronaldo|neymar|mbappe|lebron|taylor swift|beyonce|drake|eminem|rihanna|bts|blackpink|billie eilish|ed sheeran|weeknd|bad bunny|justin bieber|ariana grande|dua lipa|coldplay|imagine dragons|linkin park|metallica|beatles|nirvana|michael jackson|elvis|kanye|travis scott|post malone|shakira|adele|bruno mars|hans zimmer|john williams|bollywood|shah rukh|salman khan|allu arjun|pushpa|kgf|pathaan|jawan|kabir singh|arijit|pritam|ar rahman|a\.r\. rahman|anirudh|godzilla|king kong|jurassic|transformers|optimus prime|bumblebee|pirates of the caribbean|jack sparrow|james bond|mission impossible|john wick|fast and furious|terminator|poppy playtime|huggy wuggy|skibidi|fnaf|cuphead|genshin|honkai|clash of clans|clash royale|brawl stars|candy crush|angry birds|subway surfers|temple run|flappy bird|tom and jerry|doraemon|shinchan|ben 10|scooby|looney|bugs bunny|winnie the pooh|cars movie|lightning mcqueen|olaf|stitch|lilo|baymax|zootopia|inside out|wednesday addams|squid|haikyuu|chainsaw man|spy x family|frieren|solo leveling|sung jinwoo)\b",
    caseSensitive: false);

const String zedgePolicyRules = r'''ZEDGE MARKETPLACE POLICY (MANDATORY — a single violation permanently suspends the seller account):
- 100% ORIGINAL work only. Never name, reference, imitate or hint at any real artist, band, singer, song, lyric, album, film, TV show, game, anime, cartoon, comic, character, franchise, brand, company, product, logo, trademark, sports team, celebrity or public figure. No "in the style of", no "sounds like", no theme/cover/remix of anything existing.
- STRICT PHONE RINGTONE & TECH BRAND BAN: Never recreate, imitate, name, or reference ANY stock phone ringtone, alert tone, or OS sound (e.g. Apple/iPhone Marimba, Reflection, Opening, Tri-tone, Ding, FaceTime, Siri; Samsung Over the Horizon, Whistle; Nokia Tune; Motorola Hello Moto; Google Pixel; Windows, Skype, Discord, Teams, Netflix, Intel). Never use brand names like iPhone, Apple, Samsung, Galaxy, Nokia, Android, Pixel in titles, prompts, or tags.
- No sexual, suggestive, nude or adult content. No hate speech, slurs, hate symbols, discrimination or stereotypes. No violence, gore, weapons, drugs, self-harm or illegal activity. Nothing involving minors.
- Metadata must be truthful and describe ONLY this item. No promotional or spam words (free, download, app, website, subscribe, follow, link, buy), no URLs, hashtags, @handles, emojis, brand or service names, no misleading keywords.
- Keywords: between 2 and 10 genuine descriptive single words.''';

const String defaultNegativePrompt =
    r'''low quality, muddy, muffled, static, white noise, tape hiss, hum, harsh distortion, clipping, off-beat, arrhythmic, out of tune, dissonant, random chaotic notes, vocals, singing, talking, speech, gibberish voices, stock iPhone marimba, Samsung ringtone, Nokia tune, silence, abrupt cut-off, amateur recording, tinny, ear-piercing high frequencies''';

const String defaultBannedWords =
    r'''Glitched, Echo, Electronic, Digital, Lo-fi, Synth, Pulse, Wave, Bass, Trap, Chill, Cool, Awesome, Ringtone, Beat, Sound, Vibe, Remix, DJ, Techno, EDM''';

const String defaultMasterPrompt = r'''You are an award-winning mobile sound designer and Zedge marketplace metadata specialist. Your ringtones and notification tones top charts because they are musical, crystal-clear, harmonically rich, and pleasant to hear every day.

{{ZEDGE_POLICY_RULES}}

{{RENDERER_RULES}}

STUDIO PARAMETERS & CONSTRAINTS:
- Target Format: {{SOUND_TYPE}} ({{DURATION}} seconds)
- Tempo / BPM: {{BPM}}
- Featured Instruments: {{INSTRUMENTS}}
- Genre Direction: {{GENRE}}
- Mood / Atmosphere: {{MOOD}}
- Musical Key / Scale: {{KEY}}
- Hook Structure: {{STRUCTURE}}
- Production Mix: {{PRODUCTION}}
- STRICT NEGATIVE CONSTRAINTS (NEVER include these in the sound): {{NEGATIVE_PROMPT}}

{{CRAFT_RULES}}

TASK:
{{IDEA}}

Based on the text-to-music prompt you craft, also generate marketplace metadata:
1. A creative and UNIQUE title (max 25 characters). DO NOT USE THESE BANNED WORDS: {{BANNED_WORDS}}. No quotes.
2. 10 relevant, descriptive SINGLE-WORD keywords (comma-separated) that truthfully describe THIS sound only. Every keyword must correspond to an instrument, genre, or mood present in the audio prompt.
3. The most appropriate category selected ONLY from this list: {{VALID_CATEGORIES}}.
4. An ULTRA-SHORT description in EXACTLY 2 TO 3 WORDS (max 25 chars) capturing the core sound. No punctuation, no filler.

CRITICAL: Format your entire response EXACTLY like this template with no text outside these tags:
[ENHANCED_PROMPT]...[/ENHANCED_PROMPT]
[TITLE]...[/TITLE]
[KEYWORDS]...[/KEYWORDS]
[CATEGORY]...[/CATEGORY]
[DESCRIPTION]...[/DESCRIPTION]''';
