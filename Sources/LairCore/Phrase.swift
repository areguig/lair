/// Every line Lair itself says in a call, or writes in its transcript beside what was said, in either language.
/// Each language has its own exhaustive switch, so a line missing in French can't compile.
public enum Phrase: Equatable, Sendable {
    case done(agent: String)
    case needsOKElsewhere(agent: String)
    case needsOK(agent: String, action: String, canAlwaysAllow: Bool)
    case sayYesOrNo(canAlwaysAllow: Bool)
    case approved(ApprovalDecision, action: String)
    case askingAgent(String)
    case passedOn(to: String)
    case busy(agent: String)
    case relayedFrom(agent: String, withAnswer: Bool)
    case backWithNews
    case youCutIn
    case didntAnswer(agent: String)
    case switchedModel(String)
    case thinkingNow(String)
    case thinkingNextCall(String)
    case answers(AgentConfig.Answers)
    case silentOn
    case speakingAgain
    case cantChangeDuringCall
    case choosesItself(agent: String)
    /// Before an agent from the terminal speaks, "omp says," once its name has been made sayable.
    case says(speaker: String)
    case asks(speaker: String)

    public func text(in language: Language) -> String {
        switch language {
        case .english: english
        case .french: french
        }
    }

    private var english: String {
        switch self {
        case .done(let agent): "\(agent) is done."
        case .needsOKElsewhere(let agent): "\(agent) needs your OK."
        case .needsOK(let agent, let action, let always):
            "\(agent) needs your OK to \(action). Allow it?" + (always ? " Say yes, always, or no." : " Say yes or no.")
        case .sayYesOrNo(let always): "Sorry, say" + (always ? " yes, always, or no." : " yes or no.")
        case .approved(let decision, let action):
            switch decision {
            case .allowOnce: "Allowed once: \(action)"
            case .allowAlways: "Always allowed: \(action)"
            case .deny: "Denied: \(action)"
            }
        case .askingAgent(let name): "Asking \(name)."
        case .passedOn(let name): "Passed on to \(name)."
        case .busy(let agent): "\(agent) is busy; say it again when it's done."
        case .relayedFrom(let agent, let withAnswer):
            withAnswer ? "From \(agent), with its last answer" : "From \(agent)"
        case .backWithNews: "Back with news"
        case .youCutIn: "You cut in."
        case .didntAnswer(let agent): "\(agent) didn't answer."
        case .switchedModel(let model): "Switched to \(model)."
        case .thinkingNow(let level): "Thinking \(level) now."
        case .thinkingNextCall(let level): "I'll think \(level) from the next call."
        case .answers(let level): "\(level.rawValue.capitalized) answers for this call."
        case .silentOn: "Silent mode: I'll write instead of speaking."
        case .speakingAgain: "Speaking again."
        case .cantChangeDuringCall: "That can't change during a call."
        case .choosesItself(let agent): "\(agent) chooses that itself."
        case .says(let speaker): "\(speaker) says,"
        case .asks(let speaker): "\(speaker) asks,"
        }
    }

    // The action of an approval is the agent's own English wording, which a French voice would mangle: it stays on screen.
    private var french: String {
        switch self {
        case .done(let agent): "\(agent) a fini."
        case .needsOKElsewhere(let agent): "\(agent) a besoin de ton accord."
        case .needsOK(let agent, _, let always):
            "\(agent) a besoin de ton accord, c'est à l'écran. Tu autorises ? "
                + (always ? "Dis oui, toujours ou non." : "Dis oui ou non.")
        case .sayYesOrNo(let always): "Pardon, " + (always ? "dis oui, toujours ou non." : "dis oui ou non.")
        case .approved(let decision, let action):
            switch decision {
            case .allowOnce: "Autorisé une fois : \(action)"
            case .allowAlways: "Toujours autorisé : \(action)"
            case .deny: "Refusé : \(action)"
            }
        case .askingAgent(let name): "Je demande à \(name)."
        case .passedOn(let name): "Transmis à \(name)."
        case .busy(let agent): "\(agent) travaille encore ; redis-le quand ce sera fini."
        case .relayedFrom(let agent, let withAnswer):
            withAnswer ? "De la part de \(agent), avec sa dernière réponse" : "De la part de \(agent)"
        case .backWithNews: "De retour avec des nouvelles"
        case .youCutIn: "Tu as coupé la parole."
        case .didntAnswer(let agent): "\(agent) n'a pas répondu."
        case .switchedModel(let model): "Je passe à \(model)."
        case .thinkingNow(let level): "Réflexion \(Self.frenchLevel(level)) maintenant."
        case .thinkingNextCall(let level): "Réflexion \(Self.frenchLevel(level)) à partir du prochain appel."
        case .answers(let level):
            switch level {
            case .brief: "Réponses brèves pour cet appel."
            case .normal: "Réponses normales pour cet appel."
            case .detailed: "Réponses détaillées pour cet appel."
            }
        case .silentOn: "Mode silencieux : j'écris au lieu de parler."
        case .speakingAgain: "Je reparle."
        case .cantChangeDuringCall: "Ça ne peut pas changer pendant un appel."
        case .choosesItself(let agent): "\(agent) choisit ça tout seul."
        case .says(let speaker): "\(speaker) dit,"
        case .asks(let speaker): "\(speaker) demande,"
        }
    }

    /// The agents name their thinking levels in English; a French voice would read "low" as French.
    private static func frenchLevel(_ level: String) -> String {
        let levels = ["off": "désactivée", "minimal": "minimale", "low": "faible", "medium": "moyenne",
                      "high": "élevée", "xhigh": "très élevée", "max": "maximale"]
        return levels[level] ?? level
    }
}
