package dev.timeblock.core

import java.text.Normalizer

/** The built-in library. Made from TimeBlockKit's `Activities.swift`, so both apps offer the same activities. */
object BlockCategories {
    /** Everything built in: the activity library, the Body postures, and retired activities old logs still use. */
    val defaults: List<BlockCategory> by lazy { activities + body + retired }

    /** What can be logged, searched and starred: everything built in but the retired. */
    val library: List<BlockCategory> by lazy { activities + body }

    /** No longer offered, but still known, so blocks logged with them keep their name and color. */
    val retired: List<BlockCategory> = listOf(
        BlockCategory.activity("meal", "Meal", CategoryGroup.life, "fork.knife"),
        BlockCategory.activity("screen", "Screen time", CategoryGroup.drift, "iphone.gen3"),
    )

    /** Body runs from cool to warm: the more you move, the warmer the block. */
    val body: List<BlockCategory> = listOf(
        BlockCategory("lying", "Lying", Track.BODY, null, RGB.hex(0x5B4FC4), "bed.double.fill"),
        BlockCategory("sitting", "Sitting", Track.BODY, null, RGB.hex(0x5C86C9), "chair.fill"),
        BlockCategory("standing", "Standing", Track.BODY, null, RGB.hex(0x26B5A5), "figure.stand"),
        BlockCategory("walking", "Walking", Track.BODY, null, RGB.hex(0x3DCB5F), "figure.walk"),
        BlockCategory("exercising", "Exercising", Track.BODY, null, RGB.hex(0xFF9A1F), "figure.run"),
    )

    /** Starred out of the box: what most days are made of. Everything else is a search away. */
    val defaultFavorites: List<String> by lazy {
        listOf(
            "work",
            "meeting",
            "email",
            "study",
            "reading",
            "breakfast",
            "lunch",
            "dinner",
            "coffee",
            "cooking",
            "chores",
            "shower",
            "exercise",
            "walk",
            "outdoor",
            "social",
            "family",
            "commute",
            "rest",
            "nap",
            "shows",
            "hobby",
            "doomscroll",
        ) + body.map { it.id }
    }

    /** Ids of the first categories (work, social, outdoor, …) are kept, so old logs still find them. */
    val activities: List<BlockCategory> =
        group(
            CategoryGroup.work,
            Preset("work", "Work", "laptopcomputer", "job office"),
            Preset("deep-work", "Deep work", "brain.head.profile", "focus flow"),
            Preset("meeting", "Meeting", "person.2.fill", "sync standup"),
            Preset("one-on-one", "1:1", "person.2.circle.fill", "one on one manager"),
            Preset("email", "Email", "envelope.fill", "inbox mail"),
            Preset("work-chat", "Work chat", "message.fill", "slack teams messages"),
            Preset("planning", "Work planning", "checklist", "todo tasks roadmap"),
            Preset("coding", "Coding", "chevron.left.forwardslash.chevron.right", "programming development"),
            Preset("code-review", "Code review", "eye.fill", "pull request pr"),
            Preset("writing", "Writing", "pencil", "docs document"),
            Preset("design", "Design", "paintpalette.fill", "figma mockup"),
            Preset("research", "Research", "magnifyingglass", "investigate"),
            Preset("presenting", "Presenting", "person.wave.2.fill", "talk demo slides"),
            Preset("work-call", "Work call", "phone.fill", "client customer"),
            Preset("interview", "Interview", "person.text.rectangle.fill", "hiring candidate"),
            Preset("paperwork", "Paperwork", "doc.text.fill", "admin forms expenses"),
            Preset("side-project", "Side project", "hammer.fill", "build"),
            Preset("job-search", "Job search", "briefcase.fill", "applications resume cv"),
            Preset("teaching", "Teaching", "person.3.fill", "mentoring tutoring"),
        ) +
        group(
            CategoryGroup.learn,
            Preset("study", "Study", "book.fill", "learn"),
            Preset("reading", "Reading", "book.closed.fill", "book"),
            Preset("class", "Class", "graduationcap.fill", "lecture course school university"),
            Preset("homework", "Homework", "pencil.line", "assignment exercises"),
            Preset("online-course", "Online course", "play.rectangle.on.rectangle.fill", "tutorial video"),
            Preset("language", "Language", "character.bubble.fill", "duolingo vocabulary"),
            Preset("instrument", "Instrument practice", "pianokeys", "piano guitar music"),
            Preset("articles", "Articles", "doc.richtext.fill", "blog papers"),
            Preset("documentation", "Documentation", "text.book.closed.fill", "manual docs"),
            Preset("exam", "Exam", "checkmark.seal.fill", "test quiz"),
            Preset("revision", "Revision", "arrow.triangle.2.circlepath", "review flashcards"),
            Preset("journaling", "Journaling", "square.and.pencil", "diary reflect"),
        ) +
        group(
            CategoryGroup.health,
            Preset("exercise", "Exercise", "figure.run", "workout sport fitness"),
            Preset("gym", "Gym", "dumbbell.fill", "weights lifting strength"),
            Preset("running", "Running", "figure.run", "jog"),
            Preset("walk", "Walk", "figure.walk", "stroll"),
            Preset("outdoor", "Outdoors", "tree.fill", "nature park fresh air"),
            Preset("hiking", "Hiking", "figure.hiking", "trail mountain"),
            Preset("cycling", "Cycling", "figure.outdoor.cycle", "bike ride"),
            Preset("swimming", "Swimming", "figure.pool.swim", "pool"),
            Preset("yoga", "Yoga", "figure.yoga", "stretch"),
            Preset("pilates", "Pilates", "figure.pilates", "core"),
            Preset("stretching", "Stretching", "figure.flexibility", "mobility"),
            Preset("hiit", "HIIT", "figure.highintensity.intervaltraining", "intervals cardio"),
            Preset("climbing", "Climbing", "figure.climbing", "bouldering"),
            Preset("dance", "Dance", "figure.dance", "dancing"),
            Preset("martial-arts", "Martial arts", "figure.martial.arts", "boxing karate judo"),
            Preset("team-sport", "Team sport", "sportscourt.fill", "game match"),
            Preset("basketball", "Basketball", "figure.basketball", "sport"),
            Preset("soccer", "Football", "figure.soccer", "soccer sport"),
            Preset("tennis", "Tennis", "figure.tennis", "racket sport"),
            Preset("badminton", "Badminton", "figure.badminton", "racket sport"),
            Preset("table-tennis", "Table tennis", "figure.table.tennis", "ping pong"),
            Preset("golf", "Golf", "figure.golf", "sport"),
            Preset("skiing", "Skiing", "figure.skiing.downhill", "snow snowboard"),
            Preset("rowing", "Rowing", "figure.rower", "erg"),
            Preset("meditation", "Meditation", "figure.mind.and.body", "mindfulness breathing calm"),
            Preset("sunlight", "Sunlight", "sun.max.fill", "sun morning light"),
            Preset("doctor", "Doctor", "stethoscope", "appointment checkup clinic"),
            Preset("dentist", "Dentist", "mouth.fill", "teeth"),
            Preset("therapy", "Therapy", "heart.text.square.fill", "counseling mental health"),
            Preset("physio", "Physio", "cross.case.fill", "rehab physiotherapy"),
        ) +
        group(
            CategoryGroup.people,
            Preset("social", "Friends", "person.3.fill", "social hangout"),
            Preset("family", "Family", "house.fill", "home relatives"),
            Preset("partner", "Partner", "heart.fill", "spouse girlfriend boyfriend wife husband"),
            Preset("date", "Date", "wineglass.fill", "romance dating"),
            Preset("kids", "Kids", "figure.2.and.child.holdinghands", "children play parenting"),
            Preset("parents", "Parents", "figure.2", "mom dad"),
            Preset("call", "Call", "phone.fill", "phone catch up"),
            Preset("video-call", "Video call", "video.fill", "facetime zoom"),
            Preset("texting", "Texting", "message.fill", "chat messages"),
            Preset("party", "Party", "party.popper.fill", "birthday celebration"),
            Preset("meal-together", "Meal together", "fork.knife", "dinner lunch eat out restaurant"),
            Preset("chatting", "Chatting", "bubble.left.and.bubble.right.fill", "talk conversation"),
            Preset("networking", "Networking", "person.crop.circle.badge.plus", "meetup event"),
            Preset("volunteering", "Volunteering", "hands.sparkles.fill", "charity help"),
            Preset("helping", "Helping someone", "hand.raised.fill", "favor support"),
            Preset("caregiving", "Caregiving", "heart.circle.fill", "care elderly"),
            Preset("worship", "Worship", "building.columns.fill", "church temple religion prayer"),
            Preset("community", "Community", "person.3.sequence.fill", "club group"),
        ) +
        group(
            CategoryGroup.life,
            Preset("breakfast", "Breakfast", "sunrise.fill", "meal eat food morning"),
            Preset("lunch", "Lunch", "fork.knife", "meal eat food noon"),
            Preset("dinner", "Dinner", "fork.knife.circle.fill", "meal eat food supper evening"),
            Preset("snack", "Snack", "carrot.fill", "eat food"),
            Preset("coffee", "Coffee", "cup.and.saucer.fill", "drink cafe break"),
            Preset("tea", "Tea", "mug.fill", "drink break"),
            Preset("cooking", "Cooking", "frying.pan.fill", "meal prep kitchen"),
            Preset("groceries", "Groceries", "cart.fill", "supermarket food shopping"),
            Preset("shopping", "Shopping", "bag.fill", "store buy"),
            Preset("errands", "Errands", "checklist", "post office pickup"),
            Preset("chores", "Chores", "house.fill", "housework"),
            Preset("cleaning", "Cleaning", "bubbles.and.sparkles.fill", "tidy vacuum chores"),
            Preset("laundry", "Laundry", "washer.fill", "washing clothes chores"),
            Preset("dishes", "Dishes", "sink.fill", "washing up chores kitchen"),
            Preset("tidying", "Tidying", "archivebox.fill", "organize declutter chores"),
            Preset("repairs", "Repairs", "wrench.and.screwdriver.fill", "fix diy maintenance"),
            Preset("gardening", "Gardening", "leaf.fill", "plants garden"),
            Preset("shower", "Shower", "shower.fill", "wash bathe getting ready"),
            Preset("getting-ready", "Getting ready", "tshirt.fill", "dress grooming morning routine"),
            Preset("skincare", "Skincare", "drop.fill", "grooming"),
            Preset("haircut", "Haircut", "scissors", "barber salon hair"),
            Preset("bathroom", "Bathroom", "toilet.fill", "toilet"),
            Preset("bedtime-routine", "Bedtime routine", "moon.fill", "wind down evening"),
            Preset("medication", "Medication", "pills.fill", "medicine pills"),
            Preset("finances", "Finances", "creditcard.fill", "money budget bills bank taxes"),
            Preset("appointments", "Appointment", "calendar", "booking"),
            Preset("day-planning", "Planning the day", "calendar.day.timeline.left", "schedule organize"),
            Preset("packing", "Packing", "suitcase.fill", "luggage trip"),
            Preset("pet-care", "Pet care", "pawprint.fill", "dog cat feed"),
            Preset("dog-walk", "Dog walk", "dog.fill", "pet walk"),
            Preset("childcare", "Childcare", "stroller.fill", "baby kids"),
            Preset("car-care", "Car care", "car.fill", "fuel gas wash service"),
            Preset("waiting", "Waiting", "hourglass", "queue line"),
        ) +
        group(
            CategoryGroup.transit,
            Preset("commute", "Commute", "tram.fill", "travel to work"),
            Preset("driving", "Driving", "car.fill", "car drive"),
            Preset("bus", "Bus", "bus.fill", "transit"),
            Preset("train", "Train", "train.side.front.car", "rail transit"),
            Preset("metro", "Metro", "tram.circle.fill", "subway underground mrt transit"),
            Preset("walking-somewhere", "Walking somewhere", "figure.walk.motion", "on foot"),
            Preset("biking-somewhere", "Biking somewhere", "bicycle", "bike"),
            Preset("scooter", "Scooter", "scooter", "motorbike"),
            Preset("taxi", "Taxi", "car.side.fill", "uber ride"),
            Preset("flight", "Flight", "airplane", "plane fly"),
            Preset("airport", "Airport", "airplane.departure", "check in security"),
            Preset("ferry", "Ferry", "ferry.fill", "boat"),
            Preset("travel", "Travel", "suitcase.rolling.fill", "trip journey"),
            Preset("school-run", "School run", "figure.and.child.holdinghands", "drop off pick up kids"),
        ) +
        group(
            CategoryGroup.leisure,
            Preset("rest", "Rest", "sofa.fill", "relax break"),
            Preset("nap", "Nap", "powersleep", "sleep"),
            Preset("hobby", "Hobby", "paintbrush.fill", "craft"),
            Preset("shows", "TV and shows", "tv.fill", "series netflix watch"),
            Preset("movie", "Movie", "film.fill", "cinema film watch"),
            Preset("gaming", "Gaming", "gamecontroller.fill", "video games play"),
            Preset("music", "Music", "music.note", "listen"),
            Preset("playing-music", "Playing music", "guitars.fill", "instrument band jam"),
            Preset("reading-for-fun", "Reading for fun", "books.vertical.fill", "novel book"),
            Preset("podcast", "Podcast", "antenna.radiowaves.left.and.right", "listen audio"),
            Preset("drawing", "Drawing", "pencil.and.scribble", "art sketch paint"),
            Preset("photography", "Photography", "camera.fill", "photos"),
            Preset("crafts", "Crafts", "scissors", "knitting sewing diy"),
            Preset("board-games", "Board games", "dice.fill", "cards"),
            Preset("puzzles", "Puzzles", "puzzlepiece.fill", "crossword sudoku"),
            Preset("cafe", "Café", "cup.and.saucer.fill", "cafe coffee shop"),
            Preset("drinks", "Drinks", "wineglass.fill", "bar pub beer wine"),
            Preset("concert", "Concert", "music.mic", "gig live show"),
            Preset("theatre", "Theatre", "theatermasks.fill", "theater play show"),
            Preset("museum", "Museum", "photo.artframe", "gallery exhibition"),
            Preset("sightseeing", "Sightseeing", "binoculars.fill", "tourist explore"),
            Preset("bath", "Bath", "bathtub.fill", "relax soak"),
            Preset("massage", "Massage", "hand.raised.fingers.spread.fill", "spa"),
            Preset("vacation", "Vacation", "beach.umbrella.fill", "holiday"),
            Preset("creative-writing", "Creative writing", "text.quote", "story poetry"),
            Preset("baking", "Baking", "birthday.cake.fill", "cake bread"),
        ) +
        group(
            CategoryGroup.drift,
            Preset("doomscroll", "Doomscroll", "iphone", "scrolling feed"),
            Preset("social-media", "Social media", "at", "instagram tiktok twitter x facebook"),
            Preset("videos", "Videos", "play.rectangle.fill", "youtube shorts reels"),
            Preset("browsing", "Browsing", "safari.fill", "web internet surfing"),
            Preset("news", "News", "newspaper.fill", "headlines"),
            Preset("binge-watching", "Binge-watching", "play.tv.fill", "series episodes"),
            Preset("online-shopping", "Online shopping", "cart.badge.plus", "amazon browsing"),
            Preset("procrastinating", "Procrastinating", "clock.arrow.circlepath", "avoiding putting off"),
            Preset("zoning-out", "Zoning out", "cloud.fill", "idle daydream"),
            Preset("lying-in-bed", "Lying in bed", "bed.double.fill", "awake lazy"),
            Preset("snoozing", "Snoozing", "alarm.fill", "alarm oversleep"),
            Preset("overthinking", "Overthinking", "tornado", "worry rumination"),
        )

    private class Preset(val id: String, val name: String, val symbol: String, val keywords: String = "")

    private fun group(group: CategoryGroup, vararg presets: Preset): List<BlockCategory> = presets.map {
        BlockCategory.activity(it.id, it.name, group, it.symbol, it.keywords.split(" ").filter(String::isNotEmpty))
    }
}

/** Finds activities by name, by the other words they go by ("meal" finds Lunch), or by group. */
object ActivitySearch {
    /**
     * Activities matching every word of [query], best first: exact names, then names starting with it, then a word of
     * the name, then other words, then the group. Ties keep library order.
     */
    fun results(query: String, categories: List<BlockCategory>): List<BlockCategory> {
        val folded = fold(query).trim()
        val tokens = folded.split(" ").filter(String::isNotEmpty)
        val first = tokens.firstOrNull() ?: return emptyList()
        return categories.mapIndexedNotNull { offset, category ->
            val name = fold(category.name)
            val nameWords = words(name)
            val keywords = category.keywords.flatMap { words(fold(it)) }
            val group = category.group?.let { fold(it.name) } ?: ""
            val all = nameWords + keywords + group
            if (!tokens.all { token -> all.any { it.startsWith(token) } } && !name.contains(folded)) {
                return@mapIndexedNotNull null
            }
            val score = when {
                name == folded -> 0
                name.startsWith(folded) -> 1
                nameWords.any { it.startsWith(first) } -> 2
                keywords.any { it.startsWith(first) } -> 3
                group.startsWith(first) -> 4
                else -> 5
            }
            Triple(score, offset, category)
        }.sortedWith(compareBy({ it.first }, { it.second })).map { it.third }
    }

    private fun fold(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase()

    private fun words(text: String): List<String> = text.split(Regex("[^\\p{L}\\p{N}]+")).filter(String::isNotEmpty)
}
