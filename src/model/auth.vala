public enum Telegrama.AuthStage {
    CONNECTING,
    UNCONFIGURED,
    PHONE,
    QR,
    CODE,
    PASSWORD,
    REGISTRATION,
    READY,
    CLOSED,
}

public class Telegrama.AuthSession : Object {

    public Td.Client client { get; construct; }
    public AuthStage stage { get; private set; default = AuthStage.CONNECTING; }

    // Where Telegram says it sent the code, and the 2FA hint, both phrased for
    // the UI rather than mirrored from the API.
    public string code_target { get; private set; default = ""; }
    public string password_hint { get; private set; default = ""; }

    // Telegram rotates the login token every few seconds and re-sends the same
    // authorization state with a new link. The stage does not change across
    // those, so the UI has to follow this property, not the stage.
    public string qr_link { get; private set; default = ""; }

    // QR is the default way in. Cleared for good once the user asks for the
    // phone form, so a later state change does not drag them back.
    private bool qr_preferred = true;

    // apply() is reached twice on startup, once from the update TDLib emits when
    // the client appears and once from the getAuthorizationState reply. Both of
    // these would otherwise send their request a second time, and TDLib answers
    // the duplicate with a 400.
    private bool configuring = false;
    private bool requesting_qr = false;

    public signal void failed (string message);

    public AuthSession (Td.Client client) {
        Object (client: client);
    }

    construct {
        client.update.connect ((type, body) => {
            if (type == "updateAuthorizationState") {
                apply (body.get_object_member ("authorization_state"));
            }
        });
    }

    // TDLib does not create the client until it receives a request, so this both
    // wakes it and reports where the previous session left off.
    public async void start () {
        try {
            apply (yield client.request ("getAuthorizationState"));
        } catch (Td.ClientError e) {
            failed (e.message);
        }
    }

    public void use_qr () {
        qr_preferred = true;
        if (qr_link != "") {
            stage = AuthStage.QR;
        }
        request_qr.begin ();
    }

    // TDLib stays in WaitOtherDeviceConfirmation until a phone number arrives,
    // so going back is purely a UI move until the user submits one.
    public void use_phone () {
        qr_preferred = false;
        stage = AuthStage.PHONE;
    }

    private async void request_qr () {
        if (requesting_qr) {
            return;
        }
        requesting_qr = true;

        try {
            yield client.request ("requestQrCodeAuthentication", (b) => {
                b.set_member_name ("other_user_ids");
                b.begin_array ();
                b.end_array ();
            });
        } catch (Td.ClientError e) {
            // Never leave the user staring at a spinner with no way forward.
            failed (explain (e.message));
            use_phone ();
        }

        requesting_qr = false;
    }

    public async void submit_phone (string number) {
        yield call ("setAuthenticationPhoneNumber", (b) => {
            b.set_member_name ("phone_number");
            b.add_string_value (number);
        });
    }

    public async void submit_code (string code) {
        yield call ("checkAuthenticationCode", (b) => {
            b.set_member_name ("code");
            b.add_string_value (code);
        });
    }

    public async void submit_password (string password) {
        yield call ("checkAuthenticationPassword", (b) => {
            b.set_member_name ("password");
            b.add_string_value (password);
        });
    }

    public async void submit_registration (string first_name, string last_name) {
        yield call ("registerUser", (b) => {
            b.set_member_name ("first_name");
            b.add_string_value (first_name);
            b.set_member_name ("last_name");
            b.add_string_value (last_name);
        });
    }

    private async void call (string method, owned Td.RequestBuilder build) {
        try {
            yield client.request (method, (owned) build);
        } catch (Td.ClientError e) {
            failed (explain (e.message));
        }
    }

    private void apply (Json.Object? state) {
        if (state == null || !state.has_member ("@type")) {
            return;
        }

        switch (state.get_string_member ("@type")) {
            case "authorizationStateWaitTdlibParameters":
                configure.begin ();
                break;

            case "authorizationStateWaitPhoneNumber":
                if (qr_preferred) {
                    // Stay on the spinner for the round trip; the QR page would
                    // otherwise flash an empty square before the link lands.
                    request_qr.begin ();
                } else {
                    stage = AuthStage.PHONE;
                }
                break;

            case "authorizationStateWaitOtherDeviceConfirmation":
                qr_link = state.get_string_member ("link");
                if (qr_preferred) {
                    stage = AuthStage.QR;
                }
                break;

            case "authorizationStateWaitCode":
                code_target = describe_code (state.get_object_member ("code_info"));
                stage = AuthStage.CODE;
                break;

            case "authorizationStateWaitPassword":
                password_hint = state.has_member ("password_hint")
                    ? state.get_string_member ("password_hint")
                    : "";
                stage = AuthStage.PASSWORD;
                break;

            case "authorizationStateWaitRegistration":
                stage = AuthStage.REGISTRATION;
                break;

            case "authorizationStateReady":
                stage = AuthStage.READY;
                break;

            case "authorizationStateClosed":
                stage = AuthStage.CLOSED;
                if (!client.stopping) {
                    restart ();
                }
                break;

            default:
                break;
        }
    }

    // Terminating the session elsewhere closes TDLib for good: it answers
    // nothing further and needs a brand new client to sign in again. Without
    // this the window sits on a spinner until it is restarted by hand.
    private void restart () {
        qr_link = "";
        qr_preferred = true;
        code_target = "";
        password_hint = "";
        configuring = false;
        requesting_qr = false;

        client.start ();
        start.begin ();
    }

    private async void configure () {
        if (configuring) {
            return;
        }
        configuring = true;

        if (Config.API_ID == 0 || Config.API_HASH == "") {
            stage = AuthStage.UNCONFIGURED;
            return;
        }

        var key = yield Keyring.database_key ();

        try {
            yield client.request ("setTdlibParameters", (b) => {
                b.set_member_name ("use_test_dc");
                b.add_boolean_value (false);
                b.set_member_name ("database_directory");
                b.add_string_value (Path.build_filename (Environment.get_user_data_dir (), "telegrama"));
                b.set_member_name ("files_directory");
                b.add_string_value (Path.build_filename (Environment.get_user_cache_dir (), "telegrama"));
                b.set_member_name ("database_encryption_key");
                b.add_string_value (key);
                b.set_member_name ("use_file_database");
                b.add_boolean_value (true);
                b.set_member_name ("use_chat_info_database");
                b.add_boolean_value (true);
                b.set_member_name ("use_message_database");
                b.add_boolean_value (true);
                b.set_member_name ("use_secret_chats");
                b.add_boolean_value (false);
                b.set_member_name ("api_id");
                b.add_int_value (Config.API_ID);
                b.set_member_name ("api_hash");
                b.add_string_value (Config.API_HASH);
                b.set_member_name ("system_language_code");
                b.add_string_value (language_code ());
                b.set_member_name ("device_model");
                b.add_string_value (Environment.get_host_name ());
                b.set_member_name ("system_version");
                b.add_string_value ("Linux");
                b.set_member_name ("application_version");
                b.add_string_value (Config.VERSION);
            });
        } catch (Td.ClientError e) {
            configuring = false;
            failed (e.message);
        }
    }

    private static string language_code () {
        foreach (unowned string name in Intl.get_language_names ()) {
            if (name != "C" && name != "POSIX") {
                return name.split ("_")[0].split (".")[0];
            }
        }
        return "en";
    }

    private static string describe_code (Json.Object? info) {
        if (info == null || !info.has_member ("type")) {
            return "Enter the code Telegram sent you.";
        }

        switch (info.get_object_member ("type").get_string_member ("@type")) {
            case "authenticationCodeTypeTelegramMessage":
                return "Enter the code sent to your other Telegram devices.";
            case "authenticationCodeTypeSms":
            case "authenticationCodeTypeSmsWord":
            case "authenticationCodeTypeSmsPhrase":
                return "Enter the code sent to you by SMS.";
            case "authenticationCodeTypeCall":
                return "Enter the code you were given by phone call.";
            case "authenticationCodeTypeFlashCall":
            case "authenticationCodeTypeMissedCall":
                return "Enter the last digits of the number that called you.";
            case "authenticationCodeTypeFragment":
                return "Enter the code delivered through Fragment.";
            default:
                return "Enter the code Telegram sent you.";
        }
    }

    // TDLib passes the server's error constants straight through, and they are
    // not fit to show anyone.
    private static string explain (string message) {
        if ("PHONE_NUMBER_INVALID" in message) {
            return "That phone number is not valid.";
        }
        if ("PHONE_CODE_INVALID" in message || "PHONE_CODE_EMPTY" in message) {
            return "That code is not correct.";
        }
        if ("PHONE_CODE_EXPIRED" in message) {
            return "That code has expired. Start again to get a new one.";
        }
        if ("PASSWORD_HASH_INVALID" in message) {
            return "That password is not correct.";
        }
        if ("FLOOD_WAIT" in message) {
            return "Too many attempts. Wait a while before trying again.";
        }
        return message;
    }
}
