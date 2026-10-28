/// Appended to an agent's system prompt so its answers are worth hearing.
public enum VoicePrompt {
    public static let text = """
        You are talking with the user by voice: your reply is read aloud. \
        Answer in plain spoken English, one to three short sentences unless asked for more. \
        No markdown, lists, code blocks, file paths or URLs; describe them in words instead.
        """
}
