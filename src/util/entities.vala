// formattedText is a plain string plus a flat list of ranges. Turning that into
// Pango markup is mostly bookkeeping, with one trap: Telegram counts in UTF-16.
namespace Telegrama.Entities {

    private class Span {
        public int start;
        public int end;
        public string kind;
        public string url;
    }

    public string markup (Json.Object formatted, bool reveal_spoilers, string spoiler_colour) {
        var text = formatted.get_string_member ("text");

        if (!formatted.has_member ("entities")) {
            return Markup.escape_text (text);
        }

        var entities = formatted.get_array_member ("entities");
        if (entities.get_length () == 0) {
            return Markup.escape_text (text);
        }

        var offsets = byte_offsets (text);
        var units = offsets.length - 1;
        var spans = new GenericArray<Span> ();

        for (var i = 0; i < entities.get_length (); i++) {
            var entity = entities.get_object_element (i);
            var offset = (int) entity.get_int_member ("offset");
            var length = (int) entity.get_int_member ("length");

            // A range that does not fit the text is not worth guessing about.
            if (offset < 0 || length <= 0 || offset + length > units) {
                continue;
            }

            var type = entity.get_object_member ("type");
            var span = new Span ();
            span.start = offsets[offset];
            span.end = offsets[offset + length];
            span.kind = type.get_string_member ("@type");
            span.url = url_of (type, text.slice (span.start, span.end));

            spans.add (span);
        }

        if (spans.length == 0) {
            return Markup.escape_text (text);
        }

        var result = new StringBuilder ();
        var cuts = boundaries (spans, text.length);

        for (var i = 0; i + 1 < cuts.length; i++) {
            var from = cuts[i];
            var to = cuts[i + 1];
            if (to <= from) {
                continue;
            }

            var open = new StringBuilder ();
            var close = new StringBuilder ();

            for (var s = 0; s < spans.length; s++) {
                var span = spans[s];
                if (span.start > from || span.end < to) {
                    continue;
                }

                var tags = tags_for (span, reveal_spoilers, spoiler_colour);
                open.append (tags[0]);
                // Closing tags unwind in the order they were opened.
                close.prepend (tags[1]);
            }

            result.append (open.str);
            result.append (Markup.escape_text (text.slice (from, to)));
            result.append (close.str);
        }

        return result.str;
    }

    // Telegram counts entity offsets in UTF-16 code units while Vala strings are
    // UTF-8 bytes, and the two disagree the moment a message contains an emoji:
    // in "hi 👋 bold" the word starts at 6 in UTF-16, 5 in codepoints and 8 in
    // bytes. This maps one to the other once, so nothing downstream has to care.
    private int[] byte_offsets (string text) {
        int[] map = {};
        var index = 0;
        unichar c;

        while (true) {
            var start = index;
            if (!text.get_next_char (ref index, out c)) {
                break;
            }

            map += start;

            // Anything outside the basic plane is a surrogate pair, so it costs
            // two UTF-16 units for the one byte position it starts at.
            if (c > 0xFFFF) {
                map += start;
            }
        }

        map += text.length;
        return map;
    }

    // Entities can nest, so rather than assume a shape, cut the text at every
    // boundary and ask which spans cover each piece.
    private int[] boundaries (GenericArray<Span> spans, int length) {
        int[] cuts = { 0, length };

        for (var i = 0; i < spans.length; i++) {
            cuts += spans[i].start;
            cuts += spans[i].end;
        }

        for (var i = 1; i < cuts.length; i++) {
            var value = cuts[i];
            var j = i - 1;
            while (j >= 0 && cuts[j] > value) {
                cuts[j + 1] = cuts[j];
                j--;
            }
            cuts[j + 1] = value;
        }

        int[] unique = {};
        foreach (var cut in cuts) {
            if (unique.length == 0 || unique[unique.length - 1] != cut) {
                unique += cut;
            }
        }

        return unique;
    }

    private string url_of (Json.Object type, string covered) {
        switch (type.get_string_member ("@type")) {
            case "textEntityTypeTextUrl":
                return type.has_member ("url") ? type.get_string_member ("url") : "";
            case "textEntityTypeUrl":
                return covered;

            // A private scheme rather than a real URL: the label makes these
            // clickable, and the row intercepts them before GTK tries to hand
            // them to a browser.
            case "textEntityTypeMention":
                return covered.has_prefix ("@")
                    ? "telegrama:u/" + covered.substring (1)
                    : "telegrama:u/" + covered;
            case "textEntityTypeMentionName":
                return type.has_member ("user_id")
                    ? "telegrama:i/" + type.get_int_member ("user_id").to_string ()
                    : "";
            case "textEntityTypeEmailAddress":
                return "mailto:" + covered;
            default:
                return "";
        }
    }

    private string[] tags_for (Span span, bool reveal_spoilers, string spoiler_colour) {
        switch (span.kind) {
            case "textEntityTypeBold":
                return { "<b>", "</b>" };
            case "textEntityTypeItalic":
                return { "<i>", "</i>" };
            case "textEntityTypeUnderline":
                return { "<u>", "</u>" };
            case "textEntityTypeStrikethrough":
                return { "<s>", "</s>" };
            case "textEntityTypeCode":
            case "textEntityTypePre":
            case "textEntityTypePreCode":
                return { "<tt>", "</tt>" };

            case "textEntityTypeSpoiler":
                if (reveal_spoilers) {
                    return { "", "" };
                }
                // Painted in the label's own colour so it reads as a solid bar
                // and follows the theme without a hardcoded palette.
                return {
                    @"<span foreground=\"$spoiler_colour\" background=\"$spoiler_colour\">",
                    "</span>"
                };

            case "textEntityTypeTextUrl":
            case "textEntityTypeUrl":
            case "textEntityTypeEmailAddress":
            case "textEntityTypeMention":
            case "textEntityTypeMentionName":
                if (span.url == "") {
                    return { "", "" };
                }
                return { @"<a href=\"$(Markup.escape_text (span.url))\">", "</a>" };

            default:
                return { "", "" };
        }
    }
}
