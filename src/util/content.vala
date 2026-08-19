namespace Telegrama.Content {

    // Shared with the chat list, which needs the same one-line description.
    public string summary (Json.Object message) {
        if (!message.has_member ("content")) {
            return "";
        }

        return describe (message.get_object_member ("content"));
    }

    // The bubble wants the message as it was written, newlines and all, where
    // summary() flattens it to fit one line in the sidebar.
    public string full (Json.Object message) {
        if (!message.has_member ("content")) {
            return "";
        }

        var content = message.get_object_member ("content");

        if (content.get_string_member ("@type") == "messageText") {
            return content.get_object_member ("text").get_string_member ("text");
        }

        if (content.has_member ("caption")) {
            var caption = content.get_object_member ("caption").get_string_member ("text");
            if (caption != "") {
                return caption;
            }
        }

        return describe (content);
    }

    // TDLib does not mark service messages, so the list is hardcoded the way
    // every client hardcodes it. Roughly 80 of its 104 content types are
    // notices rather than something a person wrote.
    public bool is_service (Json.Object content) {
        var kind = content.get_string_member ("@type");

        return kind.has_prefix ("messageChat")
            || kind.has_prefix ("messageForumTopic")
            || kind.has_prefix ("messageVideoChat")
            || kind.has_prefix ("messageGiveaway")
            || kind.has_prefix ("messageGift")
            || kind.has_prefix ("messagePayment")
            || kind.has_prefix ("messageSuggested")
            || kind.has_prefix ("messagePassport")
            || kind.has_prefix ("messageWebApp")
            || kind == "messagePinMessage"
            || kind == "messageScreenshotTaken"
            || kind == "messageContactRegistered"
            || kind == "messageBasicGroupChatCreate"
            || kind == "messageSupergroupChatCreate"
            || kind == "messageCustomServiceAction"
            || kind == "messageProximityAlertTriggered"
            || kind == "messageUsersShared"
            || kind == "messageBotWriteAccessAllowed"
            || kind == "messageGameScore"
            || kind == "messageUnsupported";
    }

    // Written as a sentence about the person, since that is how a notice reads.
    public string notice (Json.Object content, string actor) {
        var who = actor == "" ? "Someone" : actor;

        switch (content.get_string_member ("@type")) {
            case "messageChatChangeTitle":
                return @"$who changed the name to \u201C$(content.get_string_member ("title"))\u201D";
            case "messageChatChangePhoto":
                return @"$who changed the photo";
            case "messageChatDeletePhoto":
                return @"$who removed the photo";
            case "messageChatAddMembers":
                return @"$who added a member";
            case "messageChatJoinByLink":
                return @"$who joined via invite link";
            case "messageChatJoinByRequest":
                return @"$who joined";
            case "messageChatDeleteMember":
                return @"$who removed a member";
            case "messageChatUpgradeTo":
            case "messageChatUpgradeFrom":
                return "The group became a supergroup";
            case "messageBasicGroupChatCreate":
            case "messageSupergroupChatCreate":
                return @"$who created the group";
            case "messagePinMessage":
                return @"$who pinned a message";
            case "messageScreenshotTaken":
                return @"$who took a screenshot";
            case "messageChatSetTheme":
                return @"$who changed the theme";
            case "messageChatSetBackground":
                return @"$who changed the background";
            case "messageChatSetMessageAutoDeleteTime":
                return "The auto-delete timer changed";
            case "messageContactRegistered":
                return @"$who joined Telegram";
            case "messageVideoChatStarted":
                return "Video chat started";
            case "messageVideoChatEnded":
                return "Video chat ended";
            case "messageVideoChatScheduled":
                return "Video chat scheduled";
            case "messageForumTopicCreated":
                return @"$who created the topic";
            case "messageCustomServiceAction":
                return content.has_member ("text") ? content.get_string_member ("text") : "Notice";
            case "messageUnsupported":
                return "Unsupported message";
            default:
                // The long tail is real but rare; a neutral notice beats a bubble
                // reading "Message".
                return describe (content);
        }
    }

    public string describe (Json.Object content) {

        switch (content.get_string_member ("@type")) {
            case "messageText":
                return one_line (content.get_object_member ("text").get_string_member ("text"));

            // An emoji sent on its own is its own content type, not text.
            case "messageAnimatedEmoji":
                return content.has_member ("emoji") ? content.get_string_member ("emoji") : "Emoji";
            case "messageDice":
                return content.has_member ("emoji") ? content.get_string_member ("emoji") : "Dice";

            case "messagePhoto":
                return captioned (content, "Photo");
            case "messageVideo":
                return captioned (content, "Video");
            case "messageAnimation":
                return captioned (content, "GIF");
            case "messageAudio":
                return captioned (content, "Audio");
            case "messageDocument":
                return captioned (content, "File");
            case "messageVoiceNote":
                return captioned (content, "Voice message");
            case "messagePaidMedia":
                return captioned (content, "Paid media");

            case "messageSticker":
                return "Sticker";
            case "messageVideoNote":
                return "Video message";
            case "messageLocation":
            case "messageVenue":
                return "Location";
            case "messageContact":
                return "Contact";
            case "messagePoll":
                return "Poll";
            case "messageCall":
                return "Call";
            case "messageStory":
                return "Story";
            case "messageGame":
                return "Game";

            case "messageExpiredPhoto":
            case "messageExpiredVideo":
            case "messageExpiredVideoNote":
                return "Expired";
            case "messageUnsupported":
                return "Unsupported message";

            case "messageChatJoinByLink":
            case "messageChatAddMembers":
                return "Joined the chat";
            case "messageChatDeleteMember":
                return "Left the chat";
            case "messagePinMessage":
                return "Pinned a message";
            case "messageChatChangeTitle":
                return "Changed the title";
            case "messageChatChangePhoto":
                return "Changed the photo";

            default:
                return "Message";
        }
    }

    // Real clients show the caption rather than the media label when there is
    // one, so a photo with text reads like the message it is.
    private string captioned (Json.Object content, string label) {
        if (!content.has_member ("caption")) {
            return label;
        }

        var caption = one_line (content.get_object_member ("caption").get_string_member ("text"));
        return caption == "" ? label : caption;
    }

    private string one_line (string text) {
        return text.replace ("\n", " ").strip ();
    }
}
