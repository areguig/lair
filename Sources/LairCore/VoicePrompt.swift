/// Sent with every call so agents know they are heard, not read.
public enum VoicePrompt {
    /// The voice rules, plus who the agent is on this call: the name the user calls it, the other agents the user
    /// can reach through Lair and, when it has one, its soul. In French the whole text is French, not translated word
    /// for word, and it tells the agent to answer in French.
    public static func forCall(name: String?, soul: String?, others: [String] = [],
                               answers: AgentConfig.Answers = .normal, language: Language = .english) -> String {
        var prompt = rules(answers, language)
        switch language {
        case .english:
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
        case .french:
            if let name, !name.isEmpty { prompt += "\n\nPendant cet appel, l'utilisateur t'appelle \(name)." }
            if !others.isEmpty {
                prompt += """
                    \n\nL'utilisateur peut aussi parler à ces agents via Lair : \(others.joined(separator: ", ")). \
                    Tu ne peux pas les joindre toi-même. Quand l'utilisateur dit « demande à <nom> … », Lair transmet \
                    sa demande avec ta dernière réponse, et tu entends la réponse à ton prochain tour. S'il veut l'un \
                    d'eux, dis-lui de le demander.
                    """
            }
            if let soul { prompt += "\n\nTa personnalité, écrite par l'utilisateur :\n\(soul)" }
        }
        return prompt
    }

    /// How long to answer, as the one rule in the voice rules.
    static func rule(_ answers: AgentConfig.Answers, _ language: Language = .english) -> String {
        switch (language, answers) {
        case (.english, .brief): "Be very brief: one short sentence with the result. Give details only when the user asks."
        case (.english, .normal): "Be concise: one to three short sentences, unless the user asks for more. Lead with the answer."
        case (.english, .detailed): """
            Explain fully when it helps: a few sentences on what you did and why, still as spoken prose, never lists. \
            Lead with the answer.
            """
        case (.french, .brief): "Sois très bref : une seule phrase courte avec le résultat. Ne donne des détails que si l'utilisateur le demande."
        case (.french, .normal): "Sois concis : une à trois phrases courtes, sauf si l'utilisateur en demande plus. Commence par la réponse."
        case (.french, .detailed): """
            Explique en détail quand c'est utile : quelques phrases sur ce que tu as fait et pourquoi, toujours à l'oral, \
            jamais sous forme de liste. Commence par la réponse.
            """
        }
    }

    /// Put before the next turn when the user changes the answer length during a call.
    public static func answers(_ answers: AgentConfig.Answers, language: Language = .english) -> String {
        switch language {
        case .english: "From now on in this call: \(rule(answers))"
        case .french: "À partir de maintenant dans cet appel : \(rule(answers, .french))"
        }
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
    public static let text = rules(.normal, .english)

    private static func rules(_ answers: AgentConfig.Answers, _ language: Language) -> String {
        switch language {
        case .english: englishRules(answers)
        case .french: frenchRules(answers)
        }
    }

    private static func englishRules(_ answers: AgentConfig.Answers) -> String {
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

    private static func frenchRules(_ answers: AgentConfig.Answers) -> String {
        """
        Cette conversation est un appel vocal en direct via Lair : l'utilisateur parle, un modèle de reconnaissance \
        vocale écrit ses mots, et tout ce que tu écris est lu à voix haute par une voix de synthèse. Parle comme une \
        personne au téléphone, et tutoie l'utilisateur.
        - \(rule(answers, .french))
        - Pas de markdown, de listes, de tableaux, de titres, d'emoji ni de blocs de code : on ne peut pas les entendre.
        - Ne lis jamais à voix haute d'URL, de chemin de fichier, de commande, de code, de hash, d'identifiant ni de \
        long nombre. Dis plutôt ce que c'est, par exemple « le fichier de configuration dans ton dossier personnel » \
        ou « le lien que j'ai trouvé dans la doc d'Apple ».
        - Quand l'utilisateur a besoin de voir l'un d'eux, entoure-le de <show>…</show> : il s'affiche à l'écran et \
        n'est jamais lu. Exemple : « J'ai modifié la config <show>~/.config/app/config.json</show> et je l'ai relancée. »
        - Arrondis les nombres et dis les unités en toutes lettres. N'épelle que ce que l'utilisateur doit taper.
        - Quand tu utilises des outils, ne commente pas chaque étape ; dis brièvement ce que tu fais si cela prend \
        du temps, puis donne le résultat.
        - Si la demande a probablement été mal comprise, pose une courte question plutôt que de deviner.
        - Réponds toujours en français, quelle que soit la langue de l'utilisateur. Garde les termes techniques comme \
        les développeurs français les disent (build, commit, pull request…).
        """
    }
}
