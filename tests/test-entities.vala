// The UTF-16 conversion is the reason this file exists: it is invisible in
// English and wrong the moment a message contains an emoji.
private Json.Object formatted (string json) {
    var parser = new Json.Parser ();
    try {
        parser.load_from_data (json);
    } catch (Error e) {
        Test.fail_printf ("bad test fixture: %s", e.message);
    }
    return parser.get_root ().get_object ();
}

private string render (string json) {
    return Telegrama.Entities.markup (formatted (json), false, "#808080");
}

private void test_plain () {
    assert (render ("""{"text":"hello","entities":[]}""") == "hello");
}

private void test_escapes_markup () {
    assert (render ("""{"text":"a < b & c","entities":[]}""") == "a &lt; b &amp; c");
}

private void test_bold () {
    assert (render ("""
        {"text":"say hello","entities":[
            {"offset":4,"length":5,"type":{"@type":"textEntityTypeBold"}}
        ]}
    """) == "say <b>hello</b>");
}

// "hi 👋 bold": the word starts at 6 in UTF-16, 5 in codepoints, 8 in bytes.
// Treating Telegram's offset as anything but UTF-16 lands mid-emoji.
private void test_offsets_are_utf16 () {
    assert (render ("""
        {"text":"hi 👋 bold","entities":[
            {"offset":6,"length":4,"type":{"@type":"textEntityTypeBold"}}
        ]}
    """) == "hi 👋 <b>bold</b>");
}

// Two astral characters before the entity: the drift doubles.
private void test_offsets_survive_several_surrogates () {
    assert (render ("""
        {"text":"👋👋ok","entities":[
            {"offset":4,"length":2,"type":{"@type":"textEntityTypeItalic"}}
        ]}
    """) == "👋👋<i>ok</i>");
}

private void test_escaping_happens_per_run () {
    assert (render ("""
        {"text":"a & <b>","entities":[
            {"offset":4,"length":3,"type":{"@type":"textEntityTypeCode"}}
        ]}
    """) == "a &amp; <tt>&lt;b&gt;</tt>");
}

private void test_nested_entities () {
    var result = render ("""
        {"text":"abcd","entities":[
            {"offset":0,"length":4,"type":{"@type":"textEntityTypeBold"}},
            {"offset":1,"length":2,"type":{"@type":"textEntityTypeItalic"}}
        ]}
    """);
    assert (result == "<b>a</b><b><i>bc</i></b><b>d</b>");
}

private void test_text_url () {
    assert (render ("""
        {"text":"click here","entities":[
            {"offset":6,"length":4,"type":{"@type":"textEntityTypeTextUrl","url":"https://a.example/?x=1&y=2"}}
        ]}
    """) == "click <a href=\"https://a.example/?x=1&amp;y=2\">here</a>");
}

private void test_spoiler_hidden_then_revealed () {
    var json = """
        {"text":"the answer","entities":[
            {"offset":4,"length":6,"type":{"@type":"textEntityTypeSpoiler"}}
        ]}
    """;

    var hidden = Telegrama.Entities.markup (formatted (json), false, "#123456");
    assert ("background=\"#123456\"" in hidden);

    var shown = Telegrama.Entities.markup (formatted (json), true, "#123456");
    assert (shown == "the answer");
}

// A range that does not fit the text should be ignored rather than crash.
private void test_out_of_range_entity () {
    assert (render ("""
        {"text":"short","entities":[
            {"offset":3,"length":99,"type":{"@type":"textEntityTypeBold"}}
        ]}
    """) == "short");
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/entities/plain", test_plain);
    Test.add_func ("/entities/escapes-markup", test_escapes_markup);
    Test.add_func ("/entities/bold", test_bold);
    Test.add_func ("/entities/offsets-are-utf16", test_offsets_are_utf16);
    Test.add_func ("/entities/offsets-several-surrogates", test_offsets_survive_several_surrogates);
    Test.add_func ("/entities/escaping-per-run", test_escaping_happens_per_run);
    Test.add_func ("/entities/nested", test_nested_entities);
    Test.add_func ("/entities/text-url", test_text_url);
    Test.add_func ("/entities/spoiler", test_spoiler_hidden_then_revealed);
    Test.add_func ("/entities/out-of-range", test_out_of_range_entity);

    return Test.run ();
}
