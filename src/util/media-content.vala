// Turning a message's content into something the bubble can draw. Kept apart
// from the text side of Content, which only ever produces strings.
namespace Telegrama.Content {

    // Empty when the sender wrote nothing: describe() would answer "Photo",
    // which is only useful where the picture itself cannot be drawn.
    public string caption_text (Json.Object content) {
        if (!content.has_member ("caption")) {
            return "";
        }

        return content.get_object_member ("caption").get_string_member ("text");
    }

    public Media? media_of (Json.Object content) {
        var kind = content.get_string_member ("@type");
        var spoiler = content.has_member ("has_spoiler")
            && content.get_boolean_member ("has_spoiler");

        switch (kind) {
            case "messagePhoto":
                return from_photo (content.get_object_member ("photo"), spoiler);
            case "messageVideo":
                return from_video (content.get_object_member ("video"), spoiler);
            case "messageAnimation":
                return from_animation (content.get_object_member ("animation"), spoiler);
            case "messageDocument":
                return from_document (content.get_object_member ("document"));
            case "messageAudio":
                return from_audio (content.get_object_member ("audio"));
            case "messageVoiceNote":
                return from_voice (content.get_object_member ("voice_note"));
            case "messageVideoNote":
                return from_video_note (content.get_object_member ("video_note"));
            case "messageSticker":
                return from_sticker (content.get_object_member ("sticker"));
            default:
                return null;
        }
    }

    // Only what Gdk.Texture can decode. A Lottie or webm thumbnail is a real
    // thumbnail, just not one we can turn into pixels.
    private bool drawable (Json.Object thumbnail) {
        switch (thumbnail.get_object_member ("format").get_string_member ("@type")) {
            case "thumbnailFormatJpeg":
            case "thumbnailFormatPng":
            case "thumbnailFormatWebp":
            case "thumbnailFormatGif":
                return true;
            default:
                return false;
        }
    }

    private Json.Object? thumb_file (Json.Object holder) {
        if (!holder.has_member ("thumbnail")) {
            return null;
        }

        var thumbnail = holder.get_object_member ("thumbnail");
        if (!drawable (thumbnail)) {
            return null;
        }

        return thumbnail.get_object_member ("file");
    }

    private int thumb_id (Json.Object holder) {
        var file = thumb_file (holder);
        return file == null ? 0 : FileStore.id_of (file);
    }

    // Anything already in TDLib's cache can be drawn without asking for it.
    private void seed_paths (Media media, Json.Object full, Json.Object? preview) {
        media.path = FileStore.local_path (full);
        if (preview != null) {
            media.preview_path = FileStore.local_path (preview);
        }
    }

    private int64 bytes_of (Json.Object file) {
        var size = file.get_int_member ("size");
        return size > 0 ? size : file.get_int_member ("expected_size");
    }

    // The base64 blur carried in the message itself. A few hundred bytes, so
    // decoding it on the spot beats any kind of deferral.
    public Gdk.Texture? blur_of (Json.Object holder) {
        if (!holder.has_member ("minithumbnail")) {
            return null;
        }

        var mini = holder.get_object_member ("minithumbnail");
        if (!mini.has_member ("data")) {
            return null;
        }

        try {
            var raw = Base64.decode (mini.get_string_member ("data"));
            return Gdk.Texture.from_bytes (new Bytes (raw));
        } catch (Error e) {
            return null;
        }
    }

    // Telegram sends a ladder of sizes. The largest is what opening it should
    // give; the bubble only ever needs something a few hundred pixels wide.
    private Media? from_photo (Json.Object photo, bool spoiler) {
        var sizes = photo.get_array_member ("sizes");
        if (sizes.get_length () == 0) {
            return null;
        }

        Json.Object? full = null;
        Json.Object? preview = null;

        for (var i = 0; i < sizes.get_length (); i++) {
            var size = sizes.get_object_element (i);
            var width = (int) size.get_int_member ("width");

            if (full == null || width > (int) full.get_int_member ("width")) {
                full = size;
            }

            if (width >= 320
                && (preview == null || width < (int) preview.get_int_member ("width"))) {
                preview = size;
            }
        }

        if (preview == null) {
            preview = full;
        }

        var media = new Media (
            MediaKind.PHOTO,
            FileStore.id_of (full.get_object_member ("photo")),
            FileStore.id_of (preview.get_object_member ("photo")),
            (int) full.get_int_member ("width"),
            (int) full.get_int_member ("height"),
            bytes_of (full.get_object_member ("photo")),
            0,
            "",
            spoiler
        );

        media.blur = blur_of (photo);
        seed_paths (media, full.get_object_member ("photo"), preview.get_object_member ("photo"));
        return media;
    }

    private Media? from_video (Json.Object video, bool spoiler) {
        var media = new Media (
            MediaKind.VIDEO,
            FileStore.id_of (video.get_object_member ("video")),
            thumb_id (video),
            (int) video.get_int_member ("width"),
            (int) video.get_int_member ("height"),
            bytes_of (video.get_object_member ("video")),
            (int) video.get_int_member ("duration"),
            video.get_string_member ("file_name"),
            spoiler
        );

        media.blur = blur_of (video);
        seed_paths (media, video.get_object_member ("video"), thumb_file (video));
        return media;
    }

    private Media? from_animation (Json.Object animation, bool spoiler) {
        var media = new Media (
            MediaKind.ANIMATION,
            FileStore.id_of (animation.get_object_member ("animation")),
            thumb_id (animation),
            (int) animation.get_int_member ("width"),
            (int) animation.get_int_member ("height"),
            bytes_of (animation.get_object_member ("animation")),
            (int) animation.get_int_member ("duration"),
            animation.get_string_member ("file_name"),
            spoiler
        );

        media.blur = blur_of (animation);
        seed_paths (media, animation.get_object_member ("animation"), thumb_file (animation));
        return media;
    }

    private Media? from_document (Json.Object document) {
        var media = new Media (
            MediaKind.DOCUMENT,
            FileStore.id_of (document.get_object_member ("document")),
            thumb_id (document),
            0,
            0,
            bytes_of (document.get_object_member ("document")),
            0,
            document.get_string_member ("file_name")
        );

        media.blur = blur_of (document);
        seed_paths (media, document.get_object_member ("document"), thumb_file (document));
        return media;
    }

    private Media? from_audio (Json.Object audio) {
        var title = audio.get_string_member ("title");
        var performer = audio.get_string_member ("performer");

        var name = title == ""
            ? audio.get_string_member ("file_name")
            : (performer == "" ? title : @"$performer - $title");

        var media = new Media (
            MediaKind.AUDIO,
            FileStore.id_of (audio.get_object_member ("audio")),
            0,
            0,
            0,
            bytes_of (audio.get_object_member ("audio")),
            (int) audio.get_int_member ("duration"),
            name
        );

        seed_paths (media, audio.get_object_member ("audio"), null);
        return media;
    }

    private Media? from_voice (Json.Object voice) {
        var media = new Media (
            MediaKind.VOICE,
            FileStore.id_of (voice.get_object_member ("voice")),
            0,
            0,
            0,
            bytes_of (voice.get_object_member ("voice")),
            (int) voice.get_int_member ("duration")
        );

        seed_paths (media, voice.get_object_member ("voice"), null);
        return media;
    }

    // Round, and always square: `length` is the side of the frame.
    private Media? from_video_note (Json.Object note) {
        var side = (int) note.get_int_member ("length");

        var media = new Media (
            MediaKind.VIDEO_NOTE,
            FileStore.id_of (note.get_object_member ("video")),
            thumb_id (note),
            side,
            side,
            bytes_of (note.get_object_member ("video")),
            (int) note.get_int_member ("duration")
        );

        media.blur = blur_of (note);
        seed_paths (media, note.get_object_member ("video"), thumb_file (note));
        return media;
    }

    // Animated stickers still have a still thumbnail, which is the whole of
    // what we can draw until there is an rlottie binding.
    private Media? from_sticker (Json.Object sticker) {
        var animated = sticker.get_object_member ("format")
            .get_string_member ("@type") != "stickerFormatWebp";

        var preview = thumb_id (sticker);
        if (animated && preview == 0) {
            return null;
        }

        var file = sticker.get_object_member ("sticker");

        var media = new Media (
            MediaKind.STICKER,
            animated ? preview : FileStore.id_of (file),
            preview,
            (int) sticker.get_int_member ("width"),
            (int) sticker.get_int_member ("height"),
            bytes_of (file)
        );

        seed_paths (media, animated ? thumb_file (sticker) : file, thumb_file (sticker));
        return media;
    }
}
