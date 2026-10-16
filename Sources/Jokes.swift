import Foundation

/// Fetches a random dad joke from icanhazdadjoke.com, falling back to a built-in bank when offline.
enum Jokes {
    static let bank = [
        "Why did the cookie go to the doctor? Because it felt crummy.",
        "What do you call a sleeping dinosaur? A dino-snore.",
        "Why can't a bicycle stand up by itself? Because it's two tired.",
        "What do you call a fish with no eyes? A fsh.",
        "Why did the scarecrow win an award? Because he was outstanding in his field.",
        "What do you call cheese that isn't yours? Nacho cheese.",
        "Why don't eggs tell jokes? They'd crack each other up.",
        "What has four wheels and flies? A rubbish truck.",
        "Why did the computer go to the doctor? It had a virus.",
        "What do you call a bear with no teeth? A gummy bear.",
        "Why did the banana go to the doctor? Because it wasn't peeling well.",
        "What's a microphone's favourite type of music? Heavy metal. Because I'm made of it.",
    ]

    static func random() async -> String {
        var request = URLRequest(url: URL(string: "https://icanhazdadjoke.com/")!, timeoutInterval: 4)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mike the Mic (https://github.com/Ellf/mike-the-mic)", forHTTPHeaderField: "User-Agent")
        struct Reply: Decodable { let joke: String }
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let reply = try? JSONDecoder().decode(Reply.self, from: data),
           !reply.joke.isEmpty {
            return reply.joke
        }
        return bank.randomElement()!
    }
}
