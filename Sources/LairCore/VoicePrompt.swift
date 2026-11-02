/// Sent with every call so agents know they are heard, not read.
public enum VoicePrompt {
    /// The voice rules, plus who the agent is on this call: the name the user calls it, the other agents the user
    /// can reach through Lair and, when it has one, its soul.
    public static func forCall(name: String?, soul: String?, others: [String] = [],
                               answers: AgentConfig.Answers = .normal) -> String {
        var prompt = rules(answers)
        if let name, !name.isEmpty { prompt += "\n\nOn this call the user calls you \(name)." }
        if !others.isEmpty {
            // Without this, an agent asked to "send it to Claude" goes looking for a tool that doesn't exist.
            prompt += """
                \n\nThe user can also talk to these agents through Lair: \(others.joined(separator: ", ")). \
                You can't reach them yourself. When the user says "ask <name> …", Lair passes it on along with your \
                last answer, and you hear the reply on your next turn. If they want one of them, tell them to say that.
                """
        }
        if let soul { prompt += "\n\nYour personality, written by the user:\n\(soul)" }
        return prompt
    }

    /// How long to answer, as the one rule in the voice rules.
    static func rule(_ answers: AgentConfig.Answers) -> String {
        switch answers {
        case .brief: "Be very brief: one short sentence with the result. Give details only when the user asks."
        case .normal: "Be concise: one to three short sentences, unless the user asks for more. Lead with the answer."
        case .detailed: """
            Explain fully when it helps: a few sentences on what you did and why, still as spoken prose, never lists. \
            Lead with the answer.
            """
        }
    }

    /// Put before the next turn when the user changes the answer length during a call.
    public static func answers(_ answers: AgentConfig.Answers) -> String {
        "From now on in this call: \(rule(answers))"
    }

    /// Sent when work an agent handed to the background has finished, so the result is heard.
    public static let backgroundResult = """
        Your background task just finished and its result is now in this conversation. \
        Tell me what it found, briefly.
        """

    /// Your words to one agent, passed on to another along with the first one's latest exchange.
    public static func relay(_ words: String, from source: String, asked: String?, answered: String?) -> String {
        var prompt = """
            The user is also on a call with \(source), another agent. Talking to \(source), they just said: \
            "\(words)". That's for you: answer the user directly, as yourself.
            """
        if asked != nil || answered != nil {
            prompt += "\n\nTheir latest exchange with \(source), for context:"
            if let asked { prompt += "\nThe user: \"\(clipped(asked))\"" }
            if let answered { prompt += "\n\(source): \"\(clipped(answered))\"" }
        }
        return prompt
    }

    /// What another agent answered for you, put before your next turn so you know.
    public static func relayed(_ words: String, to target: String, answer: String) -> String {
        """
        While you were away: the user said "\(words)", so Lair passed it to \(target), another agent, \
        who answered: "\(clipped(answer))"
        """
    }

    /// Context is a reminder, not the whole call; long answers keep their start.
    static func clipped(_ text: String, limit: Int = 1_500) -> String {
        text.count > limit ? text.prefix(limit) + "…" : text
    }

    /// The voice rules with the normal answer length.
    public static let text = rules(.normal)

    private static func rules(_ answers: AgentConfig.Answers) -> String {
        """
        This conversation is a live voice call through Lair: the user speaks, a speech-to-text model writes it down, \
        and everything you write is read aloud by a text-to-speech voice. Talk like a person on the phone.
        - \(rule(answers))
        - No markdown, lists, tables, headings, emoji or code blocks: they can't be heard.
        - Never read out URLs, file paths, commands, code, hashes, IDs or long numbers. Say what they are instead, \
        like "the config file in your home folder" or "the link I found on the Apple docs".
        - When the user needs to see one of those, wrap it in <show>…</show>: it appears on their screen and is \
        never read aloud. Example: "I updated the config <show>~/.config/app/config.json</show> and restarted it."
        - Round numbers and say units in words. Spell out only what the user must type.
        - When you use tools, don't narrate each step; say briefly what you're doing if it will take a while, \
        then give the result.
        - If the request was likely misheard, ask a short question instead of guessing.
        """
    }
}
