import Foundation

extension BlockCategory {
    /// Everything built in: the activity library, the Body postures, and retired activities old logs still use.
    public static let defaults: [BlockCategory] = activities + body + retired

    /// What can be logged, searched and starred: everything built in but the retired.
    public static let library: [BlockCategory] = activities + body

    /// No longer offered, but still known, so blocks logged with them keep their name and color.
    static let retired: [BlockCategory] = [
        BlockCategory(id: "meal", name: "Meal", group: .life, symbol: "fork.knife"),
        BlockCategory(id: "screen", name: "Screen time", group: .drift, symbol: "iphone.gen3"),
    ]

    /// Whether this is a retired built-in activity: it shows on old blocks but can't be logged again.
    public var isRetired: Bool {
        Self.retired.contains { $0.id == id }
    }

    /// Starred out of the box: what most days are made of. Everything else is a search away.
    public static let defaultFavorites: [String] = [
        "work", "meeting", "email", "study", "reading",
        "breakfast", "lunch", "dinner", "coffee", "cooking", "chores", "shower",
        "exercise", "walk", "outdoor",
        "social", "family", "commute",
        "rest", "nap", "shows", "hobby",
        "doomscroll",
    ] + body.map(\.id)

    /// Body runs from cool to warm: the more you move, the warmer the block.
    static let body: [BlockCategory] = [
        BlockCategory(id: "lying", name: "Lying", track: .body, color: RGB(hex: 0x5B4FC4), symbol: "bed.double.fill"),
        BlockCategory(id: "sitting", name: "Sitting", track: .body, color: RGB(hex: 0x5C86C9), symbol: "chair.fill"),
        BlockCategory(id: "standing", name: "Standing", track: .body, color: RGB(hex: 0x26B5A5), symbol: "figure.stand"),
        BlockCategory(id: "walking", name: "Walking", track: .body, color: RGB(hex: 0x3DCB5F), symbol: "figure.walk"),
        BlockCategory(id: "exercising", name: "Exercising", track: .body, color: RGB(hex: 0xFF9A1F), symbol: "figure.run"),
    ]

    /// Ids of the first categories (work, social, outdoor, …) are kept, so old logs still find them.
    static let activities: [BlockCategory] =
        group(.work, [
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
        ])
        + group(.learn, [
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
        ])
        + group(.health, [
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
        ])
        + group(.people, [
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
        ])
        + group(.life, [
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
        ])
        + group(.transit, [
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
        ])
        + group(.leisure, [
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
        ])
        + group(.drift, [
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
        ])

    private struct Preset {
        let id: String
        let name: String
        let symbol: String
        let keywords: String

        init(_ id: String, _ name: String, _ symbol: String, _ keywords: String = "") {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.keywords = keywords
        }
    }

    private static func group(_ group: CategoryGroup, _ presets: [Preset]) -> [BlockCategory] {
        presets.map {
            BlockCategory(
                id: $0.id, name: $0.name, group: group, symbol: $0.symbol,
                keywords: $0.keywords.split(separator: " ").map(String.init))
        }
    }
}

/// Finds activities by name, by the other words they go by ("meal" finds Lunch), or by group.
public enum ActivitySearch {
    /// Activities matching every word of `query`, best first: exact names, then names starting with it,
    /// then a word of the name, then other words, then the group. Ties keep library order.
    public static func results(for query: String, in categories: [BlockCategory]) -> [BlockCategory] {
        let query = fold(query).trimmingCharacters(in: .whitespaces)
        let tokens = query.split(separator: " ").map(String.init)
        guard let first = tokens.first else { return [] }
        let scored = categories.enumerated().compactMap { offset, category -> (score: Int, offset: Int, BlockCategory)? in
            let name = fold(category.name)
            let nameWords = words(name)
            let keywords = category.keywords.flatMap { words(fold($0)) }
            let group = category.group.map { fold($0.name) } ?? ""
            let all = nameWords + keywords + [group]
            guard tokens.allSatisfy({ token in all.contains { $0.hasPrefix(token) } }) || name.contains(query)
            else { return nil }
            let score =
                if name == query { 0 }
                else if name.hasPrefix(query) { 1 }
                else if nameWords.contains(where: { $0.hasPrefix(first) }) { 2 }
                else if keywords.contains(where: { $0.hasPrefix(first) }) { 3 }
                else if group.hasPrefix(first) { 4 }
                else { 5 }
            return (score, offset, category)
        }
        return scored.sorted { ($0.score, $0.offset) < ($1.score, $1.offset) }.map(\.2)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
