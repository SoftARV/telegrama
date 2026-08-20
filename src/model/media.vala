public enum Telegrama.MediaKind {
    PHOTO,
    VIDEO,
    ANIMATION,
    DOCUMENT,
    AUDIO,
    VOICE,
    VIDEO_NOTE,
    STICKER;

    public bool is_picture () {
        return this == PHOTO || this == VIDEO || this == ANIMATION
            || this == VIDEO_NOTE || this == STICKER;
    }

    public string label () {
        switch (this) {
            case PHOTO: return "Photo";
            case VIDEO: return "Video";
            case ANIMATION: return "GIF";
            case DOCUMENT: return "File";
            case AUDIO: return "Audio";
            case VOICE: return "Voice message";
            case VIDEO_NOTE: return "Video message";
            case STICKER: return "Sticker";
            default: return "File";
        }
    }

    public string icon () {
        switch (this) {
            case VIDEO:
            case VIDEO_NOTE:
            case ANIMATION: return "video-x-generic-symbolic";
            case AUDIO: return "audio-x-generic-symbolic";
            case VOICE: return "audio-input-microphone-symbolic";
            case PHOTO: return "image-x-generic-symbolic";
            default: return "text-x-generic-symbolic";
        }
    }
}

public class Telegrama.Media : Object {

    public MediaKind kind { get; construct; }

    // The file someone opening this would get. `preview_id` is the small one
    // worth fetching just to fill the bubble.
    public int file_id { get; construct; }
    public int preview_id { get; construct; default = 0; }

    public int width { get; construct; default = 0; }
    public int height { get; construct; default = 0; }
    public int64 size { get; construct; default = 0; }
    public int duration { get; construct; default = 0; }
    public string file_name { get; construct; default = ""; }

    // Sender marked it hidden-until-tapped.
    public bool spoiler { get; construct; default = false; }

    // Rides along in the message itself, so the bubble has something to show
    // before anything is asked of the network.
    public Gdk.Texture? blur { get; set; default = null; }

    public string path { get; set; default = ""; }
    public string preview_path { get; set; default = ""; }
    public bool opening { get; set; default = false; }
    public double progress { get; set; default = 0; }
    public bool revealed { get; set; default = false; }

    public Media (MediaKind kind, int file_id, int preview_id = 0,
                  int width = 0, int height = 0, int64 size = 0,
                  int duration = 0, string file_name = "", bool spoiler = false) {
        Object (kind: kind, file_id: file_id, preview_id: preview_id,
                width: width, height: height, size: size, duration: duration,
                file_name: file_name, spoiler: spoiler);
    }

    // Falls back to a squarish box: something has to be reserved before the
    // picture lands or every arrival would shove the history around.
    public int display_height (int for_width) {
        if (width <= 0 || height <= 0) {
            return for_width;
        }

        return (int) ((double) for_width * height / width);
    }

    public string duration_text () {
        return duration > 0 ? "%d:%02d".printf (duration / 60, duration % 60) : "";
    }

    public string detail () {
        var parts = new StringBuilder ();

        if (duration > 0) {
            parts.append (duration_text ());
        }

        if (size > 0) {
            if (parts.len > 0) {
                parts.append (" · ");
            }
            parts.append (format_size (size));
        }

        return parts.str;
    }
}
