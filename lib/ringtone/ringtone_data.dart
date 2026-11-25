// Option lists, category lists and the Smart Variety pools, ported
// from the Generator Hub workflow's Ringtone Studio (generator.yml).

/// The 26 Zedge ringtone categories (VALID_RT_CATS).
const List<String> kRingtoneCategories = [
  'LATIN', 'MESSAGE_TONES', 'OTHER', 'POP', 'RNB_SOUL', 'REGGAE',
  'RELIGIOUS', 'ROCK', 'SAYINGS', 'ALTERNATIVE', 'ANIMALS', 'BLUES',
  'BOLLYWOOD', 'CHILDREN', 'CLASSICAL', 'SOUND_EFFECTS', 'WORLD',
  'COMEDY', 'CONTACT_RINGTONES', 'COUNTRY', 'DANCE', 'ELECTRONICA',
  'GAMES', 'HIP_HOP', 'HOLIDAYS', 'JAZZ',
];

/// The 21 Zedge image categories (VALID_IMG_CATS).
const List<String> kImageCategories = [
  'ANIMALS', 'ANIME', 'CARS_N_VEHICLES', 'COMICS', 'DESIGNS',
  'DRAWINGS', 'ENTERTAINMENT', 'FUNNY', 'GAMES', 'HOLIDAYS', 'LOVE',
  'MUSIC', 'NATURE', 'OTHER', 'PATTERNS', 'PEOPLE', 'SAYINGS',
  'SPACE', 'SPIRITUAL', 'SPORTS', 'TECHNOLOGY',
];

/// Image category alias map (from the workflow's cleanCategory).
const Map<String, List<String>> kImageCategoryAliases = {
  'ANIMALS': ['ANIMAL', 'ANIMALS', 'WILDLIFE', 'PET', 'PETS', 'BIRD', 'BIRDS', 'CAT', 'DOG'],
  'ANIME': ['ANIME', 'MANGA', 'ANIMATION', 'ANIMATED'],
  'CARS_N_VEHICLES': ['CAR', 'CARS', 'VEHICLE', 'VEHICLES', 'AUTOMOTIVE', 'AUTO', 'TRUCK', 'MOTORCYCLE', 'BIKE', 'TRANSPORT', 'CARS N VEHICLES', 'CARS AND VEHICLES'],
  'COMICS': ['COMIC', 'COMICS', 'SUPERHERO', 'CARTOON', 'CARTOONS', 'ILLUSTRATION'],
  'DESIGNS': ['DESIGN', 'DESIGNS', 'GRAPHIC', 'ABSTRACT', 'ART', 'ARTISTIC', 'PATTERN ART', 'GEOMETRIC'],
  'DRAWINGS': ['DRAWING', 'DRAWINGS', 'SKETCH', 'SKETCHES', 'HAND DRAWN', 'PENCIL', 'INK'],
  'ENTERTAINMENT': ['ENTERTAINMENT', 'MOVIE', 'MOVIES', 'FILM', 'TV', 'CELEBRITY', 'CELEBRITIES', 'ACTOR', 'ACTRESS', 'SHOW'],
  'FUNNY': ['FUNNY', 'HUMOR', 'HUMOUR', 'MEME', 'MEMES', 'COMEDY', 'JOKE', 'JOKES', 'LOL'],
  'GAMES': ['GAME', 'GAMES', 'GAMING', 'VIDEO GAME', 'VIDEOGAME', 'ESPORTS', 'GAMER'],
  'HOLIDAYS': ['HOLIDAY', 'HOLIDAYS', 'CHRISTMAS', 'HALLOWEEN', 'EASTER', 'NEW YEAR', 'FESTIVAL', 'CELEBRATION'],
  'LOVE': ['LOVE', 'ROMANCE', 'ROMANTIC', 'HEART', 'HEARTS', 'VALENTINES', 'COUPLE', 'WEDDING'],
  'MUSIC': ['MUSIC', 'MUSICAL', 'SONG', 'SONGS', 'BAND', 'CONCERT', 'INSTRUMENT', 'DJ'],
  'NATURE': ['NATURE', 'NATURAL', 'LANDSCAPE', 'FOREST', 'MOUNTAIN', 'OCEAN', 'FLOWER', 'FLORAL', 'PLANT', 'TREE', 'BEACH', 'SUNSET', 'SKY', 'FOOD', 'TRAVEL', 'CITY', 'ARCHITECTURE', 'SPACE EARTH'],
  'PATTERNS': ['PATTERN', 'PATTERNS', 'TEXTURE', 'TEXTURES', 'MINIMALIST', 'MINIMAL', 'RETRO', 'VINTAGE'],
  'PEOPLE': ['PEOPLE', 'PERSON', 'PORTRAIT', 'FACE', 'HUMAN', 'MAN', 'WOMAN', 'GIRL', 'BOY'],
  'SAYINGS': ['SAYING', 'SAYINGS', 'QUOTE', 'QUOTES', 'MOTIVATIONAL', 'INSPIRATIONAL', 'TEXT', 'TYPOGRAPHY', 'WORDS'],
  'SPACE': ['SPACE', 'GALAXY', 'UNIVERSE', 'COSMOS', 'STAR', 'STARS', 'PLANET', 'NEBULA', 'ASTRONAUT', 'SCI FI', 'SCIFI', 'SCIENCE FICTION'],
  'SPIRITUAL': ['SPIRITUAL', 'RELIGION', 'RELIGIOUS', 'FAITH', 'GOD', 'MANDALA', 'MEDITATION', 'ZEN', 'BUDDHIST', 'ISLAMIC', 'CHRISTIAN'],
  'SPORTS': ['SPORT', 'SPORTS', 'FOOTBALL', 'BASKETBALL', 'SOCCER', 'TENNIS', 'BASEBALL', 'ATHLETICS', 'FITNESS', 'GYM'],
  'TECHNOLOGY': ['TECHNOLOGY', 'TECH', 'DIGITAL', 'CYBER', 'NEON', 'FUTURISTIC', 'COMPUTER', 'ROBOT', 'AI', 'CIRCUIT', 'DARK'],
};

/// UI instrument chips: label -> value sent to the prompt.
const Map<String, String> kInstrumentChips = {
  'Grand Piano': 'Grand Piano',
  'Kalimba': 'Kalimba',
  'Marimba': 'Marimba',
  'Vibraphone': 'Vibraphone',
  'Acoustic Guitar': 'Acoustic Guitar',
  'Nylon Guitar': 'Nylon Spanish Guitar',
  'Solo Violin': 'Solo Violin',
  'Warm Cello': 'Warm Cello',
  'Pizzicato Strings': 'Pizzicato Strings',
  'Concert Flute': 'Concert Flute',
  'Hang Drum': 'Hang Drum',
  'Japanese Koto': 'Japanese Koto',
  'Celtic Harp': 'Celtic Harp',
  'Music Box': 'Music Box',
  'Saxophone': 'Tenor Saxophone',
  'Muted Trumpet': 'Muted Trumpet',
  'Rhodes Piano': 'Rhodes Electric Piano',
  'Analog Pluck': 'Analog Pluck Synth',
  'Steel Pan': 'Steel Pan',
  'Djembe': 'Djembe Percussion',
  'Sitar & Tabla': 'Indian Sitar & Tabla',
  'Crystal Chimes': 'Crystal Glass Chimes',
};

/// UI genre options: label -> value ('Auto' = smart variety).
const Map<String, String> kGenreOptions = {
  'Auto (Smart Variety)': 'Auto',
  'Classical / Chamber': 'Classical / Chamber',
  'Cinematic Orchestral': 'Cinematic Orchestral',
  'Acoustic Folk': 'Acoustic Folk',
  'Smooth / Cool Jazz': 'Jazz',
  'Lofi Chill Groove': 'Lofi Hip-Hop',
  'World / Cultural Fusion': 'World Cultural',
  'Bossa Nova / Latin': 'Bossa Nova / Latin',
  'Ambient / Ethereal': 'Ambient Nature',
  'Neo Soul / R&B': 'Neo Soul / R&B',
  'Modern Synthwave': 'Synthwave',
  'Clean Minimalist': 'Minimalist',
  'Afrobeat Groove': 'Afrobeat',
};

const List<String> kMoodOptions = [
  'Auto', 'Peaceful & Serene', 'Upbeat & Joyful', 'Energetic & Punchy',
  'Mysterious & Intriguing', 'Warm & Nostalgic', 'Heroic & Epic',
  'Playful & Whimsical', 'Crisp & Futuristic', 'Romantic & Gentle',
];

/// Hook structures: label -> prompt phrase.
const Map<String, String> kStructureOptions = {
  'Auto Structure': 'Auto',
  '3-Note Motif': 'a catchy 3-note hook that repeats and resolves cleanly',
  'Seamless Loop': 'a seamless rhythmic loop with a memorable melodic phrase',
  'Rising Build': 'a rising harmonic build that peaks into a bright motif',
  'Call & Response': 'a playful call-and-response between lead and rhythm',
  'Plucked Arp': 'a crisp plucked arpeggio pattern with natural decay',
};

/// Production mixes: label -> prompt phrase.
const Map<String, String> kProductionOptions = {
  'Studio Mastered': 'crisp modern studio mastered production with clear mids',
  'Warm Analog': 'warm analog tape studio polish',
  'Close-Mic Organic': 'intimate close-mic organic acoustic recording',
  'Wide Stereo': 'lush wide stereo depth with natural room acoustics',
  'Minimalist Pure': 'airy minimalist pure tone with clean decay',
};

List<String> get kMusicalKeys => [
      'Auto',
      for (final r in ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']) '$r Minor',
      for (final r in ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B']) '$r Major',
    ];

/// Quick exclusion presets for the negative prompt.
const Map<String, String> kNegativePresets = {
  '+ Block Vocals/Speech': 'vocals, singing, speech, talking, human voice, choir, gibberish',
  '+ Block Noise/Hiss': 'white noise, static, vinyl crackle, tape hiss, hum, background noise',
  '+ Block Muddy/Distortion': 'muddy bass, sub-bass rumble, clipping, distortion, overdriven',
  '+ Block Off-Beat/Out-of-Tune': 'dissonant, out of tune, off-beat, chaotic, random notes, atonality',
  '+ Block Harsh Highs': 'harsh high frequencies, ear-piercing, shrill, metallic screech',
  '+ Block Stock Phone Tones': 'iPhone marimba, Apple reflection, Samsung Over the Horizon, Nokia tune',
};

const List<String> kSamplePromptsRingtone = [
  'Warm kalimba and Rhodes electric piano uplifting sunrise groove with subtle shaker',
  'Spanish nylon acoustic guitar flamenco rhythm with crisp hand percussion',
  'Cinematic pizzicato strings and solo cello playful detective motif',
  'Japanese koto and bamboo flute serene zen garden melody with gentle groove',
  'Upbeat jazz vibraphone and upright bass strutting mid-tempo swing melody',
];

const List<String> kSamplePromptsNotification = [
  'Crisp crystal kalimba and celesta 3-note notification chime with warm natural decay',
  'Gentle Japanese koto plucked harmonic alert motif in pentatonic scale',
  'Warm vibraphone and soft wooden xylophone double-tap message tone',
  'Bright acoustic harmonic guitar chime with airy stereo tail',
  'Subtle Tibetan singing bowl and soft harp harmonic ping',
];

// ─── Smart Variety pools (auto-discovery) ────────────────────────
const List<String> kPoolGenres = ['Classical', 'Jazz', 'Acoustic Folk', 'Heavy Metal', 'Country', 'Reggae', 'Blues', 'Latin', 'Bollywood', 'Cinematic Orchestral', 'World Music', 'Celtic Harp', 'Tribal Percussion', 'Soul', 'Funk', 'Opera', 'Bluegrass', 'Flamenco', 'Bossa Nova', 'Salsa', 'Griot', 'Ambient Nature', 'Medieval', 'Renaissance', 'Baroque', 'Gospel', 'R&B', 'Trap Soul', 'Neo Soul', 'Indie Folk', 'Post-Rock', 'Afrobeat', 'K-Pop Instrumental', 'Synthwave', 'Lofi Hip-Hop'];
const List<String> kPoolInstruments = ['Grand Piano', 'Violin', 'Trumpet', 'Saxophone', 'Cello', 'Acoustic Guitar', 'Sitar', 'Banjo', 'Ukulele', 'Accordion', 'Harmonica', 'Flute', 'Djembe Drums', 'Music Box', 'Vibraphone', 'Kalimba', 'Bagpipes', 'Steel Pan', 'Harp', 'Didgeridoo', 'Koto', 'Ocarina', 'Lute', 'Tambourine', 'Erhu', 'Duduk', 'Hurdy Gurdy', 'Hang Drum', 'Electric Sitar', 'Theremin', 'Rhodes Electric Piano'];
const List<String> kPoolMoods = ['Peaceful', 'Energetic', 'Mysterious', 'Joyful', 'Melancholic', 'Heroic', 'Whimsical', 'Dark', 'Bright', 'Epic', 'Spooky', 'Nostalgic', 'Rustic', 'Celestial', 'Primal', 'Graceful', 'Intense', 'Playful', 'Romantic', 'Triumphant', 'Haunting', 'Serene', 'Frantic', 'Dreamlike'];
const List<String> kPoolAnimals = ['Lion Roar', 'Elephant Trumpet', 'Wolf Howl', 'Whale Song', 'Tropical Birds', 'Eagle Cry', 'Owl Hoot', 'Cat Purr/Meow', 'Dog Barking', 'Horse Neigh', 'Dolphin Click', 'Frog Croak', 'Cricket Chirp', 'Cicada Buzz', 'Fox Scream', 'Bear Growl', 'Humpback Whale', 'Cheetah Chirp', 'Snow Leopard', 'Parrot Mimicry'];
const List<String> kPoolComedy = ['Slapstick Cartoon', 'Silly Laugh', 'Meme Sound', 'Clown Horn', 'Funny Sneeze', 'Ridiculous Voice', 'Boing Spring', 'Honk', 'Slide Whistle', 'Fail Horn', 'Trombone Wah-Wah', 'Cartoon Run', 'Squeaky Toy', 'Price Is Right Fail', 'Game Show Buzz'];
const List<String> kPoolNature = ['Thunderstorm', 'Ocean Waves', 'Heavy Rain', 'Wind Through Trees', 'Fire Crackling', 'Water Waterfall', 'Avalanche Rumble', 'Bamboo Forest', 'Northern Lights (Aurora Hum)', 'Cave Dripping', 'Earthquake Rumble', 'Tornado Warning', 'Spring Birds Dawn', 'Desert Wind'];
const List<String> kPoolSciFi = ['Laser Blast', 'Robot Voice', 'Spaceship Engine', 'Alien Transmission', 'Cybernetic Hum', 'Time Travel Portal', 'Digital Power Up', 'Warning Siren', 'Quantum Computer', 'Warp Drive', 'Hologram Flicker', 'AI Awakening', 'Plasma Shield', 'Nanobots Swarm'];
const List<String> kPoolSituations = ['Morning Wake-up Alarm', 'Subtle Office Notification', 'High-Energy Gaming Alert', 'Relaxing Spa Background', 'Urgent Siren Style', 'Magical Fantasy Pickup', 'Spooky Haunted House', 'Satisfying ASMR Click', 'Gym Workout Hype', 'Late Night Study', 'Road Trip Energy', 'Cooking Kitchen Ambience', 'Sports Victory Fanfare'];
const List<String> kPoolTopics = ['Cyberpunk City', 'Deep Space', 'Ancient Temple', 'Undersea Kingdom', 'Industrial Factory', 'Enchanted Forest', 'Virtual Reality', 'Desert Caravan', 'Steam Engine', 'Viking Voyage', 'Samurai Dojo', 'Aztec Pyramid', 'Arctic Expedition', 'Silk Road Journey', 'Pirate Ship'];
const List<String> kPoolActions = ['Whirring', 'Echoing', 'Resonating', 'Pulsing', 'Shimmering', 'Crashing', 'Whispering', 'Thumping', 'Gliding', 'Swirling', 'Exploding', 'Dissolving', 'Spiraling', 'Cascading', 'Vibrating'];
const List<String> kPoolAdjectives = ['Metallic', 'Ethereal', 'Rusty', 'Crystal', 'Shadowy', 'Luminous', 'Velvet', 'Frozen', 'Golden', 'Electric', 'Obsidian', 'Neon', 'Ancient', 'Celestial', 'Molten'];
const List<String> kPoolHorror = ['Creaking Door', 'Heartbeat Accelerating', 'Distant Screaming', 'Ghostly Whisper', 'Dripping Blood', 'Demon Growl', 'Haunted Music Box', 'Church Bell at Midnight', 'Eerie Silence Breaking', 'Zombie Horde'];
const List<String> kPoolSports = ['Stadium Crowd Roar', 'Starting Pistol', 'Basketball Swoosh', 'Soccer Goal Celebration', 'Boxing Bell', 'Race Car Engine', 'Skateboard Tricks', 'Weightlifting Grunt', 'Swimming Splash', 'Tennis Ace'];
const List<String> kPoolRomance = ['Soft Piano Serenade', 'Violin Love Theme', 'Heartbeat in Sync', 'Candlelight Jazz', 'Acoustic Love Song', 'Wedding Bells', 'Slow Dance Waltz', 'Sunset Guitar', 'Gentle Harp Melody', 'Whispering Lovers'];
const List<String> kPoolCultural = ['Indian Tabla Fusion', 'Japanese Shamisen', 'African Djembe Circle', 'Irish Jig', 'Arabic Oud Solo', 'Chinese Pipa Melody', 'Cuban Conga Rhythm', 'Andean Panpipe', 'Mongolian Throat Singing', 'Greek Bouzouki'];
const List<String> kPoolKids = ['Playful Xylophone', 'Cartoon Adventure', 'Lullaby Box', 'Silly Monster', 'Magic Toy Land', 'Bubble Pop Fun', 'Playground Melody', 'Rainbow Song', 'Counting Stars', 'Happy Elephant'];
const List<String> kPoolAsmr = ['Keyboard Typing', 'Paper Turning Pages', 'Rain on Window', 'Whispering Voice', 'Sand Pouring', 'Crunching Leaves', 'Hair Brushing', 'Soft Tapping', 'Coffee Brewing', 'Crackling Fireplace'];
const List<String> kPoolEpic = ['Orchestral Battle March', 'Choir of Warriors', 'Dragon Theme', 'Kingdom Rising', 'Final Boss Theme', 'Hero Transformation', 'Galaxy Explosion', 'Ancient Gods Awakening', 'Legendary Sword Unsheathing', 'Apocalypse Dawn'];
const List<String> kPoolUrban = ['City Traffic Jazz', 'Subway Beat', 'Hip-Hop Street', 'Breakbeat Alley', 'Night Club Bass', 'Graffiti Art Funk', 'Skyscraper Wind', 'Street Vendor Rhythm', 'Neon Market', 'Urban Jungle Groove'];
const List<String> kPoolStructures = ['a catchy 3-note hook that repeats continuously', 'a rising build that stays full and bright through the entire track', 'a lively call-and-response between two contrasting instruments', 'a tight seamless loop with a steady rhythmic groove from start to end', 'an immediate melodic intro that stays energetic all the way through', 'a punchy repeating motif with full sustained energy', 'a playful question-answer melody with continuous rhythm', 'a hypnotic repeating groove with crisp accents throughout'];
const List<String> kPoolProductions = ['warm analog studio polish', 'crisp modern cinematic production', 'intimate close-mic organic recording', 'lush layered stereo depth', 'punchy radio-ready mix', 'airy minimalist production with real room ambience'];
const List<String> kPoolTempos = ['90 BPM relaxed groove', '108 BPM mid-tempo groove', '120 BPM upbeat and bouncy', '128 BPM energetic pulse', '80 BPM slow and spacious'];

/// Rotating descriptor banks used to top up per-take tag lists.
const List<List<String>> kTagDescriptorBanks = [
  ['melodic', 'harmonic', 'crisp', 'bright', 'mellow', 'rhythmic', 'acoustic', 'lush', 'clean', 'vivid', 'smooth', 'uplifting'],
  ['groovy', 'warm', 'airy', 'punchy', 'sparkling', 'dreamy', 'organic', 'velvet', 'bouncy', 'gentle', 'golden', 'radiant'],
  ['cinematic', 'dramatic', 'deep', 'moody', 'mystic', 'shadowy', 'intense', 'bold', 'epic', 'resonant', 'dark', 'haunting'],
  ['playful', 'cheery', 'breezy', 'fresh', 'sunny', 'lively', 'quirky', 'sweet', 'snappy', 'light', 'joyful', 'zippy'],
];

const List<String> kFallbackTitleAdjectives = ['Velvet', 'Golden', 'Silver', 'Amber', 'Crimson', 'Cobalt', 'Misty', 'Solar', 'Lunar', 'Coral', 'Ivory', 'Emerald', 'Saffron', 'Indigo', 'Obsidian', 'Scarlet'];
const List<String> kFallbackTitleNouns = ['Horizon', 'Breeze', 'Cascade', 'Mirage', 'Meadow', 'Lantern', 'Ripple', 'Drift', 'Bloom', 'Spark', 'Cadence', 'Whisper', 'Glimmer', 'Chime', 'Prism', 'Ember'];
const List<String> kFallbackDescriptions = ['Warm melodic motif', 'Crisp rhythmic groove', 'Bright gentle chime', 'Soft mellow tune', 'Lively acoustic hook', 'Smooth dreamy melody', 'Fresh sunny motif', 'Deep calm resonance'];
