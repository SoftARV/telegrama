public class Telegrama.Message : Object {

    public int64 id { get; construct; }
    public int64 sender_id { get; construct; }

    public bool is_outgoing { get; construct; }
    public int64 date { get; construct; }

    public string text { get; set; default = ""; }

    // Only groups name and picture their senders; in a private chat there is
    // only one other person and saying so every line is noise.
    public bool in_group { get; construct; }

    // Set for messages the sidebar would summarise rather than quote, so the
    // bubble can render "Photo" differently from something someone typed.
    public bool is_media { get; construct; }

    // A notice rather than something a person wrote, laid out centred with no
    // bubble.
    public bool is_service { get; construct; }

    // Kept whole so the row can re-render when a spoiler is revealed, rather
    // than baking markup at load time.
    public Json.Object? formatted { get; set; default = null; }

    // Same-chat replies arrive as a bare message id, so the quoted text is
    // resolved afterwards and filled in here.
    public int64 reply_to_id { get; set; default = 0; }
    public int64 reply_sender_id { get; set; default = 0; }
    public string reply_preview { get; set; default = ""; }
    public bool spoilers_revealed { get; set; default = false; }

    // Set briefly after being jumped to, so the eye can find it.
    public bool highlighted { get; set; default = false; }

    // Alternates per jump so the style actually changes and the animation
    // restarts rather than being ignored as already-applied.
    public bool flash_variant { get; set; default = false; }

    public Message (int64 id, int64 sender_id, bool is_outgoing, int64 date,
                    bool is_media, bool is_service, bool in_group) {
        Object (id: id, sender_id: sender_id, is_outgoing: is_outgoing, date: date,
                is_media: is_media, is_service: is_service, in_group: in_group);
    }
}
