public class Telegrama.Message : Object {

    public int64 id { get; construct; }
    public int64 sender_id { get; construct; }

    public bool is_outgoing { get; construct; }
    public int64 date { get; construct; }

    public string text { get; set; default = ""; }
    public string sender_name { get; set; default = ""; }

    // Set for messages the sidebar would summarise rather than quote, so the
    // bubble can render "Photo" differently from something someone typed.
    public bool is_media { get; construct; }

    // A notice rather than something a person wrote, laid out centred with no
    // bubble.
    public bool is_service { get; construct; }

    // Kept whole so the row can re-render when a spoiler is revealed, rather
    // than baking markup at load time.
    public Json.Object? formatted { get; set; default = null; }
    public bool spoilers_revealed { get; set; default = false; }

    public Message (int64 id, int64 sender_id, bool is_outgoing, int64 date,
                    bool is_media, bool is_service) {
        Object (id: id, sender_id: sender_id, is_outgoing: is_outgoing, date: date,
                is_media: is_media, is_service: is_service);
    }
}
