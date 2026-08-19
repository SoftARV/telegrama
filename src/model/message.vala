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

    public Message (int64 id, int64 sender_id, bool is_outgoing, int64 date, bool is_media) {
        Object (id: id, sender_id: sender_id, is_outgoing: is_outgoing, date: date, is_media: is_media);
    }
}
